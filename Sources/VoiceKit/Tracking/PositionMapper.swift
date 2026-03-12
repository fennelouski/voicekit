//
//  PositionMapper.swift
//  VoiceKit
//
//  Maps recognized words to script position using scored candidate matching.
//  Uses an inverted index and context-aware scoring to disambiguate repeated words,
//  tolerate filler words, and recover from sync loss.
//

import Foundation

/// Maps a stream of transcript segments to character positions in the script.
/// Pause-on-pause: when no new words for threshold, position is held; resumes when speech continues.
public actor PositionMapper {
    // MARK: - Configuration

    public struct Configuration: Sendable, Codable {
        public var recentMatchesCapacity: Int
        public var forwardWindow: Int
        public var backWindow: Int
        public var skipAheadThreshold: Int
        public var minimumScoreThreshold: Double
        public var backwardJumpThreshold: Double
        public var fillerWords: Set<String>

        public var coldStartScoreThreshold: Double { minimumScoreThreshold / 3.0 }

        public init(
            recentMatchesCapacity: Int = 8,
            forwardWindow: Int = 30,
            backWindow: Int = 20,
            skipAheadThreshold: Int = 12,
            minimumScoreThreshold: Double = 1.5,
            backwardJumpThreshold: Double = 5.0,
            fillerWords: Set<String> = ["um", "uh", "er", "ah", "hm", "hmm", "mm"]
        ) {
            self.recentMatchesCapacity = recentMatchesCapacity
            self.forwardWindow = forwardWindow
            self.backWindow = backWindow
            self.skipAheadThreshold = skipAheadThreshold
            self.minimumScoreThreshold = minimumScoreThreshold
            self.backwardJumpThreshold = backwardJumpThreshold
            self.fillerWords = fillerWords
        }
    }

    /// Sendable word entry replacing the tuple type for cross-isolation access.
    public struct ScriptWord: Sendable {
        public let word: String
        public let startIndex: Int

        public init(word: String, startIndex: Int) {
            self.word = word
            self.startIndex = startIndex
        }
    }

    private let config: Configuration

    // MARK: - Script Data

    private let pauseThresholdSeconds: TimeInterval
    private let scriptText: String
    private let scriptWords: [ScriptWord]
    private let wordEndIndices: [Int]

    /// Inverted index: normalized word -> sorted positions in scriptWords array
    private let wordIndex: [String: [Int]]

    // MARK: - Matching State

    private var currentWordIndex: Int = 0
    private var lastWordTime: TimeInterval = 0
    private var isPausedDueToSilence: Bool = false
    private var lastProcessedWords: [String] = []

    /// Ring buffer of last N matched script word indices
    private var recentMatches: [Int] = []
    private var recentMatchesHead: Int = 0

    /// Count of consecutive words that failed to match
    private var consecutiveUnmatched: Int = 0

    // MARK: - Init

    public init(scriptText: String, pauseThresholdSeconds: TimeInterval = 1.0, configuration: Configuration = Configuration()) {
        self.scriptText = scriptText
        self.pauseThresholdSeconds = pauseThresholdSeconds
        self.config = configuration
        self.lastWordTime = ProcessInfo.processInfo.systemUptime

        let tupleWords = Self.extractWordsWithIndices(scriptText)
        let words = tupleWords.map { ScriptWord(word: $0.word, startIndex: $0.startIndex) }
        self.scriptWords = words
        self.wordEndIndices = words.map { $0.startIndex + $0.word.count }

        // Build inverted index
        var index: [String: [Int]] = [:]
        for (i, entry) in words.enumerated() {
            index[entry.word, default: []].append(i)
        }
        self.wordIndex = index
    }

    // MARK: - Public API

    /// Reset position to start (e.g. when starting a new session).
    public func reset() {
        currentWordIndex = 0
        lastWordTime = ProcessInfo.processInfo.systemUptime
        isPausedDueToSilence = false
        lastProcessedWords = []
        recentMatches = []
        recentMatchesHead = 0
        consecutiveUnmatched = 0
    }

    /// Resync the conservative matcher to a new character position (e.g. after skip-ahead).
    /// Clears recent context so the matcher restarts in cold-start mode at the new position.
    public func jumpTo(characterPosition: Int) {
        let newWordIndex = wordIndexForCharPosition(characterPosition)
        guard newWordIndex > currentWordIndex else { return }
        currentWordIndex = newWordIndex
        recentMatches = []
        recentMatchesHead = 0
        consecutiveUnmatched = 0
        lastProcessedWords = []
    }

    /// Process a transcript segment and return the new character position, if advanced.
    /// Handles cumulative transcripts: only processes words that are new since last segment.
    /// - Parameters:
    ///   - segment: The transcript text to process.
    ///   - timestamp: A monotonic timestamp (e.g. `ProcessInfo.processInfo.systemUptime` or `CACurrentMediaTime()`).
    /// - Returns: New character position if the match advanced, nil otherwise.
    public func processSegment(_ segment: String, timestamp: CFTimeInterval) -> Int? {
        let words = Self.normalizeForMatching(segment).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return nil }

        lastWordTime = timestamp
        isPausedDueToSilence = false

        // Common-prefix detection for transcript revisions
        let newWords: [String]
        let commonPrefixLength = zip(words, lastProcessedWords).prefix(while: { $0 == $1 }).count

        if words.count > commonPrefixLength {
            newWords = Array(words[commonPrefixLength...])
        } else {
            // Revision shortened or unchanged — nothing new to process
            lastProcessedWords = words
            return nil
        }
        lastProcessedWords = words

        let maxAdvancePerSegment = 10
        let startIndex = currentWordIndex
        var advanced = false
        for word in newWords {
            if let newIndex = advanceForWord(word) {
                currentWordIndex = newIndex
                advanced = true
                // Cap: don't advance more than maxAdvancePerSegment words per segment
                if currentWordIndex - startIndex >= maxAdvancePerSegment {
                    break
                }
            }
        }
        return advanced ? wordEndIndices[currentWordIndex] : nil
    }

    /// Estimate the current position in the script for a transcript segment without advancing state.
    /// Returns an optimistic position suitable for highlighting, even for partial/intermediate transcripts.
    /// This is separate from processSegment which conservatively advances only on confirmed matches.
    public func estimatePosition(for segment: String, timestamp: CFTimeInterval) -> Int {
        let words = Self.normalizeForMatching(segment).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return position }

        // Try to find where these words align in the script, starting from current position
        var estimatedIndex = currentWordIndex
        let segmentWords = words.filter { !config.fillerWords.contains($0) }

        guard !segmentWords.isEmpty else { return position }

        // Look ahead up to forwardWindow words for a sequence match
        let lookAheadLimit = scriptWords.count

        // Try to find the best match for the last few words in the segment
        let checkWords = Array(segmentWords.suffix(min(5, segmentWords.count)))

        outer: for startIdx in currentWordIndex..<lookAheadLimit {
            // Check if checkWords match starting at startIdx
            var matchCount = 0
            for (offset, word) in checkWords.enumerated() {
                let scriptIdx = startIdx + offset
                guard scriptIdx < scriptWords.count else { break }
                if scriptWords[scriptIdx].word == word {
                    matchCount += 1
                } else {
                    break
                }
            }

            if matchCount == checkWords.count {
                estimatedIndex = startIdx + checkWords.count - 1
                break outer
            }
        }

        // Return the estimated position (end of the matched word)
        guard estimatedIndex < wordEndIndices.count else { return scriptText.count }
        return wordEndIndices[estimatedIndex]
    }

    /// Estimate position without actor isolation. Uses only immutable (`let`) properties.
    /// `afterCharPosition` is the caller's last known character position, used as the search start.
    /// This avoids waiting on the actor queue, enabling sub-millisecond UI updates.
    public nonisolated func estimatePosition(for segment: String, afterCharPosition: Int) -> Int {
        let words = Self.normalizeForMatching(segment).split(separator: " ").map(String.init)
        let startWordIndex = wordIndexForCharPosition(afterCharPosition)
        guard !words.isEmpty else {
            guard startWordIndex < wordEndIndices.count else { return scriptText.count }
            return wordEndIndices[startWordIndex]
        }

        let segmentWords = words.filter { !config.fillerWords.contains($0) }
        guard !segmentWords.isEmpty else {
            guard startWordIndex < wordEndIndices.count else { return scriptText.count }
            return wordEndIndices[startWordIndex]
        }

        var estimatedIndex = startWordIndex
        let lookAheadLimit = scriptWords.count
        let checkWords = Array(segmentWords.suffix(min(5, segmentWords.count)))

        for startIdx in startWordIndex..<lookAheadLimit {
            var matchCount = 0
            for (offset, word) in checkWords.enumerated() {
                let scriptIdx = startIdx + offset
                guard scriptIdx < scriptWords.count else { break }
                if scriptWords[scriptIdx].word == word {
                    matchCount += 1
                } else {
                    break
                }
            }
            if matchCount == checkWords.count {
                estimatedIndex = startIdx + checkWords.count - 1
                break
            }
        }

        // Try prefix-matching the last segment word against the next expected script word
        // for mid-word highlighting (e.g., "hel" partially matching "hello")
        let lastSegmentWord = segmentWords.last!
        let prefixCheckIndex = estimatedIndex == startWordIndex ? startWordIndex : estimatedIndex + 1
        if prefixCheckIndex < scriptWords.count,
           lastSegmentWord.count >= 2,
           scriptWords[prefixCheckIndex].word.hasPrefix(lastSegmentWord),
           scriptWords[prefixCheckIndex].word != lastSegmentWord {
            return scriptWords[prefixCheckIndex].startIndex + lastSegmentWord.count
        }

        guard estimatedIndex < wordEndIndices.count else { return scriptText.count }
        return wordEndIndices[estimatedIndex]
    }

    /// Binary search `wordEndIndices` to find the word index for a character position.
    /// Nonisolated — accesses only `let` properties.
    nonisolated private func wordIndexForCharPosition(_ charPos: Int) -> Int {
        guard !wordEndIndices.isEmpty else { return 0 }
        var lo = 0
        var hi = wordEndIndices.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if wordEndIndices[mid] <= charPos {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return min(lo, wordEndIndices.count - 1)
    }

    /// Check if we should treat as paused (silence threshold exceeded).
    public func checkPause(timestamp: CFTimeInterval) -> Bool {
        let elapsed = timestamp - lastWordTime
        if elapsed >= pauseThresholdSeconds {
            isPausedDueToSilence = true
        } else {
            isPausedDueToSilence = false
        }
        return isPausedDueToSilence
    }

    /// Current character index in the original script.
    public var position: Int {
        guard currentWordIndex < wordEndIndices.count else { return scriptText.count }
        return wordEndIndices[currentWordIndex]
    }

    // MARK: - Matching Engine

    /// Advance word index for one transcript word. Returns new word index if found.
    private func advanceForWord(_ word: String) -> Int? {
        let normWord = Self.normalizeForMatching(word)
        guard !normWord.isEmpty else { return nil }

        // Skip filler words
        guard !config.fillerWords.contains(normWord) else { return nil }

        // Look up all positions where this word appears
        guard let candidates = wordIndex[normWord], !candidates.isEmpty else {
            consecutiveUnmatched += 1
            return nil
        }

        // Determine search window
        let windowStart: Int
        let windowEnd: Int

        if consecutiveUnmatched >= config.skipAheadThreshold {
            // Sync lost — search entire script
            windowStart = 0
            windowEnd = scriptWords.count - 1
        } else {
            windowStart = max(0, currentWordIndex - config.backWindow)
            windowEnd = min(scriptWords.count - 1, currentWordIndex + config.forwardWindow)
        }

        // Filter candidates to search window using binary search
        let filteredCandidates = candidatesInRange(candidates, start: windowStart, end: windowEnd)

        guard !filteredCandidates.isEmpty else {
            consecutiveUnmatched += 1
            return nil
        }

        // Score each candidate and find the best
        var bestScore = -Double.infinity
        var bestCandidate = -1

        for candidate in filteredCandidates {
            let score = computeScore(candidatePosition: candidate)
            if score > bestScore {
                bestScore = score
                bestCandidate = candidate
            }
        }

        // Determine acceptance threshold
        let isColdStart = recentMatches.isEmpty
        let threshold = isColdStart ? config.coldStartScoreThreshold : config.minimumScoreThreshold

        // Backward jumps require stronger evidence
        let isBackward = bestCandidate < currentWordIndex
        if isBackward && bestScore < config.backwardJumpThreshold {
            consecutiveUnmatched += 1
            return nil
        }

        guard bestScore >= threshold else {
            consecutiveUnmatched += 1
            return nil
        }

        // Accept the match
        consecutiveUnmatched = 0
        appendToRecentMatches(bestCandidate)
        return bestCandidate
    }

    // MARK: - Scoring

    private func computeScore(candidatePosition: Int) -> Double {
        let recent = recentMatchesOrdered
        var score = 0.0

        // Context score (0-8 pts): how well does this candidate align with recent matches?
        for (offset, matchedIndex) in recent.enumerated().reversed() {
            let expectedGap = candidatePosition - matchedIndex
            let recencyIndex = recent.count - 1 - offset
            _ = recencyIndex // used conceptually — more recent matches weighted equally for simplicity

            if expectedGap >= 1 {
                // Perfect alignment: the matched word is exactly (candidatePosition - matchedIndex) behind
                let idealGap = candidatePosition - matchedIndex
                if idealGap >= 1 && idealGap <= 3 {
                    score += 1.0
                } else if idealGap >= 1 && idealGap <= 5 {
                    score += 0.5
                } else if idealGap >= 1 && idealGap <= 10 {
                    score += 0.2
                }
            }
        }

        // Locality score (0-3 pts): prefer candidates close to current position
        let distance = abs(candidatePosition - currentWordIndex)
        let localityScore = 3.03 / (1.0 + Double(distance * distance) * 0.01)
        score += localityScore

        // Forward momentum (0-1 pt): bonus for natural reading pace
        let ahead = candidatePosition - currentWordIndex
        if ahead >= 1 && ahead <= 5 {
            score += 1.0
        }

        return score
    }

    // MARK: - Ring Buffer

    private func appendToRecentMatches(_ scriptWordIndex: Int) {
        if recentMatches.count < config.recentMatchesCapacity {
            recentMatches.append(scriptWordIndex)
        } else {
            recentMatches[recentMatchesHead] = scriptWordIndex
        }
        recentMatchesHead = (recentMatchesHead + 1) % config.recentMatchesCapacity
    }

    /// Returns recent matches in chronological order (oldest first).
    private var recentMatchesOrdered: [Int] {
        if recentMatches.count < config.recentMatchesCapacity {
            return recentMatches
        }
        // Ring buffer is full; head points to the oldest entry
        let tail = Array(recentMatches[recentMatchesHead...])
        let head = Array(recentMatches[..<recentMatchesHead])
        return tail + head
    }

    // MARK: - Helpers

    /// Use binary search to find candidates within [start, end] range.
    private func candidatesInRange(_ candidates: [Int], start: Int, end: Int) -> [Int] {
        guard !candidates.isEmpty, start <= end else { return [] }

        // Find first candidate >= start
        var lo = 0, hi = candidates.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if candidates[mid] < start {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        let firstIdx = lo

        // Find first candidate > end
        lo = firstIdx
        hi = candidates.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if candidates[mid] <= end {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        let lastIdx = lo

        guard firstIdx < lastIdx else { return [] }
        return Array(candidates[firstIdx..<lastIdx])
    }

    /// Normalize text for matching: lowercase, collapse whitespace, strip punctuation.
    public static func normalizeForMatching(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        let filtered = text.unicodeScalars
            .filter { allowed.contains($0) }
            .map { Character($0) }
        let str = String(filtered)
        return str.lowercased()
            .split(separator: " ")
            .joined(separator: " ")
    }

    /// Extract words from script with their start indices. Each word is normalized for matching.
    private static func extractWordsWithIndices(_ text: String) -> [(word: String, startIndex: Int)] {
        var result: [(word: String, startIndex: Int)] = []
        var i = text.startIndex
        var wordStart: String.Index?
        var wordChars: [Character] = []

        while i <= text.endIndex {
            let ch = i < text.endIndex ? text[i] : " "
            let isWordChar = ch.isLetter || ch.isNumber

            if isWordChar {
                if wordStart == nil {
                    wordStart = i
                    wordChars = []
                }
                wordChars.append(contentsOf: ch.lowercased())
            } else {
                if !wordChars.isEmpty, let start = wordStart {
                    let word = String(wordChars)
                    let startIndex = text.distance(from: text.startIndex, to: start)
                    result.append((word: word, startIndex: startIndex))
                    wordChars = []
                    wordStart = nil
                }
            }
            if i < text.endIndex {
                i = text.index(after: i)
            } else {
                break
            }
        }

        return result
    }
}
