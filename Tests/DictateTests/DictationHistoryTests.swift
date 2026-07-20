//
//  DictationHistoryTests.swift
//  DictateTests
//
//  The persisted recent-dictations store: newest first, empty ignored, the
//  cleanup stages round-trip through disk, and clearing wipes the file.
//

import Foundation
import Testing
@testable import Dictate

@MainActor
struct DictationHistoryTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("dictate-history-\(UUID()).json")
    }

    private func entry(_ text: String) -> DictationHistory.Entry {
        .init(date: Date(), stages: [
            .init(label: "Raw", systemImage: "waveform", text: text, status: .applied, changePercent: nil)
        ])
    }

    @Test func newestFirst() {
        let history = DictationHistory(fileURL: tempURL())
        history.add(entry("first"))
        history.add(entry("second"))
        history.add(entry("third"))
        #expect(history.recent().map(\.text) == ["third", "second", "first"])
    }

    @Test func emptyEntriesAreIgnored() {
        let history = DictationHistory(fileURL: tempURL())
        history.add(entry("   "))
        history.add(entry("hello world"))
        #expect(history.recent().map(\.text) == ["hello world"])
    }

    /// The point of persisting: a relaunch (a fresh instance on the same file) still has it,
    /// with every cleanup stage intact.
    @Test func stagesRoundTripThroughDisk() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = DictationHistory(fileURL: url)
        writer.add(.init(date: Date(), stages: [
            .init(label: "Raw", systemImage: "waveform", text: "um hello world", status: .applied, changePercent: nil),
            .init(label: "Claude", systemImage: "cloud", text: "", status: .failed, changePercent: nil),
            .init(label: "Apple Intelligence", systemImage: "apple.logo", text: "Hello world.", status: .applied, changePercent: 40),
        ]))

        let reader = DictationHistory(fileURL: url)
        let entries = reader.recent()
        #expect(entries.count == 1)
        // The inserted text is the last *applied* stage, not the failed attempt after it.
        #expect(entries.first?.text == "Hello world.")
        #expect(entries.first?.stages.count == 3)
        #expect(entries.first?.stages.contains { $0.status == .failed } == true)
    }

    @Test func clearWipesMemoryAndFile() {
        let url = tempURL()
        let history = DictationHistory(fileURL: url)
        history.add(entry("gone soon"))
        #expect(FileManager.default.fileExists(atPath: url.path))
        history.clear()
        #expect(history.recent().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func disablingHistoryStopsRecordingNewEntries() {
        let saved = UserDefaults.standard.object(forKey: Settings.dictationHistoryEnabledKey)
        defer { UserDefaults.standard.set(saved, forKey: Settings.dictationHistoryEnabledKey) }

        let history = DictationHistory(fileURL: tempURL())
        UserDefaults.standard.set(false, forKey: Settings.dictationHistoryEnabledKey)
        history.add(entry("should not be kept"))
        #expect(history.recent().isEmpty)

        UserDefaults.standard.set(true, forKey: Settings.dictationHistoryEnabledKey)
        history.add(entry("kept"))
        #expect(history.recent().map(\.text) == ["kept"])
    }

    @Test func retentionWindowDropsOldEntriesOnRead() {
        let savedEnabled = UserDefaults.standard.object(forKey: Settings.dictationHistoryEnabledKey)
        let savedRetention = UserDefaults.standard.string(forKey: Settings.dictationHistoryRetentionKey)
        defer {
            UserDefaults.standard.set(savedEnabled, forKey: Settings.dictationHistoryEnabledKey)
            UserDefaults.standard.set(savedRetention, forKey: Settings.dictationHistoryRetentionKey)
        }
        UserDefaults.standard.set(true, forKey: Settings.dictationHistoryEnabledKey)

        // Forever while writing, so both an old and a fresh entry land on disk.
        UserDefaults.standard.set(HistoryRetention.forever.rawValue, forKey: Settings.dictationHistoryRetentionKey)
        let history = DictationHistory(fileURL: tempURL())
        history.add(.init(date: Date().addingTimeInterval(-10 * 86_400), stages: [
            .init(label: "Raw", systemImage: "waveform", text: "ten days old", status: .applied, changePercent: nil),
        ]))
        history.add(entry("just now"))
        #expect(history.recent().map(\.text) == ["just now", "ten days old"])

        // Shortening the window prunes the old entry on the very next read, no relaunch needed.
        UserDefaults.standard.set(HistoryRetention.day.rawValue, forKey: Settings.dictationHistoryRetentionKey)
        #expect(history.recent().map(\.text) == ["just now"])
    }
}

/// The session record at the foot of every transcript.
@Suite struct TranscriptFooterTests {
    private let utc = TimeZone(identifier: "UTC")!
    private let berlin = TimeZone(identifier: "Europe/Berlin")!
    private let posix = Locale(identifier: "en_US_POSIX")

    @Test func durationReadsAsTimeNotSeconds() {
        #expect(TranscriptFooter.durationText(0) == "0s")
        #expect(TranscriptFooter.durationText(8) == "8s")
        #expect(TranscriptFooter.durationText(59) == "59s")
        #expect(TranscriptFooter.durationText(60) == "1m 00s")
        #expect(TranscriptFooter.durationText(90) == "1m 30s")
        #expect(TranscriptFooter.durationText(3723) == "1h 02m 03s")
    }

    /// A negative or sub-second span must not render as "-1s" or crash the footer.
    @Test func aDegenerateSpanStillRenders() {
        #expect(TranscriptFooter.durationText(-5) == "0s")
        #expect(TranscriptFooter.durationText(0.4) == "0s")
    }

    /// Local time, with the offset that makes the instant unambiguous. UTC renders as "Z".
    @Test func timestampsAreLocalTimeWithTheirOffset() {
        let epoch = Date(timeIntervalSince1970: 0) // a Thursday in UTC
        #expect(TranscriptFooter.iso8601(epoch, timeZone: utc) == "1970-01-01T00:00:00Z")
        #expect(TranscriptFooter.iso8601(epoch, timeZone: berlin) == "1970-01-01T01:00:00+01:00")
        #expect(TranscriptFooter.timestamp(epoch, locale: posix, timeZone: utc)
                == "Thursday, 1970-01-01T00:00:00Z")
    }

    /// "The local name for the day" — the reader's language, not always English.
    @Test func theWeekdayIsLocalized() {
        let epoch = Date(timeIntervalSince1970: 0)
        #expect(TranscriptFooter.weekday(epoch, locale: Locale(identifier: "es_ES"), timeZone: utc) == "jueves")
        #expect(TranscriptFooter.weekday(epoch, locale: Locale(identifier: "de_DE"), timeZone: utc) == "Donnerstag")
    }

    /// The reason for reading local rather than UTC. 23:30 UTC on a Tuesday is already
    /// Wednesday in Berlin — and the person dictating was living a Wednesday. The weekday
    /// and the date must agree with each other, and with them.
    @Test func aDictationPastMidnightReadsAsTheDayYouActuallyLived() {
        let lateTuesdayUTC = Date(timeIntervalSince1970: 1_784_071_800) // 2026-07-14 23:30 UTC

        let local = TranscriptFooter.timestamp(lateTuesdayUTC, locale: posix, timeZone: berlin)
        #expect(local == "Wednesday, 2026-07-15T01:30:00+02:00")

        // Same instant, still recoverable as UTC — that's what the offset is for.
        #expect(TranscriptFooter.iso8601(lateTuesdayUTC, timeZone: utc) == "2026-07-14T23:30:00Z")
    }

    /// The whole point: mic, start, stop and duration, all at the foot of the file.
    @Test func footerCarriesTheWholeSessionRecord() {
        let start = Date(timeIntervalSince1970: 0)
        let footer = TranscriptFooter.render(
            microphone: "MacBook Pro Microphone",
            started: start,
            stopped: start.addingTimeInterval(95),
            locale: posix,
            timeZone: utc
        )
        #expect(footer.contains("**Microphone:** MacBook Pro Microphone"))
        #expect(footer.contains("**Started:** Thursday, 1970-01-01T00:00:00Z"))
        #expect(footer.contains("**Stopped:** Thursday, 1970-01-01T00:01:35Z"))
        #expect(footer.contains("**Duration:** 1m 35s"))
    }

    /// Mid-session the file is rewritten constantly; it must not claim a stop time it
    /// doesn't have yet.
    @Test func anUnfinishedSessionSaysSo() {
        let footer = TranscriptFooter.render(
            microphone: "Mic", started: Date(timeIntervalSince1970: 0), stopped: nil,
            locale: posix, timeZone: utc
        )
        #expect(footer.contains("still recording"))
        #expect(!footer.contains("Duration"))
    }
}
