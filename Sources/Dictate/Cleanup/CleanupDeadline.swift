#if os(macOS)
import Foundation

enum CleanupDeadlineError: Error { case expired }

/// Return at the deadline even if a model ignores cancellation. Only the
/// returned value can commit; the late operation owns no insertion side effects.
enum CleanupDeadline {
    static func run<Value: Sendable>(
        seconds: TimeInterval, operation: @escaping @MainActor @Sendable () async throws -> Value
    ) async throws -> Value {
        let race = DeadlineRace<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                Task { await race.start(continuation, seconds: seconds, operation: operation) }
            }
        } onCancel: { Task { await race.cancel() } }
    }
}

private actor DeadlineRace<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Error>?
    private var work: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var cancelled = false

    func start(_ continuation: CheckedContinuation<Value, Error>, seconds: TimeInterval,
               operation: @escaping @MainActor @Sendable () async throws -> Value) {
        guard !cancelled else { continuation.resume(throwing: CancellationError()); return }
        self.continuation = continuation
        work = Task {
            do { complete(.success(try await operation())) }
            catch { complete(.failure(error)) }
        }
        timer = Task {
            do {
                try await Task.sleep(for: .seconds(max(0, seconds)))
                complete(.failure(CleanupDeadlineError.expired))
            } catch { /* successful work cancelled the timer */ }
        }
    }

    func cancel() {
        cancelled = true
        complete(.failure(CancellationError()))
    }

    private func complete(_ result: Result<Value, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        work?.cancel()
        timer?.cancel()
        work = nil
        timer = nil
        continuation.resume(with: result)
    }
}
#endif
