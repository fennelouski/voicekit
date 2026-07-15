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

    public var errorDescription: String? {
        switch self {
        case .unavailable: return "Apple Intelligence isn't available on this device"
        case .emptyResponse: return "Apple Intelligence returned nothing"
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
    public static func clean(_ text: String, hints: [Correction] = []) async throws -> String {
        guard isAvailable else { throw AICleanupError.unavailable }
        var instructions = """
            You clean up dictated text. Fix punctuation and capitalization, remove false starts \
            and repeated words, and keep the meaning and wording otherwise unchanged. \
            Reply with only the cleaned text — no preamble, no quotes.
            """
        if !hints.isEmpty {
            instructions += "\nThe user has previously corrected these transcriptions \u{2014} apply them when they occur:\n"
                + hints.map { "\"\($0.heard)\" \u{2192} \"\($0.corrected)\"" }.joined(separator: "\n")
        }
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: text)
        let cleaned = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw AICleanupError.emptyResponse }
        return cleaned
    }
}
