//
//  ConversationPane.swift
//  Dictate
//
//  Opt-in conversation recording: assign each audio input (a microphone, or
//  another app's audio) to a named person, and the Record Conversation command
//  merges them into one timestamped transcript. Off by default; nothing about
//  normal dictation changes.
//

#if os(macOS)
import AppKit
import CoreAudio
import SwiftUI
import VoiceKit

@available(macOS 26.0, *)
struct ConversationPane: View {
    @AppStorage(Settings.conversationRecordingKey) private var enabled = false
    @State private var sources: [ConversationSource] = []
    @State private var devices: [SelectableDevice] = []

    var body: some View {
        Form {
            Section {
                Toggle("Enable conversation recording", isOn: $enabled)

                Text("Adds a Record Conversation command to the menu bar. Each input below is recorded as its own named speaker — one mic for you, one for the person next to you, an app for the far side of a call. When you stop, everything is transcribed on this Mac and merged into a single timestamped transcript in the Transcripts folder. Normal dictation is unchanged, and nothing is pasted anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                SettingsLabel(String(localized: "Conversation Recording"), systemImage: "person.2.wave.2", tint: SettingsTint.conversation)
            }

            if enabled {
                Section {
                    if sources.isEmpty {
                        Text("Add a microphone for each person in the room, or an app whose audio you want transcribed (Zoom, Chrome, FaceTime).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach($sources) { $source in
                        HStack(spacing: 10) {
                            Image(systemName: source.kind == .microphone ? "mic" : "app.badge")
                                .foregroundStyle(SettingsTint.conversation)
                                .frame(width: 18)
                            TextField(String(localized: "Name"), text: $source.name)
                                .frame(maxWidth: 160)
                            Text(referenceDescription(source))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Toggle("", isOn: $source.enabled)
                                .labelsHidden()
                            Button {
                                sources.removeAll { $0.id == source.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(String(format: String(localized: "Remove %@"), source.name))
                        }
                    }

                    HStack {
                        Menu(String(localized: "Add Microphone")) {
                            ForEach(devices) { device in
                                Button(device.name) { addMicrophone(device) }
                            }
                        }
                        .fixedSize()
                        Menu(String(localized: "Add App")) {
                            ForEach(runningApps, id: \.id) { app in
                                Button(app.name) { addApp(id: app.id, name: app.name) }
                            }
                        }
                        .fixedSize()
                    }

                    Text("The first time an app's audio is captured, macOS asks for System Audio Recording permission. Audio stays on this Mac and is deleted as soon as the transcript is written; nothing is uploaded.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    SettingsLabel(String(localized: "Speakers"), systemImage: "person.wave.2", tint: SettingsTint.conversation)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            sources = Settings.conversationSources
            devices = await AudioInputSelection.availableDevices()
        }
        .onChange(of: sources) { _, newValue in
            Settings.saveConversationSources(newValue)
        }
    }

    // MARK: - Roster edits

    private func addMicrophone(_ device: SelectableDevice) {
        guard let id = AudioDeviceID(device.id),
              let uid = AudioInputSelection.deviceUID(for: id) else { return }
        sources.append(ConversationSource(kind: .microphone, reference: uid, name: device.name))
    }

    private func addApp(id: String, name: String) {
        sources.append(ConversationSource(kind: .app, reference: id, name: name))
    }

    /// What the row's name is attached to: the mic's current name, or the app.
    private func referenceDescription(_ source: ConversationSource) -> String {
        switch source.kind {
        case .microphone:
            for device in devices {
                if let id = AudioDeviceID(device.id), AudioInputSelection.deviceUID(for: id) == source.reference {
                    return device.name
                }
            }
            return String(localized: "Not connected")
        case .app:
            return NSRunningApplication.runningApplications(withBundleIdentifier: source.reference)
                .first?.localizedName ?? source.reference
        }
    }

    private var runningApps: [(id: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let id = app.bundleIdentifier, let name = app.localizedName else { return nil }
                return (id: id, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
#endif
