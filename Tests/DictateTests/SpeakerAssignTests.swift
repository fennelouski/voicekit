//
//  SpeakerAssignTests.swift
//  DictateTests
//
//  Max-overlap speaker assignment: a transcript line gets the speaker whose
//  diarized spans cover most of its time range.
//

import Testing
@testable import Dictate

struct SpeakerAssignTests {

    @Test func segmentInsideOneSpan() {
        let spans = [(speaker: 1, start: 0.0, end: 10.0)]
        #expect(SpeakerAssign.speaker(forStart: 2, end: 5, in: spans) == 1)
    }

    @Test func straddlingSegmentGoesToLargerOverlap() {
        let spans = [
            (speaker: 1, start: 0.0, end: 4.0),
            (speaker: 2, start: 4.0, end: 10.0),
        ]
        #expect(SpeakerAssign.speaker(forStart: 3, end: 8, in: spans) == 2)
    }

    @Test func noOverlapReturnsNil() {
        let spans = [(speaker: 1, start: 0.0, end: 2.0)]
        #expect(SpeakerAssign.speaker(forStart: 5, end: 8, in: spans) == nil)
        #expect(SpeakerAssign.speaker(forStart: 0, end: 3, in: []) == nil)
    }

    @Test func accumulatedOverlapBeatsSingleSpan() {
        // Speaker 1 covers 2s + 2s of the segment; speaker 2 covers 3s contiguous.
        let spans = [
            (speaker: 1, start: 0.0, end: 2.0),
            (speaker: 2, start: 2.0, end: 5.0),
            (speaker: 1, start: 5.0, end: 7.0),
        ]
        #expect(SpeakerAssign.speaker(forStart: 0, end: 7, in: spans) == 1)
    }

    @Test func touchingButNotOverlappingDoesNotCount() {
        let spans = [(speaker: 1, start: 0.0, end: 3.0)]
        #expect(SpeakerAssign.speaker(forStart: 3, end: 6, in: spans) == nil)
    }
}
