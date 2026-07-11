//
//  TranscriptCleaner.swift
//  VoiceKit
//
//  Removes filler words from dictated text and repairs capitalization
//  where a removal exposed a new sentence start.
//

import Foundation

/// Cleans dictated transcripts: strips filler words ("um", "uh", ...),
/// collapses whitespace, and re-capitalizes sentence starts exposed by a removal.
public enum TranscriptCleaner {
    /// Default filler words. Matches `PositionMapper.Configuration`.
    public static let defaultFillerWords: Set<String> = ["um", "uh", "er", "ah", "hm", "hmm", "mm"]

    /// Returns `text` with filler words removed and whitespace collapsed.
    /// A token is a filler if it equals a filler word after stripping surrounding
    /// punctuation, case-insensitively — so "Um," and "uh…" are removed,
    /// but "umbrella" is not.
    public static func clean(_ text: String, fillerWords: Set<String> = defaultFillerWords) -> String {
        var kept: [String] = []
        var atSentenceStart = true
        var removedAtSentenceStart = false

        for token in text.split(whereSeparator: \.isWhitespace) {
            var word = String(token)
            let core = word.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)

            if !core.isEmpty, fillerWords.contains(core.lowercased()) {
                if atSentenceStart { removedAtSentenceStart = true }
                continue
            }

            if removedAtSentenceStart {
                word = word.prefix(1).uppercased() + word.dropFirst()
                removedAtSentenceStart = false
            }
            kept.append(word)
            atSentenceStart = word.hasSuffix(".") || word.hasSuffix("!") || word.hasSuffix("?") || word.hasSuffix("…")
        }

        return kept.joined(separator: " ")
    }
}
