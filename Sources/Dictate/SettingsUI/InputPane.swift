//
//  InputPane.swift
//  Dictate
//
//  What Dictate listens to: the language it recognizes, and the microphone it listens with.
//

#if os(macOS)
import Speech
import SwiftUI
import VoiceKit

@available(macOS 26.0, *)
struct InputPane: View {
    @AppStorage(Settings.localeKey) private var localeId = ""

    /// The microphone doesn't live in `Settings` — VoiceKit owns that key.
    @State private var selectedDeviceId = AudioInputSelection.loadSelectedDeviceId() ?? ""
    @State private var locales: [Locale] = []
    @State private var devices: [SelectableDevice] = []

    var body: some View {
        Form {
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

                Text("Recognition runs on-device in the language you pick. System default follows your Mac's language, and whichever microphone macOS is currently using.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                SettingsLabel(String(localized: "Language & Microphone"), systemImage: "mic", tint: SettingsTint.input)
            }
        }
        .formStyle(.grouped)
        .task {
            locales = await SpeechTranscriber.supportedLocales
                .sorted { $0.identifier < $1.identifier }
            devices = await AudioInputSelection.availableDevices()
        }
    }
}
#endif
