//
//  HistoryPanel.swift
//  Dictate
//
//  ⌃⌥⌘V pops up the last hour of dictations; click one to copy it to the
//  clipboard, Esc (or clicking elsewhere) dismisses. History is in-memory
//  only — never written to disk, cleared when the app quits.
//

#if os(macOS)
import AppKit
import Carbon.HIToolbox
import SwiftUI

/// In-memory record of recently inserted dictations.
@MainActor
final class DictationHistory {
    static let shared = DictationHistory()

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let text: String
    }

    /// How long an entry stays retrievable.
    static let window: TimeInterval = 3600
    // ponytail: hard cap so an all-day session can't grow unbounded
    private let cap = 50

    private var entries: [Entry] = []

    func add(_ text: String, at date: Date = Date()) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        entries.append(Entry(date: date, text: trimmed))
        prune(now: date)
    }

    /// Entries from the last hour, newest first.
    func recent(now: Date = Date()) -> [Entry] {
        prune(now: now)
        return entries.reversed()
    }

    private func prune(now: Date) {
        entries.removeAll { now.timeIntervalSince($0.date) > Self.window }
        if entries.count > cap {
            entries.removeFirst(entries.count - cap)
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
        let view = HistoryView(entries: DictationHistory.shared.recent()) { [weak self] text in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            self?.close()
        }
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
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent dictations — click to copy")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            Divider()
            if entries.isEmpty {
                Text("Nothing dictated in the last hour.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if entries.count > 8 {
                ScrollView {
                    rows
                }
                .frame(height: 360)
            } else {
                rows
            }
        }
        .frame(width: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(entries) { entry in
                HistoryRow(entry: entry) { onSelect(entry.text) }
            }
        }
    }
}

private struct HistoryRow: View {
    let entry: DictationHistory.Entry
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top) {
                Text(entry.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer()
                Text(entry.date, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(hovered ? Color.primary.opacity(0.08) : .clear)
        .onHover { hovered = $0 }
    }
}
#endif
