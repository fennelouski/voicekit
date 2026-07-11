//
//  TranscriptAccumulator.swift
//  VoiceKit
//
//  Folds a stream of TranscriptionResult values into a single transcript:
//  finals accumulate, the latest volatile hypothesis overlays for preview.
//

import Foundation

/// Accumulates `TranscriptionResult` values from a transcription stream.
///
/// Volatile (non-final) results replace the previous volatile hypothesis;
/// final results are appended to `committed`. Use `preview` for live UI and
/// `committed` for the final transcript after the stream ends.
public struct TranscriptAccumulator: Sendable {
    /// Text the recognizer has committed.
    public private(set) var committed: String = ""
    /// The current volatile (not yet committed) hypothesis.
    public private(set) var volatileText: String = ""

    public init() {}

    /// Fold one result into the accumulator.
    public mutating func add(_ result: TranscriptionResult) {
        if result.isFinal {
            committed = Self.join(committed, result.text)
            volatileText = ""
        } else {
            volatileText = result.text
        }
    }

    /// Committed text plus the current volatile hypothesis — for live preview.
    public var preview: String { Self.join(committed, volatileText) }

    /// Clear all accumulated text.
    public mutating func reset() {
        committed = ""
        volatileText = ""
    }

    private static func join(_ a: String, _ b: String) -> String {
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        if a.last!.isWhitespace || b.first!.isWhitespace { return a + b }
        return a + " " + b
    }
}
