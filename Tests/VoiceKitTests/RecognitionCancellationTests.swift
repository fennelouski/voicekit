import Foundation
import Testing
@testable import VoiceKit

struct RecognitionCancellationTests {
    @Test func aPreCancelledStartDoesNotRequestPermissionsOrOpenTheMicrophone() async {
        guard #available(macOS 26.0, *) else { return }
        let service = SpeechRecognitionService()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.startRecognition()
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await service.silenceDuration() == 0)
    }

    @Test func preCancelledFileRecoveryStopsBeforePermissionOrFileAccess() async {
        guard #available(macOS 26.0, *) else { return }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await FileTranscriber.transcribe(fileAt: URL(fileURLWithPath: "/no-such-dictation.caf"))
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
