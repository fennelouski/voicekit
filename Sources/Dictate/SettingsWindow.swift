//
//  SettingsWindow.swift
//  Dictate
//
//  Settings: hotkey, language, microphone, AI cleanup, launch at login.
//

#if os(macOS)
import AppKit
import ServiceManagement
import Speech
import SwiftUI
import VoiceKit

@available(macOS 26.0, *)
@MainActor
final class SettingsWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
        window.title = "Dictate Settings"
        window.styleMask = [.titled, .closable]
        self.init(window: window)
    }

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@available(macOS 26.0, *)
struct SettingsView: View {
    @AppStorage(Settings.hotkeyKey) private var hotkeyRaw = Hotkey.fn.rawValue
    @AppStorage(Settings.localeKey) private var localeId = ""
    @AppStorage(Settings.cleanupModeKey) private var cleanupModeRaw = Settings.cleanupMode.rawValue
    @AppStorage(Settings.claudeModelKey) private var claudeModelRaw = Settings.claudeModel
    @AppStorage(Settings.cleanupInstructionsKey) private var cleanupInstructions = ""
    @AppStorage(Settings.localModelBaseURLKey) private var localBaseURL = "http://localhost:11434/v1"
    @AppStorage(Settings.localModelNameKey) private var localModelName = ""
    @AppStorage(Settings.learningEnabledKey) private var learningEnabled = true
    @AppStorage(Settings.showMenuBarIconKey) private var showMenuBarIcon = true

    @State private var apiKey = Settings.claudeAPIKey ?? ""
    @State private var keyTest = KeyTestState.idle

    private enum KeyTestState {
        case idle
        case testing
        case success
        case failure(String)
    }

    @State private var locales: [Locale] = []
    @State private var devices: [SelectableDevice] = []
    @State private var selectedDeviceId = AudioInputSelection.loadSelectedDeviceId() ?? ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var correctionsCleared = false

    var body: some View {
        Form {
            Section {
                Picker("Hotkey", selection: $hotkeyRaw) {
                    ForEach(Hotkey.allCases) { hotkey in
                        Text("Hold \(hotkey.displayName)").tag(hotkey.rawValue)
                    }
                }
                Text("Hold to dictate, release to insert. A quick tap locks dictation on; tap again to stop.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Language", selection: $localeId) {
                    Text("System default").tag("")
                    ForEach(locales, id: \.identifier) { locale in
                        Text(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                            .tag(locale.identifier)
                    }
                }
                Picker("Microphone", selection: $selectedDeviceId) {
                    Text("System default").tag("")
                    ForEach(devices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .onChange(of: selectedDeviceId) { _, newValue in
                    let device = devices.first { $0.id == newValue }
                    AudioInputSelection.saveSelection(device: device, input: nil)
                }
            }

            Section {
                Picker("Cleanup", selection: $cleanupModeRaw) {
                    ForEach(CleanupMode.allCases) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                switch CleanupMode(rawValue: cleanupModeRaw) ?? .off {
                case .off:
                    Text("Filler words (\"um\", \"uh\") are always removed. Cleanup additionally polishes punctuation and false starts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .onDevice:
                    Text(AICleanup.isAvailable
                         ? "Polishes punctuation and removes false starts before inserting. Runs entirely on-device."
                         : "Apple Intelligence isn't available on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .claude:
                    SecureField("Anthropic API key", text: $apiKey)
                        .onChange(of: apiKey) { _, newValue in
                            KeychainStore.set(newValue, forKey: Settings.claudeAPIKeyAccount)
                            keyTest = .idle
                        }
                    Picker("Model", selection: $claudeModelRaw) {
                        ForEach(ClaudeModel.allCases) { model in
                            Text(model.displayName).tag(model.rawValue)
                        }
                    }
                    TextField("Custom instructions (optional)", text: $cleanupInstructions, axis: .vertical)
                        .lineLimit(2...4)
                    testRow("Test key", disabled: apiKey.isEmpty)
                    Text("Transcripts are sent to Anthropic to be cleaned; if the request fails, the local transcript is inserted unchanged. Audio and transcription stay on this Mac. A typical dictation costs well under a cent.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .local:
                    TextField("Server URL", text: $localBaseURL, prompt: Text("http://localhost:11434/v1"))
                        .onChange(of: localBaseURL) { _, _ in keyTest = .idle }
                    TextField("Model name", text: $localModelName, prompt: Text("llama3.2"))
                        .onChange(of: localModelName) { _, _ in keyTest = .idle }
                    TextField("Custom instructions (optional)", text: $cleanupInstructions, axis: .vertical)
                        .lineLimit(2...4)
                    testRow("Test connection", disabled: localModelName.trimmingCharacters(in: .whitespaces).isEmpty)
                    Text("Works with any OpenAI-compatible server — Ollama, LM Studio, llama.cpp, MLX, vLLM. Everything stays on your machine; if the request fails, the transcript is inserted unchanged.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Learn from my edits", isOn: $learningEnabled)
                Text("After inserting, Dictate watches how you edit the text (via Accessibility) and learns corrections it applies next time. Everything stays on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if learningEnabled {
                    HStack {
                        Button("Reset learned corrections") {
                            CorrectionStore.shared.reset()
                            correctionsCleared = true
                        }
                        if correctionsCleared {
                            Label("Cleared", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
            }

            Section {
                Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
                if !showMenuBarIcon {
                    Text("Hotkeys keep working without the icon. To get back to Settings, open Dictate again from Finder or Spotlight.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            locales = await SpeechTranscriber.supportedLocales
                .sorted { $0.identifier < $1.identifier }
            devices = await AudioInputSelection.availableDevices()
        }
    }

    private var isTestingKey: Bool {
        if case .testing = keyTest { return true }
        return false
    }

    @ViewBuilder
    private func testRow(_ title: String, disabled: Bool) -> some View {
        HStack {
            Button(title) { runCleanupTest() }
                .disabled(disabled || isTestingKey)
            switch keyTest {
            case .idle:
                EmptyView()
            case .testing:
                ProgressView()
                    .controlSize(.small)
            case .success:
                Label("It works", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failure(let message):
                Label(message, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }

    private func runCleanupTest() {
        keyTest = .testing
        Task {
            do {
                switch CleanupMode(rawValue: cleanupModeRaw) ?? .off {
                case .claude:
                    _ = try await ClaudeCleanup.clean("Um, so this is, uh, a test.")
                case .local:
                    _ = try await LocalModelCleanup.clean("Um, so this is, uh, a test.")
                case .off, .onDevice:
                    break
                }
                keyTest = .success
            } catch {
                keyTest = .failure(error.localizedDescription)
            }
        }
    }
}
#endif
