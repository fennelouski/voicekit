//
//  MicLevelService.swift
//  VoiceKit
//
//  Mic-level-only capture for level meters and real-time level use.
//  Uses AVAudioEngine + inputNode tap + RMS; no Speech framework. On-device only.
//

import AVFoundation
import Foundation

/// Captures microphone input and emits normalized level (0...1) via an async stream.
/// Use for microphone testing or real-time level-driven UI.
public actor MicLevelService {
    public enum Error: Swift.Error, Sendable {
        case engineStartFailed(Swift.Error)
    }

    private let audioEngine = AVAudioEngine()
    private var levelContinuation: AsyncStream<Float>.Continuation?
    private var levelBufferCount: Int = 0
    private var isTapInstalled: Bool = false

    public init() {}

    /// Start capture and return a stream of normalized levels (0...1). Throttled (e.g. every 2 buffers).
    /// Call `stopCapture()` when done. On failure (permission denied, invalid format), throws.
    public func startCapture() async throws -> AsyncStream<Float> {
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0 else {
            throw Error.engineStartFailed(NSError(domain: "MicLevelService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid audio format"]))
        }

        #if os(iOS) || os(visionOS)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [])
            try audioSession.setActive(true)
        } catch {
            throw Error.engineStartFailed(error)
        }
        #endif

        do {
            try audioEngine.start()
        } catch {
            #if os(iOS) || os(visionOS)
            try? AVAudioSession.sharedInstance().setActive(false)
            #endif
            throw Error.engineStartFailed(error)
        }

        let stream = AsyncStream<Float> { continuation in
            self.levelContinuation = continuation
        }
        levelBufferCount = 0
        let levelCont = levelContinuation

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [self] buffer, _ in
            levelBufferCount += 1
            if levelBufferCount % 2 == 0, let level = RMSCalculator.rmsLevel(from: buffer, scalingFactor: 4) {
                levelCont?.yield(level)
            }
        }
        isTapInstalled = true

        return stream
    }

    /// Stop capture and release resources. Safe to call even if not capturing.
    public func stopCapture() {
        levelContinuation?.finish()
        levelContinuation = nil
        audioEngine.stop()

        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }

        #if os(iOS) || os(visionOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
