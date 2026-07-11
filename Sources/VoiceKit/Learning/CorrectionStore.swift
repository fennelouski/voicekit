//
//  CorrectionStore.swift
//  VoiceKit
//
//  Persisted (heard → corrected) pairs with counts. A pair seen twice is
//  applied to future transcripts; recording the reverse pair unlearns it.
//

import Foundation

/// On-disk store for learned corrections, keyed case-insensitively by the
/// misheard phrase. Backed by a small JSON file; use from one actor or
/// thread at a time (Dictate uses it from the main actor).
public final class CorrectionStore {
    /// A pair is auto-applied once it has been observed this many times.
    public static let applyThreshold = 2

    private let fileURL: URL
    /// [heard.lowercased(): [corrected: count]]
    private var pairs: [String: [String: Int]]

    public init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: [String: Int]].self, from: data) {
            pairs = decoded
        } else {
            pairs = [:]
        }
    }

    /// Record observed corrections. Recording the reverse of a learned pair
    /// (the user undid an applied correction) decrements it instead,
    /// removing it entirely at zero.
    public func record(_ corrections: [Correction]) {
        guard !corrections.isEmpty else { return }
        for correction in corrections {
            let reverseKey = correction.corrected.lowercased()
            if var bucket = pairs[reverseKey], let count = bucket[correction.heard] {
                bucket[correction.heard] = count <= 1 ? nil : count - 1
                pairs[reverseKey] = bucket.isEmpty ? nil : bucket
            } else {
                pairs[correction.heard.lowercased(), default: [:]][correction.corrected, default: 0] += 1
            }
        }
        save()
    }

    /// Replace learned phrases (count ≥ threshold) in `text`: whole words,
    /// case-insensitive, longest phrases first, learned casing preserved.
    public func apply(to text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = text
        let active = countedActivePairs().map(\.correction).sorted {
            ($0.heard.split(separator: " ").count, $0.heard.count)
                > ($1.heard.split(separator: " ").count, $1.heard.count)
        }
        for pair in active {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: pair.heard) + "\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: NSRegularExpression.escapedTemplate(for: pair.corrected)
            )
        }
        return result
    }

    /// Top learned pairs (count ≥ threshold) for cleanup-prompt injection.
    public func promptHints(limit: Int) -> [Correction] {
        countedActivePairs()
            .sorted { $0.count > $1.count }
            .prefix(limit)
            .map(\.correction)
    }

    /// Delete everything learned.
    public func reset() {
        pairs = [:]
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Private

    /// Best replacement per misheard phrase, at or above the apply threshold.
    private func countedActivePairs() -> [(correction: Correction, count: Int)] {
        pairs.compactMap { heard, bucket in
            guard let best = bucket.max(by: { $0.value < $1.value }),
                  best.value >= Self.applyThreshold else { return nil }
            return (Correction(heard: heard, corrected: best.key), best.value)
        }
    }

    private func save() {
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(pairs) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
