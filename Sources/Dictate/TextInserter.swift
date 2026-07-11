//
//  TextInserter.swift
//  Dictate
//
//  Inserts text into the frontmost app by pasting: stash the clipboard,
//  set the transcript, synthesize ⌘V, restore the clipboard shortly after.
//

#if os(macOS)
import AppKit

@MainActor
enum TextInserter {
    static func insert(_ text: String) {
        let pasteboard = NSPasteboard.general
        // ponytail: restores plain-text clipboard only; full multi-type restore if it ever matters
        let saved = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let source = CGEventSource(stateID: .combinedSessionState)
        let keyVDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true) // kVK_ANSI_V
        let keyVUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyVDown?.flags = .maskCommand
        keyVUp?.flags = .maskCommand
        keyVDown?.post(tap: .cghidEventTap)
        keyVUp?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            pasteboard.clearContents()
            if let saved {
                pasteboard.setString(saved, forType: .string)
            }
        }
    }
}
#endif
