//
//  TranscriptionResult.swift
//  VoiceKit
//
//  A single recognized transcript segment: text, finality flag, and optional confidence.
//

import Foundation

/// A recognized transcript segment emitted by a transcription provider.
public struct TranscriptionResult: Sendable {
    /// Cumulative transcript text for the current utterance.
    public let text: String
    /// True when the recognizer has committed this result.
    public let isFinal: Bool
    /// Recognition confidence (0...1), if available. Nil for providers that don't report confidence.
    public let confidence: Float?

    public init(text: String, isFinal: Bool, confidence: Float? = nil) {
        self.text = text
        self.isFinal = isFinal
        self.confidence = confidence
    }
}

/// Backward-compatible typealias for code migrating from SpeechService.
@available(*, deprecated, renamed: "TranscriptionResult")
public typealias TranscriptSegment = TranscriptionResult
