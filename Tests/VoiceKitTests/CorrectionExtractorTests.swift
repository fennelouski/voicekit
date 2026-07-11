//
//  CorrectionExtractorTests.swift
//  VoiceKitTests
//
//  Tests for word-diff extraction of (heard → corrected) pairs.
//

import Foundation
import Testing
@testable import VoiceKit

struct CorrectionExtractorTests {

    @Test func singleWordSwap() {
        let fixes = CorrectionExtractor.extract(
            inserted: "please deploy the cooper cluster today",
            before: "Notes: please deploy the cooper cluster today",
            after: "Notes: please deploy the Kubernetes cluster today"
        )
        #expect(fixes == [Correction(heard: "cooper", corrected: "Kubernetes")])
    }

    @Test func multiWordPhrase() {
        let inserted = "set up the cooper netties cluster for me please"
        let fixes = CorrectionExtractor.extract(
            inserted: inserted,
            before: inserted,
            after: "set up the Kubernetes cluster for me please"
        )
        #expect(fixes == [Correction(heard: "cooper netties", corrected: "Kubernetes")])
    }

    @Test func caseOnlyFixKept() {
        let inserted = "i use kubernetes daily"
        let fixes = CorrectionExtractor.extract(
            inserted: inserted,
            before: inserted,
            after: "i use Kubernetes daily"
        )
        #expect(fixes == [Correction(heard: "kubernetes", corrected: "Kubernetes")])
    }

    @Test func editOutsideInsertedSpanIgnored() {
        let fixes = CorrectionExtractor.extract(
            inserted: "new sentence here",
            before: "Old paragraph stays. new sentence here",
            after: "Ancient paragraph stays. new sentence here"
        )
        #expect(fixes.isEmpty)
    }

    @Test func fullRewriteSkipped() {
        let inserted = "hello there world"
        let fixes = CorrectionExtractor.extract(
            inserted: inserted,
            before: inserted,
            after: "completely different text"
        )
        #expect(fixes.isEmpty)
    }

    @Test func pureInsertionIgnored() {
        let inserted = "send the report"
        let fixes = CorrectionExtractor.extract(
            inserted: inserted,
            before: inserted,
            after: "send the quarterly report"
        )
        #expect(fixes.isEmpty)
    }

    @Test func pureDeletionIgnored() {
        let inserted = "send the report"
        let fixes = CorrectionExtractor.extract(
            inserted: inserted,
            before: inserted,
            after: "send report"
        )
        #expect(fixes.isEmpty)
    }

    @Test func punctuationStrippedFromPairs() {
        let inserted = "we need the cooper, right now"
        let fixes = CorrectionExtractor.extract(
            inserted: inserted,
            before: inserted,
            after: "we need the Kubernetes, right now"
        )
        #expect(fixes == [Correction(heard: "cooper", corrected: "Kubernetes")])
    }

    @Test func multipleCorrections() {
        let inserted = "the cooper cluster and the reddis cache"
        let fixes = CorrectionExtractor.extract(
            inserted: inserted,
            before: inserted,
            after: "the Kubernetes cluster and the Redis cache"
        )
        #expect(fixes == [
            Correction(heard: "cooper", corrected: "Kubernetes"),
            Correction(heard: "reddis", corrected: "Redis"),
        ])
    }

    @Test func noEditsYieldNothing() {
        let inserted = "unchanged text"
        #expect(CorrectionExtractor.extract(inserted: inserted, before: inserted, after: inserted).isEmpty)
    }
}
