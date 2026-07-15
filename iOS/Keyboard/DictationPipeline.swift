//
//  DictationPipeline.swift
//  DictateKeyboard
//
//  Raw transcript in, the text we type into the document out.
//
//  Split out from the view controller because it is the only part with branches worth
//  testing, and a keyboard extension can't be exercised from a test host.
//

import Foundation
import VoiceKit

enum DictationPipeline {
    struct Output: Equatable {
        /// The text to insert. Empty means the user said nothing worth typing.
        let text: String
        /// True when the polish pass was tried and failed — the text is still good,
        /// it just wasn't polished.
        let polishFailed: Bool
    }

    /// Local cleanup always runs; the polish pass is allowed to fail.
    ///
    /// Losing a transcript because Apple Intelligence was busy would be worse than typing
    /// it unpolished, so a failed polish falls back to the locally cleaned text.
    static func run(
        raw: String,
        polish: (String) async throws -> String
    ) async -> Output {
        let cleaned = TranscriptCleaner.clean(raw)
        guard !cleaned.isEmpty else { return Output(text: "", polishFailed: false) }

        var text = cleaned
        var polishFailed = false
        do {
            let polished = try await polish(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
            // An empty answer isn't a polish, it's a failure that would eat the transcript.
            if polished.isEmpty { polishFailed = true } else { text = polished }
        } catch {
            polishFailed = true
        }

        // Trailing space so back-to-back dictations don't run together.
        if let last = text.last, !last.isWhitespace { text += " " }
        return Output(text: text, polishFailed: polishFailed)
    }
}
