//
//  TextDistanceTests.swift
//  VoiceKitTests
//

import Testing
@testable import VoiceKit

struct TextDistanceTests {
    @Test func identicalTextIsZero() {
        #expect(TextDistance.wordEdits("hello there world", "hello there world") == 0)
        #expect(TextDistance.changePercent(from: "hello there world", to: "hello there world") == 0)
    }

    @Test func oneWordSubstitution() {
        // "cloud" → "Claude": one word changed of three.
        #expect(TextDistance.wordEdits("open cloud code", "open Claude code") == 1)
        #expect(TextDistance.changePercent(from: "open cloud code", to: "open Claude code") == 33)
    }

    @Test func insertionsAndDeletions() {
        #expect(TextDistance.wordEdits("the meeting", "the big meeting today") == 2)   // +big +today
        #expect(TextDistance.wordEdits("um so like hello", "hello") == 3)              // -um -so -like
    }

    @Test func emptyCases() {
        #expect(TextDistance.wordEdits("", "one two") == 2)
        #expect(TextDistance.wordEdits("one two three", "") == 3)
        #expect(TextDistance.changePercent(from: "", to: "") == 0)
    }

    @Test func aFullReplacementIsNearlyAHundredPercent() {
        // A refusal replacing a short transcript reads as ~100% changed.
        let original = "make this sound more like me"
        let refusal = "I'm sorry, but I cannot assist with that request as it may be harmful."
        #expect(TextDistance.changePercent(from: original, to: refusal) >= 90)
    }
}
