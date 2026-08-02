//
//  PermissionFlowTests.swift
//  DictateTests
//

import Testing
@testable import Dictate

@Suite struct PermissionFlowTests {
    /// A rebuilt or updated app can keep its microphone and speech grants while losing
    /// Accessibility. This is the exact state where transcription works but ⌘V is blocked.
    @Test func missingAccessibilityReturnsToGuidedSetup() {
        #expect(PermissionRecovery.requiresGuidedSetup(
            microphoneGranted: true, speechGranted: true, accessibilityGranted: false
        ))
    }

    @Test func fullyGrantedPermissionsDoNotInterruptLaunch() {
        #expect(!PermissionRecovery.requiresGuidedSetup(
            microphoneGranted: true, speechGranted: true, accessibilityGranted: true
        ))
    }
}
