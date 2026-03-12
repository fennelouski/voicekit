//
//  RecognitionSession.swift
//  VoiceKit
//
//  Result of starting recognition: transcript stream, mic level stream, and raw audio buffers.
//

@preconcurrency import AVFoundation
import Foundation

/// Returned by `SpeechRecognitionService.startRecognition()`.
/// Contains async streams for transcript segments, mic levels, and raw audio buffers.
public struct RecognitionSession: Sendable {
    /// Stream of recognized transcript segments.
    public let transcript: AsyncStream<TranscriptionResult>
    /// Normalized microphone level (0...1), throttled.
    public let level: AsyncStream<Float>
    /// Raw audio buffers from the microphone tap. Useful for recording or visualization.
    public let audioBuffers: AsyncStream<AVAudioPCMBuffer>

    public init(transcript: AsyncStream<TranscriptionResult>, level: AsyncStream<Float>, audioBuffers: AsyncStream<AVAudioPCMBuffer>) {
        self.transcript = transcript
        self.level = level
        self.audioBuffers = audioBuffers
    }
}
