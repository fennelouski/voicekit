import Foundation
import Testing
@testable import Dictate

struct PolishingPolicyTests {
    @Test func polishingRequiresExplicitOptInEvenWithASavedProviderChain() throws {
        let name = "DictatePolicyTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("onDevice,claude", forKey: Settings.cleanupChainKey)
        #expect(!Settings.polishingPolicy(defaults: defaults).enabled)
        #expect(Settings.polishingPolicy(defaults: defaults).budget == 2)
        defaults.set(true, forKey: Settings.aiPolishingEnabledKey)
        #expect(Settings.polishingPolicy(defaults: defaults).enabled)
        #expect(defaults.string(forKey: Settings.cleanupChainKey) == "onDevice,claude")
        defaults.set(1000.0, forKey: Settings.cleanupBudgetKey)
        #expect(Settings.polishingPolicy(defaults: defaults).budget == 30)
        defaults.set(-1.0, forKey: Settings.cleanupBudgetKey)
        #expect(Settings.polishingPolicy(defaults: defaults).budget == 0.25)
    }
}
