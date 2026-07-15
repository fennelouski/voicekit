//
//  ConversationRecorderTests.swift
//  DictateTests
//
//  Regression test for the stop-flow deadlock: the recorder must drain its
//  buffer stream and finish promptly even when diarization models aren't
//  available (first-run download in flight, or offline) — the paste path
//  must never wait on diarization.
//

import AVFoundation
import Foundation
import Testing
@testable import Dictate

struct ConversationRecorderTests {

    @Test func stopNeverWaitsOnModelDownload() async throws {
        guard #available(macOS 26.0, *) else { return }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dictate-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let recorder = ConversationRecorder(directory: dir)
        let (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream()
        let runTask = Task { await recorder.run(buffers: stream) }

        // ~8 seconds of silence at the mic's native-ish format: enough to
        // trigger a diarization chunk while no models are installed.
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
        for _ in 0..<94 {
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
            buffer.frameLength = 4096
            continuation.yield(buffer)
        }
        await recorder.addSegment(text: "hello there", start: 1.0, end: 2.0)
        continuation.finish()

        // The old code awaited the model download inside the chunk loop,
        // hanging this for minutes-to-forever. It must return in seconds.
        let stopStarted = Date()
        await runTask.value
        await recorder.finish()
        #expect(Date().timeIntervalSince(stopStarted) < 3)

        // The transcript text is on disk even though diarization never ran.
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        #expect(files.count == 1)
        let contents = try String(contentsOf: files[0], encoding: .utf8)
        #expect(contents.contains("hello there"))
    }
}
