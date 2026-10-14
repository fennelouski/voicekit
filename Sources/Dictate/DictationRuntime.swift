#if os(macOS)
import Foundation
import VoiceKit

@available(macOS 26.0, *)
protocol DictationRecognition: Sendable {
    func startRecognition(locale: Locale?, inputDeviceID: UInt32?, backupDirectory: URL?) async throws -> RecognitionSession
    func stopRecognition() async -> URL?
    func cancelRecognition() async -> URL?
    func silenceDuration() async -> TimeInterval
    func restartCapture() async -> Bool
}

@available(macOS 26.0, *)
extension SpeechRecognitionService: DictationRecognition {}

@MainActor
protocol DictationHUD: AnyObject {
    func show()
    func hide()
    func update(text: String)
    func update(level: Float)
    func setLocked(_ locked: Bool)
    func setProcessing()
    func setListening()
    func showError(_ message: String)
}

extension HUDController: DictationHUD {}

struct DictationOptions {
    var locale: Locale?
    var inputDeviceID: UInt32?
    var backupDirectory: URL?
    var saveConversation = false
    var learning = false
    var spokenCommands = false
    var formattingPosition: FormattingPosition = .beforeCleanup
    var chain: [CleanupMode] = []
    var cleanupConfigurations: [CleanupMode: CleanupConfiguration] = [:]
    var cleanupDeadline: TimeInterval = 30
    var vocabulary: [String] = []

    @MainActor static var current: Self {
        let chain = Settings.cleanupChain
        let vocabulary = VocabularyStore.shared.terms
        return Self(locale: Settings.locale, inputDeviceID: AudioInputSelection.resolveSelectedDeviceID(),
             backupDirectory: Settings.backupRecording ? LearningPaths.recovery : nil,
             saveConversation: Settings.conversationTranscripts, learning: Settings.learningEnabled,
             spokenCommands: Settings.spokenCommandsEnabled, formattingPosition: Settings.spokenCommandsPosition,
             chain: chain, cleanupConfigurations: Dictionary(uniqueKeysWithValues: chain.map {
                 var config = CleanupConfiguration.capture($0); config.vocabulary = vocabulary
                 return ($0, config)
             }), vocabulary: vocabulary)
    }
}
#endif
