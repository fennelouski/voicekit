#if os(macOS)
import Foundation

/// Identity and cancellation outlive the microphone and follow queued work.
/// A late provider result cannot revive a cancelled transaction.
@MainActor
final class DictationTransaction {
    let id = UUID()
    let destination: InsertionDestination?
    private(set) var isCancelled = false
    var task: Task<Void, Never>?
    var discardTranscript: (() -> Void)?
    var discardRecovery: (() -> Void)?

    init(destination: InsertionDestination?) { self.destination = destination }

    func cancel() {
        isCancelled = true
        task?.cancel()
        discardTranscript?()
        discardRecovery?()
    }

    func checkCancellation() throws {
        if isCancelled { throw CancellationError() }
        try Task.checkCancellation()
    }

    func finish() {
        task = nil
        discardTranscript = nil
        discardRecovery = nil
    }
}
#endif
