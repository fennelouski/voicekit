//
//  DictationController.swift
//  Dictate
//
//  Push-to-talk state machine: hold the hotkey to dictate, release to insert.
//  A quick tap (<0.35s) locks dictation on; the next tap stops and inserts.
//

#if os(macOS)
import AppKit
import AVFoundation
import os
import VoiceKit

@available(macOS 26.0, *)
@MainActor
final class DictationController {
    private static let log = Logger(subsystem: "Dictate", category: "DictationController")

    var onListeningChange: ((Bool) -> Void)?

    private let service = SpeechRecognitionService()
    private let hud = HUDController()
    private var accumulator = TranscriptAccumulator()
    private let correctionObserver = CorrectionObserver()
    private var transcriptTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?

    private var recorder: ConversationRecorder?
    private var audioTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    /// The safety recording currently being written. Cleanup of an *earlier* dictation can
    /// finish while this one is still recording, so the sweep has to know to spare it.
    private var activeBackupURL: URL?

    /// How long the microphone may go without delivering a buffer before we assume the
    /// audio path is dead rather than the room quiet. Buffers arrive every ~90ms at the
    /// sizes we ask for, so this is generous by two orders of magnitude.
    private let captureStallThreshold: TimeInterval = 2.5

    private var isStarting = false
    private var isListening = false
    private var isStopping = false
    private var locked = false
    private var pendingStop = false
    private var ignoreNextKeyUp = false
    private var pressStart: Date?

    private let tapThreshold: TimeInterval = 0.35

    // MARK: - Hotkey events

    func hotkeyDown() {
        guard !isStopping else { return }
        if isListening || isStarting {
            // Locked on from an earlier tap: this press stops and inserts.
            if locked {
                ignoreNextKeyUp = true
                requestStop()
            }
            return
        }
        pressStart = Date()
        locked = false
        start()
    }

    func hotkeyUp() {
        if ignoreNextKeyUp {
            ignoreNextKeyUp = false
            return
        }
        guard isListening || isStarting, !isStopping else { return }
        let held = Date().timeIntervalSince(pressStart ?? .distantPast)
        if held < tapThreshold {
            locked = true
            hud.setLocked(true)
        } else {
            requestStop()
        }
    }

    /// Menu-driven toggle: start locked, or stop and insert.
    func toggleManual() {
        if isListening || isStarting {
            requestStop()
        } else if !isStopping {
            pressStart = .distantPast
            locked = true
            start()
            hud.setLocked(true)
        }
    }

    // MARK: - Session lifecycle

    private func start() {
        correctionObserver.harvest()
        isStarting = true
        // A stop requested while a *previous* start was still running, and never consumed
        // because that start threw, would otherwise kill this session the instant it opens.
        pendingStop = false
        accumulator.reset()
        hud.show()
        onListeningChange?(true)

        Task {
            do {
                // Resolved, not read raw: the saved microphone may have been renumbered or
                // unplugged since it was chosen, and a stale ID is how this used to die.
                let deviceID = AudioInputSelection.resolveSelectedDeviceID()
                let backupDirectory: URL? = Settings.backupRecording ? LearningPaths.recovery : nil
                let session = try await service.startRecognition(
                    locale: Settings.locale, inputDeviceID: deviceID, backupDirectory: backupDirectory
                )
                activeBackupURL = session.backupURL

                if Settings.conversationTranscripts {
                    let rec = ConversationRecorder()
                    recorder = rec
                    audioTask = Task { await rec.run(buffers: session.audioBuffers) }
                    // Resolved off the hot path — the transcript can wait, the audio can't.
                    Task {
                        await rec.setMicrophone(await Self.microphoneDescription())
                    }
                }

                transcriptTask = Task { [weak self] in
                    for await result in session.transcript {
                        guard let self else { return }
                        self.accumulator.add(result)
                        self.hud.update(text: self.accumulator.preview)
                        if result.isFinal, let rec = self.recorder {
                            await rec.addSegment(text: result.text, start: result.start, end: result.end)
                        }
                    }
                }
                levelTask = Task {
                    for await level in session.level {
                        hud.update(level: level)
                    }
                }

                isStarting = false
                isListening = true
                startWatchdog()
                if pendingStop {
                    pendingStop = false
                    requestStop()
                }
            } catch {
                isStarting = false
                onListeningChange?(false)
                Self.log.error("start failed: \(error, privacy: .public)")
                hud.showError(Self.message(for: error))
            }
        }
    }

    // MARK: - Watchdog

    /// Watches for the microphone going quiet in the way that means "gone", not "nobody is
    /// speaking", and puts it back.
    ///
    /// This is the failure the app used to have no answer for: unplug a pair of AirPods
    /// mid-sentence and capture stops, but the session looks perfectly healthy — the HUD
    /// still says it's listening, so you keep talking and find out at the end that none of
    /// it was heard. Restarting the microphone alone, rather than the whole session, keeps
    /// everything already transcribed and costs the user only the second it takes to swap.
    private func startWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.isListening, !self.isStopping else { return }
                guard await self.service.silenceDuration() > self.captureStallThreshold else {
                    failures = 0
                    continue
                }

                Self.log.error("microphone stalled — restarting capture")
                if await self.service.restartCapture() {
                    failures = 0
                    continue
                }

                // Three failed reconnections in a row is a microphone that isn't coming
                // back. Stop rather than leave a HUD claiming to listen: stopping still
                // inserts what was heard, and still recovers from the backup audio.
                failures += 1
                guard failures >= 3 else { continue }
                Self.log.error("microphone did not come back — ending the session")
                // Stopping puts the HUD into its processing state, so the message has to
                // wait for the insert to finish or it would flash past unread.
                self.pendingHUDError = String(localized: "Microphone disconnected — dictation stopped")
                self.requestStop()
                return
            }
        }
    }

    private func requestStop() {
        if isStarting {
            pendingStop = true
            return
        }
        guard isListening, !isStopping else { return }
        isStopping = true
        hud.setProcessing()
        watchdogTask?.cancel()
        watchdogTask = nil

        Task {
            let backupURL = await service.stopRecognition()
            // Safe to clear here and nowhere later: `isStopping` is still true, so no new
            // session can have started and claimed this slot.
            activeBackupURL = nil
            await transcriptTask?.value
            levelTask?.cancel()
            // Settle the transcript file in the background. Diarization (which may be
            // downloading models on first run) must never delay — or deadlock — the paste.
            if let rec = recorder {
                let drain = audioTask
                Task {
                    await drain?.value
                    await rec.finish()
                }
            }
            recorder = nil
            audioTask = nil

            // Snapshot everything cleanup needs while the accumulator still holds this session.
            let raw = accumulator.committed.isEmpty ? accumulator.preview : accumulator.committed
            let hints = Settings.learningEnabled ? CorrectionStore.shared.promptHints(limit: 20) : []
            let chain = Settings.cleanupChain

            // Recording is fully torn down here — release the hotkey now so the next dictation
            // can start immediately, without waiting for cleanup (which may hit the network for
            // several seconds). Cleanup + insert is handed to a serial queue below.
            isListening = false
            isStopping = false
            locked = false
            onListeningChange?(false)

            enqueueCleanup(raw: raw, hints: hints, chain: chain, backup: backupURL)
        }
    }

    // MARK: - Cleanup queue

    // Cleanup + insert runs off the recording critical path, one job at a time in the order
    // dictations were stopped: a slow (networked) cleanup never blocks the next recording, and
    // back-to-back dictations still insert in sequence. The tail task chains each job behind the
    // previous one's completion; `pendingCleanups` tracks the backlog so only the last job, and
    // only when nothing is being recorded, hands the HUD back.
    private var cleanupTail: Task<Void, Never> = Task {}
    private var pendingCleanups = 0
    /// Something went wrong during recording that the user should see, held back until the
    /// text has been inserted so it isn't overwritten by the processing state.
    private var pendingHUDError: String?

    private func enqueueCleanup(raw: String, hints: [Correction], chain: [CleanupMode], backup: URL?) {
        pendingCleanups += 1
        let previous = cleanupTail
        cleanupTail = Task { [weak self] in
            await previous.value
            guard let self else { return }

            // Live recognition came back with nothing, but the microphone was recording the
            // whole time. Transcribe what it caught rather than telling the user their last
            // minute of talking is gone.
            var raw = raw
            var recovered = false
            if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let backup {
                if let text = await Self.recoverTranscript(from: backup) {
                    raw = text
                    recovered = true
                    Self.log.notice("recovered \(text.count, privacy: .public) chars from the backup recording")
                }
            }

            let failed = await self.runCleanup(raw: raw, hints: hints, chain: chain, recovered: recovered)

            // This dictation's audio existed to protect these words: if they landed, it can
            // go now; if they didn't, it survives — by default only until the next dictation
            // finishes, which is the only window in which it's any use to anyone.
            var keep: [URL] = []
            if let backup, raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                keep.append(backup)
            }
            if let recording = self.activeBackupURL {
                keep.append(recording)
            }
            BackupRecorder.sweep(
                LearningPaths.recovery, keeping: keep, retention: Settings.backupRetention.duration
            )
            self.pendingCleanups -= 1
            guard self.pendingCleanups == 0, !self.isListening, !self.isStarting else { return }
            if let message = self.pendingHUDError {
                self.pendingHUDError = nil
                self.hud.showError(message)
            } else if failed {
                self.hud.showError(String(localized: "Cleanup failed — inserted as-is"))
            } else {
                self.hud.hide()
            }
        }
    }

    /// Clean, insert, and record one dictation. Returns true if the chain had work but nothing landed.
    ///
    /// Every version the text passes through is kept as a history stage — raw, filler removed,
    /// learned corrections, and the AI polish (plus any providers that failed) — so a rewrite
    /// that went too far can be seen and recovered from Recent Dictations.
    private func runCleanup(raw: String, hints: [Correction], chain: [CleanupMode], recovered: Bool) async -> Bool {
        var stages: [DictationHistory.Stage] = [
            .init(label: recovered ? String(localized: "Recovered audio") : String(localized: "Raw"),
                  systemImage: recovered ? "arrow.clockwise" : "waveform", text: raw,
                  status: .applied, changePercent: nil)
        ]
        var previous = raw
        // Record an applied stage only when it actually changed the text — an identical
        // "filler removed" rung is just noise.
        func record(_ label: String, _ image: String, _ next: String, force: Bool = false) {
            guard force || next != previous else { return }
            stages.append(.init(label: label, systemImage: image, text: next, status: .applied,
                                changePercent: TextDistance.changePercent(from: previous, to: next)))
            previous = next
        }

        var text = TranscriptCleaner.clean(raw)
        record(String(localized: "Filler removed"), "scissors", text)
        if Settings.learningEnabled {
            text = CorrectionStore.shared.apply(to: text)
            record(String(localized: "Learned corrections"), "brain", text)
        }

        // Spoken formatting commands ("colon", "new line", ...) become literals. The user chooses
        // whether this runs and where: before the AI pass (the model capitalizes and polishes
        // around the punctuation) or after it (the model never touches the literals).
        func applyFormatting() {
            text = SpokenCommands.apply(text)
            record(String(localized: "Formatting"), "textformat", text)
        }
        if Settings.spokenCommandsEnabled, Settings.spokenCommandsPosition == .beforeCleanup {
            applyFormatting()
        }

        var cleanupFallback = false
        if !text.isEmpty, !chain.isEmpty {
            // Each step is tried in turn; a missing key just means that step isn't the one
            // that cleans your text. Only a chain where nothing worked is worth mentioning.
            let result = await CleanupChain.run(text, chain: chain, hints: hints, runStep: CleanupChain.liveStep)
            // Providers are tried in chain order: the ones that failed come before the winner.
            for step in result.failed {
                stages.append(.init(label: step.chainName, systemImage: step.systemImage, text: "",
                                    status: .failed, changePercent: nil))
            }
            if let used = result.usedStep {
                // Force it in even at 0% — "Apple Intelligence ran and changed nothing" is worth showing.
                record(used.chainName, used.systemImage, result.text, force: true)
            }
            text = result.text
            cleanupFallback = result.allFailed
        }

        if Settings.spokenCommandsEnabled, Settings.spokenCommandsPosition == .afterCleanup {
            applyFormatting()
        }

        if !text.isEmpty {
            DictationHistory.shared.add(.init(date: Date(), stages: stages))
            Settings.recordDictationCompleted()
            // Trailing space so back-to-back dictations don't run together.
            if let last = text.last, !last.isWhitespace { text += " " }
            let frontApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
            Self.log.notice("inserting \(text.count, privacy: .public) chars into \(frontApp, privacy: .public)")
            if TextInserter.insert(text) {
                correctionObserver.beginObserving(inserted: text, rawLength: raw.count)
            } else {
                Self.log.error("accessibility denied — left \(text.count, privacy: .public) chars on the clipboard")
                hud.showError(String(localized: "Accessibility denied — press ⌘V to paste"))
            }
        } else {
            Self.log.notice("nothing to insert (empty transcript; raw was \(raw.count, privacy: .public) chars)")
        }
        return cleanupFallback
    }

    /// Transcribe the session's backup recording after the fact, for when live recognition
    /// produced nothing. Same on-device model, no network, just without the pressure of
    /// keeping up — which is why it can succeed where the live pass didn't.
    private static func recoverTranscript(from url: URL) async -> String? {
        do {
            let segments = try await FileTranscriber.transcribe(fileAt: url, locale: Settings.locale)
            let text = segments.map(\.text).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            log.error("backup transcription failed: \(error, privacy: .public)")
            return nil
        }
    }

    /// Name the hardware, not the setting: "System default" tells you nothing six months
    /// later when you're trying to work out why one transcript sounds worse than another.
    private static func microphoneDescription() async -> String {
        let devices = await AudioInputSelection.availableDevices()
        if let selected = AudioInputSelection.loadSelectedDeviceId(), !selected.isEmpty {
            let tag = AudioInputSelection.selectedDeviceTag()
            if let device = devices.first(where: { $0.id == tag }) {
                return device.name
            }
            return String(format: String(localized: "Selected device unavailable (id %@)"), selected)
        }
        let name = AVCaptureDevice.default(for: .audio)?.localizedName ?? String(localized: "unknown")
        return String(format: String(localized: "%@ (system default)"), name)
    }

    private static func message(for error: Error) -> String {
        switch error {
        case RecognitionError.notAuthorized:
            return String(localized: "Permission needed — enable Microphone and Speech Recognition in System Settings")
        case RecognitionError.localeNotSupported:
            return String(localized: "Selected language isn't supported for on-device recognition")
        case RecognitionError.modelDownloadFailed:
            return String(localized: "Speech model download failed — check your connection and retry")
        default:
            return String(localized: "Couldn't start dictation")
        }
    }
}
#endif
