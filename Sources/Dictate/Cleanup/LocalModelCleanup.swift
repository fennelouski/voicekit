//
//  LocalModelCleanup.swift
//  Dictate
//
//  Bring-your-own-model cleanup via any OpenAI-compatible chat-completions
//  server (Ollama, LM Studio, llama.cpp, MLX, vLLM). Any failure throws;
//  the caller inserts the locally cleaned transcript instead.
//

#if os(macOS)
import Foundation
import VoiceKit

enum LocalModelCleanupError: LocalizedError {
    case missingConfig
    case http(Int, String?)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingConfig: return "Set the server URL and model name in Settings"
        case .http(let code, let message): return "HTTP \(code): \(message ?? "request failed")"
        case .emptyResponse: return "Empty response from the local model"
        }
    }
}

enum LocalModelCleanup {
    /// Clean `text` using the server URL and model from Settings.
    static func clean(_ text: String, hints: [Correction] = []) async throws -> String {
        guard let request = makeRequest(
            text: text,
            baseURL: Settings.localModelBaseURL,
            model: Settings.localModelName,
            customInstructions: Settings.cleanupInstructions,
            hints: hints
        ) else {
            throw LocalModelCleanupError.missingConfig
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw LocalModelCleanupError.http(http.statusCode, apiErrorMessage(from: data))
        }
        return try parseResponse(data)
    }

    // MARK: - Pure request/response pieces (unit-tested)

    /// "http://localhost:11434" and "http://localhost:11434/v1" both resolve
    /// to ".../v1/chat/completions".
    static func endpointURL(baseURL: String) -> URL? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard !base.isEmpty else { return nil }
        if !base.hasSuffix("/v1") { base += "/v1" }
        return URL(string: base + "/chat/completions")
    }

    struct RequestBody: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        let model: String
        let messages: [Message]
        let stream: Bool
    }

    static func makeRequest(text: String, baseURL: String, model: String, customInstructions: String, hints: [Correction] = []) -> URLRequest? {
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty, let url = endpointURL(baseURL: baseURL) else { return nil }

        let body = RequestBody(
            model: model,
            messages: [
                .init(role: "system", content: ClaudeCleanup.systemPrompt(customInstructions: customInstructions, hints: hints)),
                .init(role: "user", content: text),
            ],
            stream: false
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // ponytail: 30s — local models can be slow to cold-load; fallback covers the rest
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(body)
        return request
    }

    struct ResponseBody: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }
            let message: Message
        }

        let choices: [Choice]
    }

    static func parseResponse(_ data: Data) throws -> String {
        let response = try JSONDecoder().decode(ResponseBody.self, from: data)
        var text = response.choices.first?.message.content ?? ""
        // Reasoning models (e.g. deepseek-r1) inline their thinking — strip it.
        text = text.replacingOccurrences(
            of: "<think>[\\s\\S]*?</think>",
            with: "",
            options: .regularExpression
        )
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw LocalModelCleanupError.emptyResponse
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
