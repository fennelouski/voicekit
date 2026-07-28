//
//  AudioRecoveryTests.swift
//  VoiceKitTests
//
//  The pieces that keep a dictation alive when the microphone doesn't: the
//  stall detector, the safety recording's housekeeping, and the refusal to
//  hand a stale device ID to the audio engine.
//

import AVFoundation
import Foundation
import Testing
import VKObjC
@testable import VoiceKit

struct ObjCExceptionTests {

    /// The whole point of the shim: AVAudioEngine reports a bad tap format by raising,
    /// and an ObjC exception reaching Swift takes the process down with it. Turning it
    /// into a thrown error is the difference between a failed dictation and a crash.
    @Test func aRaisedExceptionBecomesAThrownError() throws {
        var error: (any Error)?
        do {
            try catchingObjCException {
                NSException(
                    name: .invalidArgumentException,
                    reason: "required condition is false: format.sampleRate == hwFormat.sampleRate",
                    userInfo: nil
                ).raise()
            }
            Issue.record("the raise should have surfaced as a Swift error")
        } catch let caught {
            error = caught
        }
        let raised = try #require(error as NSError?)
        #expect(raised.domain == VKObjCExceptionErrorDomain)
        // The reason survives, or the failure is undiagnosable next time.
        #expect(raised.localizedDescription.contains("hwFormat"))
    }

    @Test func aCallThatDoesNotRaisePassesStraightThrough() throws {
        var ran = false
        try catchingObjCException { ran = true }
        #expect(ran)
    }
}

struct SafeTapTests {

    /// A node that raises the way `AVAudioEngine.inputNode` does when its cached idea of the
    /// hardware format has gone stale. The real one only misbehaves with real hardware
    /// attached — a player or mixer node quietly accepts any format you hand it — so the
    /// retry policy can't be exercised without standing in for it.
    private final class PickyNode: AVAudioMixerNode {
        /// The format of each install attempt, in order.
        private(set) var attempts: [AVAudioFormat?] = []
        private(set) var removals = 0
        /// Formats to reject. Nil in here means even the bus format is refused.
        var rejects: (AVAudioFormat?) -> Bool = { _ in false }
        var raisesOnRemove = false

        override func installTap(
            onBus bus: AVAudioNodeBus,
            bufferSize: AVAudioFrameCount,
            format: AVAudioFormat?,
            block tapBlock: @escaping AVAudioNodeTapBlock
        ) {
            attempts.append(format)
            guard !rejects(format) else {
                NSException(
                    name: .invalidArgumentException,
                    reason: "required condition is false: format.sampleRate == hwFormat.sampleRate",
                    userInfo: nil
                ).raise()
                return
            }
            super.installTap(onBus: bus, bufferSize: bufferSize, format: format, block: tapBlock)
        }

        override func removeTap(onBus bus: AVAudioNodeBus) {
            removals += 1
            if raisesOnRemove {
                NSException(name: .internalInconsistencyException, reason: "node is gone", userInfo: nil).raise()
                return
            }
            super.removeTap(onBus: bus)
        }
    }

    /// Attached and connected, because a detached node raises on `removeTap` for reasons that
    /// have nothing to do with what's being tested here.
    private func makeNode() -> (PickyNode, AVAudioEngine) {
        let engine = AVAudioEngine()
        let node = PickyNode()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: nil)
        return (node, engine)
    }

    private func format(sampleRate: Double, channels: AVAudioChannelCount) throws -> AVAudioFormat {
        try #require(AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false
        ))
    }

    @Test func aFormatTheHardwareAcceptsIsInstalledAsAsked() throws {
        let (node, engine) = makeNode()
        defer { engine.stop() }
        let wanted = try format(sampleRate: 44_100, channels: 1)

        try node.installTapSafely(onBus: 0, bufferSize: 1024, format: wanted, block: { _, _ in })

        #expect(node.attempts.count == 1)
        #expect(node.attempts.first ?? nil === wanted)
    }

    /// The whole reason this wrapper exists: unplug headphones mid-session and the engine goes
    /// on reporting the old format, which `installTap` answers with a raise rather than an
    /// error. Falling back to the bus format is what keeps that a recoverable hiccup.
    @Test func aStaleFormatIsRetriedAgainstTheBusFormat() throws {
        let (node, engine) = makeNode()
        defer { engine.stop() }
        let stale = try format(sampleRate: 48_000, channels: 2)
        node.rejects = { $0 != nil }

        try node.installTapSafely(onBus: 0, bufferSize: 1024, format: stale, block: { _, _ in })

        #expect(node.attempts.count == 2)
        #expect(node.attempts.first ?? nil === stale)
        // Nil, not another guess: it tells the engine to use whatever the bus really is.
        #expect(node.attempts.last ?? nil == nil)
    }

    @Test func aNodeThatRefusesEvenItsOwnBusFormatReportsTheFailure() throws {
        let (node, engine) = makeNode()
        defer { engine.stop() }
        node.rejects = { _ in true }

        #expect(throws: (any Error).self) {
            try node.installTapSafely(
                onBus: 0, bufferSize: 1024, format: try self.format(sampleRate: 48_000, channels: 2),
                block: { _, _ in }
            )
        }
        #expect(node.attempts.count == 2)
    }

    /// channelCount 0 — no input device, or a mic that isn't awake yet — is the case the retry
    /// can't save, because AVFoundation traps on it deep inside rather than raising where
    /// anything can catch it. It must never reach the node at all.
    @Test func aFormatWithNoChannelsIsNeverHandedToTheNode() throws {
        let (node, engine) = makeNode()
        defer { engine.stop() }
        node.rejects = { $0 != nil }
        let empty = try #require(AVAudioFormat(streamDescription: &emptyStreamDescription))

        try node.installTapSafely(onBus: 0, bufferSize: 1024, format: empty, block: { _, _ in })

        #expect(node.attempts == [nil])
    }

    @Test func removingATapFromHardwareThatHasGoneAwayIsSurvivable() {
        let (node, engine) = makeNode()
        defer { engine.stop() }
        node.raisesOnRemove = true
        node.removeTapSafely(onBus: 0) // must not take the process with it
        #expect(node.removals == 1)
    }
}

/// 0 channels at 0 Hz: `AVAudioFormat`'s convenience initialisers refuse to build this, which
/// is exactly why the stream-description route is needed to reproduce what the input node
/// reports when there's no microphone.
private nonisolated(unsafe) var emptyStreamDescription = AudioStreamBasicDescription(
    mSampleRate: 0,
    mFormatID: kAudioFormatLinearPCM,
    mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
    mBytesPerPacket: 0, mFramesPerPacket: 1, mBytesPerFrame: 0,
    mChannelsPerFrame: 0, mBitsPerChannel: 32, mReserved: 0
)

struct CaptureHeartbeatTests {

    @Test func silenceGrowsUntilABufferArrives() async throws {
        let heartbeat = CaptureHeartbeat()
        // Never beaten: the gap is enormous, which is how a capture that never
        // started is told apart from one that is merely quiet.
        #expect(heartbeat.silence > 60 * 60)

        heartbeat.beat()
        #expect(heartbeat.silence < 1)

        try await Task.sleep(for: .milliseconds(120))
        #expect(heartbeat.silence > 0.1)

        heartbeat.reset()
        #expect(heartbeat.silence < 0.1)
    }
}

struct BackupRecorderTests {

    private func makeDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voicekit-backup-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func touch(_ url: URL, age: TimeInterval = 0) throws -> URL {
        try Data("audio".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: url.path
        )
        return url
    }

    @Test func byDefaultARecordingLastsOnlyUntilTheNextDictationFinishes() throws {
        let directory = makeDirectory()
        let previous = try touch(directory.appendingPathComponent("previous.caf"))
        let current = try touch(directory.appendingPathComponent("current.caf"))

        BackupRecorder.sweep(directory, keeping: [current])

        #expect(!FileManager.default.fileExists(atPath: previous.path))
        #expect(FileManager.default.fileExists(atPath: current.path))
    }

    @Test func aDictationThatProducedTextLeavesNothingBehind() throws {
        let directory = makeDirectory()
        let recording = try touch(directory.appendingPathComponent("done.caf"))

        // Nothing to keep: the words landed, so the audio has nothing left to protect.
        BackupRecorder.sweep(directory, keeping: [])

        #expect(!FileManager.default.fileExists(atPath: recording.path))
    }

    @Test func aRecordingStillBeingWrittenIsNeverSweptAway() throws {
        // The case that makes this more than a one-liner: cleanup of one dictation can
        // finish while the next is already recording, and deleting the live file would
        // destroy the very audio the feature exists to keep.
        let directory = makeDirectory()
        let finished = try touch(directory.appendingPathComponent("finished.caf"))
        let inFlight = try touch(directory.appendingPathComponent("in-flight.caf"))
        let orphan = try touch(directory.appendingPathComponent("orphan-from-a-crash.caf"))

        BackupRecorder.sweep(directory, keeping: [finished, inFlight])

        #expect(FileManager.default.fileExists(atPath: finished.path))
        #expect(FileManager.default.fileExists(atPath: inFlight.path))
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
    }

    @Test func aRetentionWindowSparesRecordingsUntilTheyReachThatAge() throws {
        let directory = makeDirectory()
        let recent = try touch(directory.appendingPathComponent("recent.caf"), age: 30 * 60)
        let expired = try touch(directory.appendingPathComponent("expired.caf"), age: 2 * 60 * 60)

        BackupRecorder.sweep(directory, keeping: [], retention: 60 * 60)

        // Raised deliberately to keep evidence across later dictations; the point is that
        // the sweep no longer ends a recording's life, its age does.
        #expect(FileManager.default.fileExists(atPath: recent.path))
        #expect(!FileManager.default.fileExists(atPath: expired.path))
    }

    @Test func aRetentionWindowStillSparesTheLiveRecording() throws {
        let directory = makeDirectory()
        // Old enough to be swept on age alone — but it's the file being written right now.
        let inFlight = try touch(directory.appendingPathComponent("in-flight.caf"), age: 5 * 60 * 60)

        BackupRecorder.sweep(directory, keeping: [inFlight], retention: 60 * 60)

        #expect(FileManager.default.fileExists(atPath: inFlight.path))
    }

    @Test func sweepingToleratesAMissingDirectory() {
        let directory = makeDirectory().appendingPathComponent("never-created", isDirectory: true)
        BackupRecorder.sweep(directory, keeping: [])
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    /// A buffer of silence long enough to clear the "worth transcribing" floor.
    private func silence(seconds: Double) throws -> AVAudioPCMBuffer {
        let format = try #require(AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 1, interleaved: false
        ))
        let frames = AVAudioFrameCount(seconds * format.sampleRate)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        return buffer
    }

    /// The check the earlier tests were missing: they exercised bookkeeping without ever
    /// writing a buffer, so a recorder that dropped every single one still looked healthy.
    /// A backup you cannot read back is not a backup.
    @Test func recordedAudioIsReadableBackAtTheDurationThatWentIn() throws {
        let directory = makeDirectory()
        let recorder = try #require(BackupRecorder(directory: directory))
        recorder.write(try silence(seconds: 2))

        let finished = try #require(recorder.finish())
        let written = try AVAudioFile(forReading: finished)

        #expect(written.fileFormat.sampleRate == 16_000)
        #expect(written.fileFormat.channelCount == 1)
        // 2 seconds in at 44.1 kHz, 2 seconds out at 16 kHz.
        #expect(abs(Double(written.length) - 32_000) < 800)
    }

    @Test func retentionIsCountedFromWhenTheRecordingEndedNotWhenItStarted() throws {
        let directory = makeDirectory()
        let recorder = try #require(BackupRecorder(directory: directory))
        recorder.write(try silence(seconds: 2))

        // Stand in for a long dictation: the file was opened five hours ago. Counting from
        // then would expire it under a one-hour retention the instant it was written — the
        // recording would be swept away before it could ever rescue anything.
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-5 * 60 * 60)], ofItemAtPath: recorder.url.path
        )

        let finished = try #require(recorder.finish())
        BackupRecorder.sweep(directory, keeping: [], retention: 60 * 60)

        #expect(FileManager.default.fileExists(atPath: finished.path))
    }

    /// The gap the `keeping:` list alone can't close. A session opens its file the moment it
    /// starts, but its owner doesn't learn the URL until `startRecognition` returns — and the
    /// previous dictation's cleanup can sweep in that window, with nothing to pass.
    @Test func aRecordingIsSparedWhileItIsStillOpenEvenIfNobodyAskedToKeepIt() throws {
        let directory = makeDirectory()
        let recorder = try #require(BackupRecorder(directory: directory))
        recorder.write(try silence(seconds: 2))

        BackupRecorder.sweep(directory, keeping: [])
        #expect(FileManager.default.fileExists(atPath: recorder.url.path))

        // And once it's closed, the ordinary rules resume — this must not leak into a file
        // that outlives every sweep.
        let finished = try #require(recorder.finish())
        BackupRecorder.sweep(directory, keeping: [])
        #expect(!FileManager.default.fileExists(atPath: finished.path))
    }

    /// Names come from a whole-second timestamp, and opening for writing truncates: two
    /// dictations inside one second used to mean the second one erased the first.
    @Test func twoRecordingsStartedInTheSameSecondGetSeparateFiles() throws {
        let directory = makeDirectory()
        let first = try #require(BackupRecorder(directory: directory))
        let second = try #require(BackupRecorder(directory: directory))

        #expect(first.url != second.url)
        first.write(try silence(seconds: 2))
        second.write(try silence(seconds: 2))
        #expect(try #require(first.finish()) == first.url)
        #expect(try #require(second.finish()) == second.url)
    }

    @Test func aRecordingTooShortToTranscribeIsThrownAway() throws {
        let directory = makeDirectory()
        let recorder = try #require(BackupRecorder(directory: directory))
        // Nothing written: half a second is the floor for being worth transcribing,
        // and a stray keypress shouldn't leave a file behind.
        #expect(recorder.finish() == nil)
        #expect(!FileManager.default.fileExists(atPath: recorder.url.path))
    }
}

/// The feature end to end: audio that went through the safety recording can be turned back
/// into the words that were spoken. Everything else in this file tests a link in isolation;
/// this is the only test that shows the chain holds — which is exactly what the user is
/// promised when a dictation fails and Dictate says it recovered the audio.
///
/// Skips (passes) without speech authorization or the on-device model, matching
/// `FileTranscriberTests`, so it stays green on CI and fresh machines.
struct BackupRecoveryEndToEndTests {

    @Test func speechSurvivesTheRoundTripThroughABackupRecording() async throws {
        guard #available(macOS 26.0, *) else { return }
        guard SpeechRecognitionService.authorizationStatus() == .authorized else { return }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("voicekit-recovery-e2e-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let spoken = FileManager.default.temporaryDirectory
            .appendingPathComponent("spoken-\(UUID().uuidString).aiff")
        defer { try? FileManager.default.removeItem(at: spoken) }

        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", spoken.path, "the quick brown fox jumps over the lazy dog"]
        try say.run()
        say.waitUntilExit()
        guard say.terminationStatus == 0 else { return }

        // Push that audio through BackupRecorder the way the microphone tap would.
        let source = try AVAudioFile(forReading: spoken)
        let recorder = try #require(BackupRecorder(directory: directory))
        while source.framePosition < source.length {
            guard let chunk = AVAudioPCMBuffer(
                pcmFormat: source.processingFormat, frameCapacity: 4096
            ) else { break }
            try source.read(into: chunk)
            guard chunk.frameLength > 0 else { break }
            recorder.write(chunk)
        }

        let recovered = try #require(recorder.finish(), "the recording should have held usable audio")
        let segments = try await FileTranscriber.transcribe(
            fileAt: recovered, locale: Locale(identifier: "en_US")
        )
        let text = segments.map(\.text).joined(separator: " ").lowercased()
        #expect(text.contains("fox"))
    }
}

#if os(macOS)
struct SelectedInputResolutionTests {

    /// In-memory stand-in for UserDefaults so a test can't disturb the real selection.
    private final class Storage: AudioInputStorage, @unchecked Sendable {
        var values: [String: String] = [:]
        init(deviceId: String?) { values["deviceId"] = deviceId }
        func string(forKey key: String) -> String? { values[key] }
        func set(_ value: String?, forKey key: String) { values[key] = value }
    }

    @Test func noSelectionMeansSystemDefault() {
        #expect(AudioInputSelection.resolveSelectedDeviceID(storage: Storage(deviceId: nil)) == nil)
        #expect(AudioInputSelection.resolveSelectedDeviceID(storage: Storage(deviceId: "")) == nil)
        #expect(AudioInputSelection.selectedDeviceTag(storage: Storage(deviceId: nil)) == "")
    }

    @Test func aUIDForHardwareThatIsNotConnectedFallsBackToTheSystemDefault() {
        // The crash this guards: a saved device that is no longer here must resolve to
        // "let the system choose", never to whichever device inherited its number.
        let storage = Storage(deviceId: "UID-for-headphones-in-a-drawer-\(UUID().uuidString)")
        #expect(AudioInputSelection.resolveSelectedDeviceID(storage: storage) == nil)
    }

    @Test func aLegacyNumericIDForAMissingDeviceIsNotHandedToTheEngine() {
        // Core Audio never allocates IDs this high; before UIDs were stored, a number
        // like this would have been passed straight to the audio unit.
        let storage = Storage(deviceId: "999999")
        #expect(AudioInputSelection.resolveSelectedDeviceID(storage: storage) == nil)
    }

    /// The check the tests above were missing: every one of them expects nil, so a
    /// `resolveSelectedDeviceID` that did nothing but `return nil` passed the whole suite —
    /// and a user who picked a microphone would silently get the system default forever.
    /// Skips (passes) on a machine with no input hardware.
    @Test func aConnectedDeviceThatWasChosenIsTheOneHandedToTheEngine() async throws {
        let devices = await AudioInputSelection.availableDevices()
        guard let chosen = devices.first, let expected = AudioDeviceID(chosen.id) else { return }

        let storage = Storage(deviceId: nil)
        AudioInputSelection.saveSelection(device: chosen, input: nil, storage: storage)

        // Stored by UID, never by the number — that's what survives an unplug.
        #expect(storage.string(forKey: "deviceId") != chosen.id)
        #expect(AudioInputSelection.resolveSelectedDeviceID(storage: storage) == expected)
        #expect(AudioInputSelection.selectedDeviceTag(storage: storage) == chosen.id)
    }

    /// A device that can't produce a UID is not written down as a number. Core Audio reuses
    /// those numbers, so the saved selection would eventually open different hardware while
    /// still looking correct — the system default is the honest answer instead.
    @Test func aDeviceWithNoUIDIsNotSavedAsItsNumber() {
        let storage = Storage(deviceId: nil)
        AudioInputSelection.saveSelection(
            device: SelectableDevice(id: "424242", name: "Gone by the time you read this"),
            input: nil, storage: storage
        )
        #expect(storage.string(forKey: "deviceId") == nil)
        #expect(AudioInputSelection.resolveSelectedDeviceID(storage: storage) == nil)
    }

    /// A selection saved before Dictate stored UIDs is honoured *and* upgraded, so it stops
    /// being vulnerable to Core Audio renumbering. Fails if the rewrite is deleted.
    @Test func aLegacyNumericIDForAConnectedDeviceIsHonouredAndRewrittenAsAUID() async throws {
        let devices = await AudioInputSelection.availableDevices()
        guard let chosen = devices.first, let expected = AudioDeviceID(chosen.id) else { return }
        guard let uid = AudioInputSelection.deviceUID(for: expected) else { return }

        let storage = Storage(deviceId: chosen.id)
        #expect(AudioInputSelection.resolveSelectedDeviceID(storage: storage) == expected)
        #expect(storage.string(forKey: "deviceId") == uid)
    }
}
#endif
