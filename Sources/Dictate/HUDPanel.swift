//
//  HUDPanel.swift
//  Dictate
//
//  Floating non-activating pill at the bottom of the screen showing
//  mic level and the live transcript while dictating.
//

#if os(macOS)
import AppKit
import SwiftUI

@MainActor
final class HUDController {
    private let model = HUDModel()
    private lazy var panel: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: HUDView(model: model))
        return panel
    }()

    func show() {
        model.text = ""
        model.level = 0
        model.phase = .listening
        model.locked = false
        position()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func update(text: String) {
        model.text = text
    }

    func update(level: Float) {
        model.level = level
    }

    func setLocked(_ locked: Bool) {
        model.locked = locked
    }

    func setProcessing() {
        model.phase = .processing
    }

    func showError(_ message: String) {
        model.phase = .error(message)
        position()
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.hide()
        }
    }

    private func position() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.minY + 80
        ))
    }
}

@MainActor
final class HUDModel: ObservableObject {
    enum Phase: Equatable {
        case listening
        case processing
        case error(String)
    }

    @Published var text = ""
    @Published var level: Float = 0
    @Published var phase: Phase = .listening
    @Published var locked = false
}

struct HUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        HStack(spacing: 10) {
            switch model.phase {
            case .listening:
                LevelIndicator(level: model.level)
                Text(displayText)
                    .lineLimit(1)
                    .truncationMode(.head)
                if model.locked {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                        .imageScale(.small)
                }
            case .processing:
                ProgressView()
                    .controlSize(.small)
                Text("Cleaning up…")
            case .error(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(message)
                    .lineLimit(2)
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule().fill(Color.black.opacity(0.82))
        )
        .frame(maxWidth: 420, maxHeight: 56)
    }

    private var displayText: String {
        let text = model.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Listening…" : String(text.suffix(60))
    }
}

struct LevelIndicator: View {
    let level: Float

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(Color.green)
                    .frame(width: 3, height: barHeight(index))
            }
        }
        .frame(height: 18)
        .animation(.linear(duration: 0.08), value: level)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        // Middle bars respond most, like a voice meter.
        let emphasis: [Float] = [0.5, 0.8, 1.0, 0.8, 0.5]
        let height = 4 + CGFloat(min(1, level) * emphasis[index]) * 14
        return height
    }
}
#endif
