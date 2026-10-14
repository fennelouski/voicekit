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
    case incompleteResponse

    var errorDescription: String? {
        switch self {
        case .missingKey: return "No API key — add one in Settings"
        case .http(let code, _): return CleanupFailure.http(code).message
        case .refusal: return "The model declined this request"
        case .emptyResponse: return "Empty response from the API"
        case .incompleteResponse: return "The model returned an incomplete transcript"
        }
    }
}

enum ClaudeCleanup {
    static let baseSystemPrompt = CleanupPrompt.baseInstructions

    /// Shared cleanup instructions for on-device and optional HTTP providers.
    static func systemPrompt(customInstructions: String, hints: [Correction] = []) -> String {
        CleanupPrompt.instructions(customInstructions: customInstructions, hints: hints)
    }

    /// Clean `text` using the key, model, and instructions from Settings.
    static func clean(_ text: String, hints: [Correction] = []) async throws -> String {
        try await clean(text, configuration: .capture(.claude), hints: hints)
    }

    static func clean(_ text: String, configuration: CleanupConfiguration, hints: [Correction] = []) async throws -> String {
        guard !configuration.apiKey.isEmpty else {
            throw ClaudeCleanupError.missingKey
        }
        let request = makeRequest(
            text: text,
            apiKey: configuration.apiKey,
            model: configuration.model,
            customInstructions: configuration.promptInstructions,
            hints: hints, maxTokens: min(16_000, max(1024, text.utf8.count / 2 + 512))
        )
        let (data, response) = try await CleanupTransport.send(request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw ClaudeCleanupError.http(http.statusCode, nil)
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
        let outputConfig: OutputConfig?

        enum CodingKeys: String, CodingKey {
            case model
            case maxTokens = "max_tokens"
            case system
            case messages
            case outputConfig = "output_config"
        }
    }

    static func makeRequest(text: String, apiKey: String, model: String, customInstructions: String, hints: [Correction] = [], maxTokens: Int = 16000) -> URLRequest {
        let system = systemPrompt(customInstructions: customInstructions, hints: hints)
        let body = RequestBody(
            model: model,
            maxTokens: maxTokens,
            system: system,
            messages: [.init(role: "user", content: CleanupPrompt.input(text))],
            // ponytail: effort low — latency-sensitive text transform, not intelligence-sensitive
            outputConfig: supportsEffort(model) ? .init(effort: "low") : nil
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

    static func supportsEffort(_ model: String) -> Bool {
        ["claude-opus-4-5", "claude-opus-4-6", "claude-opus-4-7", "claude-opus-4-8", "claude-opus-5",
         "claude-sonnet-4-6", "claude-sonnet-5", "claude-haiku-5-5"].contains { model.hasPrefix($0) }
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
        if let reason = response.stopReason, reason != "end_turn", reason != "stop_sequence" {
            throw ClaudeCleanupError.incompleteResponse
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

}
#endif
