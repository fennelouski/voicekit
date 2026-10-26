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

    private let service: any DictationRecognition
    private let hud: any DictationHUD
    private let captureOptions: @MainActor () -> DictationOptions
    private let captureDestination: @MainActor () -> InsertionDestination?
    private let prepareInsertion: @MainActor () async throws -> Void
    private let insert: @MainActor (String, InsertionDestination?) -> InsertionResult
    private let runStep: ((String, CleanupMode, [Correction]) async throws -> String)?
    private let recover: (URL, Locale?) async -> String?
    private let saveHistory: @MainActor (DictationHistory.Entry) -> Void
    private let recordCompleted: @MainActor () -> Void
    private let recoveryStore: RecoveryStore?
    private let sweepRecovery: @MainActor ([URL]) -> Void
    private let timingSink: @MainActor (DictationTiming.Event) -> Void
    private var sessionMetrics: RecognitionMetrics?
    private var activeTransaction: DictationTransaction?
    private var activeOptions: DictationOptions?
    private var transactions: [UUID: DictationTransaction] = [:]

    init(
        timingSink: @escaping @MainActor (DictationTiming.Event) -> Void = DictationTiming.logEvent,
        service: (any DictationRecognition)? = nil, hud: (any DictationHUD)? = nil,
        captureOptions: @escaping @MainActor () -> DictationOptions = { .current },
        captureDestination: @escaping @MainActor () -> InsertionDestination? = { InsertionDestination.capture() },
        prepareInsertion: @escaping @MainActor () async throws -> Void = { try await TextInserter.waitForPreviousPaste() },
        insert: @escaping @MainActor (String, InsertionDestination?) -> InsertionResult = { TextInserter.insert($0, into: $1) },
        runStep: ((String, CleanupMode, [Correction]) async throws -> String)? = nil,
        recover: @escaping (URL, Locale?) async -> String? = { await DictationController.recoverTranscript(from: $0, locale: $1) },
        saveHistory: @escaping @MainActor (DictationHistory.Entry) -> Void = { DictationHistory.shared.add($0) },
        recordCompleted: @escaping @MainActor () -> Void = { Settings.recordDictationCompleted() },
        recoveryStore: RecoveryStore? = .shared,
        sweepRecovery: @escaping @MainActor ([URL]) -> Void = {
            BackupRecorder.sweep(LearningPaths.recovery, keeping: $0, retention: Settings.backupRetention.duration)
        }
    ) {
        self.timingSink = timingSink
        self.service = service ?? SpeechRecognitionService(captureWhilePreparing: true)
        self.hud = hud ?? HUDController()
        self.captureOptions = captureOptions
        self.captureDestination = captureDestination
        self.prepareInsertion = prepareInsertion
        self.insert = insert
        self.runStep = runStep
        self.recover = recover
        self.saveHistory = saveHistory
        self.recordCompleted = recordCompleted
        self.sweepRecovery = sweepRecovery
        self.recoveryStore = recoveryStore
    }

    /// No microphone and no permission prompts. Idle preparation also runs after
    /// each stop, so the next hotkey consumes an already prepared analyzer.
    func prepareRecognition() {
        guard !isCapturing else { return }
        let locale = Settings.locale
        Task { await service.prepareRecognition(locale: locale) }
    }

    var hasCancellableWork: Bool { transactions.values.contains { !$0.isCancelled } }
    var hasOutstandingWork: Bool { !transactions.isEmpty }
    var isCapturing: Bool { isStarting || isListening || isStopping }

    /// Escape cancels recording and the entire outstanding insertion backlog.
    /// New dictations do not queue behind a provider that ignores cancellation.
    @discardableResult
    func cancel() -> Bool {
        guard hasCancellableWork else { return false }
        for transaction in transactions.values { transaction.cancel() }
        cleanupTail = Task {}
        pendingHUDError = nil
        pendingStop = false
        locked = false
        ignoreNextKeyUp = false
        hud.hide()
        onListeningChange?(false)
        watchdogTask?.cancel()
        if isStarting {
            // Keep the service exclusive until the cancelled start has settled.
            isStopping = true
        } else if isListening, !isStopping {
            requestStop()
        }
        return true
    }
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
    /// audio path is dead rather than the room quiet. We request 1024-frame buffers (~21ms at 48kHz),
    /// though the hardware may deliver a different size, so this is generous by two orders of magnitude.
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
        let requestedAt = ProcessInfo.processInfo.systemUptime
        let transaction = DictationTransaction(destination: captureDestination(), requestedAt: requestedAt, timingSink: timingSink)
        transaction.timing.mark("destination_captured")
        let options = captureOptions()
        transaction.timing.mark("options_captured")
        activeTransaction = transaction
        activeOptions = options
        transactions[transaction.id] = transaction
        correctionObserver.harvest()
        isStarting = true
        pendingStop = false
        accumulator.reset()
        hud.show()
        if runStep == nil, options.chain.contains(.onDevice), let config = options.cleanupConfigurations[.onDevice] {
            let polisher = AICleanup.PreparedSession(customInstructions: config.promptInstructions)
            transaction.polisher = polisher
            Task { await polisher.prewarm() }
        }

        transaction.task = Task { [self] in
            do {
                try transaction.checkCancellation()
                if let recoveryStore, let scratch = options.backupDirectory {
                    await recoveryStore.importOnce(from: scratch, locale: options.locale)
                }
                try transaction.checkCancellation()
                let session = try await service.startRecognition(
                    locale: options.locale, inputDeviceID: options.inputDeviceID,
                    backupDirectory: options.backupDirectory
                )
                sessionMetrics = session.metrics
                transaction.timing.mark("capture_started")
                activeBackupURL = session.backupURL
                try transaction.checkCancellation()

                if options.saveConversation {
                    let rec = ConversationRecorder()
                    recorder = rec
                    transaction.discardTranscript = { Task { await rec.cancel() } }
                    audioTask = Task { await rec.run(buffers: session.audioBuffers) }
                    Task { await rec.setMicrophone(await Self.microphoneDescription()) }
                }
                let sessionRecorder = recorder
                transcriptTask = Task { [weak self] in
                    for await result in session.transcript {
                        guard let self, !transaction.isCancelled,
                              self.activeTransaction === transaction else { return }
                        self.accumulator.add(result)
                        self.hud.update(text: self.accumulator.preview)
                        if result.isFinal, let sessionRecorder {
                            if !Settings.conversationTranscripts { await sessionRecorder.cancel(); continue }
                            await sessionRecorder.addSegment(text: result.text, start: result.start, end: result.end)
                        }
                    }
                }
                levelTask = Task {
                    for await level in session.level {
                        guard !transaction.isCancelled, activeTransaction === transaction else { return }
                        hud.update(level: level)
                    }
                }

                isStarting = false
                isListening = true
                hud.setListening()
                onListeningChange?(true)
                startWatchdog()
                if pendingStop {
                    pendingStop = false
                    requestStop()
                }
            } catch {
                // A non-cooperative start may return a live session after Escape.
                // Close it before allowing another start on the same service.
                let backup = await service.cancelRecognition()
                if transaction.isCancelled, let backup { try? FileManager.default.removeItem(at: backup) }
                activeBackupURL = nil
                activeTransaction = nil
                activeOptions = nil
                isStarting = false
                isStopping = false
                transaction.timing.mark(transaction.isCancelled ? "cancelled_start_finished" : "start_failed")
                transaction.finish()
                transactions[transaction.id] = nil
                onListeningChange?(false)
                if !transaction.isCancelled {
                    Self.log.error("start failed: \(error, privacy: .public)")
                    hud.showError(Self.message(for: error))
                }
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
        guard let transaction = activeTransaction else { return }
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            var watchdog = CaptureWatchdog(stall: self?.captureStallThreshold ?? 2.5)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled, !transaction.isCancelled,
                      self.activeTransaction === transaction, self.isListening, !self.isStopping else { return }
                let silence = await self.service.silenceDuration()
                guard !transaction.isCancelled, self.activeTransaction === transaction else { return }
                guard watchdog.shouldRestart(now: ProcessInfo.processInfo.systemUptime, silence: silence) else {
                    if !watchdog.exhausted || silence <= self.captureStallThreshold { continue }
                    self.pendingHUDError = String(localized: "Microphone disconnected — dictation stopped")
                    self.requestStop()
                    return
                }
                Self.log.error("microphone stalled — restarting capture")
                _ = await self.service.restartCapture()
                guard !transaction.isCancelled, self.activeTransaction === transaction else { return }
                continue
            }
        }
    }

    private func requestStop() {
        activeTransaction?.timing.stop()
        if isStarting {
            pendingStop = true
            return
        }
        guard isListening, !isStopping, let transaction = activeTransaction,
              let options = activeOptions else { return }
        isStopping = true
        if !transaction.isCancelled { hud.setProcessing() }
        watchdogTask?.cancel()
        watchdogTask = nil

        transaction.task = Task {
            let backupURL: URL?
            if transaction.isCancelled {
                backupURL = await service.cancelRecognition()
            } else {
                backupURL = await service.stopRecognition()
            }
            activeBackupURL = nil
            await transcriptTask?.value
            let snapshot = sessionMetrics?.snapshot
            if let engine = snapshot?.engineStartedAt { transaction.timing.mark("engine_started", at: engine) }
            if let first = snapshot?.firstBufferAt { transaction.timing.mark("first_audio_buffer", at: first) }
            if let ready = snapshot?.analyzerReadyAt { transaction.timing.mark(snapshot?.usedWarmPreparation == true ? "analyzer_ready_warm" : "analyzer_ready_cold", at: ready) }
            if let final = snapshot?.finalResultAt { transaction.timing.mark("last_final_result", at: final) }
            transaction.timing.mark("recognition_finished")
            sessionMetrics = nil
            levelTask?.cancel()
            if let rec = recorder {
                let drain = audioTask
                Task {
                    await drain?.value
                    if transaction.isCancelled { await rec.cancel() }
                    else { await rec.finish() }
                }
            }
            recorder = nil
            audioTask = nil
            // A failed/overflowed pipeline must recover the complete backup, never
            // insert a seemingly successful partial transcript.
            let raw = snapshot?.pipelineFailed == true ? "" : (accumulator.committed.isEmpty ? accumulator.preview : accumulator.committed)
            let hints = options.learning ? CorrectionStore.shared.promptHints(limit: 20) : []
            isListening = false
            isStopping = false
            locked = false
            activeTransaction = nil
            activeOptions = nil
            onListeningChange?(false)
            prepareRecognition()

            if transaction.isCancelled {
                if let backupURL { try? FileManager.default.removeItem(at: backupURL) }
                transaction.finish()
                transactions[transaction.id] = nil
            } else {
                enqueueCleanup(raw: raw, hints: hints, options: options, backup: backupURL, transaction: transaction)
            }
        }
    }

    // MARK: - Cleanup queue

    // Cleanup + insert runs off the recording critical path, one job at a time in the order
    // dictations were stopped: a slow (networked) cleanup never blocks the next recording, and
    // back-to-back dictations still insert in sequence. The tail task chains each job behind the
    // previous one's completion. The transaction registry tracks live work so only
    // the final non-cancelled job hands the HUD back when recording is idle.
    private var cleanupTail: Task<Void, Never> = Task {}
    /// Every queued job still owns its recording. An earlier job's sweep must
    /// not delete audio a later job has yet to recover.
    private var recoveryRecordings = RecoveryRecordingQueue()
    /// Something went wrong during recording that the user should see, held back until the
    /// text has been inserted so it isn't overwritten by the processing state.
    private var pendingHUDError: String?

    private func enqueueCleanup(
        raw: String, hints: [Correction], options: DictationOptions,
        backup: URL?, transaction: DictationTransaction
    ) {
        recoveryRecordings.enqueue(backup)
        if let backup {
            transaction.discardRecovery = { Task { try? FileManager.default.removeItem(at: backup) } }
        }
        let previous = cleanupTail
        let task = Task { [weak self] in
            await previous.value
            transaction.timing.mark("processing_started")
            guard let self else { return }
            var raw = raw
            var recovered = false
            do {
                try transaction.checkCancellation()
                if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let backup {
                    if let text = await self.recover(backup, options.locale) {
                        raw = text
                        recovered = true
                    }
                    try transaction.checkCancellation()
                }
                let message = try await self.runCleanup(
                    raw: raw, hints: hints, options: options, recovered: recovered, transaction: transaction
                )
                if self.pendingHUDError == nil { self.pendingHUDError = message }
            } catch {
                // Cancellation is not a failed cleanup and must never insert the
                // fallback transcript, update history, or revive an old HUD.
                if !(error is CancellationError), !transaction.isCancelled {
                    Self.log.error("dictation processing failed: \(error, privacy: .public)")
                }
            }
            if !transaction.isCancelled, let recoveryStore {
                var archived: UUID?
                if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let backup, Settings.backupRecording {
                    do {
                        archived = try await recoveryStore.register(audio: backup, source: String(localized: "Untranscribed dictation"),
                                                                    locale: options.locale, kind: .dictation).id
                        if let archived {
                            transaction.discardRecovery = { Task { try? await recoveryStore.delete(archived) } }
                        }
                        self.pendingHUDError = String(localized: "Nothing recognized — audio is available in Recover Recordings")
                    } catch {
                        self.pendingHUDError = String(localized: "Nothing recognized — recovery audio could not be saved")
                    }
                }
                if transaction.isCancelled {
                    if let archived { try? await recoveryStore.delete(archived) }
                } else {
                    await recoveryStore.expireDictations(retention: Settings.backupRetention.duration, keeping: archived)
                }
            }
            if transaction.isCancelled, let backup { try? FileManager.default.removeItem(at: backup) }
            let keep = self.recoveryRecordings.complete(
                backup, failed: !transaction.isCancelled && raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                active: self.activeBackupURL
            )
            self.sweepRecovery(keep)
            transaction.finish()
            self.transactions[transaction.id] = nil
            guard !transaction.isCancelled, !self.hasCancellableWork,
                  !self.isListening, !self.isStarting else { return }
            if let message = self.pendingHUDError {
                self.pendingHUDError = nil
                self.hud.showError(message)
            } else {
                self.hud.hide()
            }
        }
        transaction.task = task
        cleanupTail = task
    }

    /// Clean, insert, and record one dictation. Returns a message to show once the queue settles.
    ///
    /// Every version the text passes through is kept as a history stage — raw, filler removed,
    /// learned corrections, and the AI polish (plus any providers that failed) — so a rewrite
    /// that went too far can be seen and recovered from Recent Dictations.
    private func runCleanup(
        raw: String, hints: [Correction], options: DictationOptions,
        recovered: Bool, transaction: DictationTransaction
    ) async throws -> String? {
        try transaction.checkCancellation()
        let chain = options.chain
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
        let correctionInput = text
        record(String(localized: "Filler removed"), "scissors", text)
        text = VocabularyStore.applySpellings(to: text, terms: options.vocabulary)
        record(String(localized: "Vocabulary spelling"), "textformat.abc", text)
        if options.learning, Settings.learningEnabled {
            text = CorrectionStore.shared.apply(to: text, recordUsage: false)
            record(String(localized: "Learned corrections"), "brain", text)
        }

        // Spoken formatting commands ("colon", "new line", ...) become literals. The user chooses
        // whether this runs and where: before the AI pass (the model capitalizes and polishes
        // around the punctuation) or after it (the model never touches the literals).
        func applyFormatting() {
            text = SpokenCommands.apply(text)
            record(String(localized: "Formatting"), "textformat", text)
        }
        if options.spokenCommands, options.formattingPosition == .beforeCleanup {
            applyFormatting()
        }

        transaction.timing.mark("local_cleanup_finished")
        var cleanupFallback = false
        if !text.isEmpty, !chain.isEmpty {
            // Each step is tried in turn; a missing key just means that step isn't the one
            // that cleans your text. Only a chain where nothing worked is worth mentioning.
            transaction.timing.mark("ai_cleanup_started")
            let input = text
            let relevantHints = CleanupPrompt.relevantHints(hints, to: text)
            let runner = runStep
            let configurations = options.cleanupConfigurations
            let result: CleanupChain.Result
            var timedOut = false
            do {
                result = try await CleanupDeadline.run(seconds: options.cleanupDeadline) {
                    await CleanupChain.run(input, chain: chain, hints: relevantHints) { input, step, hints in
                        if let runner { return try await runner(input, step, hints) }
                        guard let configuration = configurations[step] else { throw OpenAICompatibleError.missingConfig }
                        let allowedHints = Settings.learningEnabled ? hints : []
                        if step == .onDevice, let polisher = transaction.polisher {
                            return try await polisher.clean(input, hints: allowedHints)
                        }
                        return try await CleanupService.clean(input, configuration: configuration, hints: allowedHints)
                    }
                }
            } catch CleanupDeadlineError.expired {
                timedOut = true
                result = CleanupChain.Result(text: input, usedStep: nil, failed: [])
            }
            try transaction.checkCancellation()
            if result.isCancelled { throw CancellationError() }
            if timedOut {
                stages.append(.init(label: String(localized: "Cleanup deadline"), systemImage: "clock",
                                    text: "", status: .failed, changePercent: nil, failure: .timeout))
            }
            // Providers are tried in chain order: the ones that failed come before the winner.
            for step in result.failed {
                stages.append(.init(label: step.chainName, systemImage: step.systemImage, text: "",
                                    status: .failed, changePercent: nil, failure: result.failureReasons[step]))
            }
            if let used = result.usedStep {
                // Force it in even at 0% — "Apple Intelligence ran and changed nothing" is worth showing.
                record(used.chainName, used.systemImage, result.text, force: true)
            }
            text = result.text
            cleanupFallback = result.allFailed || timedOut
            transaction.timing.mark(timedOut ? "ai_cleanup_deadline" : "ai_cleanup_finished")
        }

        if options.spokenCommands, options.formattingPosition == .afterCleanup {
            applyFormatting()
        }

        try transaction.checkCancellation()
        if !text.isEmpty {
            transaction.timing.mark("insertion_wait_started")
            try await prepareInsertion()
            try transaction.checkCancellation()
            transaction.timing.mark("paste_ready")
            text = DictationSpacing.appendingSeparator(to: text)
            let result = insert(text, transaction.destination)
            transaction.timing.mark(result == .pasted ? "paste_posted" : "manual_paste_required")
            saveHistory(.init(date: Date(), stages: stages))
            recordCompleted()
            if result == .pasted {
                if options.learning, Settings.learningEnabled {
                    // Count use only when this transaction commits a paste.
                    _ = CorrectionStore.shared.apply(to: correctionInput)
                    correctionObserver.beginObserving(inserted: text, rawLength: raw.count, destination: transaction.destination)
                }
            } else {
                Self.log.error("automatic paste unavailable — left \(text.count, privacy: .public) chars on the clipboard")
                return result.message
            }
        } else {
            Self.log.notice("nothing to insert (empty transcript; raw was \(raw.count, privacy: .public) chars)")
        }
        return cleanupFallback ? String(localized: "Cleanup failed — inserted as-is") : nil
    }

    /// Transcribe the session's backup recording after the fact, for when live recognition
    /// produced nothing. Same on-device model, no network, just without the pressure of
    /// keeping up — which is why it can succeed where the live pass didn't.
    private static func recoverTranscript(from url: URL, locale: Locale?) async -> String? {
        do {
            let segments = try await FileTranscriber.transcribe(fileAt: url, locale: locale)
            let text = segments.map(\.text).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            if error is CancellationError || Task.isCancelled { return nil }
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
