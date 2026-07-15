//
//  GeneralPane.swift
//  Dictate
//
//  Hotkey and the two system toggles.
//

#if os(macOS)
import ServiceManagement
import SwiftUI

@available(macOS 26.0, *)
struct GeneralPane: View {
    @AppStorage(Settings.hotkeyKey) private var hotkeyRaw = Hotkey.fn.rawValue
    @AppStorage(Settings.showMenuBarIconKey) private var showMenuBarIcon = true

    /// Not a default — the real state lives in ServiceManagement, so we read it back on every appear.
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Picker("Hotkey", selection: $hotkeyRaw.asEnum(Hotkey.fn)) {
                    ForEach(Hotkey.allCases) { hotkey in
                        Text("Hold \(hotkey.displayName)").tag(hotkey)
                    }
                }

                SettingCaptionRow(
                    caption: "Hold to dictate, release to insert. A quick tap locks dictation on.",
                    title: "Hotkey",
                    explanation: """
                        Hold the key and speak; let go and your words are inserted wherever the \
                        cursor is. If you'd rather not hold it down, tap it once to lock dictation \
                        on and tap again to stop.

                        Fn sits under your left thumb and does nothing else in most apps, which is \
                        why it's the default. Pick Right ⌘ if you use Fn for something else — \
                        switching input sources, say, or the emoji picker.
                        """,
                    value: $hotkeyRaw.asEnum(Hotkey.fn)
                ) { HotkeyDemo(hotkey: $0) }
            } header: {
                SettingsLabel("Hotkey", systemImage: "keyboard", tint: SettingsTint.hotkey)
            }

            Section {
                Toggle("Show menu bar icon", isOn: $showMenuBarIcon)

                SettingCaptionRow(
                    caption: "Hide it and Dictate runs invisibly — ⌃⌥⌘, always brings Settings back.",
                    title: "Menu Bar Icon",
                    explanation: """
                        The menu bar icon is the visible way to reach Settings, the Welcome Guide, \
                        and your recent dictations.

                        Hiding it disables none of that, because the app's controls are keyboard \
                        shortcuts rather than menu items:

                        • Your hotkey still starts and stops dictation.
                        • ⌃⌥⌘V still opens recent dictations.
                        • ⌃⌥⌘, still opens this window.

                        Those work system-wide whether the icon is showing or not, so you can't \
                        lock yourself out by turning it off.
                        """,
                    value: $showMenuBarIcon
                ) { MenuBarIconDemo(shown: $0) }

                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            // macOS refused; don't leave the toggle claiming something untrue.
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }

                Text("Dictate starts hidden and waits for your hotkey.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                SettingsLabel("System", systemImage: "gearshape", tint: SettingsTint.system)
            }
        }
        .formStyle(.grouped)
    }
}
#endif
