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
    var onShowHistory: () -> Void = {}

    @AppStorage(Settings.learningEnabledKey) private var learningEnabled = true
    @AppStorage(Settings.conversationTranscriptsKey) private var conversationTranscripts = true
    @AppStorage(Settings.backupRecordingKey) private var backupRecording = true
    @AppStorage(Settings.backupRetentionKey) private var backupRetentionRaw = BackupRetention.untilNextDictation.rawValue
    @AppStorage(Settings.dictationHistoryEnabledKey) private var dictationHistoryEnabled = true
    @AppStorage(Settings.dictationHistoryRetentionKey) private var retentionRaw = HistoryRetention.month.rawValue

    @State private var correctionsCleared = false
    @State private var historyCleared = false
    @State private var correctionHistory: [CorrectionStore.HistoryEntry] = []

    var body: some View {
        Form {
            Section {
                Toggle("Learn from my edits", isOn: $learningEnabled)

                SettingCaptionRow(
                    caption: String(localized: "Dictate watches how you fix its text and stops making the same mistake."),
                    title: String(localized: "Learn From My Edits"),
                    explanation: String(localized: """
                        After inserting text, Dictate watches (via Accessibility) how you edit it. \
                        If you keep correcting "cloud code" to "Claude Code", it learns that and \
                        applies the correction itself next time.

                        Corrections are stored on this Mac and applied locally. If you configure a \
                        cloud cleanup provider, learned spelling hints are also sent with the \
                        transcript to help it preserve your terminology. Reset them any time below.
                        """),
                    value: $learningEnabled
                ) { LearningDemo(enabled: $0) }

                if learningEnabled {
                    HStack {
                        Button("Reset learned corrections") {
                            CorrectionStore.shared.reset()
                            correctionsCleared = true
                            correctionHistory = []
                        }
                        if correctionsCleared {
                            Label("Cleared", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }

                    if !correctionHistory.isEmpty {
                        Divider()
                        Text("Corrections Learned")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(correctionHistory.prefix(20), id: \.correction) { entry in
                            HStack(spacing: 6) {
                                if entry.isActive {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                        .help("Applied automatically")
                                }
                                Text("\(entry.correction.heard) → \(entry.correction.corrected)")
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(String(format: String(localized: "%d manual · %d auto"), entry.manualCount, entry.autoCount))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Button("Remove", role: .destructive) {
                                    CorrectionStore.shared.remove(entry.correction)
                                    correctionHistory = CorrectionStore.shared.history()
                                }
                                .accessibilityLabel("Remove correction for \(entry.correction.heard)")
                            }
                        }
                        if correctionHistory.count > 20 {
                            Text(String(format: String(localized: "+ %d more"), correctionHistory.count - 20))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            } header: {
                SettingsLabel(String(localized: "Learning"), systemImage: "brain", tint: SettingsTint.learning)
            }
            .task { correctionHistory = CorrectionStore.shared.history() }

            Section {
                Toggle("Save conversation transcripts", isOn: $conversationTranscripts)

                SettingCaptionRow(
                    caption: String(localized: "Write a speaker-labeled transcript to disk as you dictate."),
                    title: String(localized: "Conversation Transcripts"),
                    explanation: String(localized: """
                        Saves a transcript to this Mac while you dictate, written to disk moments \
                        after the words are spoken, with speakers told apart. It works best with \
                        two or three voices.

                        Each file ends with a record of the session: which microphone was used, \
                        when it started and stopped, and how long it ran. Times are your local \
                        time, with the UTC offset attached, so the day of the week is the one you \
                        actually lived and the exact instant is still unambiguous.

                        The transcript holds no audio, nothing is uploaded, and the speaker labels \
                        appear only in the file — they never show up in the text Dictate pastes \
                        for you. On by default; turn it off to stop saving these transcript files.
                        """),
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
                SettingsLabel(String(localized: "Transcripts"), systemImage: "doc.text", tint: SettingsTint.privacy)
            }

            Section {
                Toggle("Keep a safety copy of the audio", isOn: $backupRecording)
                    // Turning it off means "stop keeping my audio", not "stop keeping it from
                    // now on" — the recording already on disk goes with the setting, rather
                    // than waiting out a retention window for a feature that's off.
                    .onChange(of: backupRecording) { _, on in
                        guard !on else { return }
                        BackupRecorder.sweep(LearningPaths.recovery, keeping: [])
                        Task { await RecoveryStore.shared.clearDictations() }
                    }

                Text("While you dictate, Dictate also records the audio to a file on this Mac. If recognition comes back with nothing — the microphone was unplugged, the recognizer stalled — it transcribes that file instead, so what you said isn't lost. The recording is deleted the moment your words are inserted, and a recording kept because it couldn't be transcribed lasts only until your next dictation finishes. Queued dictations keep their recovery files until processing finishes. Audio never leaves this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if backupRecording {
                    // Folded away: the default is right for everyone who isn't actively
                    // chasing a flaky microphone, and a longer setting trades disk and
                    // privacy for evidence.
                    DisclosureGroup("Advanced") {
                        Picker(
                            "Keep failed recordings for",
                            selection: $backupRetentionRaw.asEnum(BackupRetention.untilNextDictation)
                        ) {
                            ForEach(BackupRetention.allCases) { retention in
                                Text(retention.displayName).tag(retention)
                            }
                        }

                        Text("Only recordings Dictate couldn't transcribe are affected — one that produced text is always deleted immediately. Anything longer than the default keeps audio of your failed dictations on disk for that long, so raise it while you're tracking down a microphone problem and put it back afterwards.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("Open Recovery Folder") {
                        try? FileManager.default.createDirectory(
                            at: LearningPaths.recoverable, withIntermediateDirectories: true
                        )
                        NSWorkspace.shared.open(LearningPaths.recoverable)
                    }
                }
                Text("Recover Recordings offers local retry, audio export, and deletion. Failed conversation recordings stay until you delete them, separately from dictation retention.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Recover Recordings…") {
                    NotificationCenter.default.post(name: .dictateShowRecovery, object: nil)
                }
            } header: {
                SettingsLabel(String(localized: "Recovery"), systemImage: "arrow.clockwise", tint: SettingsTint.privacy)
            }

            Section {
                Toggle("Keep dictation history", isOn: $dictationHistoryEnabled)

                Text("Every dictation keeps every version the cleanup pipeline produced, so you can recover an earlier one if a cleanup pass rewrote more than you wanted. Turning this off stops new dictations from being recorded — it doesn't erase what's already saved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if dictationHistoryEnabled {
                    Picker("Keep history for", selection: $retentionRaw.asEnum(HistoryRetention.month)) {
                        ForEach(HistoryRetention.allCases) { retention in
                            Text(retention.displayName).tag(retention)
                        }
                    }
                }

                HStack {
                    Button("Show Recent Dictations") { onShowHistory() }
                    Button("Clear History") {
                        DictationHistory.shared.clear()
                        historyCleared = true
                    }
                    if historyCleared {
                        Label("Cleared", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            } header: {
                SettingsLabel(String(localized: "Dictation History"), systemImage: "clock.arrow.circlepath", tint: SettingsTint.history)
            }
        }
        .formStyle(.grouped)
    }
}
#endif
