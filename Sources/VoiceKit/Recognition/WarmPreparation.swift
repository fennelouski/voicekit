import Foundation

/// Coalesces preparation until a recording claims it. Claimed resources are never
/// cancelled by a later warm-up or language change. All access is actor isolated.
actor WarmPreparation<Value: Sendable> {
    private var pending: (key: String, task: Task<Value, Error>)?

    func warm(key: String, make: @escaping @Sendable () async throws -> Value) -> Task<Value, Error> {
        if let pending, pending.key == key { return pending.task }
        pending?.task.cancel()
        let task = Task { try await make() }
        pending = (key, task)
        return task
    }

    func take(key: String, make: @escaping @Sendable () async throws -> Value) -> Task<Value, Error> {
        let task = warm(key: key, make: make)
        pending = nil
        return task
    }

    func invalidate() { pending?.task.cancel(); pending = nil }
}
