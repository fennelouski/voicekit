//
//  TranscriptAccumulatorTests.swift
//  VoiceKitTests
//
//  Tests for TranscriptAccumulator volatile/final folding.
//

import Testing
@testable import VoiceKit

struct TranscriptAccumulatorTests {

    @Test func volatileReplacesPreviousVolatile() {
        var acc = TranscriptAccumulator()
        acc.add(TranscriptionResult(text: "hel", isFinal: false))
        acc.add(TranscriptionResult(text: "hello", isFinal: false))
        #expect(acc.preview == "hello")
        #expect(acc.committed == "")
    }

    @Test func finalCommitsAndClearsVolatile() {
        var acc = TranscriptAccumulator()
        acc.add(TranscriptionResult(text: "hello wor", isFinal: false))
        acc.add(TranscriptionResult(text: "Hello world.", isFinal: true))
        #expect(acc.committed == "Hello world.")
        #expect(acc.preview == "Hello world.")
    }

    @Test func previewOverlaysVolatileOnCommitted() {
        var acc = TranscriptAccumulator()
        acc.add(TranscriptionResult(text: "Hello world.", isFinal: true))
        acc.add(TranscriptionResult(text: "And then", isFinal: false))
        #expect(acc.preview == "Hello world. And then")
        #expect(acc.committed == "Hello world.")
    }

    @Test func multipleFinalsJoined() {
        var acc = TranscriptAccumulator()
        acc.add(TranscriptionResult(text: "First sentence.", isFinal: true))
        acc.add(TranscriptionResult(text: "Second sentence.", isFinal: true))
        #expect(acc.committed == "First sentence. Second sentence.")
    }

    @Test func resetClears() {
        var acc = TranscriptAccumulator()
        acc.add(TranscriptionResult(text: "Hello.", isFinal: true))
        acc.add(TranscriptionResult(text: "more", isFinal: false))
        acc.reset()
        #expect(acc.committed == "")
        #expect(acc.preview == "")
    }
}
