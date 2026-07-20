//
//  Settings.swift
//  Dictate
//
//  UserDefaults-backed app settings shared between the UI and the controller.
//  The Claude API key is the one exception: it lives in the Keychain.
//

#if os(macOS)
import AppKit
import Foundation

enum Hotkey: String, CaseIterable, Identifiable {
    case fn
    case rightCommand

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fn: return "Fn"
        case .rightCommand: return String(localized: "Right ⌘")
        }
    }

    /// Virtual key code seen in flagsChanged events (fn = 63, right ⌘ = 54).
    var keyCode: UInt16 {
        switch self {
        case .fn: return 63
        case .rightCommand: return 54
        }
    }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .fn: return .function
        case .rightCommand: return .command
        }
    }
}

enum HUDStyle: String, CaseIterable, Identifiable {
    case bars
    case orb
    case wave
    case ripple
    case halo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bars: return String(localized: "Level bars")
        case .orb: return String(localized: "Voice orb")
        case .wave: return String(localized: "Waveform")
        case .ripple: return String(localized: "Sonar ripple")
        case .halo: return String(localized: "Breathing halo")
        }
    }
}

/// Where the dictation pill sits. The pill grows toward the screen's centre axis, so an
/// edge-anchored HUD can't run off the screen as the transcript gets longer.
enum HUDPosition: String, CaseIterable, Identifiable {
    case topLeft, topCenter, topRight
    case centerLeft, center, centerRight
    case bottomLeft, bottomCenter, bottomRight

    var id: String { rawValue }

    /// 0 = top, 1 = middle, 2 = bottom.
    var row: Int {
        switch self {
        case .topLeft, .topCenter, .topRight: return 0
        case .centerLeft, .center, .centerRight: return 1
        case .bottomLeft, .bottomCenter, .bottomRight: return 2
        }
    }

    /// 0 = left, 1 = centre, 2 = right.
    var column: Int {
        switch self {
        case .topLeft, .centerLeft, .bottomLeft: return 0
        case .topCenter, .center, .bottomCenter: return 1
        case .topRight, .centerRight, .bottomRight: return 2
        }
    }

    static func at(row: Int, column: Int) -> HUDPosition {
        allCases.first { $0.row == row && $0.column == column } ?? .bottomCenter
    }

    var displayName: String {
        // Whole phrases, not composed from "Top"/"left": word order and casing vary by language.
        switch self {
        case .topLeft: return String(localized: "Top left")
        case .topCenter: return String(localized: "Top centre")
        case .topRight: return String(localized: "Top right")
        case .centerLeft: return String(localized: "Middle left")
        case .center: return String(localized: "Centre")
        case .centerRight: return String(localized: "Middle right")
        case .bottomLeft: return String(localized: "Bottom left")
        case .bottomCenter: return String(localized: "Bottom centre")
        case .bottomRight: return String(localized: "Bottom right")
        }
    }
}

/// The transcript's type size in the pill.
enum HUDTextSize: String, CaseIterable, Identifiable {
    case small, medium, large, extraLarge

    var id: String { rawValue }

    var points: CGFloat {
        switch self {
        case .small: return 11
        case .medium: return 13
        case .large: return 17
        case .extraLarge: return 22
        }
    }

    var displayName: String {
        switch self {
        case .small: return String(localized: "Small")
        case .medium: return String(localized: "Medium")
        case .large: return String(localized: "Large")
        case .extraLarge: return String(localized: "Extra Large")
        }
    }
}

/// One speed scale, used for both the state transitions and the transcript reveal.
/// `.instant` means no animation at all, not a very short one.
enum HUDSpeed: String, CaseIterable, Identifiable {
    case instant, fast, normal, slow, slowMo

    var id: String { rawValue }

    var seconds: Double {
        switch self {
        case .instant: return 0
        case .fast: return 0.15
        case .normal: return 0.28
        case .slow: return 0.5
        case .slowMo: return 1.2
        }
    }

    /// How the state transitions read.
    var displayName: String {
        switch self {
        case .instant: return String(localized: "Instant")
        case .fast: return String(localized: "Fast")
        case .normal: return String(localized: "Normal")
        case .slow: return String(localized: "Slow")
        case .slowMo: return String(localized: "Slow-mo")
        }
    }

    /// How the transcript reveal reads — same scale, friendlier names for words landing.
    var revealName: String {
        switch self {
        case .instant: return String(localized: "ASAP")
        case .fast: return String(localized: "Quick")
        case .normal: return String(localized: "Natural")
        case .slow: return String(localized: "Leisurely")
        case .slowMo: return String(localized: "Slow-mo", comment: "Transcript reveal speed (reuses the Slow-mo label)")
        }
    }
}

enum CleanupMode: String, CaseIterable, Identifiable {
    case off
    case onDevice
    case claude
    case openAI
    case gemini
    case groq
    case openRouter
    case local

    var id: String { rawValue }

    /// The raw values line up with `AIProvider`, so a mode either names a provider or it
    /// doesn't. That keeps the two lists from drifting apart.
    var provider: AIProvider? { AIProvider(rawValue: rawValue) }

    var displayName: String {
        switch self {
        case .off: return String(localized: "Off")
        case .onDevice: return String(localized: "Apple Intelligence (on-device)")
        case .claude: return String(localized: "Claude (your API key)")
        case .openAI: return String(localized: "OpenAI (your API key)")
        case .gemini: return String(localized: "Google Gemini (your API key)")
        case .groq: return String(localized: "Groq (your API key)")
        case .openRouter: return String(localized: "OpenRouter (your API key)")
        case .local: return String(localized: "Custom local model")
        }
    }

    /// Short enough to read in a numbered list.
    var chainName: String {
        switch self {
        case .off: return String(localized: "Off")
        case .onDevice: return String(localized: "Apple Intelligence")
        case .local: return String(localized: "Custom local model")
        default: return provider?.displayName ?? rawValue
        }
    }

    var systemImage: String {
        switch self {
        case .off: return "slash.circle"
        case .onDevice: return "apple.logo"
        case .local: return "desktopcomputer"
        default: return "cloud"
        }
    }

    /// Every step a chain can contain. `off` isn't one of them — an empty chain is "off".
    static var chainable: [CleanupMode] {
        allCases.filter { $0 != .off }
    }
}

enum ClaudeModel: String, CaseIterable, Identifiable {
    case opus = "claude-opus-4-8"
    case sonnet = "claude-sonnet-5"
    case haiku = "claude-haiku-4-5"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .opus: return String(localized: "Claude Opus 4.8 — best quality")
        case .sonnet: return String(localized: "Claude Sonnet 5 — balanced")
        case .haiku: return String(localized: "Claude Haiku 4.5 — fastest")
        }
    }
}

/// Where the spoken-command → literal pass runs relative to the AI cleanup chain.
enum FormattingPosition: String, CaseIterable, Identifiable {
    /// Before the AI pass: the model sees the punctuation and capitalizes/polishes around it.
    case beforeCleanup
    /// After the AI pass: the literals are the last word, untouched by any model.
    case afterCleanup

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .beforeCleanup: return String(localized: "Before AI cleanup")
        case .afterCleanup: return String(localized: "After AI cleanup")
        }
    }
}

enum Settings {
    static let hotkeyKey = "dictate_hotkey"
    static let localeKey = "dictate_localeId"
    static let cleanupModeKey = "dictate_cleanupMode"
    static let cleanupChainKey = "dictate_cleanupChain"
    static let claudeModelKey = "dictate_claudeModel"
    /// Shared across cleanup providers; key name kept for back-compat.
    static let cleanupInstructionsKey = "dictate_claudeInstructions"
    static let localModelBaseURLKey = "dictate_localModelBaseURL"
    static let localModelNameKey = "dictate_localModelName"
    static let claudeAPIKeyAccount = "anthropic-api-key"
    static let onboardingCompleteKey = "dictate_onboardingComplete"
    static let showMenuBarIconKey = "dictate_showMenuBarIcon"
    static let hudStyleKey = "dictate_hudStyle"
    static let hudPositionKey = "dictate_hudPosition"
    static let hudTextSizeKey = "dictate_hudTextSize"
    static let hudTransitionSpeedKey = "dictate_hudTransitionSpeed"
    static let hudRevealSpeedKey = "dictate_hudRevealSpeed"
    /// The settings pane last shown, so the window reopens where you left it.
    static let settingsPaneKey = "dictate_settingsPane"
    static let learningEnabledKey = "dictate_learningEnabled"
    static let conversationTranscriptsKey = "dictate_conversationTranscripts"
    static let conversationRecordingKey = "dictate_conversationRecording"
    static let conversationSourcesKey = "dictate_conversationSources"
    static let spokenCommandsEnabledKey = "dictate_spokenCommandsEnabled"
    static let spokenCommandsPositionKey = "dictate_spokenCommandsPosition"
    /// Pre-cloud boolean toggle; read only to migrate into cleanupMode.
    static let legacyAICleanupKey = "dictate_aiCleanup"

    static var hotkey: Hotkey {
        Hotkey(rawValue: UserDefaults.standard.string(forKey: hotkeyKey) ?? "") ?? .fn
    }

    /// Nil means system default locale.
    static var locale: Locale? {
        guard let id = UserDefaults.standard.string(forKey: localeKey), !id.isEmpty else { return nil }
        return Locale(identifier: id)
    }

    /// Pre-chain builds stored a single choice. Read only to seed the chain.
    static var cleanupMode: CleanupMode {
        if let raw = UserDefaults.standard.string(forKey: cleanupModeKey),
           let mode = CleanupMode(rawValue: raw) {
            return mode
        }
        return UserDefaults.standard.bool(forKey: legacyAICleanupKey) ? .onDevice : .off
    }

    /// Cleanup steps, tried in order until one works. Empty means cleanup is off.
    ///
    /// Defaults to the on-device pass: it's free, needs no key, sends nothing anywhere, and
    /// works the moment you install. Anything else is something the user opts into.
    static var cleanupChain: [CleanupMode] {
        if let raw = UserDefaults.standard.string(forKey: cleanupChainKey) {
            return decodeChain(raw)
        }
        // No chain and no legacy choice: a fresh install, which gets the sensible default.
        guard UserDefaults.standard.string(forKey: cleanupModeKey) != nil
                || UserDefaults.standard.object(forKey: legacyAICleanupKey) != nil else {
            return [.onDevice]
        }
        // Seeded from the old single-choice setting. A cloud step on its own is exactly the
        // trap this chain exists to fix — it fails every time you're without a key — so the
        // migration puts the free on-device pass behind it.
        let legacy = cleanupMode
        switch legacy {
        case .off: return []
        case .onDevice: return [.onDevice]
        default: return [legacy, .onDevice]
        }
    }

    static func decodeChain(_ raw: String) -> [CleanupMode] {
        raw.split(separator: ",")
            .compactMap { CleanupMode(rawValue: String($0)) }
            .filter { $0 != .off }
    }

    /// Comma-separated raw values — one defaults key, and readable in `defaults read`.
    static func encodeChain(_ chain: [CleanupMode]) -> String {
        chain.filter { $0 != .off }.map(\.rawValue).joined(separator: ",")
    }

    static var claudeModel: String {
        UserDefaults.standard.string(forKey: claudeModelKey) ?? ClaudeModel.opus.rawValue
    }

    static var cleanupInstructions: String {
        UserDefaults.standard.string(forKey: cleanupInstructionsKey) ?? ""
    }

    static var localModelBaseURL: String {
        UserDefaults.standard.string(forKey: localModelBaseURLKey) ?? "http://localhost:11434/v1"
    }

    static var localModelName: String {
        UserDefaults.standard.string(forKey: localModelNameKey) ?? ""
    }

    static var claudeAPIKey: String? {
        KeychainStore.string(forKey: claudeAPIKeyAccount)
    }

    // MARK: - Per-provider config

    /// One defaults key per provider, so switching providers doesn't clobber the model you
    /// picked for the last one.
    static func modelKey(for provider: AIProvider) -> String {
        "dictate_model_" + provider.rawValue
    }

    static func model(for provider: AIProvider) -> String {
        let stored = UserDefaults.standard.string(forKey: modelKey(for: provider)) ?? ""
        if !stored.trimmingCharacters(in: .whitespaces).isEmpty { return stored }

        // Single-provider builds kept these two under their own keys.
        switch provider {
        case .claude:
            if let legacy = UserDefaults.standard.string(forKey: claudeModelKey) { return legacy }
        case .local:
            if let legacy = UserDefaults.standard.string(forKey: localModelNameKey) { return legacy }
        default:
            break
        }
        return provider.defaultModel
    }

    static func apiKey(for provider: AIProvider) -> String? {
        KeychainStore.string(forKey: provider.keychainAccount)
    }

    /// Fixed for the cloud providers; only the custom option reads the user's server URL.
    static func baseURL(for provider: AIProvider) -> String {
        guard provider.editableBaseURL else { return provider.baseURL }
        let stored = localModelBaseURL.trimmingCharacters(in: .whitespaces)
        return stored.isEmpty ? provider.baseURL : stored
    }

    static var onboardingComplete: Bool {
        UserDefaults.standard.bool(forKey: onboardingCompleteKey)
    }

    static let acceptedTermsVersionKey = "dictate_acceptedTermsVersion"

    /// 0 (default) for anyone who has never accepted, so a fresh install re-prompts.
    static var acceptedTermsVersion: Int {
        UserDefaults.standard.integer(forKey: acceptedTermsVersionKey)
    }

    /// Behind the current version → re-prompt (new install or revised terms).
    static var termsAccepted: Bool {
        acceptedTermsVersion >= TermsOfService.version
    }

    static func acceptTerms() {
        UserDefaults.standard.set(TermsOfService.version, forKey: acceptedTermsVersionKey)
    }

    /// Default on. Hotkeys work without it; reopening the app shows Settings.
    static var showMenuBarIcon: Bool {
        UserDefaults.standard.object(forKey: showMenuBarIconKey) as? Bool ?? true
    }

    static var hudStyle: HUDStyle {
        HUDStyle(rawValue: UserDefaults.standard.string(forKey: hudStyleKey) ?? "") ?? .bars
    }

    static var hudPosition: HUDPosition {
        HUDPosition(rawValue: UserDefaults.standard.string(forKey: hudPositionKey) ?? "") ?? .bottomCenter
    }

    static var hudTextSize: HUDTextSize {
        HUDTextSize(rawValue: UserDefaults.standard.string(forKey: hudTextSizeKey) ?? "") ?? .medium
    }

    /// State changes (listening → cleaning up → error). Default lands in the 200–350ms band
    /// that reads as a transition rather than a flash.
    static var hudTransitionSpeed: HUDSpeed {
        HUDSpeed(rawValue: UserDefaults.standard.string(forKey: hudTransitionSpeedKey) ?? "") ?? .normal
    }

    /// How long new words take to land in the pill. Faster than the state transitions by
    /// default, because these fire continuously while you speak.
    static var hudRevealSpeed: HUDSpeed {
        HUDSpeed(rawValue: UserDefaults.standard.string(forKey: hudRevealSpeedKey) ?? "") ?? .fast
    }

    /// Learn corrections from how the user edits inserted text. Default on.
    static var learningEnabled: Bool {
        UserDefaults.standard.object(forKey: learningEnabledKey) as? Bool ?? true
    }

    /// Convert spoken formatting commands ("colon", "new line") into literals. Default on.
    static var spokenCommandsEnabled: Bool {
        UserDefaults.standard.object(forKey: spokenCommandsEnabledKey) as? Bool ?? true
    }

    /// Where that conversion runs in the cleanup flow. Default before the AI pass.
    static var spokenCommandsPosition: FormattingPosition {
        FormattingPosition(rawValue: UserDefaults.standard.string(forKey: spokenCommandsPositionKey) ?? "") ?? .beforeCleanup
    }

    /// Save a speaker-labeled transcript to disk while dictating. Default on: it stays on
    /// this Mac, and it's the only record of what you actually said.
    static var conversationTranscripts: Bool {
        UserDefaults.standard.object(forKey: conversationTranscriptsKey) as? Bool ?? true
    }

    /// Multi-input conversation recording (named mics + app audio → merged transcript).
    /// Opt-in and default off; nothing about normal dictation changes when it's off.
    static var conversationRecordingEnabled: Bool {
        UserDefaults.standard.bool(forKey: conversationRecordingKey)
    }

    /// The conversation-source roster, JSON in one defaults key (same one-key idiom as
    /// cleanupChain). Corrupt or missing data reads as an empty roster.
    static var conversationSources: [ConversationSource] {
        guard let data = UserDefaults.standard.string(forKey: conversationSourcesKey)?.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([ConversationSource].self, from: data)) ?? []
    }

    static func saveConversationSources(_ sources: [ConversationSource]) {
        guard let data = try? JSONEncoder().encode(sources) else { return }
        UserDefaults.standard.set(String(decoding: data, as: UTF8.self), forKey: conversationSourcesKey)
    }
}
#endif
