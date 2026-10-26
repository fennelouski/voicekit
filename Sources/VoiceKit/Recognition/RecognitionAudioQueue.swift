@preconcurrency import AVFoundation
import Foundation

/// Bounded FIFO used both during cold preparation and live analysis. AVAudioEngine
/// owns its callback buffer, so only copied samples may cross this boundary.
struct RecognitionAudioQueue: Sendable {
    let stream: AsyncThrowingStream<CapturedAudioBuffer, Error>
    let continuation: AsyncThrowingStream<CapturedAudioBuffer, Error>.Continuation
    init(capacity: Int = 512) {
        (stream, continuation) = AsyncThrowingStream.makeStream(bufferingPolicy: .bufferingOldest(capacity))
    }
    func append(_ packet: CapturedAudioBuffer) -> Bool {
        switch continuation.yield(packet) {
        case .enqueued: return true
        case .dropped:
            continuation.finish(throwing: RecognitionError.recognitionUnavailable)
            return false
        case .terminated: return false
        @unknown default: return false
        }
    }
}
