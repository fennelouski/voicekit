//
//  DictationHistoryTests.swift
//  DictateTests
//
//  The in-memory recent-dictations store: one-hour window, newest first,
//  empty input ignored.
//

import Foundation
import Testing
@testable import Dictate

@MainActor
struct DictationHistoryTests {

    @Test func newestFirstWithinWindow() {
        let history = DictationHistory()
        let now = Date()
        history.add("too old", at: now.addingTimeInterval(-3700))
        history.add("first", at: now.addingTimeInterval(-120))
        history.add("second", at: now.addingTimeInterval(-5))
        #expect(history.recent(now: now).map(\.text) == ["second", "first"])
    }

    @Test func entriesExpireAsTimePasses() {
        let history = DictationHistory()
        let now = Date()
        history.add("fades", at: now)
        #expect(history.recent(now: now).count == 1)
        #expect(history.recent(now: now.addingTimeInterval(3700)).isEmpty)
    }

    @Test func whitespaceOnlyIgnoredAndTextTrimmed() {
        let history = DictationHistory()
        let now = Date()
        history.add("   ", at: now)
        history.add("hello world \n", at: now)
        let texts = history.recent(now: now).map(\.text)
        #expect(texts == ["hello world"])
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
