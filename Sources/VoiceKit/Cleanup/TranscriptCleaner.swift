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

    /// Whether `cleaned` is a plausible cleanup of `original` rather than a replacement.
    ///
    /// A cleanup pass fixes punctuation and filler; it must not rewrite. When the model instead
    /// answers a dictated question, refuses it, or hallucinates, its output shares few words with
    /// what the user said and often balloons in length. This returns false for those cases so the
    /// caller keeps the user's transcript instead of pasting words they never spoke.
    ///
    /// Lenient toward real cleanups (which keep nearly every input word) and strict against
    /// replacements (a refusal or answer reuses few of them).
    public static func preservesWording(original: String, cleaned: String) -> Bool {
        let cleanedWords = Set(wordBag(cleaned))
        guard !cleanedWords.isEmpty else { return false }
        // Cleanup trims filler and repairs punctuation; it never balloons the text. A refusal or
        // an answer, on the other hand, expands a short transcript into paragraphs.
        if cleaned.count > original.count * 2 + 40 { return false }
        // Most distinct cleaned words must be words the user actually said.
        let shared = cleanedWords.intersection(wordBag(original)).count
        return Double(shared) / Double(cleanedWords.count) >= 0.5
    }

    /// Lowercased word tokens with apostrophes folded, so "What's" matches "whats".
    private static func wordBag(_ s: String) -> Set<String> {
        Set(
            s.lowercased()
                .replacingOccurrences(of: "'", with: "")
                .replacingOccurrences(of: "\u{2019}", with: "")
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
    }
}
