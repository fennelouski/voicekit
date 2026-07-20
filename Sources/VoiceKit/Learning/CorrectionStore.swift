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

    /// One learned pair's lifetime history: how often the user has manually made this
    /// edit, versus how often Dictate has since made it for them automatically. An
    /// audit trail, separate from `pairs`' net count that drives the apply threshold.
    public struct HistoryEntry: Sendable {
        public let correction: Correction
        public let manualCount: Int
        public let autoCount: Int
        /// Currently at or above the apply threshold — actively auto-corrected.
        public let isActive: Bool
    }

    private struct Stats: Codable {
        var manual: Int = 0
        var auto: Int = 0
    }

    private let fileURL: URL
    private let statsFileURL: URL
    /// [heard.lowercased(): [corrected: count]]
    private var pairs: [String: [String: Int]]
    /// [heard.lowercased(): [corrected: Stats]], append-only — never decremented by unlearning.
    private var stats: [String: [String: Stats]]

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.statsFileURL = fileURL.deletingLastPathComponent().appendingPathComponent("correction-stats.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: [String: Int]].self, from: data) {
            pairs = decoded
        } else {
            pairs = [:]
        }
        if let data = try? Data(contentsOf: statsFileURL),
           let decoded = try? JSONDecoder().decode([String: [String: Stats]].self, from: data) {
            stats = decoded
        } else {
            stats = [:]
        }
    }

    /// Record observed corrections. Recording the reverse of a learned pair
    /// (the user undid an applied correction) decrements it instead,
    /// removing it entirely at zero.
    public func record(_ corrections: [Correction]) {
        guard !corrections.isEmpty else { return }
        for correction in corrections {
            stats[correction.heard.lowercased(), default: [:]][correction.corrected, default: Stats()].manual += 1
            let reverseKey = correction.corrected.lowercased()
            if var bucket = pairs[reverseKey], let count = bucket[correction.heard] {
                bucket[correction.heard] = count <= 1 ? nil : count - 1
                pairs[reverseKey] = bucket.isEmpty ? nil : bucket
            } else {
                pairs[correction.heard.lowercased(), default: [:]][correction.corrected, default: 0] += 1
            }
        }
        save()
        saveStats()
    }

    /// Every correction ever observed, most-used first — for the Learning settings pane,
    /// not the apply path. Shows manual edits and automatic applications separately so
    /// it's clear which corrections are actually helping.
    public func history() -> [HistoryEntry] {
        stats.flatMap { heard, bucket in
            bucket.map { corrected, s in
                HistoryEntry(
                    correction: Correction(heard: heard, corrected: corrected),
                    manualCount: s.manual, autoCount: s.auto,
                    isActive: (pairs[heard]?[corrected] ?? 0) >= Self.applyThreshold
                )
            }
        }.sorted { ($0.manualCount + $0.autoCount) > ($1.manualCount + $1.autoCount) }
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
        var appliedAny = false
        for pair in active {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: pair.heard) + "\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.numberOfMatches(in: result, range: range)
            guard matches > 0 else { continue }
            result = regex.stringByReplacingMatches(
                in: result, range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: pair.corrected)
            )
            // pair.heard is already lowercased — it's the countedActivePairs dictionary key.
            stats[pair.heard, default: [:]][pair.corrected, default: Stats()].auto += matches
            appliedAny = true
        }
        if appliedAny { saveStats() }
        return result
    }

    /// Top learned pairs (count ≥ threshold) for cleanup-prompt injection.
    public func promptHints(limit: Int) -> [Correction] {
        countedActivePairs()
            .sorted { $0.count > $1.count }
            .prefix(limit)
            .map(\.correction)
    }

    /// Delete everything learned, including the manual/automatic history.
    public func reset() {
        pairs = [:]
        stats = [:]
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: statsFileURL)
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

    private func saveStats() {
        try? FileManager.default.createDirectory(
            at: statsFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(stats) {
            try? data.write(to: statsFileURL, options: .atomic)
        }
    }
}
