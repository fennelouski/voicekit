import Foundation
import Testing
import VoiceKit
@testable import Dictate

struct RecoveryRecordingQueueTests {
    @Test func aSweepCannotDeleteALaterJobsRecoveryAudio() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.caf")
        let second = directory.appendingPathComponent("second.caf")
        let active = directory.appendingPathComponent("active.caf")
        for url in [first, second, active] { try Data("audio fixture".utf8).write(to: url) }

        var queue = RecoveryRecordingQueue()
        queue.enqueue(first)
        queue.enqueue(second)
        BackupRecorder.sweep(directory, keeping: queue.complete(first, failed: false, active: active))
        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: second.path))
        #expect(FileManager.default.fileExists(atPath: active.path))

        // Once the later job fails, keep its audio for recovery. It is removed
        // only after another dictation completes, under default retention.
        BackupRecorder.sweep(directory, keeping: queue.complete(second, failed: true, active: active))
        #expect(FileManager.default.fileExists(atPath: second.path))
        BackupRecorder.sweep(directory, keeping: queue.complete(active, failed: false, active: nil))
        #expect((try FileManager.default.contentsOfDirectory(atPath: directory.path)).isEmpty)
    }
}
