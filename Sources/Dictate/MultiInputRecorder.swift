//
//  MultiInputRecorder.swift
//  Dictate
//
//  Merged transcript for conversation recording: segments arrive from several
//  named sources (mics, app taps), each stamped with wall-clock time, and the
//  document is rewritten in timestamp order after every addition. No diarization
//  needed — the input IS the speaker.
//

#if os(macOS)
import Foundation

@available(macOS 26.0, *)
actor MultiInputRecorder {
    private let fileURL: URL
    private let started: Date
    private var stopped: Date?
    /// Footer descriptions, e.g. "Nathan — MacBook Pro Microphone".
    private let sources: [String]
    private var entries: [ConversationMerge.Entry] = []

    /// `started` is when recording began — transcription happens later, so the
    /// document's date and footer must not read as "now".
    init(directory: URL = LearningPaths.transcripts, sources: [String], started: Date = Date()) {
        self.sources = sources
        self.started = started
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        fileURL = directory.appendingPathComponent("Conversation \(formatter.string(from: started)).md")
    }

    func addSegment(speaker: String, at date: Date, text: String) {
        entries.append(.init(speaker: speaker, date: date, text: text))
        write()
    }

    /// A session event ("Zoom call: capture failed"), merged inline so the reader sees
    /// where the gap in that speaker's lines comes from.
    func noteEvent(_ text: String, at date: Date) {
        entries.append(.init(speaker: nil, date: date, text: text))
        write()
    }

    func finish() {
        stopped = Date()
        write()
    }

    private func write() {
        var rendered = "# Conversation — \(started.formatted(date: .abbreviated, time: .shortened))\n\n"
        rendered += ConversationMerge.render(entries)
        rendered += TranscriptFooter.render(sources: sources, started: started, stopped: stopped)
        // ponytail: rewrite the whole file atomically each update, same as ConversationRecorder —
        // transcripts are KB and late segments from another source can land mid-document
        try? rendered.data(using: .utf8)?.write(to: fileURL, options: .atomic)
    }
}

/// Pure merge/render, separate so it's testable without audio hardware or macOS 26.
enum ConversationMerge {
    struct Entry {
        /// nil marks a session event, rendered italic without a speaker label.
        let speaker: String?
        let date: Date
        let text: String

        init(speaker: String?, date: Date, text: String) {
            self.speaker = speaker
            self.date = date
            self.text = text
        }
    }

    /// Timestamp-ordered markdown body: `**[18:32:05] Nathan:** text`.
    /// Same-instant entries keep their arrival order.
    static func render(_ entries: [Entry], timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let ordered = entries.enumerated()
            .sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
            .map(\.element)
        var out = ""
        for entry in ordered {
            let time = formatter.string(from: entry.date)
            if let speaker = entry.speaker {
                out += "**[\(time)] \(speaker):** \(entry.text)\n\n"
            } else {
                out += "*[\(time)] \(entry.text)*\n\n"
            }
        }
        return out
    }
}
#endif
