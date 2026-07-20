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
import Carbon.HIToolbox
import VoiceKit

@available(macOS 26.0, *)
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let controller = DictationController()
    private let hotkeyMonitor = HotkeyMonitor()
    private let historyPanel = HistoryPanelController()
    private var settingsController: SettingsWindowController?
    private var onboardingController: OnboardingWindowController?
    private var termsController: TermsWindowController?
    private var toggleMenuItem: NSMenuItem?
    private var hintMenuItem: NSMenuItem?
    private let conversationController = ConversationSessionController()
    private var conversationMenuItem: NSMenuItem?
    private var dictationListening = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Touch it now so "first used" in About reflects the real first launch,
        // not whenever someone happens to open the panel for the first time.
        _ = Settings.firstLaunchDate
        updateStatusItemVisibility()

        // Nothing else runs until the current Terms are accepted. Covers new installs and,
        // via the version check, anyone who accepted an older revision.
        if Settings.termsAccepted {
            beginAfterTerms()
        } else {
            showTerms()
        }

        // Global NSEvent monitors installed before Accessibility trust never fire;
        // re-register the moment trust is granted during onboarding.
        NotificationCenter.default.addObserver(
            forName: .dictateAccessibilityGranted, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hotkeyMonitor.start() }
        }

        controller.onListeningChange = { [weak self] listening in
            self?.dictationListening = listening
            self?.updateStatusIcon(listening: listening)
            self?.toggleMenuItem?.title = listening
                ? String(localized: "Stop Dictation")
                : String(localized: "Start Dictation")
        }

        conversationController.onStateChange = { [weak self] state in
            guard let self else { return }
            self.updateStatusIcon(listening: self.dictationListening)
            guard let item = self.conversationMenuItem else { return }
            switch state {
            case .idle:
                item.title = String(localized: "Record Conversation")
                item.action = #selector(self.toggleConversationRecording)
            case .recording:
                item.title = String(localized: "Stop Recording Conversation")
                item.action = #selector(self.toggleConversationRecording)
            case .transcribing:
                // No action → the item grays out until the transcript is written.
                item.title = String(localized: "Transcribing Conversation…")
                item.action = nil
            }
        }

        hotkeyMonitor.onKeyDown = { [weak self] in self?.controller.hotkeyDown() }
        hotkeyMonitor.onKeyUp = { [weak self] in self?.controller.hotkeyUp() }
        hotkeyMonitor.hotkey = Settings.hotkey
        hotkeyMonitor.start()

        GlobalHotkey.register(keyCode: kVK_ANSI_V, id: GlobalHotkey.history) { [weak self] in
            self?.historyPanel.toggle()
        }
        // The way back in when the menu bar icon is hidden. Registered whether it's hidden or
        // not, so the shortcut is already in muscle memory by the time someone turns it off.
        GlobalHotkey.register(keyCode: kVK_ANSI_Comma, id: GlobalHotkey.settings) { [weak self] in
            self?.showSettings()
        }

        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.hotkeyMonitor.hotkey = Settings.hotkey
                self.hintMenuItem?.title = String(
                    format: String(localized: "Hold %@ to dictate"), Settings.hotkey.displayName
                )
                self.conversationMenuItem?.isHidden = !Settings.conversationRecordingEnabled
                self.updateStatusItemVisibility()
            }
        }
    }

    /// The onboarding/permission flow, gated behind Terms acceptance.
    private func beginAfterTerms() {
        if Settings.onboardingComplete {
            promptForPermissionsIfNeeded()
        } else {
            showOnboarding()
        }
    }

    private func showTerms() {
        termsController = TermsWindowController(readOnly: false) { [weak self] in
            self?.termsController = nil
            self?.beginAfterTerms()
        }
        termsController?.show()
    }

    @objc private func showTermsReadOnly() {
        // If the acceptance gate is still up, don't replace it — just surface it.
        guard Settings.termsAccepted else {
            termsController?.show()
            return
        }
        termsController = TermsWindowController(readOnly: true) {}
        termsController?.show()
    }

    /// The icon is optional: hotkeys keep working without it, and reopening
    /// the app (Finder, Spotlight) brings up Settings to get back in.
    private func updateStatusItemVisibility() {
        if Settings.showMenuBarIcon {
            if statusItem == nil { setUpStatusItem() }
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
            toggleMenuItem = nil
            hintMenuItem = nil
            conversationMenuItem = nil
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !Settings.showMenuBarIcon {
            showSettings()
        }
        return true
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusIcon(listening: false)

        let menu = NSMenu()
        let hint = NSMenuItem(
            title: String(format: String(localized: "Hold %@ to dictate"), Settings.hotkey.displayName),
            action: nil, keyEquivalent: ""
        )
        hint.isEnabled = false
        menu.addItem(hint)
        hintMenuItem = hint
        menu.addItem(.separator())
        let toggle = NSMenuItem(title: String(localized: "Start Dictation"), action: #selector(toggleDictation), keyEquivalent: "d")
        toggle.target = self
        menu.addItem(toggle)
        toggleMenuItem = toggle
        // Only surfaces once conversation recording is enabled in Settings — the menu is
        // byte-identical for everyone else.
        let conversationItem = NSMenuItem(
            title: conversationController.isRecording
                ? String(localized: "Stop Recording Conversation")
                : String(localized: "Record Conversation"),
            action: #selector(toggleConversationRecording), keyEquivalent: ""
        )
        conversationItem.target = self
        conversationItem.isHidden = !Settings.conversationRecordingEnabled
        menu.addItem(conversationItem)
        conversationMenuItem = conversationItem
        let historyItem = NSMenuItem(title: String(localized: "Recent Dictations"), action: #selector(showHistory), keyEquivalent: "v")
        historyItem.keyEquivalentModifierMask = [.control, .option, .command]
        historyItem.target = self
        menu.addItem(historyItem)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: String(localized: "Settings…"), action: #selector(showSettings), keyEquivalent: ",")
        // Advertise the global shortcut, not ⌘, — that's the one that still works once the
        // icon (and this menu) are gone.
        settingsItem.keyEquivalentModifierMask = [.control, .option, .command]
        settingsItem.target = self
        menu.addItem(settingsItem)
        let welcomeItem = NSMenuItem(title: String(localized: "Welcome Guide…"), action: #selector(showWelcomeGuide), keyEquivalent: "")
        welcomeItem.target = self
        menu.addItem(welcomeItem)
        let termsItem = NSMenuItem(title: String(localized: "Terms of Service…"), action: #selector(showTermsReadOnly), keyEquivalent: "")
        termsItem.target = self
        menu.addItem(termsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: String(localized: "Quit Dictate"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    private func updateStatusIcon(listening: Bool) {
        // Dictation's live state wins; a running conversation shows the record glyph.
        let name = listening ? "mic.fill" : (conversationController.isRecording ? "record.circle" : "mic")
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Dictate")
        image?.isTemplate = true
        statusItem?.button?.image = image
    }

    @objc private func toggleDictation() {
        controller.toggleManual()
    }

    @objc private func toggleConversationRecording() {
        conversationController.toggle()
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
            settingsController = SettingsWindowController(
                onWelcome: { [weak self] in
                    self?.settingsController?.close()
                    self?.showOnboarding()
                },
                onShowHistory: { [weak self] in self?.historyPanel.toggle() }
            )
        }
        settingsController?.show()
    }
}
#endif
