//
//  LiveCaptureRecoveryTests.swift
//  VoiceKitTests
//
//  The two recovery paths that only a real microphone can prove: restarting capture
//  mid-session without losing the transcript, and refusing to die on a device ID that
//  no longer names anything. Both are unreachable from a unit test — the failure they
//  guard lives in Core Audio, not in our bookkeeping.
//
//  Skips (passes) without speech authorization or an input device.
//

import AVFoundation
import Foundation
import Testing
@testable import VoiceKit

#if os(macOS)
struct LiveCaptureRecoveryTests {

    /// Speak through the speakers so the microphone hears it. Crude, and exactly what the
    /// real failure needs: audio arriving from hardware rather than from a file.
    private func speak(_ phrase: String) {
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-r", "170", phrase]
        try? say.run()
        say.waitUntilExit()
    }

    /// The watchdog's whole job, minus the timer: tear the microphone down mid-sentence and
    /// bring it back, and the words from before the break must still be there afterwards.
    @Test func captureRestartsMidSessionAndTheTranscriptCarriesOn() async throws {
        guard #available(macOS 26.0, *) else { return }
        guard SpeechRecognitionService.authorizationStatus() == .authorized else { return }
        let service = SpeechRecognitionService()
        let session = try await service.startRecognition(locale: Locale(identifier: "en_US"))

        // Folded the way the app folds it: a result's text covers the current utterance
        // only, and the restart ends one, so reading the last result alone would show the
        // first half missing when it is merely committed.
        let collected = Task {
            var accumulator = TranscriptAccumulator()
            for await result in session.transcript { accumulator.add(result) }
            return accumulator.preview
        }

        speak("the quick brown fox")
        try await Task.sleep(for: .seconds(1))

        // Everything the watchdog does once it decides the microphone is gone.
        let restarted = await service.restartCapture()
        #expect(restarted, "capture should come back")

        // Buffers flowing again is the restart working; the transcript is the point.
        try await Task.sleep(for: .milliseconds(500))
        let gap = await service.silenceDuration()
        #expect(gap < 1, "the microphone should be feeding us again, gap was \(gap)s")

        speak("jumps over the lazy dog")
        try await Task.sleep(for: .seconds(1))

        _ = await service.stopRecognition()
        let text = await collected.value.lowercased()
        // Both halves in one transcript: the restart didn't reset the analyzer.
        #expect(text.contains("fox"), "lost what was said before the restart: \(text)")
        #expect(text.contains("dog"), "lost what was said after the restart: \(text)")
    }

    /// A device ID that named a microphone yesterday and nothing today. The session must
    /// start anyway, on whatever the system's default input is.
    @Test func aDeviceIDThatNamesNothingFallsBackToTheSystemDefault() async throws {
        guard #available(macOS 26.0, *) else { return }
        guard SpeechRecognitionService.authorizationStatus() == .authorized else { return }
        let service = SpeechRecognitionService()
        // Core Audio never allocates IDs this high, so this is guaranteed to be stale.
        _ = try await service.startRecognition(locale: Locale(identifier: "en_US"), inputDeviceID: 999_999)
        defer { Task { _ = await service.stopRecognition() } }

        try await Task.sleep(for: .seconds(1))
        let gap = await service.silenceDuration()
        #expect(gap < 1, "the default input should be delivering buffers, gap was \(gap)s")
    }
}
#endif
