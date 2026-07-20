//
//  AboutPanel.swift
//  Dictate
//
//  Opened from the version label at the foot of the Settings sidebar. Usage
//  numbers and debug info pulled straight from the stores that already track
//  them (DictationHistory, CorrectionStore, Settings) — nothing new is
//  measured just for this panel, so there's nothing extra to keep on disk.
//

#if os(macOS)
import ApplicationServices
import AVFoundation
import AppKit
import Speech
import SwiftUI
import VoiceKit

@available(macOS 26.0, *)
struct AboutPanel: View {
    @State private var copied = false

    private var micGranted: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }
    private var speechGranted: Bool { SFSpeechRecognizer.authorizationStatus() == .authorized }
    private var accessibilityGranted: Bool { AXIsProcessTrusted() }

    private var correctionHistory: [CorrectionStore.HistoryEntry] { CorrectionStore.shared.history() }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                    .resizable()
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dictate").font(.system(size: 16, weight: .semibold))
                    Text(String(format: String(localized: "Version %@ (%@)"), AppInfo.version, AppInfo.build))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Link(destination: URL(string: "https://nathanfennel.com/dictate")!) {
                Label("About Dictate on nathanfennel.com", systemImage: "arrow.up.forward.square")
                    .font(.caption)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                SettingsLabel(String(localized: "Usage"), systemImage: "chart.bar", tint: SettingsTint.history)
                infoRow(String(localized: "First used"), Settings.firstLaunchDate, style: .date)
                infoRow(String(localized: "Total dictations"), "\(Settings.totalDictations)")
                infoRow(String(localized: "Kept in history"), "\(DictationHistory.shared.recent().count)")
                infoRow(String(localized: "Corrections learned"), "\(correctionHistory.count)")
                infoRow(String(localized: "Auto-applying now"), "\(correctionHistory.filter(\.isActive).count)")
                infoRow(String(localized: "Conversation sources"), "\(Settings.conversationSources.count)")
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                SettingsLabel(String(localized: "Debug"), systemImage: "ladybug", tint: SettingsTint.system)
                infoRow(String(localized: "macOS"), ProcessInfo.processInfo.operatingSystemVersionString)
                infoRow(String(localized: "Language"), Settings.locale?.identifier ?? String(localized: "System default"))
                infoRow(String(localized: "Hotkey"), Settings.hotkey.displayName)
                infoRow(String(localized: "Launch at login"), LaunchAtLogin.isEnabled ? String(localized: "On") : String(localized: "Off"))
                permissionRow(String(localized: "Microphone"), granted: micGranted)
                permissionRow(String(localized: "Speech Recognition"), granted: speechGranted)
                permissionRow(String(localized: "Accessibility"), granted: accessibilityGranted)
            }

            HStack {
                Button("Copy Diagnostic Info") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(diagnosticText, forType: .string)
                    copied = true
                }
                if copied {
                    Label("Copied", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
                Spacer()
                Button("Open App Support Folder") {
                    try? FileManager.default.createDirectory(at: LearningPaths.directory, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(LearningPaths.directory)
                }
            }
            .font(.caption)
        }
        .padding(18)
        .frame(width: 360)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
        }
        .font(.caption)
    }

    private func infoRow(_ label: String, _ date: Date, style: Text.DateStyle) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(date, style: style)
        }
        .font(.caption)
    }

    private func permissionRow(_ label: String, granted: Bool) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Label(
                granted ? String(localized: "Granted") : String(localized: "Not granted"),
                systemImage: granted ? "checkmark.circle.fill" : "xmark.circle"
            )
            .foregroundStyle(granted ? .green : .secondary)
        }
        .font(.caption)
    }

    private var diagnosticText: String {
        """
        Dictate \(AppInfo.version) (\(AppInfo.build))
        macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        Language: \(Settings.locale?.identifier ?? "System default")
        Hotkey: \(Settings.hotkey.displayName)
        Launch at login: \(LaunchAtLogin.isEnabled ? "On" : "Off")
        Microphone: \(micGranted ? "Granted" : "Not granted")
        Speech Recognition: \(speechGranted ? "Granted" : "Not granted")
        Accessibility: \(accessibilityGranted ? "Granted" : "Not granted")
        First used: \(Settings.firstLaunchDate.formatted(date: .abbreviated, time: .omitted))
        Total dictations: \(Settings.totalDictations)
        Kept in history: \(DictationHistory.shared.recent().count)
        Corrections learned: \(correctionHistory.count) (\(correctionHistory.filter(\.isActive).count) auto-applying)
        Conversation sources: \(Settings.conversationSources.count)
        """
    }
}
#endif
