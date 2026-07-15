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
