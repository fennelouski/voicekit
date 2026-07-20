//
//  SettingsWindow.swift
//  Dictate
//
//  The settings window: a sidebar of panes, each one a Form. The panes themselves
//  live in SettingsUI/.
//

#if os(macOS)
import AppKit
import SwiftUI

@available(macOS 26.0, *)
enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case input
    case cleanup
    case appearance
    case conversation
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .input: return String(localized: "Input")
        case .cleanup: return String(localized: "Cleanup")
        case .appearance: return String(localized: "Appearance")
        case .conversation: return String(localized: "Conversation")
        case .privacy: return String(localized: "Privacy")
        }
    }

    /// What's actually inside, so the sidebar answers "which pane was that in?" without
    /// making you click through all five.
    var subtitle: String {
        switch self {
        case .general: return String(localized: "Hotkey, menu bar, launch at login")
        case .input: return String(localized: "Language and microphone")
        case .cleanup: return String(localized: "Which model polishes your words")
        case .appearance: return String(localized: "The popup you see while dictating")
        case .conversation: return String(localized: "Record several people to one transcript")
        case .privacy: return String(localized: "Learned corrections, transcripts")
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .input: return "mic"
        case .cleanup: return "wand.and.sparkles"
        case .appearance: return "paintbrush"
        case .conversation: return "person.2.wave.2"
        case .privacy: return "hand.raised"
        }
    }

    var tint: Color {
        switch self {
        case .general: return SettingsTint.system
        case .input: return SettingsTint.input
        case .cleanup: return SettingsTint.cleanup
        case .appearance: return SettingsTint.appearance
        case .conversation: return SettingsTint.conversation
        case .privacy: return SettingsTint.privacy
        }
    }
}

@available(macOS 26.0, *)
@MainActor
final class SettingsWindowController: NSWindowController {
    private static let autosaveName = "DictateSettings"

    /// `onWelcome` closes this window and opens the guide — AppDelegate owns both, so it
    /// hands the action down rather than the view reaching back up for it.
    convenience init(onWelcome: @escaping () -> Void, onShowHistory: @escaping () -> Void = {}) {
        let hosting = NSHostingController(rootView: SettingsView(onWelcome: onWelcome, onShowHistory: onShowHistory))
        // The default, .preferredContentSize, makes the window track SwiftUI's intrinsic size —
        // which fights a resizable split view and pins the window to whichever pane is showing.
        hosting.sizingOptions = []

        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "Dictate Settings")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.contentMinSize = NSSize(width: 640, height: 460)
        window.setContentSize(NSSize(width: 780, height: 580))

        self.init(window: window)

        // Restore before naming, or the name-setting call saves the frame we're about to replace.
        if !window.setFrameUsingName(Self.autosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.autosaveName)
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@available(macOS 26.0, *)
struct SettingsView: View {
    var onWelcome: () -> Void = {}
    var onShowHistory: () -> Void = {}

    @AppStorage(Settings.settingsPaneKey) private var paneRaw = SettingsPane.general.rawValue

    private var pane: SettingsPane { SettingsPane(rawValue: paneRaw) ?? .general }

    var body: some View {
        NavigationSplitView {
            // Cards rather than list rows: five bare rows left most of the sidebar empty,
            // and the room was better spent saying what's in each pane.
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(SettingsPane.allCases) { pane in
                        card(pane)
                    }

                    Divider()
                        .padding(.vertical, 4)

                    welcomeCard
                }
                .padding(10)
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            detail
                .navigationTitle(pane.title)
        }
    }

    /// An action, not a pane — it's below a divider and never draws as selected, because it
    /// takes you out of Settings entirely.
    private var welcomeCard: some View {
        Button(action: onWelcome) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundStyle(SettingsTint.learning)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome Guide")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Permissions, your hotkey, and a box to try it in")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Welcome Guide. Closes settings and opens the guide.")
    }

    private func card(_ target: SettingsPane) -> some View {
        let selected = target == pane
        return Button {
            paneRaw = target.rawValue
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: target.systemImage)
                    .font(.system(size: 14))
                    // Selected, the card is already the accent colour — a tinted glyph on top
                    // of it would be unreadable.
                    .foregroundStyle(selected ? Color.white : target.tint)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(target.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(target.subtitle)
                        .font(.caption)
                        .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color.accentColor : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(selected ? 0 : 0.10), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(target.title). \(target.subtitle)")
    }

    @ViewBuilder
    private var detail: some View {
        switch pane {
        case .general: GeneralPane()
        case .input: InputPane()
        case .cleanup: CleanupPane()
        case .appearance: AppearancePane()
        case .conversation: ConversationPane()
        case .privacy: PrivacyPane(onShowHistory: onShowHistory)
        }
    }
}
#endif
