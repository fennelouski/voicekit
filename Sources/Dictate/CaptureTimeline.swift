#if os(macOS)
import Foundation
import AVFoundation
import Synchronization

/// File time advances with written samples; wall time can contain capture gaps.
/// Map each recognized file timestamp through the actual captured spans.
struct CaptureTimeline: Codable, Equatable, Sendable {
    struct Span: Codable, Equatable, Sendable {
        var offset: TimeInterval
        var duration: TimeInterval
        let capturedAt: Date
    }
    private(set) var spans: [Span] = []
    private(set) var duration: TimeInterval = 0

    mutating func append(frames: UInt32, sampleRate: Double, capturedAt: Date) {
        guard frames > 0, sampleRate > 0, sampleRate.isFinite else { return }
        let length = Double(frames) / sampleRate
        if let last = spans.last,
           abs(capturedAt.timeIntervalSince(last.capturedAt) - last.duration) < 0.1 {
            spans[spans.count - 1].duration += length
        } else {
            spans.append(Span(offset: duration, duration: length, capturedAt: capturedAt))
        }
        duration += length
    }

    func date(at offset: TimeInterval) -> Date? {
        guard let first = spans.first else { return nil }
        let value = max(0, offset.isFinite ? offset : 0)
        let span = spans.last(where: { $0.offset <= value }) ?? first
        return span.capturedAt.addingTimeInterval(min(span.duration, max(0, value - span.offset)))
    }
}

/// A monotonic watchdog: sleep/main-loop stalls rebase delivery evidence, and
/// recovery attempts are bounded across an entire session, not just failures.
struct CaptureWatchdog {
    var stall: TimeInterval = 2.5
    var maximumRestarts = 3
    private var lastTick: TimeInterval?
    private var restarts = 0
    private var wakeUntil: TimeInterval = 0

    mutating func shouldRestart(now: TimeInterval, silence: TimeInterval) -> Bool {
        defer { lastTick = now }
        if let lastTick, now - lastTick > 5 { wakeUntil = now + stall; return false }
        guard now >= wakeUntil else { return false }
        guard silence > stall, restarts < maximumRestarts else { return false }
        restarts += 1
        return true
    }
    var exhausted: Bool { restarts >= maximumRestarts && (lastTick ?? 0) >= wakeUntil }
}
/// Only mutex-protected monotonic times cross the audio callback/main-actor boundary.
final class CaptureDeliveryClock: Sendable {
    private let last = Mutex<TimeInterval>(ProcessInfo.processInfo.systemUptime)
    func reset() { beat() }
    func beat() { last.withLock { $0 = ProcessInfo.processInfo.systemUptime } }
    var silence: TimeInterval { last.withLock { max(0, ProcessInfo.processInfo.systemUptime - $0) } }
}
#endif
