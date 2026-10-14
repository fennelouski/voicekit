//
//  FileTranscriberTests.swift
//  VoiceKitTests
//
//  End-to-end check of offline file transcription using synthesized speech.
//  Explicitly opt in with VOICEKIT_HARDWARE_TESTS=1. CI reports a skip;
//  opted-in runs require authorization and synthesis instead of silently passing.
//

import Foundation
import Testing
@testable import VoiceKit

@Suite(.enabled(if: ProcessInfo.processInfo.environment["VOICEKIT_HARDWARE_TESTS"] == "1",
                 "Opt-in ASR integration: set VOICEKIT_HARDWARE_TESTS=1 on an authorized Mac"))
struct FileTranscriberTests {
    @Test func transcribesSynthesizedSpeech() async throws {
        guard #available(macOS 26.0, *) else { return }
        try #require(SpeechRecognitionService.authorizationStatus() == .authorized, "Speech permission is required")

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("filetranscriber-\(UUID().uuidString).aiff")
        defer { try? FileManager.default.removeItem(at: url) }

        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", url.path, "the quick brown fox jumps over the lazy dog"]
        try say.run()
        say.waitUntilExit()
        try #require(say.terminationStatus == 0, "Speech fixture synthesis failed")

        let segments = try await FileTranscriber.transcribe(fileAt: url, locale: Locale(identifier: "en_US"))
        let text = segments.map(\.text).joined(separator: " ").lowercased()
        #expect(text.contains("fox"))
        // Timestamps are file-relative and ordered.
        let starts = segments.compactMap(\.start)
        #expect(starts == starts.sorted())
    }
}
