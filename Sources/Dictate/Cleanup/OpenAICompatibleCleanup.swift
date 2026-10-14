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
    case incompleteResponse

    var errorDescription: String? {
        switch self {
        case .missingConfig: return "Set the server URL and model name in Settings"
        case .missingKey: return "No API key — add one in Settings"
        case .http(let code, _): return CleanupFailure.http(code).message
        case .emptyResponse: return "Empty response from the model"
        case .incompleteResponse: return "The model returned an incomplete transcript"
        }
    }
}

enum OpenAICompatibleCleanup {
    /// Clean `text` with `provider`, using the key, model, and instructions from Settings.
    static func clean(_ text: String, provider: AIProvider, hints: [Correction] = []) async throws -> String {
        guard let step = CleanupMode.chainable.first(where: { $0.provider == provider }) else { throw OpenAICompatibleError.missingConfig }
        return try await clean(text, configuration: .capture(step), hints: hints)
    }

    static func clean(_ text: String, configuration: CleanupConfiguration, hints: [Correction] = []) async throws -> String {
        guard let provider = configuration.step.provider else { throw OpenAICompatibleError.missingConfig }
        let apiKey = configuration.apiKey
        if provider.requiresKey, apiKey.isEmpty {
            throw OpenAICompatibleError.missingKey
        }
        guard let request = makeRequest(
            text: text,
            baseURL: configuration.baseURL,
            model: configuration.model,
            customInstructions: configuration.promptInstructions,
            apiKey: apiKey,
            hints: hints
        ) else {
            throw OpenAICompatibleError.missingConfig
        }
        let (data, response) = try await CleanupTransport.send(request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw OpenAICompatibleError.http(http.statusCode, nil)
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
        guard !base.isEmpty, var components = URLComponents(string: base),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else { return nil }
        if components.path.isEmpty || components.path == "/" {
            components.path = "/v1"
        }
        if !components.path.hasSuffix("/chat/completions") {
            components.path += "/chat/completions"
        }
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
        var maxTokens: Int? = nil
        var maxCompletionTokens: Int? = nil
        var reasoningEffort: String? = nil
        enum CodingKeys: String, CodingKey {
            case model, messages, stream
            case maxTokens = "max_tokens"
            case maxCompletionTokens = "max_completion_tokens"
            case reasoningEffort = "reasoning_effort"
        }
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

        var body = RequestBody(
            model: model,
            messages: [
                .init(role: "system", content: CleanupPrompt.instructions(customInstructions: customInstructions, hints: hints)),
                .init(role: "user", content: CleanupPrompt.input(text)),
            ],
            stream: false
        )

        // Apply model-specific knobs only to the known official OpenAI host.
        // Compatible/custom servers keep the minimal request unless configured.
        if url.host?.lowercased() == "api.openai.com" {
            let reasoning = model.hasPrefix("gpt-5") || model.hasPrefix("o1") || model.hasPrefix("o3") || model.hasPrefix("o4")
            if reasoning {
                body.maxCompletionTokens = 25_000
                body.reasoningEffort = "low"
            } else {
                body.maxTokens = min(16_000, max(1024, text.utf8.count / 2 + 512))
            }
        }
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
            let finishReason: String?

            enum CodingKeys: String, CodingKey {
                case message
                case finishReason = "finish_reason"
            }
        }

        let choices: [Choice]
    }

    static func parseResponse(_ data: Data) throws -> String {
        let response = try JSONDecoder().decode(ResponseBody.self, from: data)
        let choice = response.choices.first
        // Minimal local servers can omit this field. When provided, only a
        // completed generation is usable; token limits must fall through.
        if let reason = choice?.finishReason, reason != "stop" {
            throw OpenAICompatibleError.incompleteResponse
        }
        let text = try CleanupOutput.removingReasoning(from: choice?.message.content ?? "")
        guard !text.isEmpty else {
            throw OpenAICompatibleError.emptyResponse
        }
        return text
    }

}
#endif
