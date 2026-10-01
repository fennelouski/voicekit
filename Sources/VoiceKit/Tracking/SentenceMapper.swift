//
//  SentenceMapper.swift
//  VoiceKit
//
//  Utility for detecting sentence boundaries in scripts using Foundation.
//  Provides navigation to previous/next sentence starts for keyboard controls.
//

import Foundation

/// Maps character positions to sentence boundaries in a script.
public final class SentenceMapper {
    private let text: String
    private var sentenceRanges: [Range<String.Index>] = []

    public init(text: String) {
        self.text = text
        detectSentences()
    }

    /// Foundation's sentence enumeration supports sentence ranges without word token filtering.
    private func detectSentences() {
        guard !text.isEmpty else { return }

        var ranges: [Range<String.Index>] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.bySentences, .substringNotRequired]) { _, range, _, _ in
            ranges.append(range)
        }

        sentenceRanges = ranges
    }

    /// Returns the character offset of the previous sentence start, or nil if at beginning.
    /// - Parameter currentPosition: Current character offset in the text.
    public func previousSentenceStart(from currentPosition: Int) -> Int? {
        guard !sentenceRanges.isEmpty else { return nil }

        // Find the sentence containing or after the current position
        for (index, range) in sentenceRanges.enumerated() {
            let startOffset = text.distance(from: text.startIndex, to: range.lowerBound)

            // If we're beyond the start of this sentence, look for the previous one
            if currentPosition > startOffset {
                continue
            }

            // Go to previous sentence if available
            if index > 0 {
                let prevRange = sentenceRanges[index - 1]
                return text.distance(from: text.startIndex, to: prevRange.lowerBound)
            }

            return nil
        }

        // We're past all detected sentences, go to last sentence
        if let lastRange = sentenceRanges.last {
            return text.distance(from: text.startIndex, to: lastRange.lowerBound)
        }

        return nil
    }

    /// Returns the character offset of the next sentence start, or nil if at end.
    /// - Parameter currentPosition: Current character offset in the text.
    public func nextSentenceStart(from currentPosition: Int) -> Int? {
        guard !sentenceRanges.isEmpty else { return nil }

        // Find the first sentence that starts after current position
        for range in sentenceRanges {
            let startOffset = text.distance(from: text.startIndex, to: range.lowerBound)

            if startOffset > currentPosition {
                return startOffset
            }
        }

        return nil
    }
}
