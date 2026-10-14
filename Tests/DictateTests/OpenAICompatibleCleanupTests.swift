//
//  OpenAICompatibleCleanupTests.swift
//  DictateTests
//
//  Tests for the OpenAI-compatible request builder and response parser.
//  No network involved.
//

import Foundation
import Testing
import VoiceKit
@testable import Dictate

struct OpenAICompatibleCleanupTests {

    @Test func endpointURLNormalization() {
        #expect(OpenAICompatibleCleanup.endpointURL(baseURL: "http://localhost:11434")?.absoluteString
                == "http://localhost:11434/v1/chat/completions")
        #expect(OpenAICompatibleCleanup.endpointURL(baseURL: "http://localhost:11434/v1")?.absoluteString
                == "http://localhost:11434/v1/chat/completions")
        #expect(OpenAICompatibleCleanup.endpointURL(baseURL: "http://localhost:1234/v1/")?.absoluteString
                == "http://localhost:1234/v1/chat/completions")
        #expect(OpenAICompatibleCleanup.endpointURL(baseURL: "   ") == nil)
    }

    @Test func requestShape() throws {
        let request = try #require(OpenAICompatibleCleanup.makeRequest(
            text: "hello world",
            baseURL: "http://localhost:11434",
            model: "llama3.2",
            customInstructions: "Use British spelling."
        ))
        #expect(request.url?.absoluteString == "http://localhost:11434/v1/chat/completions")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        #expect(body?["model"] as? String == "llama3.2")
        #expect(body?["stream"] as? Bool == false)
        let messages = body?["messages"] as? [[String: Any]]
        #expect(messages?.count == 2)
        #expect(messages?.first?["role"] as? String == "system")
        let system = messages?.first?["content"] as? String
        #expect(system?.contains("Reply with only the cleaned text") == true)
        #expect(system?.contains("Use British spelling.") == true)
        #expect(messages?.last?["role"] as? String == "user")
        #expect(messages?.last?["content"] as? String == CleanupPrompt.input("hello world"))
    }

    @Test func emptyModelNameReturnsNil() {
        #expect(OpenAICompatibleCleanup.makeRequest(
            text: "hi", baseURL: "http://localhost:11434", model: "  ", customInstructions: ""
        ) == nil)
    }

    @Test func parsesFirstChoice() throws {
        let json = """
        {"choices":[{"index":0,"message":{"role":"assistant","content":"Hello world."},"finish_reason":"stop"}]}
        """
        #expect(try OpenAICompatibleCleanup.parseResponse(Data(json.utf8)) == "Hello world.")
    }

    @Test func stripsInlineThinking() throws {
        let json = """
        {"choices":[{"message":{"content":"<think>the user wants...\\nokay</think>\\nHello world."}}]}
        """
        #expect(try OpenAICompatibleCleanup.parseResponse(Data(json.utf8)) == "Hello world.")
    }

    @Test func emptyChoicesThrows() {
        let json = """
        {"choices":[]}
        """
        #expect(throws: OpenAICompatibleError.self) {
            try OpenAICompatibleCleanup.parseResponse(Data(json.utf8))
        }
    }

    @Test func malformedJSONThrows() {
        #expect(throws: Error.self) {
            try OpenAICompatibleCleanup.parseResponse(Data("not json".utf8))
        }
    }

    @Test func fullEndpointIsNotAppendedTwiceAndProviderPathsSurvive() {
        for base in ["https://example.test/v1/chat/completions", "https://example.test/v1/chat/completions/"] {
            #expect(OpenAICompatibleCleanup.endpointURL(baseURL: base)?.absoluteString == "https://example.test/v1/chat/completions")
        }
        #expect(OpenAICompatibleCleanup.endpointURL(baseURL: "https://api.groq.com/openai/v1")?.path == "/openai/v1/chat/completions")
        #expect(OpenAICompatibleCleanup.endpointURL(baseURL: "https://generativelanguage.googleapis.com/v1beta/openai")?.path == "/v1beta/openai/chat/completions")
    }

    @Test(arguments: ["localhost:11434", "file:///tmp/model", "/v1", "https://", "https://user:password@example.test", "https://example.test/v1?key=secret", "https://example.test/v1#fragment"])
    func invalidEndpointsAreRejected(_ base: String) {
        #expect(OpenAICompatibleCleanup.endpointURL(baseURL: base) == nil)
    }

    @Test(arguments: ["length", "content_filter", "tool_calls"])
    func partialOrNonTextGenerationsFail(_ reason: String) throws {
        let data = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": "Partial output"], "finish_reason": reason]]])
        #expect(throws: OpenAICompatibleError.self) { try OpenAICompatibleCleanup.parseResponse(data) }
    }

    @Test func unfinishedThinkingFails() throws {
        let data = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": "<think>unfinished"]]]])
        #expect(throws: CleanupOutputError.self) { try OpenAICompatibleCleanup.parseResponse(data) }
    }
}
