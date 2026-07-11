//
//  AppDelegate.swift
//  Dictate
//
//  Menu bar presence, permission prompts at launch, and wiring between
//  the hotkey monitor and the dictation controller.
//

#if os(macOS)
import AppKit
import AVFoundation
import VoiceKit

@available(macOS 26.0, *)
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let controller = DictationController()
    private let hotkeyMonitor = HotkeyMonitor()
    private let historyPanel = HistoryPanelController()
    private var settingsController: SettingsWindowController?
    private var onboardingController: OnboardingWindowController?
    private var toggleMenuItem: NSMenuItem!
    private var hintMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()

        if Settings.onboardingComplete {
            promptForPermissionsIfNeeded()
        } else {
            showOnboarding()
        }

        // Global NSEvent monitors installed before Accessibility trust never fire;
        // re-register the moment trust is granted during onboarding.
        NotificationCenter.default.addObserver(
            forName: .dictateAccessibilityGranted, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hotkeyMonitor.start() }
        }

        controller.onListeningChange = { [weak self] listening in
            self?.updateStatusIcon(listening: listening)
            self?.toggleMenuItem.title = listening ? "Stop Dictation" : "Start Dictation"
        }

        hotkeyMonitor.onKeyDown = { [weak self] in self?.controller.hotkeyDown() }
        hotkeyMonitor.onKeyUp = { [weak self] in self?.controller.hotkeyUp() }
        hotkeyMonitor.hotkey = Settings.hotkey
        hotkeyMonitor.start()

        HistoryHotkey.register { [weak self] in self?.historyPanel.toggle() }

        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.hotkeyMonitor.hotkey = Settings.hotkey
                self.hintMenuItem.title = "Hold \(Settings.hotkey.displayName) to dictate"
            }
        }
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusIcon(listening: false)

        let menu = NSMenu()
        hintMenuItem = NSMenuItem(title: "Hold \(Settings.hotkey.displayName) to dictate", action: nil, keyEquivalent: "")
        hintMenuItem.isEnabled = false
        menu.addItem(hintMenuItem)
        menu.addItem(.separator())
        toggleMenuItem = NSMenuItem(title: "Start Dictation", action: #selector(toggleDictation), keyEquivalent: "d")
        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)
        let historyItem = NSMenuItem(title: "Recent Dictations", action: #selector(showHistory), keyEquivalent: "v")
        historyItem.keyEquivalentModifierMask = [.control, .option, .command]
        historyItem.target = self
        menu.addItem(historyItem)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let welcomeItem = NSMenuItem(title: "Welcome Guide…", action: #selector(showWelcomeGuide), keyEquivalent: "")
        welcomeItem.target = self
        menu.addItem(welcomeItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Dictate", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func updateStatusIcon(listening: Bool) {
        let name = listening ? "mic.fill" : "mic"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Dictate")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    @objc private func toggleDictation() {
        controller.toggleManual()
    }

    @objc private func showHistory() {
        historyPanel.toggle()
    }

    /// Post-onboarding launches: quietly prompt for anything still missing.
    private func promptForPermissionsIfNeeded() {
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        Task {
            _ = await SpeechRecognitionService.requestAuthorization()
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
    }

    private func showOnboarding() {
        if onboardingController == nil {
            onboardingController = OnboardingWindowController()
        }
        onboardingController?.show()
    }

    @objc private func showWelcomeGuide() {
        showOnboarding()
    }

    @objc private func showSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController()
        }
        settingsController?.show()
    }
}
#endif
