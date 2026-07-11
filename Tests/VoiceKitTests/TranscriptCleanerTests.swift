//
//  TranscriptCleanerTests.swift
//  VoiceKitTests
//
//  Tests for TranscriptCleaner filler removal and capitalization repair.
//

import Testing
@testable import VoiceKit

struct TranscriptCleanerTests {

    @Test func removesLeadingFillerAndRecapitalizes() {
        #expect(TranscriptCleaner.clean("Um, hello world.") == "Hello world.")
    }

    @Test func removesMidSentenceFiller() {
        #expect(TranscriptCleaner.clean("I was, uh, thinking.") == "I was, thinking.")
    }

    @Test func recapitalizesAfterSentenceBoundary() {
        #expect(TranscriptCleaner.clean("Nice. Um, so we go.") == "Nice. So we go.")
    }

    @Test func allFillersYieldsEmpty() {
        #expect(TranscriptCleaner.clean("um uh hmm") == "")
    }

    @Test func cleanTextUnchanged() {
        #expect(TranscriptCleaner.clean("Hello world.") == "Hello world.")
    }

    @Test func fillerAsSubstringNotRemoved() {
        #expect(TranscriptCleaner.clean("My umbrella era") == "My umbrella era")
    }

    @Test func collapsesWhitespace() {
        #expect(TranscriptCleaner.clean("hello   world\n again") == "hello world again")
    }

    @Test func customFillerWords() {
        #expect(TranscriptCleaner.clean("like, totally rad", fillerWords: ["like"]) == "Totally rad")
    }
}
