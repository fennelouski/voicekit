//
//  CleanupChain.swift
//  Dictate
//
//  Cleanup is an ordered list of attempts, not a single choice. Each step is tried in turn
//  and the first one that works wins. A step with no API key isn't an error — it just isn't
//  the step that cleans your text.
//
//  The user only hears "cleanup failed" when *every* step failed, because that's the only
//  case where the failure changed what they got.
//

#if os(macOS)
import Foundation
import VoiceKit

enum CleanupChain {
    struct Result: Equatable {
        /// The cleaned text, or the original if nothing in the chain worked.
        let text: String
        /// The step that produced it. Nil means every step failed.
        let usedStep: CleanupMode?
        /// Steps that were tried and didn't work, in order.
        let failed: [CleanupMode]

        /// Only true when the chain had work to do and none of it landed.
        var allFailed: Bool { usedStep == nil && !failed.isEmpty }
    }

    /// Run `chain` in order, taking the first success.
    ///
    /// `runStep` is injected — pass `liveStep` in the app — so the ordering and fallback
    /// logic can be tested without a network, an API key, or Apple Intelligence. It also
    /// keeps this logic free of the macOS 26 gate that `liveStep` carries.
    static func run(
        _ text: String,
        chain: [CleanupMode],
        hints: [Correction] = [],
        runStep: (String, CleanupMode, [Correction]) async throws -> String
    ) async -> Result {
        var failed: [CleanupMode] = []

        for step in chain where step != .off {
            do {
                let cleaned = try await runStep(text, step, hints)
                let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
                // A step that hands back nothing hasn't cleaned anything — keep going rather
                // than inserting an empty string.
                guard !trimmed.isEmpty else {
                    failed.append(step)
                    continue
                }
                // A step that answered, refused, or otherwise rewrote the transcript isn't a
                // cleanup — discard it so we never paste words the user didn't say.
                guard TranscriptCleaner.preservesWording(original: text, cleaned: trimmed) else {
                    failed.append(step)
                    continue
                }
                return Result(text: trimmed, usedStep: step, failed: failed)
            } catch {
                failed.append(step)
            }
        }

        // Never lose the transcript: the caller inserts the locally cleaned text as-is.
        return Result(text: text, usedStep: nil, failed: failed)
    }

    /// Where a newly added step belongs.
    ///
    /// Above the on-device pass, not below it. On-device is the last-resort fallback — it's
    /// free and needs no key, so it almost always succeeds. A step added *underneath* it
    /// would never run, because the chain stops at the first step that works.
    static func adding(_ step: CleanupMode, to chain: [CleanupMode]) -> [CleanupMode] {
        guard step != .off, !chain.contains(step) else { return chain }
        guard step != .onDevice, let fallback = chain.firstIndex(of: .onDevice) else {
            return chain + [step]
        }
        var updated = chain
        updated.insert(step, at: fallback)
        return updated
    }

    /// The real thing: on-device via Apple Intelligence, everything else via its provider.
    @available(macOS 26.0, *)
    static func liveStep(_ text: String, step: CleanupMode, hints: [Correction]) async throws -> String {
        switch step {
        case .off:
            return text
        case .onDevice:
            return try await AICleanup.clean(text, hints: hints)
        default:
            guard let provider = step.provider else { return text }
            return try await CleanupService.clean(text, provider: provider, hints: hints)
        }
    }
}
#endif
