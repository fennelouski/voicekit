//
//  OpenAICompatibleCleanupTests.swift
//  DictateTests
//
//  Tests for the OpenAI-compatible request builder and response parser.
//  No network involved.
//

import Foundation
import Testing
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
        #expect(messages?.last?["content"] as? String == "hello world")
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
}
