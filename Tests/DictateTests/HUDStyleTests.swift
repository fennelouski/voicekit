//
//  HUDStyleTests.swift
//  DictateTests
//
//  The level → geometry/colour maths behind the HUD styles: clamped at both
//  ends, monotonic in level, and never outgrowing the slot it draws into.
//

import Testing
import VoiceKit
@testable import Dictate

@Suite struct HUDStyleTests {
    @Test func levelClampsAtBothEnds() {
        #expect(clampedLevel(-0.5) == 0)
        #expect(clampedLevel(3) == 1)
        #expect(clampedLevel(.nan) == 0)
        #expect(clampedLevel(0.4) == 0.4)
    }

    @Test func louderIsBiggerAndWarmerInEveryStyle() {
        #expect(VoiceOrb.orbScale(0) < VoiceOrb.orbScale(1))
        #expect(VoiceOrb.glowRadius(0) < VoiceOrb.glowRadius(1))
        #expect(VoiceOrb.hotHue(0) < VoiceOrb.hotHue(1))
        #expect(Waveform.amplitude(0) < Waveform.amplitude(1))
        #expect(Waveform.hue(0) < Waveform.hue(1))
        #expect(SonarRipple.coreScale(0) < SonarRipple.coreScale(1))
        #expect(SonarRipple.ringScale(0, phase: 1) < SonarRipple.ringScale(1, phase: 1))
        #expect(BreathingHalo.lineWidth(0, breath: 0) < BreathingHalo.lineWidth(1, breath: 0))
        #expect(BreathingHalo.glowRadius(0, breath: 0) < BreathingHalo.glowRadius(1, breath: 0))
    }

    /// A runaway level must saturate, not blow an indicator past its slot.
    @Test func extremeLevelsSaturate() {
        #expect(VoiceOrb.orbScale(99) == VoiceOrb.orbScale(1))
        #expect(Waveform.amplitude(99) == Waveform.amplitude(1))
        #expect(SonarRipple.ringScale(99, phase: 1) == SonarRipple.ringScale(1, phase: 1))
        #expect(BreathingHalo.glowRadius(-99, breath: 0) == BreathingHalo.glowRadius(0, breath: 0))
    }

    /// Rings travel outward and fade as they go, whatever the level.
    @Test func ripplesFadeAsTheyExpand() {
        #expect(SonarRipple.ringScale(0.8, phase: 0.1) < SonarRipple.ringScale(0.8, phase: 0.9))
        #expect(SonarRipple.ringOpacity(0.8, phase: 0.1) > SonarRipple.ringOpacity(0.8, phase: 0.9))
    }

    /// Crest to trough at full volume, the wave still fits the slot it draws into.
    @Test func waveformFitsItsSlot() {
        #expect(Waveform.amplitude(1) * 2 <= Waveform.slotHeight)
    }
}
