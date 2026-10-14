import AVFoundation
import Foundation
import Testing
@testable import VoiceKit

struct VocabularyTests {
    @Test func termsNormalizeDeduplicateAndPersist() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("terms.json")
        let store = VocabularyStore(fileURL: file)
        try store.setTerms([" OpenWhispr ", "openwhispr", "cafe\u{301}"])
        #expect(store.terms == ["OpenWhispr", "café"])
        #expect(VocabularyStore(fileURL: file).terms == store.terms)
        #expect(throws: VocabularyStore.ValidationError.self) { try store.setTerms(["bad\nterm"]) }
        #expect(store.terms == ["OpenWhispr", "café"])
    }

    @Test func invalidOrUnwritableVocabularyDoesNotLosePreviousTerms() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("terms.json")
        let store = VocabularyStore(fileURL: file)
        try store.setTerms(["VoiceKit"])
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        #expect(throws: Error.self) { try store.setTerms(["OpenWhispr"]) }
        #expect(store.terms == ["VoiceKit"])
        #expect(throws: VocabularyStore.ValidationError.self) { try VocabularyStore.validate([""]) }
        #expect(throws: VocabularyStore.ValidationError.self) { try VocabularyStore.validate([String(repeating: "x", count: 81)]) }
        #expect(throws: VocabularyStore.ValidationError.self) { try VocabularyStore.validate((0..<65).map { "term\($0)" }) }
        #expect(throws: VocabularyStore.ValidationError.self) { try VocabularyStore.validate((0..<64).map { String(repeating: "x", count: 70) + String($0) }) }
    }

    @Test func literalSpellingMatchesWholeWordsAndKeepsLongPhrases() {
        let terms = ["VoiceKit", "C++", "$Project", "OpenWhispr Project"]
        #expect(VocabularyStore.applySpellings(to: "voicekit and voicekitten use c++ in $project with openwhispr project.", terms: terms)
                == "VoiceKit and voicekitten use C++ in $Project with OpenWhispr Project.")
        #expect(VocabularyStore.applySpellings(to: "café CAFÉS", terms: ["Café"]) == "Café CAFÉS")
    }

    @Test func onlyRelevantBoundedCorrectionsEnterCleanup() {
        let good = Correction(heard: "cooper netties", corrected: "Kubernetes")
        let irrelevant = Correction(heard: "alpha", corrected: "Beta")
        let substring = Correction(heard: "net", corrected: "Net")
        #expect(CleanupPrompt.relevantHints([good, irrelevant, substring], to: "COOPER NETTIES cluster") == [good])
        let many = (0..<30).map { Correction(heard: "word\($0)", corrected: "Name\($0)") }
        #expect(CleanupPrompt.relevantHints(many, to: many.map(\.heard).joined(separator: " ")).count == 20)
        let oversized = Correction(heard: String(repeating: "x", count: 81), corrected: "name")
        #expect(CleanupPrompt.relevantHints([oversized], to: oversized.heard).isEmpty)
    }

    @Test func removingOneLearnedPairKeepsOtherHistoryAndSurvivesReload() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("corrections.json")
        let store = CorrectionStore(fileURL: file)
        let removed = Correction(heard: "cooper", corrected: "Kubernetes")
        let kept = Correction(heard: "reddis", corrected: "Redis")
        store.record([removed, kept, removed, kept])
        store.remove(removed)
        #expect(store.history().map(\.correction) == [kept])
        let reloaded = CorrectionStore(fileURL: file)
        #expect(reloaded.apply(to: "cooper and reddis", recordUsage: false) == "cooper and Redis")
    }
}

struct BufferFormatRegressionTests {
    @Test func interleavingAndTargetChangesRebuildConverter() throws {
        let inputFormat = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: true))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 4800))
        buffer.frameLength = 4800
        buffer.floatChannelData?[0].initialize(repeating: 0.25, count: 9600)
        let converter = BufferConverter()
        let stereo = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false))
        let mono = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false))
        let output = try converter.convertBuffer(buffer, to: stereo)
        #expect(output.format == stereo && output !== buffer && output.frameLength == buffer.frameLength)
        #expect(abs((output.floatChannelData?[1][0] ?? 0) - 0.25) < 0.0001)
        let switched = try converter.convertBuffer(buffer, to: mono)
        #expect(switched.format == mono && switched.frameLength == 4800)
    }
}
