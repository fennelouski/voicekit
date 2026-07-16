//
//  CorrectionObserver.swift
//  Dictate
//
//  The closed learning loop: right after inserting, snapshot the focused
//  text field via Accessibility; when the next dictation starts (or 60s
//  passes), re-read it, diff, learn the user's corrections, and append a
//  compact JSONL line to the on-device learning log.
//

#if os(macOS)
import AppKit
import ApplicationServices
import VoiceKit

/// On-device file locations for the learning loop.
enum LearningPaths {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dictate", isDirectory: true)
    }

    static var corrections: URL { directory.appendingPathComponent("corrections.json") }
    static var log: URL { directory.appendingPathComponent("learning-log.jsonl") }
    static var transcripts: URL { directory.appendingPathComponent("Transcripts", isDirectory: true) }
    static var history: URL { directory.appendingPathComponent("history.json") }
}

extension CorrectionStore {
    @MainActor static let shared = CorrectionStore(fileURL: LearningPaths.corrections)
}

@MainActor
final class CorrectionObserver {
    private struct Pending {
        let element: AXUIElement
        let inserted: String
        let before: String
        let rawLength: Int
        let mode: String
        let app: String?
    }

    private var store: CorrectionStore { .shared }
    private var pending: Pending?
    private var harvestTimer: Timer?

    /// Call right after inserting `text` into the frontmost app.
    func beginObserving(inserted: String, rawLength: Int) {
        guard Settings.learningEnabled, !inserted.isEmpty else { return }
        harvest()
        let mode = Settings.cleanupMode.rawValue
        let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        Task { [weak self] in
            // Let the paste land before snapshotting.
            try? await Task.sleep(nanoseconds: 500_000_000)
            self?.snapshot(inserted: inserted, rawLength: rawLength, mode: mode, app: app)
        }
    }

    /// Diff the field against its post-insert snapshot, learn, and log.
    /// Called by a 60s timer or at the start of the next dictation.
    func harvest() {
        harvestTimer?.invalidate()
        harvestTimer = nil
        guard let pending else { return }
        self.pending = nil
        let after = Self.textValue(of: pending.element) ?? pending.before
        let fixes = CorrectionExtractor.extract(inserted: pending.inserted, before: pending.before, after: after)
        if !fixes.isEmpty {
            store.record(fixes)
        }
        appendLog(app: pending.app, mode: pending.mode, rawLength: pending.rawLength,
                  insertedLength: pending.inserted.count, fixes: fixes)
    }

    private func snapshot(inserted: String, rawLength: Int, mode: String, app: String?) {
        guard let element = Self.focusedElement(),
              let value = Self.textValue(of: element),
              value.contains(inserted) else {
            // Field unreadable or the paste landed elsewhere: log the dictation, learn nothing.
            appendLog(app: app, mode: mode, rawLength: rawLength, insertedLength: inserted.count, fixes: [])
            return
        }
        pending = Pending(element: element, inserted: inserted, before: value,
                          rawLength: rawLength, mode: mode, app: app)
        harvestTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.harvest() }
        }
    }

    // MARK: - Accessibility

    private static func focusedElement() -> AXUIElement? {
        var focused: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &focused
        )
        guard result == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        return (focused as! AXUIElement)
    }

    private static func textValue(of element: AXUIElement) -> String? {
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        // Never read password fields.
        if let role = roleRef as? String, role == "AXSecureTextField" { return nil }

        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let value = valueRef as? String,
              value.count <= 100_000 else { return nil }
        return value
    }

    // MARK: - Learning log

    private struct LogLine: Encodable {
        let t: String
        let app: String?
        let mode: String
        let raw: Int
        let ins: Int
        let fix: [[String]]?
    }

    private func appendLog(app: String?, mode: String, rawLength: Int, insertedLength: Int, fixes: [Correction]) {
        let line = LogLine(
            t: ISO8601DateFormatter().string(from: Date()),
            app: app,
            mode: mode,
            raw: rawLength,
            ins: insertedLength,
            fix: fixes.isEmpty ? nil : fixes.map { [$0.heard, $0.corrected] }
        )
        guard var data = try? JSONEncoder().encode(line) else { return }
        data.append(0x0A)

        // ponytail: append-only, no rotation — ~150 B/line is years of use before size matters
        try? FileManager.default.createDirectory(at: LearningPaths.directory, withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: LearningPaths.log) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: LearningPaths.log)
        }
    }
}
#endif
