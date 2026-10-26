import Foundation
import os

/// Local monotonic timings only: no audio, text, application identity, or credentials.
/// Safe to update from the audio callback and snapshot after recognition finishes.
public final class RecognitionMetrics: Sendable {
    public struct Snapshot: Sendable {
        public var engineStartedAt: TimeInterval?
        public var firstBufferAt: TimeInterval?
        public var analyzerReadyAt: TimeInterval?
        public var finalResultAt: TimeInterval?
        public var usedWarmPreparation = false
        public var pipelineFailed = false
    }
    private let state = OSAllocatedUnfairLock(initialState: Snapshot())
    public init() {}
    public var snapshot: Snapshot { state.withLock { $0 } }
    func engineStarted() { state.withLock { $0.engineStartedAt = ProcessInfo.processInfo.systemUptime } }
    func audioArrived() { state.withLock { if $0.firstBufferAt == nil { $0.firstBufferAt = ProcessInfo.processInfo.systemUptime } } }
    func analyzerReady() { state.withLock { $0.analyzerReadyAt = ProcessInfo.processInfo.systemUptime } }
    func finalResult() { state.withLock { $0.finalResultAt = ProcessInfo.processInfo.systemUptime } }
    func warm(_ value: Bool) { state.withLock { $0.usedWarmPreparation = value } }
    func fail() { state.withLock { $0.pipelineFailed = true } }
}
