//
//  PrivacyPane.swift
//  Dictate
//
//  The two settings that write something to this Mac: learned corrections and
//  conversation transcripts.
//

#if os(macOS)
import AppKit
import SwiftUI
import VoiceKit

@available(macOS 26.0, *)
struct PrivacyPane: View {
    @AppStorage(Settings.learningEnabledKey) private var learningEnabled = true
    @AppStorage(Settings.conversationTranscriptsKey) private var conversationTranscripts = true

    @State private var correctionsCleared = false

    var body: some View {
        Form {
            Section {
                Toggle("Learn from my edits", isOn: $learningEnabled)

                SettingCaptionRow(
                    caption: "Dictate watches how you fix its text and stops making the same mistake.",
                    title: "Learn From My Edits",
                    explanation: """
                        After inserting text, Dictate watches (via Accessibility) how you edit it. \
                        If you keep correcting "cloud code" to "Claude Code", it learns that and \
                        applies the correction itself next time.

                        Everything stays on this Mac — the corrections are never uploaded, and they \
                        apply no matter which cleanup mode you're using. Reset them any time below.
                        """,
                    value: $learningEnabled
                ) { LearningDemo(enabled: $0) }

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
            } header: {
                SettingsLabel("Learning", systemImage: "brain", tint: SettingsTint.learning)
            }

            Section {
                Toggle("Save conversation transcripts", isOn: $conversationTranscripts)

                SettingCaptionRow(
                    caption: "Write a speaker-labeled transcript to disk as you dictate.",
                    title: "Conversation Transcripts",
                    explanation: """
                        Saves a transcript to this Mac while you dictate, written to disk moments \
                        after the words are spoken, with speakers told apart. It works best with \
                        two or three voices.

                        Each file ends with a record of the session: which microphone was used, \
                        when it started and stopped, and how long it ran. Times are your local \
                        time, with the UTC offset attached, so the day of the week is the one you \
                        actually lived and the exact instant is still unambiguous.

                        No audio is ever stored, nothing is uploaded, and the speaker labels \
                        appear only in the file — they never show up in the text Dictate pastes \
                        for you. On by default; turn it off and nothing is written at all.
                        """,
                    value: $conversationTranscripts
                ) { TranscriptsDemo(enabled: $0) }

                if conversationTranscripts {
                    Button("Open Transcripts Folder") {
                        try? FileManager.default.createDirectory(
                            at: LearningPaths.transcripts,
                            withIntermediateDirectories: true
                        )
                        NSWorkspace.shared.open(LearningPaths.transcripts)
                    }
                }
            } header: {
                SettingsLabel("Transcripts", systemImage: "doc.text", tint: SettingsTint.privacy)
            }
        }
        .formStyle(.grouped)
    }
}
#endif
