//
//  DictateApp.swift
//  Dictate
//
//  The keyboard does the work; this app exists to get it turned on. A keyboard extension
//  can't present a permission prompt, so the microphone and speech grants have to be asked
//  for here — the extension inherits them.
//

import AVFoundation
import Speech
import SwiftUI
import VoiceKit

@main
struct DictateApp: App {
    var body: some Scene {
        WindowGroup {
            SetupView()
        }
    }
}

struct SetupView: View {
    @State private var granted: Bool?
    @State private var tryItText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Allow microphone & speech") {
                        Task { granted = await requestPermissions() }
                    }
                    .disabled(granted == true)

                    if let granted {
                        Label(
                            granted ? "Granted" : "Denied — enable in Settings → Dictate",
                            systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(granted ? .green : .orange)
                    }
                } header: {
                    Text("1. Permissions")
                } footer: {
                    Text("The keyboard can't ask for these itself — it uses what you grant here.")
                }

                Section {
                    Link("Open Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                } header: {
                    Text("2. Turn the keyboard on")
                } footer: {
                    Text("General → Keyboard → Keyboards → Add New Keyboard → Dictate, then tap Dictate again and turn on Full Access. Without Full Access the extension can't open the microphone.")
                }

                Section {
                    TextField("Hold the globe key, pick Dictate, and talk", text: $tryItText, axis: .vertical)
                        .lineLimit(3...)
                } header: {
                    Text("3. Try it")
                }

                Section {
                    Label(
                        AICleanup.isAvailable
                            ? "Apple Intelligence is ready"
                            : "Apple Intelligence unavailable — text is typed as dictated",
                        systemImage: AICleanup.isAvailable ? "sparkles" : "sparkles.slash"
                    )
                    .foregroundStyle(AICleanup.isAvailable ? Color.secondary : Color.orange)
                } footer: {
                    Text("Speech is transcribed and polished on-device. No audio or text is sent anywhere.")
                }
            }
            .navigationTitle("Dictate")
        }
    }

    /// Both grants are needed and they're separate prompts: speech recognition authorizes the
    /// transcriber, the record permission authorizes the mic the extension opens.
    private func requestPermissions() async -> Bool {
        let speech = await SpeechRecognitionService.requestAuthorization()
        let mic = await AVAudioApplication.requestRecordPermission()
        return speech == .authorized && mic
    }
}
