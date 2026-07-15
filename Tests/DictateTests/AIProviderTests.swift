//
//  AIProviderTests.swift
//  DictateTests
//
//  The provider table, and the URL building that has to be right for every one of them —
//  a wrong endpoint is a 404 the user can only diagnose by reading our source.
//

import Foundation
import Testing
@testable import Dictate

struct AIProviderTests {

    /// `CleanupMode` and `AIProvider` share raw values on purpose. If someone adds a case to
    /// one and not the other, this catches it.
    @Test func everyCloudModeMapsToAProvider() {
        #expect(CleanupMode.off.provider == nil)
        #expect(CleanupMode.onDevice.provider == nil)

        for mode in CleanupMode.allCases where mode != .off && mode != .onDevice {
            #expect(mode.provider != nil, "\(mode) has no provider")
        }
        // Every provider is reachable from the picker.
        for provider in AIProvider.allCases {
            #expect(CleanupMode(rawValue: provider.rawValue) != nil, "\(provider) has no mode")
        }
    }

    /// The `/v1` fixup exists for Ollama's bare host. It must not mangle providers that
    /// already carry a path — Gemini's `/v1beta/openai` is the one that would break.
    @Test func everyProviderBuildsItsRealEndpoint() {
        let expected: [AIProvider: String] = [
            .openAI: "https://api.openai.com/v1/chat/completions",
            .gemini: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
            .groq: "https://api.groq.com/openai/v1/chat/completions",
            .openRouter: "https://openrouter.ai/api/v1/chat/completions",
            .local: "http://localhost:11434/v1/chat/completions",
        ]
        for (provider, url) in expected {
            #expect(
                OpenAICompatibleCleanup.endpointURL(baseURL: provider.baseURL)?.absoluteString == url,
                "\(provider) built the wrong endpoint"
            )
        }
    }

    /// Claude doesn't go through this client at all — it speaks Anthropic's Messages API.
    @Test func claudeIsTheOnlyAnthropicProvider() {
        #expect(AIProvider.claude.usesAnthropicAPI)
        for provider in AIProvider.allCases where provider != .claude {
            #expect(!provider.usesAnthropicAPI, "\(provider) should use the OpenAI-compatible client")
        }
    }

    /// A key goes in the Authorization header for the cloud providers, and local servers
    /// must get no header at all — some of them 401 on an empty bearer token.
    @Test func keyBecomesABearerTokenAndIsOmittedWhenAbsent() throws {
        let withKey = try #require(OpenAICompatibleCleanup.makeRequest(
            text: "hi",
            baseURL: AIProvider.openAI.baseURL,
            model: "gpt-4o-mini",
            customInstructions: "",
            apiKey: "sk-test-123"
        ))
        #expect(withKey.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test-123")

        let noKey = try #require(OpenAICompatibleCleanup.makeRequest(
            text: "hi",
            baseURL: AIProvider.local.baseURL,
            model: "llama3.2",
            customInstructions: ""
        ))
        #expect(noKey.value(forHTTPHeaderField: "Authorization") == nil)
    }

    /// Each provider gets its own Keychain account and defaults key, so switching providers
    /// doesn't overwrite the key or model you set for the last one.
    @Test func providerConfigIsKeptApart() {
        let accounts = AIProvider.allCases.map(\.keychainAccount)
        #expect(Set(accounts).count == accounts.count, "two providers share a Keychain account")

        let modelKeys = AIProvider.allCases.map { Settings.modelKey(for: $0) }
        #expect(Set(modelKeys).count == modelKeys.count, "two providers share a model key")

        // The key Claude has always used, so upgrading doesn't lose it.
        #expect(AIProvider.claude.keychainAccount == "anthropic-api-key")
    }

    @Test func onlyTheCustomProviderExposesItsServerURL() {
        #expect(AIProvider.local.editableBaseURL)
        #expect(!AIProvider.local.requiresKey)
        for provider in AIProvider.allCases where provider != .local {
            #expect(!provider.editableBaseURL, "\(provider) has a fixed endpoint")
            #expect(provider.requiresKey, "\(provider) is a cloud service and needs a key")
            #expect(provider.keyURL != nil, "\(provider) should tell the user where to get a key")
            #expect(!provider.defaultModel.isEmpty, "\(provider) needs a starting model")
        }
    }
}
