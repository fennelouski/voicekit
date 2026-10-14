import Foundation

public enum DictationSpacing {
    /// Separate successive dictations in spaced languages. Chinese and Japanese
    /// text should not accumulate ASCII spaces; Korean still uses word spaces.
    public static func appendingSeparator(to text: String) -> String {
        guard let last = text.last, !last.isWhitespace else { return text }
        let ending = String(last)
        let unspaced = "[\\p{Han}\\p{Hiragana}\\p{Katakana}\\u3000-\\u303F\\uFF00-\\uFF65\\uFE10-\\uFE1F\\uFE30-\\uFE4F]$"
        guard ending.range(of: unspaced, options: .regularExpression) == nil else { return text }
        return text + " "
    }
}
