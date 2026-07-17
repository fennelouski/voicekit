//
//  SpokenCommandsTests.swift
//  VoiceKitTests
//
//  Tests spoken formatting commands → literal punctuation and line breaks.
//

import Testing
@testable import VoiceKit

struct SpokenCommandsTests {

    @Test func colonNewLineBecomesLiterals() {
        #expect(SpokenCommands.apply("colon new line") == ":\n")
    }

    @Test func punctuationHugsPrecedingWord() {
        #expect(SpokenCommands.apply("buy milk period new line eggs") == "buy milk.\neggs")
    }

    @Test func multiWordWinsOverSingle() {
        #expect(SpokenCommands.apply("new paragraph") == "\n\n")
    }

    @Test func matchesCaseAndEdgePunctuation() {
        #expect(SpokenCommands.apply("Hello Comma world") == "Hello, world")
    }

    @Test func parensHugTheirContents() {
        #expect(SpokenCommands.apply("see open paren note close paren") == "see (note)")
    }

    @Test func leavesOrdinaryWordsUntouched() {
        #expect(SpokenCommands.apply("the umbrella is colonial") == "the umbrella is colonial")
    }

    @Test func emptyStaysEmpty() {
        #expect(SpokenCommands.apply("") == "")
    }
}
