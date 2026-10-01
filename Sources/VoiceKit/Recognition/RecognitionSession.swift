//
//  RecognitionSession.swift
//  VoiceKit
//
//  Result of starting recognition: transcript stream, mic level stream, and raw audio buffers.
//

@preconcurrency import AVFoundation
import Foundation

/// A microphone buffer copied before the audio tap returns, with its capture clock time.
/// The buffer is owned by this value and must be treated as read-only by consumers.
public struct CapturedAudioBuffer: @unchecked Sendable {
    public let buffer: AVAudioPCMBuffer
    public let hostTime: UInt64

    public static func copy(_ source: AVAudioPCMBuffer, at time: AVAudioTime) -> CapturedAudioBuffer? {
        guard time.isHostTimeValid, source.frameLength > 0,
              let copy = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameLength) else { return nil }
        copy.frameLength = source.frameLength
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: source.audioBufferList))
        let outputs = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        guard inputs.count == outputs.count else { return nil }
        for index in inputs.indices {
            guard let sourceData = inputs[index].mData, let destination = outputs[index].mData,
                  inputs[index].mDataByteSize <= outputs[index].mDataByteSize else { return nil }
            memcpy(destination, sourceData, Int(inputs[index].mDataByteSize))
        }
        return CapturedAudioBuffer(buffer: copy, hostTime: time.hostTime)
    }
}

/// Returned by `SpeechRecognitionService.startRecognition()`.
/// Contains async streams for transcript segments, mic levels, and raw audio buffers.
public struct RecognitionSession: Sendable {
    /// Stream of recognized transcript segments.
    public let transcript: AsyncStream<TranscriptionResult>
    /// Normalized microphone level (0...1), throttled.
    public let level: AsyncStream<Float>
    /// Raw audio buffers from the microphone tap. Useful for recording or visualization.
    public let audioBuffers: AsyncStream<AVAudioPCMBuffer>
    /// Copied microphone samples on the host-clock timeline, for synchronized video recording.
    public let timestampedAudioBuffers: AsyncStream<CapturedAudioBuffer>
    /// Where this session's safety recording is being written, if one was requested.
    /// Known from the start — a caller tidying up old recordings needs to know which file
    /// is still being written to so it doesn't delete the live one.
    public let backupURL: URL?

    public init(
        transcript: AsyncStream<TranscriptionResult>,
        level: AsyncStream<Float>,
        audioBuffers: AsyncStream<AVAudioPCMBuffer>,
        backupURL: URL? = nil,
        timestampedAudioBuffers: AsyncStream<CapturedAudioBuffer> = AsyncStream { $0.finish() }
    ) {
        self.transcript = transcript
        self.level = level
        self.audioBuffers = audioBuffers
        self.timestampedAudioBuffers = timestampedAudioBuffers
        self.backupURL = backupURL
    }
}
