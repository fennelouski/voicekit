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
        guard isListening || isStarting else { return }
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
        accumulator.reset()
        hud.show()
        onListeningChange?(true)

        Task {
            do {
                let deviceID = AudioInputSelection.loadSelectedDeviceId().flatMap { UInt32($0) }
                let session = try await service.startRecognition(locale: Settings.locale, inputDeviceID: deviceID)

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

    private func requestStop() {
        if isStarting {
            pendingStop = true
            return
        }
        guard isListening, !isStopping else { return }
        isStopping = true
        hud.setProcessing()

        Task {
            await service.stopRecognition()
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

            enqueueCleanup(raw: raw, hints: hints, chain: chain)
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

    private func enqueueCleanup(raw: String, hints: [Correction], chain: [CleanupMode]) {
        pendingCleanups += 1
        let previous = cleanupTail
        cleanupTail = Task { [weak self] in
            await previous.value
            guard let self else { return }
            let failed = await self.runCleanup(raw: raw, hints: hints, chain: chain)
            self.pendingCleanups -= 1
            guard self.pendingCleanups == 0, !self.isListening, !self.isStarting else { return }
            if failed {
                self.hud.showError("Cleanup failed — inserted as-is")
            } else {
                self.hud.hide()
            }
        }
    }

    /// Clean, insert, and record one dictation. Returns true if the chain had work but nothing landed.
    private func runCleanup(raw: String, hints: [Correction], chain: [CleanupMode]) async -> Bool {
        var text = TranscriptCleaner.clean(raw)
        if Settings.learningEnabled {
            text = CorrectionStore.shared.apply(to: text)
        }
        var cleanupFallback = false
        if !text.isEmpty, !chain.isEmpty {
            // Each step is tried in turn; a missing key just means that step isn't the one
            // that cleans your text. Only a chain where nothing worked is worth mentioning.
            let result = await CleanupChain.run(text, chain: chain, hints: hints, runStep: CleanupChain.liveStep)
            text = result.text
            cleanupFallback = result.allFailed
        }
        if !text.isEmpty {
            // Trailing space so back-to-back dictations don't run together.
            if let last = text.last, !last.isWhitespace { text += " " }
            let frontApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
            Self.log.notice("inserting \(text.count, privacy: .public) chars into \(frontApp, privacy: .public)")
            TextInserter.insert(text)
            DictationHistory.shared.add(text)
            correctionObserver.beginObserving(inserted: text, rawLength: raw.count)
        } else {
            Self.log.notice("nothing to insert (empty transcript; raw was \(raw.count, privacy: .public) chars)")
        }
        return cleanupFallback
    }

    /// Name the hardware, not the setting: "System default" tells you nothing six months
    /// later when you're trying to work out why one transcript sounds worse than another.
    private static func microphoneDescription() async -> String {
        let devices = await AudioInputSelection.availableDevices()
        if let selected = AudioInputSelection.loadSelectedDeviceId(), !selected.isEmpty {
            if let device = devices.first(where: { $0.id == selected }) {
                return device.name
            }
            return "Selected device unavailable (id \(selected))"
        }
        let name = AVCaptureDevice.default(for: .audio)?.localizedName ?? "unknown"
        return "\(name) (system default)"
    }

    private static func message(for error: Error) -> String {
        switch error {
        case RecognitionError.notAuthorized:
            return "Permission needed — enable Microphone and Speech Recognition in System Settings"
        case RecognitionError.localeNotSupported:
            return "Selected language isn't supported for on-device recognition"
        case RecognitionError.modelDownloadFailed:
            return "Speech model download failed — check your connection and retry"
        default:
            return "Couldn't start dictation"
        }
    }
}
#endif
