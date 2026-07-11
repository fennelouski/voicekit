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
        case .rightCommand: return "Right ⌘"
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

enum CleanupMode: String, CaseIterable, Identifiable {
    case off
    case onDevice
    case claude
    case local

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .onDevice: return "Apple Intelligence (on-device)"
        case .claude: return "Claude (cloud, your API key)"
        case .local: return "Custom local model"
        }
    }
}

enum ClaudeModel: String, CaseIterable, Identifiable {
    case opus = "claude-opus-4-8"
    case sonnet = "claude-sonnet-5"
    case haiku = "claude-haiku-4-5"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .opus: return "Claude Opus 4.8 — best quality"
        case .sonnet: return "Claude Sonnet 5 — balanced"
        case .haiku: return "Claude Haiku 4.5 — fastest"
        }
    }
}

enum Settings {
    static let hotkeyKey = "dictate_hotkey"
    static let localeKey = "dictate_localeId"
    static let cleanupModeKey = "dictate_cleanupMode"
    static let claudeModelKey = "dictate_claudeModel"
    /// Shared across cleanup providers; key name kept for back-compat.
    static let cleanupInstructionsKey = "dictate_claudeInstructions"
    static let localModelBaseURLKey = "dictate_localModelBaseURL"
    static let localModelNameKey = "dictate_localModelName"
    static let claudeAPIKeyAccount = "anthropic-api-key"
    static let onboardingCompleteKey = "dictate_onboardingComplete"
    static let showMenuBarIconKey = "dictate_showMenuBarIcon"
    static let learningEnabledKey = "dictate_learningEnabled"
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

    static var cleanupMode: CleanupMode {
        if let raw = UserDefaults.standard.string(forKey: cleanupModeKey),
           let mode = CleanupMode(rawValue: raw) {
            return mode
        }
        return UserDefaults.standard.bool(forKey: legacyAICleanupKey) ? .onDevice : .off
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

    static var onboardingComplete: Bool {
        UserDefaults.standard.bool(forKey: onboardingCompleteKey)
    }

    /// Default on. Hotkeys work without it; reopening the app shows Settings.
    static var showMenuBarIcon: Bool {
        UserDefaults.standard.object(forKey: showMenuBarIconKey) as? Bool ?? true
    }

    /// Learn corrections from how the user edits inserted text. Default on.
    static var learningEnabled: Bool {
        UserDefaults.standard.object(forKey: learningEnabledKey) as? Bool ?? true
    }
}
#endif
