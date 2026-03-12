//
//  MockTranscriptionProvider.swift
//  VoiceKit
//
//  A controllable transcription provider for testing without audio hardware.
//

import Foundation

/// A mock transcription provider that yields controlled segments for testing.
///
/// Use this in unit tests or SwiftUI previews to simulate speech recognition
/// without requiring microphone access or audio hardware.
///
/// ```swift
/// let mock = MockTranscriptionProvider()
/// let stream = try await mock.startTranscription(locale: nil)
///
/// // Feed segments from another task
/// Task {
///     await mock.yield(TranscriptionResult(text: "Hello world", isFinal: false))
///     await mock.yield(TranscriptionResult(text: "Hello world", isFinal: true))
///     await mock.finish()
/// }
///
/// for await result in stream {
///     print(result.text)
/// }
/// ```
public actor MockTranscriptionProvider: TranscriptionProvider {
    private var continuation: AsyncStream<TranscriptionResult>.Continuation?
    private var isActive: Bool = false

    public init() {}

    /// Start a mock transcription session. Feed segments via `yield(_:)`.
    public func startTranscription(locale: Locale?) async throws -> AsyncStream<TranscriptionResult> {
        let stream = AsyncStream<TranscriptionResult> { continuation in
            self.continuation = continuation
        }
        isActive = true
        return stream
    }

    /// Stop the mock session and finish the stream.
    public func stopTranscription() async {
        finish()
    }

    /// Yield a transcript result to the consumer.
    public func yield(_ result: TranscriptionResult) {
        continuation?.yield(result)
    }

    /// Finish the stream (signals end of transcription).
    public func finish() {
        continuation?.finish()
        continuation = nil
        isActive = false
    }

    /// Whether a transcription session is currently active.
    public var active: Bool { isActive }
}
