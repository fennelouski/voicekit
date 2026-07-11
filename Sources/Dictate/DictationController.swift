//
//  DictationController.swift
//  Dictate
//
//  Push-to-talk state machine: hold the hotkey to dictate, release to insert.
//  A quick tap (<0.35s) locks dictation on; the next tap stops and inserts.
//

#if os(macOS)
import AppKit
import VoiceKit

@available(macOS 26.0, *)
@MainActor
final class DictationController {
    var onListeningChange: ((Bool) -> Void)?

    private let service = SpeechRecognitionService()
    private let hud = HUDController()
    private var accumulator = TranscriptAccumulator()
    private let correctionObserver = CorrectionObserver()
    private var transcriptTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?

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

                transcriptTask = Task {
                    for await result in session.transcript {
                        accumulator.add(result)
                        hud.update(text: accumulator.preview)
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

            let raw = accumulator.committed.isEmpty ? accumulator.preview : accumulator.committed
            var text = TranscriptCleaner.clean(raw)
            if Settings.learningEnabled {
                text = CorrectionStore.shared.apply(to: text)
            }
            let hints = Settings.learningEnabled ? CorrectionStore.shared.promptHints(limit: 20) : []
            var cleanupFallback = false
            if !text.isEmpty {
                switch Settings.cleanupMode {
                case .off:
                    break
                case .onDevice:
                    text = await AICleanup.clean(text, hints: hints)
                case .claude:
                    do {
                        text = try await ClaudeCleanup.clean(text, hints: hints)
                    } catch {
                        // The invariant: never lose the transcript. Insert the
                        // locally cleaned text and say why.
                        cleanupFallback = true
                    }
                case .local:
                    do {
                        text = try await LocalModelCleanup.clean(text, hints: hints)
                    } catch {
                        cleanupFallback = true
                    }
                }
            }
            if !text.isEmpty {
                // Trailing space so back-to-back dictations don't run together.
                if let last = text.last, !last.isWhitespace { text += " " }
                TextInserter.insert(text)
                DictationHistory.shared.add(text)
                correctionObserver.beginObserving(inserted: text, rawLength: raw.count)
            }

            if cleanupFallback {
                hud.showError("Cleanup failed — inserted as-is")
            } else {
                hud.hide()
            }
            isListening = false
            isStopping = false
            locked = false
            onListeningChange?(false)
        }
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
