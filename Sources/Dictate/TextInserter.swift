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

    /// Returns false when Accessibility is denied: the text is on the clipboard but ⌘V was
    /// never delivered, so the caller has to say so rather than let it fail silently.
    @discardableResult
    static func insert(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general

        // A stale TCC grant (same bundle id, different signature) leaves the toggle looking
        // on in System Settings while every posted event is dropped. Leave the transcript on
        // the clipboard, skip the restore, and let the user paste it themselves.
        guard AXIsProcessTrusted() else {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            restoreWork?.cancel()
            restoreWork = nil
            savedClipboard = nil
            return false
        }

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
        return true
    }
}
#endif
