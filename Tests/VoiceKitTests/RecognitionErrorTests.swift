import Foundation
import Testing
@testable import VoiceKit

struct RecognitionErrorTests {
    @Test func descriptionsExplainRecoveryAndPreserveUsefulCauses() {
        let rawCause = NSError(domain: "VoiceKitTests.RawPipeline", code: 42)
        let errors: [RecognitionError] = [.notAuthorized, .recognitionUnavailable, .localeNotSupported,
                                          .engineStartFailed(rawCause), .recognitionFailed(rawCause), .modelDownloadFailed(rawCause)]
        for error in errors {
            let description = error.localizedDescription
            #expect(!description.isEmpty)
            #expect(!description.contains("VoiceKit.RecognitionError"))
            #expect(!description.contains(rawCause.domain))
        }
        #expect(RecognitionError.localeNotSupported.localizedDescription.contains("language"))
        #expect(RecognitionError.localeNotSupported.localizedDescription.contains("device"))
        #expect(RecognitionError.notAuthorized.localizedDescription.contains("Settings"))
        let usefulCause = NSError(domain: "VoiceKitTests.Audio", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "No microphone is connected."])
        #expect(RecognitionError.engineStartFailed(usefulCause).localizedDescription.contains("No microphone is connected."))
        let downloadCause = NSError(domain: "VoiceKitTests.Download", code: 2,
                                    userInfo: [NSLocalizedDescriptionKey: "There is not enough storage for the speech model."])
        #expect(RecognitionError.modelDownloadFailed(downloadCause).localizedDescription.contains("There is not enough storage"))
    }
}
