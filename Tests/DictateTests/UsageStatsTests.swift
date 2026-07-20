//
//  UsageStatsTests.swift
//  DictateTests
//
//  The lifetime counters behind the About panel: a monotonic dictation
//  count, and a first-launch date that seeds itself exactly once.
//

import Foundation
import Testing
@testable import Dictate

@Suite(.serialized)
struct UsageStatsTests {
    @Test func totalDictationsIncrementsAndPersists() {
        let saved = UserDefaults.standard.object(forKey: Settings.totalDictationsKey)
        defer { UserDefaults.standard.set(saved, forKey: Settings.totalDictationsKey) }

        UserDefaults.standard.set(0, forKey: Settings.totalDictationsKey)
        #expect(Settings.totalDictations == 0)
        Settings.recordDictationCompleted()
        Settings.recordDictationCompleted()
        #expect(Settings.totalDictations == 2)
    }

    @Test func firstLaunchDateSeedsOnceAndThenStaysFixed() {
        let saved = UserDefaults.standard.object(forKey: Settings.firstLaunchDateKey)
        defer { UserDefaults.standard.set(saved, forKey: Settings.firstLaunchDateKey) }

        UserDefaults.standard.removeObject(forKey: Settings.firstLaunchDateKey)
        let first = Settings.firstLaunchDate
        let second = Settings.firstLaunchDate
        #expect(first == second)
    }
}
