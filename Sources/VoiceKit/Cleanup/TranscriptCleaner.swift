//
//  TranscriptCleaner.swift
//  VoiceKit
//
//  Removes filler words from dictated text and repairs capitalization
//  where a removal exposed a new sentence start.
//

import Foundation
import NaturalLanguage

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
        guard !duplicatesTranscript(original: original, cleaned: cleaned) else { return false }
        let cleanedWords = Set(wordBag(cleaned))
        guard !cleanedWords.isEmpty else { return false }
        // Cleanup trims filler and repairs punctuation; it never balloons the text. A refusal or
        // an answer, on the other hand, expands a short transcript into paragraphs.
        if cleaned.count > original.count * 2 + 40 { return false }
        // Most distinct cleaned words must be words the user actually said.
        let shared = cleanedWords.intersection(wordBag(original)).count
        return Double(shared) / Double(cleanedWords.count) >= 0.5
    }

    /// A model can echo the entire cleanup twice and still pass a word-overlap
    /// check. Reject an exact doubled answer unless the speaker also repeated it.
    private static func duplicatesTranscript(original: String, cleaned: String) -> Bool {
        let labels: Set<String> = ["cleaned transcript:", "**cleaned transcript:**", "**cleaned transcript**:"]
        let content = cleaned.components(separatedBy: .newlines).filter {
            !labels.contains($0.trimmingCharacters(in: .whitespaces).lowercased())
        }.joined(separator: "\n")
        let output = words(content)
        guard output.count.isMultiple(of: 2), output.count >= 12 else { return false }
        let half = output.count / 2
        let copy = Array(output.prefix(half))
        guard copy == Array(output.suffix(half)) else { return false }

        // Adjacent stutters should not count as intentionally dictating it twice.
        let input = words(original)
        var counts: [String: Int] = [:]
        for (index, word) in input.enumerated() where index == 0 || word != input[index - 1] {
            counts[word, default: 0] += 1
        }
        var repeated = 0
        for word in copy where counts[word, default: 0] >= 2 {
            counts[word, default: 0] -= 2
            repeated += 1
        }
        return repeated * 2 <= half
    }

    /// Lowercased word tokens with apostrophes folded, so "What's" matches "whats".
    private static func wordBag(_ s: String) -> Set<String> {
        Set(words(s))
    }

    private static func words(_ text: String) -> [String] {
        let normalized = text.precomposedStringWithCompatibilityMapping.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = normalized
        var result: [String] = []
        tokenizer.enumerateTokens(in: normalized.startIndex..<normalized.endIndex) { range, _ in
            let token = String(normalized[range])
            if token.rangeOfCharacter(from: .alphanumerics) != nil { result.append(token) }
            return true
        }
        return result
    }
}
