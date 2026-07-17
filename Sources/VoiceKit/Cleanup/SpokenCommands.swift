//
//  SpokenCommands.swift
//  VoiceKit
//
//  Turns spoken formatting commands into literal punctuation and line breaks,
//  the way system dictation does: "colon" → ":", "new line" → a line break.
//
//  Deterministic on purpose. A cleanup model can't be trusted to emit an exact
//  literal — and Dictate's cleanup guard (`preservesWording`) rejects any pass
//  that changes wording, so the model *couldn't* do this even if it wanted to.
//

import Foundation

public enum SpokenCommands {
    /// Spoken phrase → the literal it becomes. Multi-word phrases win first (see `phrases`),
    /// so "new line" is taken before "line" is ever considered on its own.
    // ponytail: fixed table, always converts — the same tradeoff Apple/Dragon dictation make.
    // Known ceiling: ambiguity ("a new line of work" → a break). Add a per-user off-switch or a
    // spoken "no format" escape if that friction ever actually shows up.
    static let table: [(spoken: String, literal: String)] = [
        ("new paragraph", "\n\n"),
        ("new line", "\n"),
        ("open parenthesis", "("),
        ("close parenthesis", ")"),
        ("open paren", "("),
        ("close paren", ")"),
        ("open quote", "\u{201C}"),
        ("close quote", "\u{201D}"),
        ("question mark", "?"),
        ("exclamation point", "!"),
        ("exclamation mark", "!"),
        ("full stop", "."),
        ("period", "."),
        ("comma", ","),
        ("colon", ":"),
        ("semicolon", ";"),
        ("hyphen", "-"),
        ("ampersand", "&"),
        ("asterisk", "*"),
    ]

    /// No space *before* these literals — they hug the preceding word ("word:", "word.").
    private static let hugsLeft: Set<Character> = [",", ".", ";", ":", "!", "?", ")", "\u{201D}", "\n", "-"]
    /// No space *after* these literals — the next word hugs them ("(word", a break).
    private static let hugsRight: Set<Character> = ["(", "\u{201C}", "\n", "-"]

    /// Table pre-tokenised and sorted longest-first for greedy matching.
    private static let phrases: [(words: [String], literal: String)] =
        table.map { (normalize($0.spoken).split(separator: " ").map(String.init), $0.literal) }
             .sorted { $0.words.count > $1.words.count }

    /// Replace every spoken command in `text` with its literal, fixing the spacing around it.
    public static func apply(_ text: String) -> String {
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var pieces: [(text: String, literal: Bool)] = []
        var i = 0
        while i < tokens.count {
            if let match = phrases.first(where: { p in
                i + p.words.count <= tokens.count &&
                    zip(p.words, tokens[i..<i + p.words.count]).allSatisfy { $0 == normalize($1) }
            }) {
                pieces.append((match.literal, true))
                i += match.words.count
            } else {
                pieces.append((tokens[i], false))
                i += 1
            }
        }
        return join(pieces)
    }

    private static func join(_ pieces: [(text: String, literal: Bool)]) -> String {
        var out = ""
        var suppressSpace = true   // no leading space at the very start
        for piece in pieces {
            let hugLeft = piece.literal && piece.text.first.map(hugsLeft.contains) == true
            if !suppressSpace && !hugLeft { out += " " }
            out += piece.text
            suppressSpace = piece.literal && piece.text.last.map(hugsRight.contains) == true
        }
        return out
    }

    /// Lowercased, edge-punctuation-stripped form used only for matching (never for output),
    /// so "New" and "line." still match "new" and "line".
    private static func normalize(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    }
}
