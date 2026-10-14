#if os(macOS)
import Foundation
import VoiceKit

/// A job owns these values from recording start. Never persist or log the key.
struct CleanupConfiguration: CustomStringConvertible, CustomDebugStringConvertible {
    let step: CleanupMode
    let model: String
    let baseURL: String
    let apiKey: String
    let instructions: String
    var vocabulary: [String] = []

    var description: String { "CleanupConfiguration(\(step.rawValue), credentials redacted)" }
    var debugDescription: String { description }

    static func capture(_ step: CleanupMode) -> Self {
        let provider = step.provider
        return Self(step: step, model: provider.map { Settings.model(for: $0) } ?? "",
                    baseURL: provider.map { Settings.baseURL(for: $0) } ?? "",
                    apiKey: provider.flatMap { Settings.apiKey(for: $0) } ?? "",
                    instructions: Settings.cleanupInstructions)
    }

    var promptInstructions: String {
        guard !vocabulary.isEmpty,
              let data = try? JSONEncoder().encode(vocabulary), let json = String(data: data, encoding: .utf8) else { return instructions }
        return instructions + "\nExact spelling vocabulary (JSON data; use only when relevant):\n" + json
    }
}

enum CleanupFailure: String, Codable, Equatable, Sendable {
    case missingKey, configuration, authentication, accessDenied, rateLimited, unavailable
    case modelNotFound, timeout, unreachable, emptyOutput, incompleteOutput, invalidOutput, unknown

    var message: String {
        switch self {
        case .missingKey: return String(localized: "Add an API key in Cleanup settings")
        case .configuration: return String(localized: "Check the server URL and model in Cleanup settings")
        case .authentication: return String(localized: "The provider rejected the API key")
        case .accessDenied: return String(localized: "The key does not have access to this model")
        case .rateLimited: return String(localized: "Provider quota or rate limit reached")
        case .unavailable: return String(localized: "The model or provider is unavailable")
        case .modelNotFound: return String(localized: "The provider could not find this model")
        case .timeout: return String(localized: "Cleanup took too long; original text kept")
        case .unreachable: return String(localized: "Could not reach the provider")
        case .emptyOutput: return String(localized: "The model returned no text")
        case .incompleteOutput: return String(localized: "The model returned incomplete text")
        case .invalidOutput: return String(localized: "The model changed or duplicated the dictation")
        case .unknown: return String(localized: "Cleanup failed; original text kept")
        }
    }

    static func http(_ status: Int) -> Self {
        switch status {
        case 401: return .authentication
        case 403: return .accessDenied
        case 404: return .modelNotFound
        case 408, 504: return .timeout
        case 429: return .rateLimited
        case 500...599: return .unavailable
        default: return .configuration
        }
    }

    static func classify(_ error: Error) -> Self {
        if let error = error as? OpenAICompatibleError {
            switch error {
            case .missingConfig: return .configuration
            case .missingKey: return .missingKey
            case .http(let status, _): return http(status)
            case .emptyResponse: return .emptyOutput
            case .incompleteResponse: return .incompleteOutput
            }
        }
        if let error = error as? ClaudeCleanupError {
            switch error {
            case .missingKey: return .missingKey
            case .http(let status, _): return http(status)
            case .emptyResponse: return .emptyOutput
            case .incompleteResponse: return .incompleteOutput
            case .refusal: return .invalidOutput
            }
        }
        if let error = error as? URLError { return error.code == .timedOut ? .timeout : .unreachable }
        if error is CleanupOutputError { return .incompleteOutput }
        if let error = error as? AICleanupError {
            switch error {
            case .unavailable: return .unavailable
            case .emptyResponse: return .emptyOutput
            case .invalidResponse: return .invalidOutput
            }
        }
        return .unknown
    }
}
#endif
