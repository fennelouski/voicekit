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
    // Back-to-back dictations can land inside the restore window. Remember the user's
    // clipboard across the whole run and restore it 0.4s after the last paste, so a pending
    // restore can't clobber the next paste and our own text is never "saved" over theirs.
    private static var savedClipboard: String?
    private static var restoreWork: DispatchWorkItem?

    static func insert(_ text: String) {
        let pasteboard = NSPasteboard.general

        if let pending = restoreWork {
            pending.cancel() // mid-run: keep the original saved clipboard
        } else {
            // ponytail: restores plain-text clipboard only; full multi-type restore if it ever matters
            savedClipboard = pasteboard.string(forType: .string)
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let source = CGEventSource(stateID: .combinedSessionState)
        let keyVDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true) // kVK_ANSI_V
        let keyVUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyVDown?.flags = .maskCommand
        keyVUp?.flags = .maskCommand
        keyVDown?.post(tap: .cghidEventTap)
        keyVUp?.post(tap: .cghidEventTap)

        let work = DispatchWorkItem {
            pasteboard.clearContents()
            if let saved = savedClipboard {
                pasteboard.setString(saved, forType: .string)
            }
            savedClipboard = nil
            restoreWork = nil
        }
        restoreWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}
#endif
