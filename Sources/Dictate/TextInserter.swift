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
    private static let clipboard = ClipboardTransaction(pasteboard: .general)
    private static var restoreWork: DispatchWorkItem?
    private static var lastPaste: ContinuousClock.Instant?

    /// Keep a queued paste from replacing clipboard text before the preceding
    /// event has had the same settling interval as clipboard restoration. This
    /// is bounded compatibility time, not an editor delivery acknowledgement.
    static func waitForPreviousPaste() async throws {
        guard let lastPaste else { return }
        let ready = lastPaste + .milliseconds(400)
        if ContinuousClock.now < ready { try await Task.sleep(until: ready, clock: .continuous) }
    }

    static func insert(_ text: String, into destination: InsertionDestination?) -> InsertionResult {
        InsertionGate.insert(text, into: destination, copy: copyForManualPaste, paste: paste)
    }

    private static func copyForManualPaste(_ text: String) {
        restoreWork?.cancel()
        restoreWork = nil
        clipboard.discard()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// True means events were posted, not that the destination acknowledged them.
    private static func paste(_ text: String, processID: pid_t) -> Bool {
        // A stale TCC grant (same bundle id, different signature) leaves the toggle looking
        // on in System Settings while every posted event is dropped. Leave the transcript on
        // the clipboard, skip the restore, and let the user paste it themselves.
        let source = CGEventSource(stateID: .combinedSessionState)
        guard AXIsProcessTrusted(),
              let keyVDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyVUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            return false
        }

        restoreWork?.cancel()
        restoreWork = nil
        guard clipboard.write(text) else { return false }

        keyVDown.flags = .maskCommand
        keyVUp.flags = .maskCommand
        // Address the captured process, so a focus change while WindowServer
        // dispatches the event cannot redirect it to another application.
        keyVDown.postToPid(processID)
        keyVUp.postToPid(processID)
        lastPaste = ContinuousClock.now

        let work = DispatchWorkItem {
            clipboard.restore()
            restoreWork = nil
        }
        restoreWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        return true
    }
}
#endif
