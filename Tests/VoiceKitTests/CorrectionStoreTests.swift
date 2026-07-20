//
//  CorrectionStoreTests.swift
//  VoiceKitTests
//
//  Tests for the learned-correction store: threshold, unlearning, apply.
//

import Foundation
import Testing
@testable import VoiceKit

struct CorrectionStoreTests {

    private let cooper = Correction(heard: "cooper", corrected: "Kubernetes")

    private func makeStore() -> (store: CorrectionStore, url: URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voicekit-store-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("corrections.json")
        return (CorrectionStore(fileURL: url), url)
    }

    @Test func appliesOnlyAtThreshold() {
        let (store, _) = makeStore()
        store.record([cooper])
        #expect(store.apply(to: "the cooper cluster") == "the cooper cluster")
        store.record([cooper])
        #expect(store.apply(to: "the cooper cluster") == "the Kubernetes cluster")
    }

    @Test func applyIsCaseInsensitiveAndPreservesLearnedCasing() {
        let (store, _) = makeStore()
        store.record([cooper])
        store.record([cooper])
        #expect(store.apply(to: "Cooper is here") == "Kubernetes is here")
    }

    @Test func applyMatchesWholeWordsOnly() {
        let (store, _) = makeStore()
        let um = Correction(heard: "um", corrected: "gum")
        store.record([um])
        store.record([um])
        #expect(store.apply(to: "my umbrella era") == "my umbrella era")
        #expect(store.apply(to: "chewing um daily") == "chewing gum daily")
    }

    @Test func reversePairUnlearns() {
        let (store, _) = makeStore()
        store.record([cooper])
        store.record([cooper])
        #expect(store.apply(to: "cooper") == "Kubernetes")
        store.record([Correction(heard: "Kubernetes", corrected: "cooper")])
        #expect(store.apply(to: "cooper") == "cooper")
    }

    @Test func caseOnlyPairsAccumulateInsteadOfCancelling() {
        let (store, _) = makeStore()
        let k = Correction(heard: "kubernetes", corrected: "Kubernetes")
        store.record([k])
        store.record([k])
        #expect(store.apply(to: "i use kubernetes") == "i use Kubernetes")
    }

    @Test func longerPhrasesApplyFirst() {
        let (store, _) = makeStore()
        let phrase = Correction(heard: "cooper netties", corrected: "Kubernetes")
        let word = Correction(heard: "cooper", corrected: "Cooper")
        store.record([phrase, word])
        store.record([phrase, word])
        #expect(store.apply(to: "the cooper netties cluster") == "the Kubernetes cluster")
    }

    @Test func persistenceRoundTrip() {
        let (store, url) = makeStore()
        store.record([cooper])
        store.record([cooper])
        let reloaded = CorrectionStore(fileURL: url)
        #expect(reloaded.apply(to: "cooper") == "Kubernetes")
    }

    @Test func promptHintsRespectThresholdAndLimit() {
        let (store, _) = makeStore()
        store.record([cooper])
        store.record([cooper])
        store.record([Correction(heard: "reddis", corrected: "Redis")]) // seen once: below threshold
        #expect(store.promptHints(limit: 5) == [Correction(heard: "cooper", corrected: "Kubernetes")])
        #expect(store.promptHints(limit: 0).isEmpty)
    }

    @Test func resetClearsEverything() {
        let (store, url) = makeStore()
        store.record([cooper])
        store.record([cooper])
        store.reset()
        #expect(store.apply(to: "cooper") == "cooper")
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func historyTracksManualEditsBeforeThreshold() {
        let (store, _) = makeStore()
        store.record([cooper]) // below threshold: manual only, not yet auto-applied
        let entry = store.history().first { $0.correction == cooper }
        #expect(entry?.manualCount == 1)
        #expect(entry?.autoCount == 0)
        #expect(entry?.isActive == false)
    }

    @Test func historyCountsAutomaticApplicationsSeparately() {
        let (store, _) = makeStore()
        store.record([cooper])
        store.record([cooper]) // crosses the threshold
        _ = store.apply(to: "cooper near the cooper cluster") // two matches in one pass
        let entry = store.history().first { $0.correction == cooper }
        #expect(entry?.manualCount == 2)
        #expect(entry?.autoCount == 2)
        #expect(entry?.isActive == true)
    }

    @Test func historyIsSortedByTotalUsageDescending() {
        let (store, _) = makeStore()
        let rare = Correction(heard: "reddis", corrected: "Redis")
        store.record([cooper])
        store.record([cooper])
        store.record([cooper])
        store.record([rare])
        let ordered = store.history()
        #expect(ordered.first?.correction == cooper)
    }

    @Test func historySurvivesAnUnlearnedReversal() {
        // Undoing an auto-applied correction still counts as a real manual edit.
        let (store, _) = makeStore()
        store.record([cooper])
        store.record([cooper])
        store.record([Correction(heard: "Kubernetes", corrected: "cooper")])
        let entry = store.history().first { $0.correction == cooper }
        #expect(entry?.manualCount == 2)
        #expect(entry?.isActive == false) // unlearned back below threshold
    }

    @Test func resetClearsHistoryToo() {
        let (store, _) = makeStore()
        store.record([cooper])
        store.record([cooper])
        _ = store.apply(to: "cooper")
        store.reset()
        #expect(store.history().isEmpty)
    }
}
