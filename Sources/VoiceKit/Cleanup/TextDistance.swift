//
//  TextDistance.swift
//  VoiceKit
//
//  How much one version of a transcript differs from the next. Word-level rather
//  than character-level: "the AI changed ~12 words" is the signal a user wants,
//  and it's cheap enough to run on every cleanup stage instantly.
//

import Foundation

public enum TextDistance {
    /// Word-level Levenshtein distance: the number of word insertions, deletions, and
    /// substitutions to turn `a` into `b`. O(n·m) over word counts — a few milliseconds even
    /// for a long dictation.
    public static func wordEdits(_ a: String, _ b: String) -> Int {
        edits(words(a), words(b))
    }

    /// Roughly what fraction of the words changed from `original` to `revised`, 0…100.
    /// Normalised by the longer of the two so inserts and deletes both count.
    public static func changePercent(from original: String, to revised: String) -> Int {
        let wa = words(original), wb = words(revised)
        let denominator = max(wa.count, wb.count)
        guard denominator > 0 else { return 0 }
        return Int((Double(edits(wa, wb)) / Double(denominator) * 100).rounded())
    }

    static func words(_ s: String) -> [String] {
        s.split(whereSeparator: \.isWhitespace).map { String($0) }
    }

    /// Levenshtein over two token arrays, two rolling rows.
    static func edits(_ a: [String], _ b: [String]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1,        // deletion
                    current[j - 1] + 1,     // insertion
                    previous[j - 1] + cost  // substitution
                )
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
