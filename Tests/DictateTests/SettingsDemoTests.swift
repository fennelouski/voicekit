//
//  SettingsDemoTests.swift
//  DictateTests
//
//  The only non-view logic behind the settings demos: the synthetic voice level the
//  HUD preview runs on, the canned cleanup results, and the raw-string → enum bridge.
//

import SwiftUI
import Testing
@testable import Dictate

@Suite struct SettingsDemoTests {
    /// Every indicator clamps its input, so an out-of-range level wouldn't crash — it would
    /// silently flatten the preview into a still image, which is exactly the bug worth catching.
    @Test func previewLevelStaysInRangeAndKeepsMoving() {
        var seen: [Float] = []
        for step in 0..<2000 {
            let level = previewLevel(at: Double(step) * 0.02)
            #expect(level >= 0 && level <= 1)
            seen.append(level)
        }
        let swing = (seen.max() ?? 0) - (seen.min() ?? 0)
        #expect(swing > 0.5, "the preview has to actually swell and fall, not sit at one level")
    }

    @Test func everyCleanupModeHasSomethingToShow() {
        for mode in CleanupMode.allCases {
            #expect(!cleanupDemoResult(mode).isEmpty)
            #expect(!cleanupDemoNote(mode).isEmpty)
        }
    }

    /// Off does local filler-word stripping only, so it must not fabricate the polish the
    /// other modes are the whole reason you'd turn on.
    @Test func cleanupOffIsVisiblyWeakerThanTheRest() {
        #expect(cleanupDemoResult(.off) != cleanupDemoResult(.onDevice))
        #expect(!cleanupDemoResult(.off).contains("um "))
        #expect(cleanupDemoSample.contains("um "))
    }

    @Test func rawStringBindingBridgesToItsEnum() {
        var raw = HUDStyle.orb.rawValue
        let binding = Binding(get: { raw }, set: { raw = $0 }).asEnum(HUDStyle.bars)

        #expect(binding.wrappedValue == .orb)

        binding.wrappedValue = .halo
        #expect(raw == HUDStyle.halo.rawValue)
    }

    @Test func unknownRawValueFallsBackInsteadOfCrashing() {
        var raw = "a-style-from-a-newer-build"
        let binding = Binding(get: { raw }, set: { raw = $0 }).asEnum(HUDStyle.bars)

        #expect(binding.wrappedValue == .bars)
    }
}
