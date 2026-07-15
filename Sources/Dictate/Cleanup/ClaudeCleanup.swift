//
//  ClaudeCleanup.swift
//  Dictate
//
//  Optional cloud polish pass using the Anthropic Messages API (bring your
//  own key). Raw URLSession — Swift has no official Anthropic SDK. Any
//  failure throws; the caller inserts the locally cleaned transcript instead.
//

#if os(macOS)
import Foundation
import VoiceKit

enum ClaudeCleanupError: LocalizedError {
    case missingKey
    case http(Int, String?)
    case refusal
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingKey: return "No API key — add one in Settings"
        case .http(let code, let message): return "HTTP \(code): \(message ?? "request failed")"
        case .refusal: return "The model declined this request"
        case .emptyResponse: return "Empty response from the API"
        }
    }
}

enum ClaudeCleanup {
    static let baseSystemPrompt = """
        You clean up dictated text. Fix punctuation, capitalization, and sentence structure; \
        remove filler words, false starts, and repeated words; keep the meaning and wording \
        otherwise unchanged. Reply with only the cleaned text — no preamble, no quotes, no commentary.
        """

    /// Shared with LocalModelCleanup — same job, same prompt.
    static func systemPrompt(customInstructions: String, hints: [Correction] = []) -> String {
        var system = baseSystemPrompt
        let custom = customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            system += "\n\nAdditional instructions from the user:\n\(custom)"
        }
        if !hints.isEmpty {
            system += "\n\nThe user has previously corrected these transcriptions \u{2014} apply them when they occur:\n"
                + hints.map { "\"\($0.heard)\" \u{2192} \"\($0.corrected)\"" }.joined(separator: "\n")
        }
        return system
    }

    /// Clean `text` using the key, model, and instructions from Settings.
    static func clean(_ text: String, hints: [Correction] = []) async throws -> String {
        guard let apiKey = Settings.apiKey(for: .claude), !apiKey.isEmpty else {
            throw ClaudeCleanupError.missingKey
        }
        let request = makeRequest(
            text: text,
            apiKey: apiKey,
            model: Settings.model(for: .claude),
            customInstructions: Settings.cleanupInstructions,
            hints: hints
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw ClaudeCleanupError.http(http.statusCode, apiErrorMessage(from: data))
        }
        return try parseResponse(data)
    }

    // MARK: - Pure request/response pieces (unit-tested)

    struct RequestBody: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        struct OutputConfig: Encodable {
            let effort: String
        }

        let model: String
        let maxTokens: Int
        let system: String
        let messages: [Message]
        let outputConfig: OutputConfig

        enum CodingKeys: String, CodingKey {
            case model
            case maxTokens = "max_tokens"
            case system
            case messages
            case outputConfig = "output_config"
        }
    }

    static func makeRequest(text: String, apiKey: String, model: String, customInstructions: String, hints: [Correction] = []) -> URLRequest {
        let system = systemPrompt(customInstructions: customInstructions, hints: hints)
        let body = RequestBody(
            model: model,
            maxTokens: 16000,
            system: system,
            messages: [.init(role: "user", content: text)],
            // ponytail: effort low — latency-sensitive text transform, not intelligence-sensitive
            outputConfig: .init(effort: "low")
        )

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(body)
        return request
    }

    struct ResponseBody: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }

        let content: [Block]
        let stopReason: String?

        enum CodingKeys: String, CodingKey {
            case content
            case stopReason = "stop_reason"
        }
    }

    static func parseResponse(_ data: Data) throws -> String {
        let response = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard response.stopReason != "refusal" else {
            throw ClaudeCleanupError.refusal
        }
        let text = response.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw ClaudeCleanupError.emptyResponse
        }
        return text
    }

    private static func apiErrorMessage(from data: Data) -> String? {
        struct ErrorEnvelope: Decodable {
            struct APIError: Decodable { let message: String }
            let error: APIError
        }
        return (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error.message
    }
}
#endif
