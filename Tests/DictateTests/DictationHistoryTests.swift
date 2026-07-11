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
