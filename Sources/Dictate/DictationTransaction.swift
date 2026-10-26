#if os(macOS)
import Foundation
import VoiceKit

/// Identity and cancellation outlive the microphone and follow queued work.
/// A late provider result cannot revive a cancelled transaction.
@MainActor
@available(macOS 26.0, *)
final class DictationTransaction {
    let id = UUID()
    let timing: DictationTiming
    var polisher: AICleanup.PreparedSession?
    let destination: InsertionDestination?
    private(set) var isCancelled = false
    var task: Task<Void, Never>?
    var discardTranscript: (() -> Void)?
    var discardRecovery: (() -> Void)?

    init(destination: InsertionDestination?, requestedAt: TimeInterval = ProcessInfo.processInfo.systemUptime, timingSink: @escaping @MainActor (DictationTiming.Event) -> Void = DictationTiming.logEvent) {
        self.destination = destination
        timing = DictationTiming(id: id, startedAt: requestedAt, emit: timingSink)
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        timing.mark("cancelled")
        task?.cancel()
        discardTranscript?()
        discardRecovery?()
    }

    func checkCancellation() throws {
        if isCancelled { throw CancellationError() }
        try Task.checkCancellation()
    }

    func finish() {
        polisher = nil
        task = nil
        discardTranscript = nil
        discardRecovery = nil
    }
}
#endif
