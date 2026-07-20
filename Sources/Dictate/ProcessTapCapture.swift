//
//  ProcessTapCapture.swift
//  Dictate
//
//  Captures another app's audio output via a Core Audio process tap: tap on the
//  target process → private aggregate device → IOProc delivering PCM buffers.
//  Used by conversation recording to transcribe Zoom/Chrome/FaceTime audio.
//  The first tap creation triggers the System Audio Recording permission prompt.
//

#if os(macOS)
@preconcurrency import AVFoundation
import CoreAudio
import Foundation
import os

@available(macOS 26.0, *)
final class ProcessTapCapture {
    private static let logger = Logger(subsystem: "Dictate", category: "ProcessTapCapture")

    enum CaptureError: Swift.Error, LocalizedError {
        case processNotFound
        case badFormat
        case osStatus(String, OSStatus)

        var errorDescription: String? {
            switch self {
            case .processNotFound: return "process is not playing audio"
            case .badFormat: return "unreadable tap audio format"
            case .osStatus(let stage, let code): return "\(stage) failed (\(code))"
            }
        }
    }

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private let queue = DispatchQueue(label: "com.dictate.processTap")

    /// The HAL object for a pid. Only processes currently doing audio I/O are registered
    /// with the HAL, so this returns nil until the target app actually plays audio —
    /// callers retry rather than fail.
    static func processObject(forPID pid: pid_t) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pidValue = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let err = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address,
            UInt32(MemoryLayout<pid_t>.size), &pidValue,
            &size, &object
        )
        guard err == noErr, object != AudioObjectID(kAudioObjectUnknown) else { return nil }
        return object
    }

    /// Start capturing the process's audio. Buffers arrive in the tap's native format;
    /// the caller converts. Call `stop()` to tear down.
    func start(pid: pid_t) throws -> AsyncStream<AVAudioPCMBuffer> {
        guard let processObject = Self.processObject(forPID: pid) else {
            throw CaptureError.processNotFound
        }

        let description = CATapDescription(stereoMixdownOfProcesses: [processObject])
        description.name = "Dictate-\(pid)"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        var err = AudioHardwareCreateProcessTap(description, &newTapID)
        guard err == noErr, newTapID != AudioObjectID(kAudioObjectUnknown) else {
            throw CaptureError.osStatus("tap creation", err)
        }
        tapID = newTapID

        var formatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        err = AudioObjectGetPropertyData(tapID, &formatAddress, 0, nil, &size, &asbd)
        guard err == noErr, let format = AVAudioFormat(streamDescription: &asbd) else {
            stop()
            throw CaptureError.badFormat
        }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceNameKey: "Dictate Tap \(pid)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        var newAggregateID = AudioObjectID(kAudioObjectUnknown)
        err = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &newAggregateID)
        guard err == noErr else {
            stop()
            throw CaptureError.osStatus("aggregate device creation", err)
        }
        aggregateID = newAggregateID

        let (stream, cont) = AsyncStream<AVAudioPCMBuffer>.makeStream()
        continuation = cont

        err = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, inInputData, _, _, _ in
            // Copy out of the HAL's buffer — it owns this memory and reuses it immediately.
            if let copy = Self.copyBuffer(inInputData, format: format) {
                cont.yield(copy)
            }
        }
        guard err == noErr, procID != nil else {
            stop()
            throw CaptureError.osStatus("IOProc creation", err)
        }

        err = AudioDeviceStart(aggregateID, procID)
        guard err == noErr else {
            stop()
            throw CaptureError.osStatus("device start", err)
        }

        return stream
    }

    func stop() {
        if let procID, aggregateID != AudioObjectID(kAudioObjectUnknown) {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        continuation?.finish()
        continuation = nil
    }

    private static func copyBuffer(_ list: UnsafePointer<AudioBufferList>, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        let bytesPerFrame = format.streamDescription.pointee.mBytesPerFrame
        guard let first = source.first, bytesPerFrame > 0 else { return nil }
        let frames = AVAudioFrameCount(first.mDataByteSize / bytesPerFrame)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let destination = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        for (i, src) in source.enumerated() where i < destination.count {
            guard let srcData = src.mData, let dstData = destination[i].mData else { continue }
            let bytes = min(src.mDataByteSize, destination[i].mDataByteSize)
            memcpy(dstData, srcData, Int(bytes))
            destination[i].mDataByteSize = bytes
        }
        return buffer
    }
}
#endif
