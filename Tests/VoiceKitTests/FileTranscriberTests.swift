//
//  FileTranscriberTests.swift
//  VoiceKitTests
//
//  End-to-end check of offline file transcription using synthesized speech.
//  Skips (passes) when speech auth or the on-device model isn't available,
//  so it stays green on CI and fresh machines.
//

import Foundation
import Testing
@testable import VoiceKit

struct FileTranscriberTests {
    @Test func transcribesSynthesizedSpeech() async throws {
        guard #available(macOS 26.0, *) else { return }
        guard SpeechRecognitionService.authorizationStatus() == .authorized else { return }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("filetranscriber-\(UUID().uuidString).aiff")
        defer { try? FileManager.default.removeItem(at: url) }

        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", url.path, "the quick brown fox jumps over the lazy dog"]
        try say.run()
        say.waitUntilExit()
        guard say.terminationStatus == 0 else { return }

        let segments = try await FileTranscriber.transcribe(fileAt: url, locale: Locale(identifier: "en_US"))
        let text = segments.map(\.text).joined(separator: " ").lowercased()
        #expect(text.contains("fox"))
        // Timestamps are file-relative and ordered.
        let starts = segments.compactMap(\.start)
        #expect(starts == starts.sorted())
    }
}
