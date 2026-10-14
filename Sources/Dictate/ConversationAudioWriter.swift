#if os(macOS)
@preconcurrency import AVFoundation
import Foundation
import VoiceKit

struct ConversationAudioSegment: Codable, Sendable {
    let fileName: String
    let source: String
    var timeline = CaptureTimeline()
}

struct ConversationScratchManifest: Codable, Sendable {
    let localeIdentifier: String?
    var segments: [ConversationAudioSegment]
}

actor ConversationAudioWriter {
    private let url: URL
    private var file: AVAudioFile?
    private let converter = BufferConverter()
    private var timeline = CaptureTimeline()
    init(url: URL) { self.url = url }

    func append(_ packet: CapturedAudioBuffer) throws {
        if file == nil { file = try AVAudioFile(forWriting: url, settings: packet.buffer.format.settings) }
        guard let file else { return }
        let converted = try converter.convertBuffer(packet.buffer, to: file.processingFormat)
        var writeError: Error?
        try catchingObjCException { do { try file.write(from: converted) } catch { writeError = error } }
        if let writeError { throw writeError }
        timeline.append(frames: converted.frameLength, sampleRate: converted.format.sampleRate, capturedAt: packet.capturedAt)
    }

    func finish() -> CaptureTimeline { file = nil; return timeline }
}

enum ConversationFinalizer {
    struct Outcome: Sendable { let transcript: URL?; let retainedAudio: Bool }

    @available(macOS 26.0, *)
    static func finish(
        directory: URL, manifest: ConversationScratchManifest, sources: [String], started: Date,
        events: [(date: Date, text: String)], recovery: RecoveryStore = .shared,
        transcriptDirectory: URL = LearningPaths.transcripts,
        transcribe: (URL, Locale?) async throws -> [TranscriptionResult] = { try await FileTranscriber.transcribe(fileAt: $0, locale: $1) }
    ) async -> Outcome {
        let recorder = MultiInputRecorder(directory: transcriptDirectory, sources: sources, started: started)
        for event in events { await recorder.noteEvent(event.text, at: event.date) }
        var successful: Set<String> = []
        let locale = manifest.localeIdentifier.map(Locale.init(identifier:))
        let safeSegments = manifest.segments.filter {
            $0.fileName == URL(fileURLWithPath: $0.fileName).lastPathComponent && $0.fileName.hasSuffix(".caf")
        }
        for segment in safeSegments {
            for (previous, next) in zip(segment.timeline.spans, segment.timeline.spans.dropFirst()) {
                let gap = next.capturedAt.timeIntervalSince(previous.capturedAt) - previous.duration
                if gap > 0.1 {
                    await recorder.noteEvent("\(segment.source): capture gap (\(String(format: "%.1f", gap)) seconds)",
                                             at: previous.capturedAt.addingTimeInterval(previous.duration))
                }
            }
            let url = directory.appendingPathComponent(segment.fileName)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                let results = try await transcribe(url, locale)
                guard results.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                    throw RecoveryStore.StoreError.missingAudio
                }
                for result in results {
                    await recorder.addSegment(speaker: segment.source,
                        at: segment.timeline.date(at: result.start ?? 0) ?? started, text: result.text)
                }
                successful.insert(segment.fileName)
            } catch {
                await recorder.noteEvent("\(segment.source): transcription incomplete; audio retained for recovery", at: started)
            }
        }
        let saved = await recorder.finish()
        var retained = false
        var archivedAll = safeSegments.count == manifest.segments.count
        for segment in safeSegments {
            let url = directory.appendingPathComponent(segment.fileName)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            if saved, successful.contains(segment.fileName) { try? FileManager.default.removeItem(at: url) }
            else {
                retained = true
                do { _ = try await recovery.register(audio: url, source: segment.source, locale: locale, kind: .conversation) }
                catch { archivedAll = false } // durable scratch remains discoverable on launch
            }
        }
        if archivedAll { try? FileManager.default.removeItem(at: directory) }
        return Outcome(transcript: saved ? recorder.fileURL : nil, retainedAudio: retained)
    }
}
#endif
