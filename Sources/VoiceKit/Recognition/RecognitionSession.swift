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
    /// Where this session's safety recording is being written, if one was requested.
    /// Known from the start — a caller tidying up old recordings needs to know which file
    /// is still being written to so it doesn't delete the live one.
    public let backupURL: URL?

    public init(
        transcript: AsyncStream<TranscriptionResult>,
        level: AsyncStream<Float>,
        audioBuffers: AsyncStream<AVAudioPCMBuffer>,
        backupURL: URL? = nil
    ) {
        self.transcript = transcript
        self.level = level
        self.audioBuffers = audioBuffers
        self.backupURL = backupURL
    }
}
