import Foundation

/// Explicit spelling preferences, separate from learned substitutions. Budgets
/// keep cleanup prompts and local replacements bounded.
public final class VocabularyStore {
    public static let maximumTerms = 64
    public static let maximumTermLength = 80
    public static let maximumCharacters = 4096
    public enum ValidationError: Error { case invalidTerm, tooManyTerms, tooLong }
    private let fileURL: URL
    public private(set) var terms: [String] = []

    public init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL), let values = try? JSONDecoder().decode([String].self, from: data),
           let valid = try? Self.validate(values) { terms = valid }
    }

    public func setTerms(_ values: [String]) throws {
        let valid = try Self.validate(values)
        let data = try JSONEncoder().encode(valid)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        terms = valid
    }

    public static func validate(_ values: [String]) throws -> [String] {
        var result: [String] = []
        var seen: Set<String> = []
        for value in values {
            let term = value.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
            guard !term.isEmpty, term.count <= maximumTermLength,
                  term.rangeOfCharacter(from: .controlCharacters) == nil else { throw ValidationError.invalidTerm }
            if seen.insert(term.lowercased()).inserted { result.append(term) }
        }
        guard result.count <= maximumTerms else { throw ValidationError.tooManyTerms }
        guard result.reduce(0, { $0 + $1.count }) <= maximumCharacters else { throw ValidationError.tooLong }
        return result
    }

    public static func applySpellings(to text: String, terms: [String]) -> String {
        var result = text
        for term in terms.sorted(by: { $0.count > $1.count }) {
            let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: term) + "(?![\\p{L}\\p{N}])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result),
                                                    withTemplate: NSRegularExpression.escapedTemplate(for: term))
        }
        return result
    }
}
