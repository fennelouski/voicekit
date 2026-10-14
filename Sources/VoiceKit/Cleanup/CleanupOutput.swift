import Foundation

public enum CleanupOutputError: Error {
    case unfinishedReasoning
}

public enum CleanupOutput {
    /// Remove reasoning from local models, including nested and case-varied tags.
    /// An unfinished block means generation stopped before a complete answer.
    public static func removingReasoning(from text: String) throws -> String {
        let regex = try NSRegularExpression(pattern: "<(/?)think>", options: [.caseInsensitive])
        let source = text as NSString
        var depth = 0
        var cursor = 0
        var result = ""
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            if depth == 0 {
                result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            }
            let closing = source.substring(with: match.range(at: 1)) == "/"
            depth = closing ? max(0, depth - 1) : depth + 1
            cursor = NSMaxRange(match.range)
        }
        guard depth == 0 else { throw CleanupOutputError.unfinishedReasoning }
        result += source.substring(from: cursor)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
