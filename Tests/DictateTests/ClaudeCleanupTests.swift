//
//  ClaudeCleanupTests.swift
//  DictateTests
//
//  Tests for the Anthropic Messages API request builder and response parser.
//  No network involved.
//

import Foundation
import Testing
@testable import Dictate

struct ClaudeCleanupTests {

    @Test func requestShape() throws {
        let request = ClaudeCleanup.makeRequest(
            text: "hello world",
            apiKey: "sk-test",
            model: "claude-opus-4-8",
            customInstructions: ""
        )
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        #expect(body?["model"] as? String == "claude-opus-4-8")
        #expect(body?["max_tokens"] as? Int == 16000)
        #expect((body?["output_config"] as? [String: Any])?["effort"] as? String == "low")
        let messages = body?["messages"] as? [[String: Any]]
        #expect(messages?.count == 1)
        #expect(messages?.first?["role"] as? String == "user")
        #expect(messages?.first?["content"] as? String == "hello world")
        #expect((body?["system"] as? String)?.contains("Reply with only the cleaned text") == true)
    }

    @Test func customInstructionsAppendedToSystemPrompt() throws {
        let request = ClaudeCleanup.makeRequest(
            text: "hi",
            apiKey: "k",
            model: "m",
            customInstructions: "Always use British spelling."
        )
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        let system = body?["system"] as? String
        #expect(system?.contains("Always use British spelling.") == true)
        #expect(system?.contains("Reply with only the cleaned text") == true)
    }

    @Test func parsesAndJoinsTextBlocks() throws {
        let json = """
        {"content":[{"type":"text","text":"Hello "},{"type":"text","text":"world."}],"stop_reason":"end_turn"}
        """
        #expect(try ClaudeCleanup.parseResponse(Data(json.utf8)) == "Hello world.")
    }

    @Test func refusalThrows() {
        let json = """
        {"content":[{"type":"text","text":"partial"}],"stop_reason":"refusal"}
        """
        #expect(throws: ClaudeCleanupError.self) {
            try ClaudeCleanup.parseResponse(Data(json.utf8))
        }
    }

    @Test func emptyContentThrows() {
        let json = """
        {"content":[],"stop_reason":"end_turn"}
        """
        #expect(throws: ClaudeCleanupError.self) {
            try ClaudeCleanup.parseResponse(Data(json.utf8))
        }
    }

    @Test func nonTextBlocksIgnored() {
        let json = """
        {"content":[{"type":"thinking","text":null}],"stop_reason":"end_turn"}
        """
        #expect(throws: ClaudeCleanupError.self) {
            try ClaudeCleanup.parseResponse(Data(json.utf8))
        }
    }

    @Test func malformedJSONThrows() {
        #expect(throws: Error.self) {
            try ClaudeCleanup.parseResponse(Data("not json".utf8))
        }
    }
}

struct KeychainStoreTests {

    @Test func roundtrip() {
        let account = "test-\(UUID().uuidString)"
        KeychainStore.set("secret123", forKey: account)
        #expect(KeychainStore.string(forKey: account) == "secret123")
        KeychainStore.set("updated", forKey: account)
        #expect(KeychainStore.string(forKey: account) == "updated")
        KeychainStore.set(nil, forKey: account)
        #expect(KeychainStore.string(forKey: account) == nil)
    }

    @Test func emptyStringDeletes() {
        let account = "test-\(UUID().uuidString)"
        KeychainStore.set("value", forKey: account)
        KeychainStore.set("", forKey: account)
        #expect(KeychainStore.string(forKey: account) == nil)
    }
}
