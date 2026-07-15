//
//  OpenAICompatibleCleanup.swift
//  Dictate
//
//  One client for every provider that speaks OpenAI chat-completions: OpenAI, Gemini (via
//  its compatibility layer), Groq, OpenRouter, and any local server (Ollama, LM Studio,
//  llama.cpp, MLX, vLLM). Any failure throws; the caller inserts the locally cleaned
//  transcript instead.
//

#if os(macOS)
import Foundation
import VoiceKit

enum OpenAICompatibleError: LocalizedError {
    case missingConfig
    case missingKey
    case http(Int, String?)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingConfig: return "Set the server URL and model name in Settings"
        case .missingKey: return "No API key — add one in Settings"
        case .http(let code, let message): return "HTTP \(code): \(message ?? "request failed")"
        case .emptyResponse: return "Empty response from the model"
        }
    }
}

enum OpenAICompatibleCleanup {
    /// Clean `text` with `provider`, using the key, model, and instructions from Settings.
    static func clean(_ text: String, provider: AIProvider, hints: [Correction] = []) async throws -> String {
        let apiKey = Settings.apiKey(for: provider) ?? ""
        if provider.requiresKey, apiKey.isEmpty {
            throw OpenAICompatibleError.missingKey
        }
        guard let request = makeRequest(
            text: text,
            baseURL: Settings.baseURL(for: provider),
            model: Settings.model(for: provider),
            customInstructions: Settings.cleanupInstructions,
            apiKey: apiKey,
            hints: hints
        ) else {
            throw OpenAICompatibleError.missingConfig
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw OpenAICompatibleError.http(http.statusCode, apiErrorMessage(from: data))
        }
        return try parseResponse(data)
    }

    // MARK: - Pure request/response pieces (unit-tested)

    /// Ollama is habitually given as a bare host ("http://localhost:11434") and needs the
    /// `/v1` it omits. Anything that already carries a path — `/v1`, Groq's `/openai/v1`,
    /// Gemini's `/v1beta/openai` — is left exactly as the provider specified it.
    static func endpointURL(baseURL: String) -> URL? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard !base.isEmpty, var components = URLComponents(string: base) else { return nil }
        if components.path.isEmpty || components.path == "/" {
            components.path = "/v1"
        }
        components.path += "/chat/completions"
        return components.url
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

    static func makeRequest(
        text: String,
        baseURL: String,
        model: String,
        customInstructions: String,
        apiKey: String = "",
        hints: [Correction] = []
    ) -> URLRequest? {
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
        // Local servers usually want no auth at all, and sending an empty bearer token
        // makes some of them 401 rather than ignore it.
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
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
            throw OpenAICompatibleError.emptyResponse
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
