//
//  AICleanup.swift
//  VoiceKit
//
//  Optional on-device polish pass using Apple Intelligence (FoundationModels).
//  Throws if the model is unavailable or errors — the caller decides the fallback.
//

import Foundation
import FoundationModels

public enum AICleanupError: LocalizedError {
    case unavailable
    case emptyResponse
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .unavailable: return "Apple Intelligence isn't available on this device"
        case .emptyResponse: return "Apple Intelligence returned nothing"
        case .invalidResponse: return "Apple Intelligence changed the dictated wording"
        }
    }
}

@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
public enum AICleanup {
    public static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Throws rather than quietly handing back the input. A cleanup chain has to be able to
    /// tell "Apple Intelligence polished this" apart from "Apple Intelligence did nothing" —
    /// otherwise an unavailable model looks like a success and the chain stops at it.
    public static func clean(_ text: String, hints: [Correction] = [], customInstructions: String = "") async throws -> String {
        let prepared = PreparedSession(customInstructions: customInstructions)
        return try await prepared.clean(text, hints: hints)
    }

    /// A fresh session per dictation. Only explicitly opted-in polishing loads this
    /// model; no conversation or prior dictation is carried into the next request.
    public actor PreparedSession {
        private let session: LanguageModelSession
        public init(customInstructions: String = "") {
            session = LanguageModelSession(instructions: CleanupPrompt.instructions(customInstructions: customInstructions))
        }
        public func prewarm() {
            guard AICleanup.isAvailable else { return }
            session.prewarm()
        }
        public func clean(_ text: String, hints: [Correction] = []) async throws -> String {
            try Task.checkCancellation()
            guard AICleanup.isAvailable else { throw AICleanupError.unavailable }
            let prompt = CleanupPrompt.input(text) + CleanupPrompt.spellingHints(hints)
            let response = try await session.respond(to: prompt)
            try Task.checkCancellation()
            let cleaned = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { throw AICleanupError.emptyResponse }
            guard TranscriptCleaner.preservesWording(original: text, cleaned: cleaned) else {
                throw AICleanupError.invalidResponse
            }
            return cleaned
        }
    }
}
