//
//  FileTranscriber.swift
//  VoiceKit
//
//  Offline transcription of a recorded audio file, used by conversation
//  recording: capture first, transcribe after the fact — one analyzer at a
//  time instead of N live ones. Runs on-device; nothing leaves the machine.
//

@preconcurrency import AVFoundation
import Foundation
import Speech

@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
public enum FileTranscriber {
    /// Transcribe an audio file and return the finalized segments, with timestamps
    /// relative to the start of the file.
    /// - Throws: `RecognitionError.notAuthorized`, `.localeNotSupported`,
    ///   `.modelDownloadFailed`, or file-reading errors.
    public static func transcribe(fileAt url: URL, locale: Locale? = nil) async throws -> [TranscriptionResult] {
        let status = SpeechRecognitionService.authorizationStatus()
        if status != .authorized {
            guard status == .notDetermined,
                  await SpeechRecognitionService.requestAuthorization() == .authorized else {
                throw RecognitionError.notAuthorized
            }
        }

        let recognitionLocale = locale ?? Locale.current
        let supportedLocales = await SpeechTranscriber.supportedLocales
        guard supportedLocales.contains(where: {
            $0.language.languageCode == recognitionLocale.language.languageCode
        }) else {
            throw RecognitionError.localeNotSupported
        }

        let transcriber = SpeechTranscriber(locale: recognitionLocale, preset: .progressiveTranscription)
        if let downloadRequest = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            do {
                try await downloadRequest.downloadAndInstall()
            } catch {
                throw RecognitionError.modelDownloadFailed(error)
            }
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])

        // Collect concurrently: results stream while the file is analyzed, and the
        // stream ends when the analyzer finishes.
        let collector = Task {
            var segments: [TranscriptionResult] = []
            do {
                for try await result in transcriber.results where result.isFinal {
                    let text = String(result.text.characters)
                    guard !text.isEmpty else { continue }
                    segments.append(TranscriptionResult(
                        text: text, isFinal: true,
                        start: result.range.start.seconds.isFinite ? result.range.start.seconds : nil,
                        end: result.range.end.seconds.isFinite ? result.range.end.seconds : nil))
                }
            } catch {}
            return segments
        }

        do {
            let file = try AVAudioFile(forReading: url)
            // Apple's file API: reads, converts, and paces the audio itself.
            if let lastSample = try await analyzer.analyzeSequence(from: file) {
                try await analyzer.finalizeAndFinish(through: lastSample)
            } else {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            }
        } catch {
            await analyzer.cancelAndFinishNow()
            collector.cancel()
            _ = await collector.value
            throw error
        }

        return await collector.value
    }
}
