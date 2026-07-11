//
//  AICleanup.swift
//  Dictate
//
//  Optional on-device polish pass using Apple Intelligence (FoundationModels).
//  Falls back to the input text if the model is unavailable or errors.
//

#if os(macOS)
import Foundation
import FoundationModels
import VoiceKit

@available(macOS 26.0, *)
enum AICleanup {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static func clean(_ text: String, hints: [Correction] = []) async -> String {
        guard isAvailable else { return text }
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
        do {
            let response = try await session.respond(to: text)
            let cleaned = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? text : cleaned
        } catch {
            return text
        }
    }
}
#endif
