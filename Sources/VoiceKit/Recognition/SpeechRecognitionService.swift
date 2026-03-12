//
//  SpeechRecognitionService.swift
//  VoiceKit
//
//  On-device speech recognition using Apple's SpeechAnalyzer/SpeechTranscriber.
//  Requests permission when starting; emits transcript segments for position mapping.
//  No audio or transcript sent off-device.
//

@preconcurrency import AVFoundation
import Foundation
import Speech
#if os(macOS)
import CoreAudio
import AudioUnit
#endif

/// On-device speech recognition service using Apple's SpeechTranscriber pipeline.
///
/// Emits recognized transcript segments (words/phrases) for the position mapper to consume.
/// Permission is requested when starting; denied permission yields an error and manual scroll only.
///
/// - Note: Requires macOS 26+ / iOS 26+. Available on older deployment targets but
///   guarded with `@available`.
@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
public actor SpeechRecognitionService: TranscriptionProvider {
    // MARK: - SpeechAnalyzer pipeline state

    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzerFormat: AVAudioFormat?
    private var bufferConverter: BufferConverter?

    // Audio engine
    private let audioEngine = AVAudioEngine()
    private var isTapInstalled: Bool = false

    // Level stream for mic indicator
    private var levelContinuation: AsyncStream<Float>.Continuation?
    private var levelBufferCount: Int = 0

    // Audio buffer forwarding (for camera recording mux)
    private var audioBufferContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?

    // Tasks for consuming results
    private var resultsTask: Task<Void, Swift.Error>?
    private var transcriptContinuation: AsyncStream<TranscriptionResult>.Continuation?

    public init() {}

    /// Check current speech recognition authorization status.
    public static func authorizationStatus() -> SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    /// Request microphone and speech recognition permission. Call before starting recognition.
    /// Returns authorization result; does not request at app launch.
    public static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    // MARK: - TranscriptionProvider conformance

    /// Start transcription and return an async stream of results.
    /// This is the protocol-conforming entry point; use `startRecognition(locale:inputDeviceID:)`
    /// for access to the full `RecognitionSession` with level and audio buffer streams.
    public func startTranscription(locale: Locale?) async throws -> AsyncStream<TranscriptionResult> {
        let session = try await startRecognition(locale: locale)
        return session.transcript
    }

    /// Stop the current transcription session.
    public func stopTranscription() async {
        await stopRecognition()
    }

    // MARK: - Full recognition API

    /// Start recognition and emit transcript segments and mic levels via the returned session.
    /// Call `stopRecognition()` when done.
    /// - Parameters:
    ///   - locale: Optional locale for recognition (e.g. from Settings). Nil uses system default.
    ///   - inputDeviceID: On macOS only, optional Core Audio device ID to use as input. Nil uses system default.
    /// - Throws: `RecognitionError.notAuthorized` if permission denied, `RecognitionError.localeNotSupported` if locale unavailable.
    public func startRecognition(locale: Locale? = nil, inputDeviceID: UInt32? = nil) async throws -> RecognitionSession {
        // Check authorization
        let status = Self.authorizationStatus()
        if status != .authorized {
            if status == .notDetermined {
                let newStatus = await Self.requestAuthorization()
                if newStatus != .authorized {
                    throw RecognitionError.notAuthorized
                }
            } else {
                throw RecognitionError.notAuthorized
            }
        }

        // Determine locale
        let recognitionLocale = locale ?? Locale.current

        // Verify locale is supported
        let supportedLocales = await SpeechTranscriber.supportedLocales
        let localeSupported = supportedLocales.contains { supported in
            supported.language.languageCode == recognitionLocale.language.languageCode
        }
        guard localeSupported else {
            throw RecognitionError.localeNotSupported
        }

        // Create transcriber — progressiveTranscription preset for low-latency live transcription
        let newTranscriber = SpeechTranscriber(
            locale: recognitionLocale,
            preset: .progressiveTranscription
        )
        transcriber = newTranscriber

        // Ensure speech model is installed
        if let downloadRequest = try await AssetInventory.assetInstallationRequest(supporting: [newTranscriber]) {
            do {
                try await downloadRequest.downloadAndInstall()
            } catch {
                throw RecognitionError.modelDownloadFailed(error)
            }
        }

        // Create analyzer
        let newAnalyzer = SpeechAnalyzer(modules: [newTranscriber])
        analyzer = newAnalyzer

        // Get optimal audio format for the transcriber
        let optimalFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [newTranscriber])
        analyzerFormat = optimalFormat
        bufferConverter = BufferConverter()

        // Configure audio session for recording (iOS/visionOS only; macOS handles this via AVAudioEngine)
        #if os(iOS) || os(visionOS)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try audioSession.setActive(true)
        } catch {
            throw RecognitionError.engineStartFailed(error)
        }
        #endif

        // Create the input stream for feeding audio to the analyzer
        let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
        inputContinuation = inputBuilder

        // Start the analyzer with the input sequence
        try await newAnalyzer.start(inputSequence: inputSequence)

        // Set up level stream
        let levelStream = AsyncStream<Float> { continuation in
            self.levelContinuation = continuation
        }
        levelBufferCount = 0

        // Set up audio buffer stream (for camera recording mux)
        let audioBufferStream = AsyncStream<AVAudioPCMBuffer> { continuation in
            self.audioBufferContinuation = continuation
        }

        // Set up transcript stream
        let transcriptStream = AsyncStream<TranscriptionResult> { continuation in
            self.transcriptContinuation = continuation
        }

        // Spawn task to consume transcriber results
        let capturedTranscriptCont = transcriptContinuation
        resultsTask = Task {
            do {
                for try await result in newTranscriber.results {
                    let text = String(result.text.characters)
                    let isFinal = result.isFinal
                    guard !text.isEmpty else { continue }
                    print("[SpeechRecognition] segment: \"\(text)\" isFinal: \(isFinal)")
                    capturedTranscriptCont?.yield(TranscriptionResult(text: text, isFinal: isFinal))
                }
            } catch {
                print("[SpeechRecognition] results stream error: \(error)")
            }
            capturedTranscriptCont?.finish()
        }

        // Set up audio engine and tap
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0 else {
            throw RecognitionError.engineStartFailed(NSError(
                domain: "SpeechRecognitionService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid audio format"]
            ))
        }

        // Capture references for the tap callback
        let levelCont = levelContinuation
        let audioBufferCont = audioBufferContinuation
        let converter = bufferConverter
        let targetFormat = analyzerFormat

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { buffer, _ in
            // Feed converted audio to the analyzer
            if let targetFormat, let converter {
                do {
                    let converted = try converter.convertBuffer(buffer, to: targetFormat)
                    inputBuilder.yield(AnalyzerInput(buffer: converted))
                } catch {
                    print("[SpeechRecognition] buffer conversion error: \(error)")
                }
            }

            // Forward raw audio buffer for camera recording
            audioBufferCont?.yield(buffer)

            // Compute RMS level for mic indicator (throttled)
            self.levelBufferCount += 1
            if self.levelBufferCount % 2 == 0, let level = RMSCalculator.rmsLevel(from: buffer, scalingFactor: 10) {
                levelCont?.yield(level)
            }
        }
        isTapInstalled = true

        #if os(macOS)
        if let deviceID = inputDeviceID, let audioUnit = inputNode.audioUnit {
            var id = deviceID
            let err = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &id,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            if err != noErr {
                throw RecognitionError.engineStartFailed(NSError(domain: NSOSStatusErrorDomain, code: Int(err), userInfo: [NSLocalizedDescriptionKey: "Failed to set input device"]))
            }
        }
        #endif

        do {
            try audioEngine.start()
        } catch {
            if isTapInstalled {
                inputNode.removeTap(onBus: 0)
                isTapInstalled = false
            }
            #if os(iOS) || os(visionOS)
            try? AVAudioSession.sharedInstance().setActive(false)
            #endif
            throw RecognitionError.engineStartFailed(error)
        }

        return RecognitionSession(transcript: transcriptStream, level: levelStream, audioBuffers: audioBufferStream)
    }

    /// Stop recognition and release resources. Call when session ends.
    public func stopRecognition() async {
        // Stop audio engine and remove tap
        audioEngine.stop()
        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }

        // Finish the input stream to signal end of audio
        inputContinuation?.finish()
        inputContinuation = nil

        // Finalize the analyzer
        if let analyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }

        // Cancel results task
        resultsTask?.cancel()
        resultsTask = nil

        // Finish transcript, level, and audio buffer streams
        transcriptContinuation?.finish()
        transcriptContinuation = nil
        levelContinuation?.finish()
        levelContinuation = nil
        audioBufferContinuation?.finish()
        audioBufferContinuation = nil

        // Deactivate audio session (iOS/visionOS only)
        #if os(iOS) || os(visionOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif

        // Clean up state
        transcriber = nil
        analyzer = nil
        analyzerFormat = nil
        bufferConverter = nil
        levelBufferCount = 0
    }
}
