//
//  LiveCaptureRecoveryTests.swift
//  VoiceKitTests
//
//  The recovery paths that only a real microphone can prove: restarting capture
//  mid-session without losing the transcript, surviving a device that disappears, and
//  refusing to die on a device ID that no longer names anything. None are reachable from
//  a unit test — the failures they guard live in Core Audio, not in our bookkeeping.
//
//  Skips (passes) without speech authorization. The transcript assertions additionally
//  need the machine to hear its own speakers, so they stand down when output is muted.
//

import AVFoundation
import CoreAudio
import Foundation
import Testing
@testable import VoiceKit

#if os(macOS)
/// Serialized: there is one microphone, and two of these tests talking into it at once
/// hear each other.
@Suite(.serialized)
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

    /// The transcript so far, readable while the session is still running — which is what
    /// makes a heard-it-or-not check possible before the interesting part begins.
    private actor Live {
        private var accumulator = TranscriptAccumulator()

        func add(_ result: TranscriptionResult) { accumulator.add(result) }

        /// Folded the way the app folds it: a result's text covers the current utterance
        /// only, and a restart ends one, so reading the last result alone would show the
        /// first half missing when it is merely committed.
        var text: String { accumulator.preview.lowercased() }

        func heard(_ word: String) -> Bool { text.contains(word) }

        func collect(_ transcript: AsyncStream<TranscriptionResult>) -> Task<Void, Never> {
            Task { for await result in transcript { await self.add(result) } }
        }
    }

    /// Say something and report whether the machine heard itself say it.
    ///
    /// Every assertion here rests on a loopback through the speakers, and that loopback is
    /// not something a test can insist on: output may be muted, the volume low, the room
    /// loud, or someone talking nearby — during one run this test transcribed a conversation
    /// happening next to the laptop. All of those are the environment failing to cooperate,
    /// not the code being wrong, and a test that reports them as bugs gets ignored, which
    /// costs more than the coverage is worth. So they skip.
    private func canHearItself(_ live: Live, saying phrase: String, listeningFor word: String) async -> Bool {
        speak(phrase)
        // Recognition trails the audio; give it a moment before deciding nothing arrived.
        for _ in 0..<8 {
            if await live.heard(word) { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        // Said out loud, because a silent skip is indistinguishable from a test that ran —
        // which is how this file came to be green while proving nothing.
        print("[LiveCaptureRecovery] skipped: said \"\(phrase)\" and heard nothing back. "
              + "Unmute output and turn the volume up to run these for real.")
        return false
    }

    /// The watchdog's whole job, minus the timer: tear the microphone down mid-sentence and
    /// bring it back, and the words from before the break must still be there afterwards.
    @Test func captureRestartsMidSessionAndTheTranscriptCarriesOn() async throws {
        guard #available(macOS 26.0, *) else { return }
        guard SpeechRecognitionService.authorizationStatus() == .authorized else { return }
        let service = SpeechRecognitionService()
        let session = try await service.startRecognition(locale: Locale(identifier: "en_US"))

        let live = Live()
        let collecting = await live.collect(session.transcript)
        defer { collecting.cancel() }

        // The first half of the test doubles as the check that this machine can hear itself:
        // if "fox" doesn't come back now, nothing measured after the restart would mean
        // anything either, so there is no test to run.
        guard await canHearItself(live, saying: "the quick brown fox", listeningFor: "fox") else {
            _ = await service.stopRecognition()
            return
        }

        // Everything the watchdog does once it decides the microphone is gone.
        let restarted = await service.restartCapture()
        #expect(restarted, "capture should come back")

        // Buffers flowing again is the restart working; the transcript is the point.
        try await Task.sleep(for: .milliseconds(500))
        let gap = await service.silenceDuration()
        #expect(gap < 1, "the microphone should be feeding us again, gap was \(gap)s")

        speak("jumps over the lazy dog")
        try await Task.sleep(for: .seconds(2))

        _ = await service.stopRecognition()
        let text = await live.text
        // Both halves in one transcript: the restart didn't reset the analyzer. "fox" is
        // known to have arrived before the restart, so its absence now is the analyzer
        // having been torn down with the microphone — the exact regression this guards.
        #expect(text.contains("fox"), "lost what was said before the restart: \(text)")
        #expect(text.contains("dog"), "lost what was said after the restart: \(text)")
    }

    /// The failure the watchdog was written for, staged for real: capture from a device that
    /// then ceases to exist mid-session.
    ///
    /// It turns out not to be a stall. Core Audio reroutes the input node to the default
    /// device and buffers keep arriving carrying real audio, so the heartbeat stays healthy
    /// and the transcript survives on its own. Worth pinning down: if that behaviour ever
    /// changes, dictation goes deaf while still looking alive, and this test says so.
    @Test func aDeviceThatCeasesToExistMidSessionDoesNotTakeTheTranscriptWithIt() async throws {
        guard #available(macOS 26.0, *) else { return }
        guard SpeechRecognitionService.authorizationStatus() == .authorized else { return }
        guard let uid = defaultInputUID(), let aggregate = makeAggregate(over: uid) else { return }
        // The test destroys this itself, mid-session — that's the point of it. This is for
        // every other way out: a throw, a cancellation, a stopped run. An aggregate device
        // outlives the process that made it, and leaving one registered on the developer's
        // Mac is not something a test gets to do. Destroying twice just returns an error.
        defer { AudioHardwareDestroyAggregateDevice(aggregate) }

        let service = SpeechRecognitionService()
        let session = try await service.startRecognition(
            locale: Locale(identifier: "en_US"), inputDeviceID: aggregate
        )
        let live = Live()
        let collecting = await live.collect(session.transcript)
        defer { collecting.cancel() }

        // Same precondition as the test above, and it has to be established *before* the
        // device is destroyed: afterwards there would be no way to tell "the code went deaf"
        // from "this machine was never able to hear itself".
        guard await canHearItself(live, saying: "sound check", listeningFor: "check") else {
            _ = await service.stopRecognition()
            return
        }

        // The microphone vanishes mid-sentence.
        AudioHardwareDestroyAggregateDevice(aggregate)
        try await Task.sleep(for: .seconds(3))
        let gap = await service.silenceDuration()
        #expect(gap < 2.5, "buffers stopped when the device went away, gap was \(gap)s")

        // Buffers still arriving proves nothing on its own — the question is whether they
        // still carry the room, or whether the heartbeat is being fed silence.
        speak("the quick brown fox")
        try await Task.sleep(for: .seconds(2))

        // And the recovery still works from here, now that the ID names nothing.
        #expect(await service.restartCapture())
        _ = await service.stopRecognition()

        let text = await live.text
        #expect(text.contains("fox"), "went deaf when the device disappeared: \(text)")
    }

    /// A throwaway aggregate device wrapping the built-in mic. Destroying it mid-session is
    /// the closest a test can get, unaided, to yanking out a pair of AirPods.
    private func makeAggregate(over uid: String) -> AudioDeviceID? {
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "VoiceKit Recovery Test",
            kAudioAggregateDeviceUIDKey: "voicekit-recovery-test-\(UUID().uuidString)",
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: uid]],
            kAudioAggregateDeviceIsPrivateKey: 1,
        ]
        var device: AudioDeviceID = 0
        let err = AudioHardwareCreateAggregateDevice(description as CFDictionary, &device)
        return err == noErr && device != 0 ? device : nil
    }

    private func defaultInputUID() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        ) == noErr else { return nil }
        return AudioInputSelection.deviceUID(for: device)
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
