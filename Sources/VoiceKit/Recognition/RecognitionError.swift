//
//  RecognitionError.swift
//  VoiceKit
//
//  Errors from the speech recognition pipeline.
//

import Foundation

/// Errors from the speech recognition service.
public enum RecognitionError: Error, Sendable {
    /// User denied speech recognition or microphone permission.
    case notAuthorized
    /// Speech recognizer is unavailable on this device.
    case recognitionUnavailable
    /// Audio engine failed to start.
    case engineStartFailed(Error)
    /// Recognition pipeline encountered an error.
    case recognitionFailed(Error)
    /// On-device model download failed.
    case modelDownloadFailed(Error)
    /// Requested locale is not supported for on-device recognition.
    case localeNotSupported
}
