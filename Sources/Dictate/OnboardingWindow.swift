//
//  OnboardingWindow.swift
//  Dictate
//
//  First-launch onboarding: what Dictate is, granting the three permissions
//  (with live status), freeing up the Fn key, and a practice dictation box.
//

#if os(macOS)
import AppKit
import ApplicationServices
import AVFoundation
import Speech
import SwiftUI

extension Notification.Name {
    /// Posted when Accessibility trust flips on mid-onboarding, so the
    /// global hotkey monitor can re-register without an app relaunch.
    static let dictateAccessibilityGranted = Notification.Name("dictate.accessibilityGranted")
}

@available(macOS 26.0, *)
@MainActor
final class OnboardingWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 540),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        self.init(window: window)
        window.contentViewController = NSHostingController(rootView: OnboardingView { [weak self] in
            UserDefaults.standard.set(true, forKey: Settings.onboardingCompleteKey)
            self?.close()
        })
    }

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Permission state

@available(macOS 26.0, *)
@MainActor
final class PermissionModel: ObservableObject {
    enum Status {
        case granted, denied, notDetermined
    }

    @Published var mic: Status = .notDetermined
    @Published var speech: Status = .notDetermined
    @Published var accessibility = false
    /// com.apple.HIToolbox AppleFnUsageType: 0 nothing, 1 input source, 2 emoji, 3 dictation.
    @Published var fnUsage = 2

    private var timer: Timer?

    var allGranted: Bool { mic == .granted && speech == .granted && accessibility }

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        mic = Self.map(AVCaptureDevice.authorizationStatus(for: .audio))
        speech = Self.map(SFSpeechRecognizer.authorizationStatus())
        let trusted = AXIsProcessTrusted()
        if trusted, !accessibility {
            NotificationCenter.default.post(name: .dictateAccessibilityGranted, object: nil)
        }
        accessibility = trusted
        fnUsage = UserDefaults(suiteName: "com.apple.HIToolbox")?
            .object(forKey: "AppleFnUsageType") as? Int ?? 2
    }

    func requestMic() {
        if mic == .denied {
            Self.openPrivacyPane("Privacy_Microphone")
            return
        }
        Task {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            refresh()
        }
    }

    func requestSpeech() {
        if speech == .denied {
            Self.openPrivacyPane("Privacy_SpeechRecognition")
            return
        }
        Task {
            _ = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
            refresh()
        }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        Self.openPrivacyPane("Privacy_Accessibility")
    }

    static func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func map(_ status: AVAuthorizationStatus) -> Status {
        switch status {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    private static func map(_ status: SFSpeechRecognizerAuthorizationStatus) -> Status {
        switch status {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }
}

// MARK: - Root view

@available(macOS 26.0, *)
struct OnboardingView: View {
    let finish: () -> Void

    @State private var step = 0
    @StateObject private var permissions = PermissionModel()

    private let stepCount = 5

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: WelcomeStep()
                case 1: PermissionsStep(model: permissions)
                case 2: FnKeyStep(model: permissions)
                case 3: LaunchAtLoginStep()
                default: DoneStep()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 44)
            .padding(.top, 36)
            .id(step)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

            footer
        }
        .frame(width: 600, height: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.snappy(duration: 0.3), value: step)
        .onDisappear { permissions.stopPolling() }
    }

    private var footer: some View {
        HStack {
            Button("Back") { step -= 1 }
                .controlSize(.large)
                .opacity(step > 0 ? 1 : 0)
                .disabled(step == 0)

            Spacer()

            HStack(spacing: 7) {
                ForEach(0..<stepCount, id: \.self) { index in
                    Circle()
                        .fill(index == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }

            Spacer()

            Button(primaryTitle) {
                if step == stepCount - 1 {
                    finish()
                } else {
                    step += 1
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(step == 1 && !permissions.allGranted)
        }
        .padding(20)
    }

    private var primaryTitle: String {
        switch step {
        case 0: return String(localized: "Get Started")
        case stepCount - 1: return String(localized: "Start Dictating")
        default: return String(localized: "Continue")
        }
    }
}

// MARK: - Steps

@available(macOS 26.0, *)
private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform")
                .font(.system(size: 56, weight: .medium))
                .foregroundStyle(.tint)
                .symbolEffect(.variableColor.iterative, options: .repeating)
                .padding(.bottom, 6)

            Text("Welcome to Dictate")
                .font(.system(size: 30, weight: .bold))
            Text("Hold a key. Speak. Your words appear — in any app.")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                FeatureRow(symbol: "lock.shield.fill",
                           title: String(localized: "Completely private"),
                           detail: String(localized: "Speech is transcribed on your Mac's Neural Engine. Audio and text never leave this machine."))
                FeatureRow(symbol: "bolt.fill",
                           title: String(localized: "Fast"),
                           detail: String(localized: "Live on-device transcription with no network round-trip — it works on airplane mode."))
                FeatureRow(symbol: "keyboard.fill",
                           title: String(localized: "Works everywhere"),
                           detail: String(localized: "Mail, Slack, your editor — anywhere you can type, you can dictate."))
            }
            .padding(.top, 22)
        }
    }
}

@available(macOS 26.0, *)
private struct FeatureRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

@available(macOS 26.0, *)
private struct PermissionsStep: View {
    @ObservedObject var model: PermissionModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.tint)

            Text("Three quick permissions")
                .font(.system(size: 26, weight: .bold))
            Text("Dictate needs these to hear you and type for you.\nEverything stays on this Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                PermissionRow(
                    symbol: "mic.fill",
                    title: String(localized: "Microphone"),
                    detail: String(localized: "To hear your voice"),
                    granted: model.mic == .granted,
                    buttonTitle: model.mic == .denied ? String(localized: "Open Settings") : String(localized: "Grant"),
                    action: model.requestMic
                )
                PermissionRow(
                    symbol: "waveform.badge.mic",
                    title: String(localized: "Speech Recognition"),
                    detail: String(localized: "To transcribe on-device"),
                    granted: model.speech == .granted,
                    buttonTitle: model.speech == .denied ? String(localized: "Open Settings") : String(localized: "Grant"),
                    action: model.requestSpeech
                )
                PermissionRow(
                    symbol: "accessibility",
                    title: String(localized: "Accessibility"),
                    detail: String(localized: "For the global hotkey, and to type into other apps"),
                    granted: model.accessibility,
                    buttonTitle: String(localized: "Open Settings"),
                    action: model.requestAccessibility
                )
            }
            .padding(.top, 16)

            if model.allGranted {
                Label("All set", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .padding(.top, 6)
            }
        }
    }
}

@available(macOS 26.0, *)
private struct PermissionRow: View {
    let symbol: String
    let title: String
    let detail: String
    let granted: Bool
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Button(buttonTitle, action: action)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(.quinary))
        .animation(.snappy, value: granted)
    }
}

@available(macOS 26.0, *)
private struct FnKeyStep: View {
    @ObservedObject var model: PermissionModel

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.system(size: 15))
                Text("fn")
                    .font(.system(size: 24, weight: .medium, design: .rounded))
            }
            .foregroundStyle(.primary)
            .frame(width: 72, height: 72)
            .background(RoundedRectangle(cornerRadius: 14).fill(.quaternary))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator))

            Text("Free up the Fn key")
                .font(.system(size: 26, weight: .bold))
            Text("Dictate uses **hold Fn** as its push-to-talk key. macOS also assigns the Fn key its own action — set it to **Do Nothing** so the two don't collide.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            statusLabel
                .padding(.top, 10)

            Button("Open Keyboard Settings") {
                PermissionModel.openKeyboardSettings()
            }
            .controlSize(.large)

            Text("In Keyboard settings, set “Press 🌐 key to” → “Do Nothing.”\nPrefer a different key? Pick Right ⌘ later in Dictate’s Settings.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch model.fnUsage {
        case 0:
            Label("The Fn key is free — you're good to go", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case 1:
            Label("Fn currently changes your input source", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case 3:
            Label("Fn currently starts Apple's dictation", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        default:
            Label("Fn currently opens the emoji picker", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}

/// Surfaced during onboarding — not just left as a Settings toggle — because someone who
/// dictates once, restarts their Mac, and finds Dictate silently gone is likely to assume
/// it's broken rather than realize this was never turned on.
@available(macOS 26.0, *)
private struct LaunchAtLoginStep: View {
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "power")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.tint)

            Text("Keep Dictate running")
                .font(.system(size: 26, weight: .bold))
            Text("Dictate waits quietly in the menu bar for your hotkey. Without this, restarting your Mac stops it until you reopen it yourself.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Toggle("Launch Dictate at login", isOn: $launchAtLogin)
                .toggleStyle(.switch)
                .controlSize(.large)
                .onChange(of: launchAtLogin) { _, enabled in
                    launchAtLogin = LaunchAtLogin.setEnabled(enabled)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(.quinary))
                .padding(.top, 10)

            Text("You can change this anytime in Settings.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
    }
}

@available(macOS 26.0, *)
private struct DoneStep: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(.green)

            Text("You're all set")
                .font(.system(size: 28, weight: .bold))
            Label("Dictate lives in your menu bar — look for the microphone icon.", systemImage: "mic")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                FeatureRow(symbol: "hand.tap.fill",
                           title: String(localized: "Quick tap to lock"),
                           detail: String(localized: "Tap the hotkey to keep dictation running hands-free; tap again to stop and insert."))
                FeatureRow(symbol: "sparkles",
                           title: String(localized: "AI cleanup"),
                           detail: String(localized: "Turn on Apple Intelligence polish in Settings to remove false starts and fix punctuation — still fully on-device."))
                FeatureRow(symbol: "gearshape.fill",
                           title: String(localized: "Make it yours"),
                           detail: String(localized: "Change the hotkey, language, or microphone anytime from the menu bar icon → Settings."))
            }
            .padding(.top, 22)
        }
    }
}
#endif
