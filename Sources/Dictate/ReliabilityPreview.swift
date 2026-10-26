#if os(macOS) && DEBUG
import AppKit
import SwiftUI
import VoiceKit

/// Isolated fixtures for inspecting reliability UI. Runs before single-instance
/// replacement and never installs hotkeys, starts capture, or touches app data.
@available(macOS 26.0, *)
@MainActor
enum ReliabilityPreview {
    static func run() {
        let app = NSApplication.shared
        let delegate = PreviewDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Dictate-UI-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let observer = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            try? FileManager.default.removeItem(at: directory)
        }
        let window: NSWindowController
        if CommandLine.arguments.contains("--preview-cleanup") {
            let suiteName = "Dictate-Cleanup-Preview-\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            defaults.set(false, forKey: Settings.aiPolishingEnabledKey)
            let host = NSHostingController(rootView: CleanupPane().defaultAppStorage(defaults))
            let viewWindow = NSWindow(contentViewController: host)
            viewWindow.title = "Cleanup — isolated preview"
            viewWindow.setContentSize(NSSize(width: 680, height: 640))
            viewWindow.styleMask = [.titled, .closable, .resizable]
            viewWindow.center()
            window = NSWindowController(window: viewWindow)
            window.showWindow(nil)
            NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
                UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
            }
        } else if CommandLine.arguments.contains("--preview-vocabulary") {
            let store = VocabularyStore(fileURL: directory.appendingPathComponent("vocabulary.json"))
            try? store.setTerms(["OpenWhispr", "VoiceKit", "Kubernetes"])
            let host = NSHostingController(rootView: Form { VocabularySection(store: store) }.formStyle(.grouped))
            let viewWindow = NSWindow(contentViewController: host)
            viewWindow.title = "Vocabulary — isolated preview"
            viewWindow.setContentSize(NSSize(width: 640, height: 480))
            viewWindow.styleMask = [.titled, .closable, .resizable]
            viewWindow.center()
            window = NSWindowController(window: viewWindow)
            window.showWindow(nil)
        } else {
            let store = RecoveryStore(directory: directory.appendingPathComponent("recovery"))
            let model = RecoveryModel(store: store, conversationScratch: nil) { _, _ in
                try await Task.sleep(for: .seconds(2))
                return "This is synthetic preview text. Recovery stays local and waits for you to copy or export it."
            }
            let recovery = RecoveryWindowController(model: model)
            window = recovery
            Task {
                for source in ["Interrupted dictation (fixture)", "Meeting microphone (fixture)"] {
                    let audio = directory.appendingPathComponent(UUID().uuidString + ".caf")
                    try? Data("synthetic fixture".utf8).write(to: audio)
                    _ = try? await store.register(audio: audio, source: source, locale: nil, kind: .conversation)
                }
                recovery.show()
            }
        }
        app.activate(ignoringOtherApps: true)
        withExtendedLifetime((window, delegate, observer)) { app.run() }
    }
}

@MainActor
private final class PreviewDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
#endif
