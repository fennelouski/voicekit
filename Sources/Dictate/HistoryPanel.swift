//
//  HistoryPanel.swift
//  Dictate
//
//  ⌃⌥⌘V pops up recent dictations. Each one keeps every version the cleanup
//  pipeline produced — raw transcript, filler removed, learned corrections, and
//  the AI polish (plus which providers failed) — so you can expand a dictation,
//  see how hard the AI edited (percent changed), and copy any earlier version if
//  a cleanup pass rewrote more than you wanted. Persisted to disk so it survives
//  a relaunch; clear it any time from the panel.
//

#if os(macOS)
import AppKit
import Carbon.HIToolbox
import SwiftUI
import VoiceKit

/// On-disk record of recent dictations and the cleanup stages behind each.
@MainActor
final class DictationHistory {
    static let shared = DictationHistory(fileURL: LearningPaths.history)

    enum StageStatus: String, Codable { case applied, failed }

    /// One rung of the cleanup ladder for a dictation.
    struct Stage: Codable, Identifiable {
        var id = UUID()
        let label: String
        let systemImage: String
        let text: String
        let status: StageStatus
        /// Percent of words changed from the previous applied stage. Nil for the raw
        /// transcript (nothing precedes it) and for failed provider attempts (no output).
        let changePercent: Int?

        private enum CodingKeys: String, CodingKey { case label, systemImage, text, status, changePercent }
    }

    struct Entry: Codable, Identifiable {
        var id = UUID()
        let date: Date
        let stages: [Stage]

        /// What actually got inserted: the last stage that produced text.
        var finalStage: Stage? { stages.last { $0.status == .applied } }
        var text: String { finalStage?.text ?? "" }

        /// Overall change from the raw transcript to what was inserted.
        var overallChange: Int? {
            guard let raw = stages.first?.text, !raw.isEmpty else { return nil }
            return TextDistance.changePercent(from: raw, to: text)
        }

        private enum CodingKeys: String, CodingKey { case date, stages }
    }

    private let fileURL: URL
    // ponytail: hard count cap so history can't grow unbounded on disk
    private let cap = 100
    private(set) var entries: [Entry] = []

    init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = decoded
        }
        prune()
    }

    func add(_ entry: Entry) {
        guard Settings.dictationHistoryEnabled else { return }
        guard !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        entries.append(entry)
        prune()
        save()
    }

    /// Newest first. Prunes first so a shortened retention setting takes effect
    /// immediately, not just after the next dictation.
    func recent() -> [Entry] {
        prune()
        return entries.reversed()
    }

    func clear() {
        entries = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Drops entries older than the configured retention window, then enforces the
    /// hard cap — which still applies even at "Forever", so history can't grow unbounded.
    private func prune() {
        if let days = Settings.dictationHistoryRetention.days {
            let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
            entries.removeAll { $0.date < cutoff }
        }
        if entries.count > cap { entries.removeFirst(entries.count - cap) }
    }

    private func save() {
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

@MainActor
final class HistoryPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?

    func toggle() {
        if panel != nil { close() } else { show() }
    }

    func show() {
        let view = HistoryView(
            entries: DictationHistory.shared.recent(),
            onCopy: { [weak self] text in
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                self?.close()
            },
            onClear: { [weak self] in
                DictationHistory.shared.clear()
                self?.close()
            }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame.size = hosting.fittingSize

        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: hosting.frame.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.close() }

        // Spotlight-ish: centered, upper third of the screen.
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - panel.frame.width / 2,
                y: frame.minY + frame.height * 0.66 - panel.frame.height / 2
            ))
        }
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func close() {
        guard let panel else { return }
        self.panel = nil
        panel.delegate = nil
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }
}

/// Borderless panels can't become key by default; this one must, so it can
/// receive Esc and clicks without activating the app.
private final class KeyablePanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

struct HistoryView: View {
    let entries: [DictationHistory.Entry]
    let onCopy: (String) -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recent dictations — expand one to copy any cleanup stage")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if !entries.isEmpty {
                    Button("Clear") { onClear() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            if entries.isEmpty {
                Text("Nothing dictated recently.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(entries) { entry in
                            HistoryRow(entry: entry, onCopy: onCopy)
                            Divider()
                        }
                    }
                }
                .frame(height: 380)
            }
        }
        .frame(width: 460)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct HistoryRow: View {
    let entry: DictationHistory.Entry
    let onCopy: (String) -> Void
    @State private var expanded = false
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                // Only meaningful when there's more than the raw transcript to show.
                Button { expanded.toggle() } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                        .padding(.top, 3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(entry.stages.count < 2)
                .opacity(entry.stages.count < 2 ? 0.25 : 1)

                Button { onCopy(entry.text) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.text)
                            .lineLimit(expanded ? nil : 2)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            if let final = entry.finalStage {
                                Label(final.label, systemImage: final.systemImage)
                                    .labelStyle(.titleAndIcon)
                            }
                            if let pct = entry.overallChange, pct > 0 {
                                Text(String(format: String(localized: "· %d%% changed"), pct))
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text(entry.date, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(hovered ? Color.primary.opacity(0.06) : .clear)
            .onHover { hovered = $0 }

            if expanded {
                VStack(spacing: 0) {
                    ForEach(entry.stages) { stage in
                        StageRow(stage: stage, onCopy: onCopy)
                    }
                }
                .padding(.leading, 22)
                .padding(.bottom, 6)
            }
        }
    }
}

private struct StageRow: View {
    let stage: DictationHistory.Stage
    let onCopy: (String) -> Void
    @State private var copied = false

    private var copyable: Bool { stage.status == .applied && !stage.text.isEmpty }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: stage.systemImage)
                .font(.caption)
                .frame(width: 16)
                .foregroundStyle(stage.status == .failed ? Color.orange : Color.secondary)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(stage.label)
                        .font(.caption)
                        .fontWeight(.medium)
                    if stage.status == .failed {
                        Text("failed")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else if let pct = stage.changePercent {
                        Text(pct == 0
                             ? String(localized: "no change")
                             : String(format: String(localized: "%d%% changed"), pct))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                if copyable {
                    Text(stage.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
            }

            Spacer(minLength: 8)

            if copyable {
                Button {
                    onCopy(stage.text)
                    copied = true
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy this version")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
    }
}
#endif
