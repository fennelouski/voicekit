//
//  CorrectionExtractor.swift
//  VoiceKit
//
//  Word-level diff between the text that was inserted and the text the user
//  left behind, yielding (heard → corrected) pairs for the learning loop.
//

import Foundation

/// A single learned substitution: recognition produced `heard`,
/// the user changed it to `corrected`.
public struct Correction: Codable, Equatable, Hashable, Sendable {
    public let heard: String
    public let corrected: String

    public init(heard: String, corrected: String) {
        self.heard = heard
        self.corrected = corrected
    }
}

/// Extracts correction pairs by diffing a text-field snapshot taken right
/// after insertion against one taken after the user has edited.
public enum CorrectionExtractor {
    /// Maximum words per side of a learned phrase.
    public static let maxPhraseWords = 4

    /// - Parameters:
    ///   - inserted: The text that was inserted; corrections must come from it.
    ///   - before: Full field value right after insertion.
    ///   - after: Full field value once the user has edited.
    public static func extract(inserted: String, before: String, after: String) -> [Correction] {
        guard !inserted.isEmpty, before != after else { return [] }
        let insertedWords = tokenize(inserted)
        guard !insertedWords.isEmpty else { return [] }
        let beforeWords = tokenize(before)
        let afterWords = tokenize(after)

        var removed = Set<Int>()
        var added = Set<Int>()
        for change in afterWords.difference(from: beforeWords) {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): added.insert(offset)
            }
        }

        // Walk both token lists, grouping each contiguous removed+added run
        // into one (old phrase → new phrase) replacement.
        var corrections: [Correction] = []
        var changedWords = 0
        var b = 0
        var a = 0
        while b < beforeWords.count || a < afterWords.count {
            let bChanged = b < beforeWords.count && removed.contains(b)
            let aChanged = a < afterWords.count && added.contains(a)
            if !bChanged && !aChanged {
                b += 1
                a += 1
                continue
            }
            var old: [String] = []
            var new: [String] = []
            while b < beforeWords.count, removed.contains(b) {
                old.append(beforeWords[b])
                b += 1
            }
            while a < afterWords.count, added.contains(a) {
                new.append(afterWords[a])
                a += 1
            }
            guard !old.isEmpty, !new.isEmpty,             // pure insert/delete isn't a correction
                  old.count <= maxPhraseWords, new.count <= maxPhraseWords,
                  old != new,
                  containsRun(insertedWords, old)          // the edit must touch what we inserted
            else { continue }
            changedWords += old.count
            corrections.append(Correction(heard: old.joined(separator: " "), corrected: new.joined(separator: " ")))
        }

        // Most of the inserted text changed: that's a rewrite, not corrections.
        guard changedWords * 2 <= insertedWords.count else { return [] }
        return corrections
    }

    /// Whitespace-split tokens with surrounding punctuation stripped,
    /// so "Kubernetes," pairs with "Kubernetes".
    private static func tokenize(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).compactMap { token in
            let core = token.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            return core.isEmpty ? nil : core
        }
    }

    private static func containsRun(_ words: [String], _ run: [String]) -> Bool {
        guard !run.isEmpty, run.count <= words.count else { return false }
        for start in 0...(words.count - run.count) where Array(words[start..<(start + run.count)]) == run {
            return true
        }
        return false
    }
}
