import Foundation
import NaturalLanguage

/// Case/punctuation-insensitive scores, reported with raw text for inspection.
/// WER uses Apple's Unicode word tokenizer; CER counts NFC graphemes, no spaces.
enum EvaluationMetrics {
    struct Score: Codable, Equatable {
        let wordEdits: Int
        let referenceWords: Int
        let characterEdits: Int
        let referenceCharacters: Int
        var wordErrorRate: Double { Double(wordEdits) / Double(max(1, referenceWords)) }
        var characterErrorRate: Double { Double(characterEdits) / Double(max(1, referenceCharacters)) }
    }
    static func score(reference: String, hypothesis: String) -> Score {
        func normalize(_ text: String) -> String { text.precomposedStringWithCanonicalMapping.lowercased() }
        func words(_ text: String) -> [String] {
            let tokenizer = NLTokenizer(unit: .word)
            tokenizer.string = text
            return tokenizer.tokens(for: text.startIndex..<text.endIndex).compactMap { range in
                let word = String(text[range])
                return word.rangeOfCharacter(from: .alphanumerics) == nil ? nil : word
            }
        }
        func characters(_ text: String) -> [Character] {
            Array(text.filter { !$0.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).contains($0) } })
        }
        let ref = normalize(reference), hyp = normalize(hypothesis)
        let refWords = words(ref), hypWords = words(hyp)
        let refCharacters = characters(ref), hypCharacters = characters(hyp)
        return Score(wordEdits: distance(refWords, hypWords), referenceWords: refWords.count,
                     characterEdits: distance(refCharacters, hypCharacters), referenceCharacters: refCharacters.count)
    }
    private static func distance<T: Equatable>(_ reference: [T], _ hypothesis: [T]) -> Int {
        var previous = Array(0...hypothesis.count)
        for (i, token) in reference.enumerated() {
            var row = [i + 1]
            for (j, other) in hypothesis.enumerated() {
                row.append(min(row[j] + 1, previous[j + 1] + 1, previous[j] + (token == other ? 0 : 1)))
            }
            previous = row
        }
        return previous.last ?? reference.count
    }
}
