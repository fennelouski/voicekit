//
//  AIProvider.swift
//  Dictate
//
//  Which model polishes the transcript.
//
//  Every provider here except Claude speaks the OpenAI chat-completions API, so they all
//  share one client — a provider is really just a base URL, a key, and a default model.
//  Claude is the exception: Anthropic's Messages API has a different request shape.
//

#if os(macOS)
import Foundation
import VoiceKit

enum AIProvider: String, CaseIterable, Identifiable {
    case claude
    case openAI
    case gemini
    case groq
    case openRouter
    case local

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .openAI: return "OpenAI"
        case .gemini: return "Google Gemini"
        case .groq: return "Groq"
        case .openRouter: return "OpenRouter"
        case .local: return String(localized: "your local model")
        }
    }

    /// The one behavioural fork. Everything else is a base URL and a bearer token.
    var usesAnthropicAPI: Bool { self == .claude }

    /// Only the custom option lets you point at your own server; the rest are fixed endpoints.
    var editableBaseURL: Bool { self == .local }

    var requiresKey: Bool { self != .local }

    var baseURL: String {
        switch self {
        case .claude: return "https://api.anthropic.com"
        case .openAI: return "https://api.openai.com/v1"
        // Google's OpenAI-compatibility layer, so it needs no client of its own.
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta/openai"
        case .groq: return "https://api.groq.com/openai/v1"
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .local: return "http://localhost:11434/v1"
        }
    }

    /// Keychain account. Claude's predates the others and keeps its name so existing keys survive.
    var keychainAccount: String {
        switch self {
        case .claude: return Settings.claudeAPIKeyAccount
        case .openAI: return "openai-api-key"
        case .gemini: return "gemini-api-key"
        case .groq: return "groq-api-key"
        case .openRouter: return "openrouter-api-key"
        case .local: return "local-api-key"
        }
    }

    /// A starting point, not gospel — model IDs churn faster than this app ships, which is
    /// why every provider but Claude gets a free-text field rather than a fixed list.
    var defaultModel: String {
        switch self {
        case .claude: return ClaudeModel.opus.rawValue
        case .openAI: return "gpt-4o-mini"
        case .gemini: return "gemini-2.5-flash"
        case .groq: return "llama-3.3-70b-versatile"
        case .openRouter: return "openai/gpt-4o-mini"
        case .local: return ""
        }
    }

    var modelPrompt: String {
        self == .local ? "llama3.2" : defaultModel
    }

    var keyURL: URL? {
        switch self {
        case .claude: return URL(string: "https://console.anthropic.com/settings/keys")
        case .openAI: return URL(string: "https://platform.openai.com/api-keys")
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")
        case .groq: return URL(string: "https://console.groq.com/keys")
        case .openRouter: return URL(string: "https://openrouter.ai/keys")
        case .local: return nil
        }
    }

    var privacyNote: String {
        switch self {
        case .local:
            return String(localized: "Works with any OpenAI-compatible server — Ollama, LM Studio, llama.cpp, MLX, vLLM. Everything stays on your machine; if the request fails, your transcript is inserted unchanged.")
        default:
            return String(format: String(localized: "Your key is stored in the Keychain, never in preferences. Transcripts are sent to %@ to be cleaned; audio and transcription stay on this Mac. If the request fails, your transcript is inserted unchanged."), displayName)
        }
    }
}

/// The single place that decides which client a provider needs.
enum CleanupService {
    static func clean(_ text: String, provider: AIProvider, hints: [Correction] = []) async throws -> String {
        if provider.usesAnthropicAPI {
            return try await ClaudeCleanup.clean(text, hints: hints)
        }
        return try await OpenAICompatibleCleanup.clean(text, provider: provider, hints: hints)
    }
}
#endif
