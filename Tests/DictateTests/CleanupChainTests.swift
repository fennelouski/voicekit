//
//  CleanupChainTests.swift
//  DictateTests
//
//  The fallback logic: order, first-success-wins, and — the point of the whole thing — that
//  a missing API key is not an error the user should ever hear about.
//

import Foundation
import Testing
import VoiceKit
@testable import Dictate

struct CleanupChainTests {
    private struct Boom: Error {}

    /// A realistic transcript: fixture cleanups reuse its words so they pass the
    /// wording-preservation guard, and the step name is prefixed only to identify which step won.
    private let input = "the quick brown fox jumps over"

    /// A step runner that only succeeds for the steps you name.
    private func runner(succeeding: Set<CleanupMode>, log: Log? = nil)
        -> (String, CleanupMode, [Correction]) async throws -> String {
        { text, step, _ in
            log?.append(step)
            guard succeeding.contains(step) else { throw Boom() }
            return "\(step.rawValue) \(text)"
        }
    }

    /// Records the order steps were attempted in.
    private final class Log: @unchecked Sendable {
        private(set) var steps: [CleanupMode] = []
        func append(_ step: CleanupMode) { steps.append(step) }
    }

    @Test func firstWorkingStepWinsAndTheRestAreNeverTried() async {
        let log = Log()
        let result = await CleanupChain.run(
            input,
            chain: [.claude, .openAI, .onDevice],
            runStep: runner(succeeding: [.openAI, .onDevice], log: log)
        )
        #expect(result.text == "openAI \(input)")
        #expect(result.usedStep == .openAI)
        #expect(result.failed == [.claude])
        #expect(!result.allFailed)
        // .onDevice must not have been reached — a wasted model call on every dictation.
        #expect(log.steps == [.claude, .openAI])
    }

    /// The bug this feature exists to fix: a cloud step with no key used to fail the whole
    /// dictation. Now it's just a step that isn't the one that cleans your text.
    @Test func aMissingKeyIsNotAnErrorWhenSomethingElseWorks() async {
        let result = await CleanupChain.run(
            input,
            chain: [.claude, .onDevice],
            runStep: runner(succeeding: [.onDevice])
        )
        #expect(result.usedStep == .onDevice)
        #expect(result.allFailed == false, "the user must not be told cleanup failed")
    }

    @Test func onlyACompletelyDeadChainReportsFailure() async {
        let result = await CleanupChain.run(
            input,
            chain: [.claude, .openAI, .onDevice],
            runStep: runner(succeeding: [])
        )
        #expect(result.allFailed)
        #expect(result.usedStep == nil)
        #expect(result.failed == [.claude, .openAI, .onDevice])
        // Never lose the transcript.
        #expect(result.text == input)
    }

    @Test func anEmptyChainIsOffAndIsNotAFailure() async {
        let result = await CleanupChain.run(input, chain: [], runStep: runner(succeeding: []))
        #expect(result.text == input)
        #expect(result.usedStep == nil)
        #expect(!result.allFailed, "cleanup being off is not a failure to report")
    }

    /// A step that returns blank hasn't cleaned anything — inserting that would eat the
    /// user's words, which is worse than not cleaning at all.
    @Test func aStepReturningNothingFallsThroughRatherThanErasingTheText() async {
        let result = await CleanupChain.run(
            input,
            chain: [.claude, .onDevice]
        ) { text, step, _ in
            step == .claude ? "   " : "onDevice \(text)"
        }
        #expect(result.usedStep == .onDevice)
        #expect(result.text == "onDevice \(input)")
        #expect(result.failed == [.claude])
    }

    @Test func reorderingChangesWhichStepWins() async {
        let both: Set<CleanupMode> = [.claude, .onDevice]
        let claudeFirst = await CleanupChain.run(input, chain: [.claude, .onDevice], runStep: runner(succeeding: both))
        let deviceFirst = await CleanupChain.run(input, chain: [.onDevice, .claude], runStep: runner(succeeding: both))
        #expect(claudeFirst.usedStep == .claude)
        #expect(deviceFirst.usedStep == .onDevice)
    }

    // MARK: - Adding steps

    /// The trap this rule exists to avoid: on-device is free and needs no key, so it almost
    /// always succeeds. A cloud step appended *below* it would never get a turn.
    @Test func addedStepsGoAboveTheOnDeviceFallback() {
        #expect(CleanupChain.adding(.claude, to: [.onDevice]) == [.claude, .onDevice])
        #expect(CleanupChain.adding(.gemini, to: [.claude, .onDevice]) == [.claude, .gemini, .onDevice])
    }

    /// Only on-device gets that treatment — the others queue up in the order you add them.
    @Test func withoutAnOnDeviceFallbackStepsSimplyAppend() {
        #expect(CleanupChain.adding(.gemini, to: [.claude]) == [.claude, .gemini])
        #expect(CleanupChain.adding(.onDevice, to: [.claude]) == [.claude, .onDevice])
    }

    @Test func addingIsIdempotentAndRejectsOff() {
        #expect(CleanupChain.adding(.claude, to: [.claude, .onDevice]) == [.claude, .onDevice])
        #expect(CleanupChain.adding(.off, to: [.onDevice]) == [.onDevice])
    }

    /// A step added above on-device must actually win when it's working.
    @Test func theAddedStepActuallyRunsFirst() async {
        let chain = CleanupChain.adding(.claude, to: [.onDevice])
        let result = await CleanupChain.run(
            input,
            chain: chain,
            runStep: runner(succeeding: [.claude, .onDevice])
        )
        #expect(result.usedStep == .claude)
    }

    // MARK: - Storage

    @Test func chainRoundTripsThroughDefaults() {
        let chain: [CleanupMode] = [.gemini, .groq, .onDevice]
        #expect(Settings.decodeChain(Settings.encodeChain(chain)) == chain)
        #expect(Settings.encodeChain(chain) == "gemini,groq,onDevice")
    }

    /// `off` is the absence of a chain, not a step inside one — it would be a silent no-op
    /// that swallows the text.
    @Test func offIsNeverAStepInTheChain() {
        #expect(!CleanupMode.chainable.contains(.off))
        #expect(Settings.decodeChain("claude,off,onDevice") == [.claude, .onDevice])
        #expect(Settings.encodeChain([.off, .claude]) == "claude")
        #expect(Settings.decodeChain("") == [])
    }

    @Test func garbageInDefaultsIsIgnoredRatherThanCrashing() {
        #expect(Settings.decodeChain("claude,notAProvider,onDevice") == [.claude, .onDevice])
    }
}
