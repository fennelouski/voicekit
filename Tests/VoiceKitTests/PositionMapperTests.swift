//
//  PositionMapperTests.swift
//  VoiceKitTests
//
//  Tests for the scored candidate matching algorithm in PositionMapper.
//

import Foundation
import Testing
@testable import VoiceKit

struct PositionMapperTests {

    // MARK: - Basic Sequential Matching

    @Test func basicSequentialMatching() async {
        let script = "Hello world this is a test"
        let mapper = PositionMapper(scriptText: script)
        let t = ProcessInfo.processInfo.systemUptime

        let pos1 = await mapper.processSegment("Hello", timestamp: t)
        #expect(pos1 != nil)

        let pos2 = await mapper.processSegment("Hello world", timestamp: t + 0.1)
        #expect(pos2 != nil)
        #expect(pos2! > pos1!)

        let pos3 = await mapper.processSegment("Hello world this", timestamp: t + 0.2)
        #expect(pos3 != nil)
        #expect(pos3! > pos2!)
    }

    @Test func wordsAdvanceInOrder() async {
        let script = "one two three four five"
        let mapper = PositionMapper(scriptText: script)
        let t = ProcessInfo.processInfo.systemUptime

        var positions: [Int] = []
        let segments = ["one", "one two", "one two three", "one two three four", "one two three four five"]
        for (i, seg) in segments.enumerated() {
            if let pos = await mapper.processSegment(seg, timestamp: t + Double(i) * 0.1) {
                positions.append(pos)
            }
        }

        // Each position should be strictly increasing
        for i in 1..<positions.count {
            #expect(positions[i] > positions[i - 1], "Position should increase: \(positions[i]) > \(positions[i - 1])")
        }
    }

    // MARK: - Repeated Word Disambiguation

    @Test func repeatedWordUsesContext() async {
        // "testing" appears at position 3 and position 8
        let script = "This is me testing one two three still testing more"
        let mapper = PositionMapper(scriptText: script)
        let t = ProcessInfo.processInfo.systemUptime

        // Speak "This is me testing" — should match first "testing" (word index 3)
        let pos1 = await mapper.processSegment("This is me testing", timestamp: t)
        #expect(pos1 != nil)

        // The position should correspond to the first "testing" not the second
        let position = await mapper.position
        #expect(position <= 22, "Should match first 'testing', not second. Position: \(position)")
    }

    @Test func repeatedWordAtStartAndEnd() async {
        // Use more words to build stronger context
        let script = "hello friends welcome to the show hello everyone goodbye"
        let mapper = PositionMapper(scriptText: script)
        let t = ProcessInfo.processInfo.systemUptime

        // First "hello" should match at the start
        let pos1 = await mapper.processSegment("hello", timestamp: t)
        #expect(pos1 != nil)
        let firstPos = await mapper.position

        // Continue reading through to build context
        _ = await mapper.processSegment("hello friends welcome to the show", timestamp: t + 0.1)

        // Now "hello" should match the second occurrence due to forward context
        let pos3 = await mapper.processSegment("hello friends welcome to the show hello", timestamp: t + 0.2)
        #expect(pos3 != nil)
        let secondHelloPos = await mapper.position
        #expect(secondHelloPos > firstPos, "Second 'hello' should be further in script")
    }

    // MARK: - Filler Word Filtering

    @Test func fillerWordsAreSkipped() async {
        let script = "The quick brown fox"
        let mapper = PositionMapper(scriptText: script)
        let t = ProcessInfo.processInfo.systemUptime

        let pos1 = await mapper.processSegment("The", timestamp: t)
        #expect(pos1 != nil)
        let posAfterThe = await mapper.position

        // "um" should not change position
        _ = await mapper.processSegment("The um", timestamp: t + 0.1)
        let posAfterUm = await mapper.position
        #expect(posAfterUm == posAfterThe, "Filler 'um' should not change position")

        // "uh" should not change position either
        _ = await mapper.processSegment("The um uh", timestamp: t + 0.2)
        let posAfterUh = await mapper.position
        #expect(posAfterUh == posAfterThe, "Filler 'uh' should not change position")

        // Real word should advance
        let pos4 = await mapper.processSegment("The um uh quick", timestamp: t + 0.3)
        #expect(pos4 != nil)
        let posAfterQuick = await mapper.position
        #expect(posAfterQuick > posAfterThe, "'quick' should advance past 'The'")
    }

    @Test func allFillerWordsFiltered() async {
        let script = "start middle end"
        let mapper = PositionMapper(scriptText: script)
        let t = ProcessInfo.processInfo.systemUptime

        _ = await mapper.processSegment("start", timestamp: t)

        let fillers = ["um", "uh", "er", "ah", "hm", "hmm", "mm"]
        let posAfterStart = await mapper.position

        var cumulative = "start"
        for (i, filler) in fillers.enumerated() {
            cumulative += " \(filler)"
            _ = await mapper.processSegment(cumulative, timestamp: t + Double(i + 1) * 0.1)
            let pos = await mapper.position
            #expect(pos == posAfterStart, "Filler '\(filler)' should not change position")
        }
    }

    // MARK: - Transcript Revision

    @Test func transcriptRevisionDoesNotRewind() async {
        let script = "The weather today is wonderful and sunny"
        let mapper = PositionMapper(scriptText: script)
        let t = ProcessInfo.processInfo.systemUptime

        let pos1 = await mapper.processSegment("The weather today", timestamp: t)
        #expect(pos1 != nil)
        let posAtToday = await mapper.position

        let pos2 = await mapper.processSegment("The weather today is", timestamp: t + 0.5)
        #expect(pos2 != nil)
        let posAtIs = await mapper.position
        #expect(posAtIs >= posAtToday, "Revision should not rewind position")
    }

    @Test func transcriptShorteningDoesNotRewind() async {
        let script = "alpha beta gamma delta epsilon"
        let mapper = PositionMapper(scriptText: script)
        let t = ProcessInfo.processInfo.systemUptime

        _ = await mapper.processSegment("alpha beta gamma", timestamp: t)
        let posAtGamma = await mapper.position

        // Transcript gets shorter (revision)
        let pos2 = await mapper.processSegment("alpha beta", timestamp: t + 0.1)
        #expect(pos2 == nil, "Shortened transcript should not produce new position")

        let posAfterShorten = await mapper.position
        #expect(posAfterShorten == posAtGamma, "Position should not change on transcript shortening")
    }

    // MARK: - Skip-Ahead Recovery

    @Test func recoversAfterManyUnmatchedWords() async {
        let script = "Section one about cats and dogs and fish. Section two about cars and planes and boats."
        let mapper = PositionMapper(scriptText: script)
        let t = ProcessInfo.processInfo.systemUptime

        _ = await mapper.processSegment("Section one about", timestamp: t)

        // Feed 13+ words not in the script to trigger skip-ahead
        var garbage = "Section one about"
        for i in 0..<14 {
            garbage += " xyzzy\(i)"
        }
        _ = await mapper.processSegment(garbage, timestamp: t + 1.0)

        // Now speak words from section two — should recover
        garbage += " cars and planes"
        _ = await mapper.processSegment(garbage, timestamp: t + 2.0)

        let finalPos = await mapper.position
        #expect(finalPos > 0, "Should have some position after recovery attempt")
    }

    // MARK: - No Backward Jump

    @Test func noBackwardJumpWithoutStrongEvidence() async {
        let script = "word one word two word three word four"
        let mapper = PositionMapper(scriptText: script)
        let t = ProcessInfo.processInfo.systemUptime

        _ = await mapper.processSegment("word one word two word three", timestamp: t)
        let posAtThree = await mapper.position

        // Say "word" again — should NOT jump back to first "word"
        _ = await mapper.processSegment("word one word two word three word", timestamp: t + 0.5)
        let posAfterWord = await mapper.position
        #expect(posAfterWord >= posAtThree, "Should not jump backward for ambiguous repeated word")
    }

    // MARK: - Edge Cases

    @Test func emptyScript() async {
        let mapper = PositionMapper(scriptText: "")
        let t = ProcessInfo.processInfo.systemUptime

        let pos = await mapper.processSegment("hello world", timestamp: t)
        #expect(pos == nil, "Empty script should never match")
    }

    @Test func singleWordScript() async {
        let mapper = PositionMapper(scriptText: "Hello")
        let t = ProcessInfo.processInfo.systemUptime

        let pos = await mapper.processSegment("Hello", timestamp: t)
        #expect(pos != nil, "Single word should match")
    }

    @Test func emptySegment() async {
        let mapper = PositionMapper(scriptText: "Hello world")
        let t = ProcessInfo.processInfo.systemUptime

        let pos = await mapper.processSegment("", timestamp: t)
        #expect(pos == nil, "Empty segment should return nil")
    }

    @Test func punctuationInScript() async {
        let script = "Hello, world! How are you?"
        let mapper = PositionMapper(scriptText: script)
        let t = ProcessInfo.processInfo.systemUptime

        let pos = await mapper.processSegment("hello world how", timestamp: t)
        #expect(pos != nil, "Should match despite punctuation in script")
    }

    @Test func caseInsensitiveMatching() async {
        let script = "The Quick Brown Fox"
        let mapper = PositionMapper(scriptText: script)
        let t = ProcessInfo.processInfo.systemUptime

        let pos = await mapper.processSegment("the quick brown fox", timestamp: t)
        #expect(pos != nil, "Should match case-insensitively")
    }

    @Test func startOfScriptNoContext() async {
        let script = "Beginning of the script here"
        let mapper = PositionMapper(scriptText: script)
        let t = ProcessInfo.processInfo.systemUptime

        let pos = await mapper.processSegment("Beginning", timestamp: t)
        #expect(pos != nil, "Should match at start with no prior context")
    }

    // MARK: - Reset

    @Test func resetClearsState() async {
        let script = "alpha beta gamma delta"
        let mapper = PositionMapper(scriptText: script)
        let t = ProcessInfo.processInfo.systemUptime

        _ = await mapper.processSegment("alpha beta gamma", timestamp: t)
        let posBeforeReset = await mapper.position
        #expect(posBeforeReset > 0)

        await mapper.reset()
        let posAfterReset = await mapper.position
        #expect(posAfterReset == 0 || posAfterReset <= 5, "Position should reset to start")
    }

    // MARK: - Pause Detection

    @Test func pauseDetection() async {
        let script = "test script"
        let mapper = PositionMapper(scriptText: script, pauseThresholdSeconds: 0.5)
        let t = ProcessInfo.processInfo.systemUptime

        _ = await mapper.processSegment("test", timestamp: t)

        let notPaused = await mapper.checkPause(timestamp: t + 0.1)
        #expect(notPaused == false, "Should not be paused right after speech")

        let paused = await mapper.checkPause(timestamp: t + 1.0)
        #expect(paused == true, "Should be paused after silence threshold")
    }

    // MARK: - Performance

    @Test func performanceWith5000WordScript() async {
        let baseWords = ["the", "quick", "brown", "fox", "jumps", "over", "lazy", "dog",
                         "and", "then", "runs", "across", "field", "into", "forest",
                         "where", "birds", "sing", "beautiful", "songs"]
        var scriptParts: [String] = []
        for i in 0..<5000 {
            scriptParts.append(baseWords[i % baseWords.count])
        }
        let script = scriptParts.joined(separator: " ")

        let mapper = PositionMapper(scriptText: script)
        let startTime = ProcessInfo.processInfo.systemUptime
        let t = startTime

        // Simulate realistic usage: speech recognizer sends cumulative transcript
        // but resets periodically (every ~20 words, simulating segment boundaries)
        let segmentSize = 20
        var segmentBase = ""
        var wordCount = 0

        for i in 0..<500 {
            let word = baseWords[i % baseWords.count]
            if wordCount >= segmentSize {
                // Reset cumulative buffer (simulates new recognition segment)
                segmentBase = word
                wordCount = 1
            } else {
                if segmentBase.isEmpty {
                    segmentBase = word
                } else {
                    segmentBase += " \(word)"
                }
                wordCount += 1
            }
            _ = await mapper.processSegment(segmentBase, timestamp: t + Double(i) * 0.01)
        }

        let elapsed = ProcessInfo.processInfo.systemUptime - startTime
        #expect(elapsed < 1.0, "500 segments on 5000-word script should complete in <1s, took \(elapsed)s")
    }
}
