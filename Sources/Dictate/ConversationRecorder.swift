//
//  ConversationRecorder.swift
//  Dictate
//
//  Conversation transcripts: diarizes the mic audio on-device (FluidAudio,
//  CoreML) while dictation runs and keeps a speaker-labeled transcript on
//  disk, rewritten moments after each phrase is finalized. Audio samples are
//  held in memory only for the current ~5s chunk and never written anywhere.
//

#if os(macOS)
@preconcurrency import AVFoundation
import FluidAudio
import Foundation
import VoiceKit

@available(macOS 26.0, *)
actor ConversationRecorder {
    private struct Line {
        let text: String
        let start: Double
        let end: Double
        var speaker: Int?
    }

    private let fileURL: URL
    private let started = Date()
    private var stopped: Date?
    /// Filled in by the controller once it knows which device the session actually opened.
    private var microphone = "Unknown"
    private let converter = BufferConverter()
    private let format16k = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private let chunkSamples = 5 * 16_000        // ~5s per diarization pass
    private let maxPendingSamples = 120 * 16_000 // hold ≤2 min of audio while models download

    private var pending: [Float] = []      // converted samples awaiting diarization
    private var processedSamples = 0       // diarization frontier, in absolute samples
    private var diarizer: DiarizerManager? // one instance per session → stable speaker IDs
    private var spans: [(speaker: Int, start: Double, end: Double)] = []
    private var speakerNumbers: [String: Int] = [:]  // FluidAudio speakerId → 1, 2, 3…
    private var lines: [Line] = []

    init(directory: URL = LearningPaths.transcripts) {
        let dir = directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        fileURL = dir.appendingPathComponent("\(formatter.string(from: started)).md")
    }

    func setMicrophone(_ description: String) {
        microphone = description
        write()
    }

    /// Consume the session's raw mic buffers until the stream ends.
    func run(buffers: AsyncStream<AVAudioPCMBuffer>) async {
        // Model download must NEVER block audio consumption or the stop flow:
        // it installs the diarizer whenever it finishes (instant after first run).
        Task {
            if let models = try? await DiarizerModels.downloadIfNeeded() {
                install(models)
            }
        }
        for await buffer in buffers {
            if let converted = try? converter.convertBuffer(buffer, to: format16k),
               let data = converted.floatChannelData {
                pending.append(contentsOf: UnsafeBufferPointer(start: data[0], count: Int(converted.frameLength)))
            }
            if pending.count >= chunkSamples {
                diarizeChunk()
            }
        }
    }

    private func install(_ models: DiarizerModels) {
        let d = DiarizerManager()
        d.initialize(models: models)
        diarizer = d
    }

    /// Record one finalized transcript segment. Text hits disk immediately;
    /// its speaker label fills in once diarization catches up.
    func addSegment(text: String, start: Double?, end: Double?) {
        let s = start ?? lines.last?.end ?? 0
        lines.append(Line(text: text, start: s, end: end ?? s, speaker: nil))
        assignAndWrite()
    }

    /// Diarize the remaining tail and settle every line's speaker.
    func finish() {
        stopped = Date()
        if !pending.isEmpty {
            diarizeChunk()
        }
        for i in lines.indices where lines[i].speaker == nil {
            // Best guess for lines diarization never covered: the previous speaker.
            lines[i].speaker = SpeakerAssign.speaker(forStart: lines[i].start, end: lines[i].end, in: spans)
                ?? (i > lines.startIndex ? lines[i - 1].speaker : nil)
        }
        write()
    }

    private func diarizeChunk() {
        guard let diarizer else {
            // Models still downloading (first run only): hold the audio so it can be
            // diarized in one batch once they land, capped so a failed download can't
            // grow memory forever.
            // ponytail: audio past the cap is skipped and its lines stay unlabeled
            let overflow = pending.count - maxPendingSamples
            if overflow > 0 {
                pending.removeFirst(overflow)
                processedSamples += overflow
            }
            return
        }
        let base = Double(processedSamples) / 16_000
        if let result = try? diarizer.performCompleteDiarization(pending, sampleRate: 16_000) {
            for seg in result.segments {
                let number: Int
                if let known = speakerNumbers[seg.speakerId] {
                    number = known
                } else {
                    number = speakerNumbers.count + 1
                    speakerNumbers[seg.speakerId] = number
                }
                spans.append((number, base + Double(seg.startTimeSeconds), base + Double(seg.endTimeSeconds)))
            }
        }
        processedSamples += pending.count
        pending.removeAll(keepingCapacity: true)
        assignAndWrite()
    }

    /// Label every line the diarization frontier has passed, then persist.
    private func assignAndWrite() {
        let frontier = Double(processedSamples) / 16_000
        for i in lines.indices where lines[i].speaker == nil && lines[i].end <= frontier {
            if let speaker = SpeakerAssign.speaker(forStart: lines[i].start, end: lines[i].end, in: spans) {
                lines[i].speaker = speaker
            }
        }
        write()
    }

    private func write() {
        var rendered = "# Dictation — \(started.formatted(date: .abbreviated, time: .shortened))\n\n"
        for line in lines {
            let label = line.speaker.map { "Speaker \($0)" } ?? "Speaker ?"
            rendered += "\(label): \(line.text)\n\n"
        }
        rendered += session()
        // ponytail: rewrite the whole file atomically each update — transcripts are KB
        // and this lets labels correct themselves retroactively; append if files ever grow
        try? rendered.data(using: .utf8)?.write(to: fileURL, options: .atomic)
    }

    /// The session's own record, at the foot of the file so it never gets between you and
    /// what was said. UTC because these get compared across machines and timezones.
    private func session() -> String {
        TranscriptFooter.render(microphone: microphone, started: started, stopped: stopped)
    }
}

/// The session record at the foot of a transcript. Pure and ungated so it can be tested
/// without a diarizer, a microphone, or macOS 26.
enum TranscriptFooter {
    /// Footer for multi-input conversation recordings: one line per named source.
    static func render(
        sources: [String],
        started: Date,
        stopped: Date?,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .current
    ) -> String {
        var footer = "---\n\n"
        for source in sources {
            footer += "- **Source:** \(source)\n"
        }
        footer += "- **Started:** \(timestamp(started, locale: locale, timeZone: timeZone))\n"
        if let stopped {
            footer += "- **Stopped:** \(timestamp(stopped, locale: locale, timeZone: timeZone))\n"
            footer += "- **Duration:** \(durationText(stopped.timeIntervalSince(started)))\n"
        } else {
            footer += "- **Stopped:** still recording\n"
        }
        return footer
    }

    static func render(
        microphone: String,
        started: Date,
        stopped: Date?,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .current
    ) -> String {
        var footer = "---\n\n"
        footer += "- **Microphone:** \(microphone)\n"
        footer += "- **Started:** \(timestamp(started, locale: locale, timeZone: timeZone))\n"
        if let stopped {
            footer += "- **Stopped:** \(timestamp(stopped, locale: locale, timeZone: timeZone))\n"
            footer += "- **Duration:** \(durationText(stopped.timeIntervalSince(started)))\n"
        } else {
            footer += "- **Stopped:** still recording\n"
        }
        return footer
    }

    /// The weekday in the reader's own language — "Tuesday", "Dienstag", "martes" — and in
    /// their own timezone, so it always names the same day as the date beside it.
    static func weekday(
        _ date: Date,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        formatter.timeZone = timeZone
        formatter.locale = locale
        return formatter.string(from: date)
    }

    /// Local time with its ISO 8601 offset: `2026-07-14T18:38:29+02:00`.
    ///
    /// Local because that's the time you were actually sitting there; the offset because it
    /// makes the instant unambiguous — UTC is a subtraction away, and any tool can parse it.
    static func iso8601(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        formatter.timeZone = timeZone
        // Fixed locale, or a Japanese calendar renders a year nobody else can parse.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    static func timestamp(
        _ date: Date,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .current
    ) -> String {
        "\(weekday(date, locale: locale, timeZone: timeZone)), \(iso8601(date, timeZone: timeZone))"
    }

    /// "8s", "1m 30s", "1h 02m 03s".
    static func durationText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        guard total > 0 else { return "0s" }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%dh %02dm %02ds", hours, minutes, secs)
        }
        if minutes > 0 {
            return String(format: "%dm %02ds", minutes, secs)
        }
        return "\(secs)s"
    }
}

/// Pure max-overlap speaker assignment, kept separate so it's testable without models.
enum SpeakerAssign {
    /// The speaker whose diarized spans overlap [start, end] the most, or nil if none do.
    static func speaker(
        forStart start: Double, end: Double,
        in spans: [(speaker: Int, start: Double, end: Double)]
    ) -> Int? {
        var overlap: [Int: Double] = [:]
        for span in spans {
            let shared = min(end, span.end) - max(start, span.start)
            if shared > 0 {
                overlap[span.speaker, default: 0] += shared
            }
        }
        return overlap.max { $0.value < $1.value }?.key
    }
}
#endif
