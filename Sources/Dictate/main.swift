//
//  main.swift
//  Dictate
//
//  Entry point. Menu bar app; requires macOS 26 for on-device SpeechTranscriber.
//

#if os(macOS)
import AppKit

if #available(macOS 26.0, *) {
    MainActor.assumeIsolated {
        // A Sparkle relaunch (or a stray build) can leave an older copy running. Both answer
        // the same hotkey, both write the transcript to the pasteboard, and the loser clobbers
        // the winner's clipboard mid-paste — so ⌘V lands on the wrong text or nothing at all.
        // Newest instance wins: it is the one that just got installed.
        let others = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
        ).filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        for other in others { other.terminate() }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run() // never returns; keeps `delegate` alive
    }
} else {
    let alert = NSAlert()
    alert.messageText = String(localized: "Dictate requires macOS 26")
    alert.informativeText = String(localized: "On-device speech recognition (SpeechTranscriber) is only available on macOS 26 or later.")
    alert.runModal()
    exit(1)
}
#endif
