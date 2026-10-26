#if os(macOS)
import Foundation
import os

/// One bounded event sequence per transaction. Numbers use a monotonic clock and
/// describe event posting, not an editor acknowledgement. Payloads never include text.
@MainActor
final class DictationTiming {
    struct Event: Sendable {
        let transaction: UUID
        let stage: String
        let fromStartMS: Double
        let fromStopMS: Double?
    }
    private static let log = Logger(subsystem: "Dictate", category: "Latency")
    let startedAt: TimeInterval
    private var stoppedAt: TimeInterval?
    private let id: UUID
    private let emit: @MainActor (Event) -> Void

    init(id: UUID, startedAt: TimeInterval = ProcessInfo.processInfo.systemUptime, emit: @escaping @MainActor (Event) -> Void = DictationTiming.logEvent) {
        self.id = id; self.emit = emit
        self.startedAt = startedAt
        mark("requested", at: startedAt)
    }
    static func logEvent(_ event: Event) {
        if let stop = event.fromStopMS {
            log.notice("transaction=\(event.transaction.uuidString, privacy: .public) stage=\(event.stage, privacy: .public) start_ms=\(event.fromStartMS, privacy: .public) stop_ms=\(stop, privacy: .public)")
        } else {
            log.notice("transaction=\(event.transaction.uuidString, privacy: .public) stage=\(event.stage, privacy: .public) start_ms=\(event.fromStartMS, privacy: .public)")
        }
    }
    func stop() {
        guard stoppedAt == nil else { return }
        stoppedAt = ProcessInfo.processInfo.systemUptime
        mark("stop_requested")
    }
    func mark(_ stage: String, at instant: TimeInterval? = nil) {
        let now = instant ?? ProcessInfo.processInfo.systemUptime
        emit(Event(transaction: id, stage: stage, fromStartMS: max(0, (now - startedAt) * 1000),
                   fromStopMS: stoppedAt.map { (now - $0) * 1000 }))
    }
}
#endif
