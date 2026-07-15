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
import VoiceKit

/// Everything about how the pill looks and moves. Read from defaults when a dictation
/// starts, so a mid-session settings change can't restyle the HUD out from under you.
struct HUDAppearance: Equatable {
    var style: HUDStyle = .bars
    var textSize: HUDTextSize = .medium
    var position: HUDPosition = .bottomCenter
    var transition: HUDSpeed = .normal
    var reveal: HUDSpeed = .fast

    static var current: HUDAppearance {
        HUDAppearance(
            style: Settings.hudStyle,
            textSize: Settings.hudTextSize,
            position: Settings.hudPosition,
            transition: Settings.hudTransitionSpeed,
            reveal: Settings.hudRevealSpeed
        )
    }

    /// Capped so a long transcript can't span the whole screen.
    var pillMaxWidth: CGFloat { 420 }

    /// Text plus its vertical padding. Big type needs a taller pill — and a taller panel.
    var pillHeight: CGFloat { textSize.points * 1.7 + 20 }

    /// The panel is bigger than the pill on every side so the halo and orb glows have room
    /// to bloom instead of being clipped at the panel's edge.
    static let bloom: CGFloat = 10
    var panelSize: NSSize {
        NSSize(width: pillMaxWidth + Self.bloom * 2, height: pillHeight + Self.bloom * 2)
    }

    /// Inside the panel, which is only a bloom's width bigger than the pill: the horizontal
    /// edge is all that matters, because the pill hugs it and grows inward toward the centre
    /// of the screen. Vertically the panel hugs the pill and the *panel* is what moves.
    var pillAlignment: Alignment {
        switch position.column {
        case 0: return .leading
        case 2: return .trailing
        default: return .center
        }
    }

    /// Against a whole screen — or a preview standing in for one — the pill has to move in
    /// both axes, since there's no panel doing the vertical work.
    var screenAlignment: Alignment {
        let horizontal: HorizontalAlignment = switch position.column {
        case 0: .leading
        case 2: .trailing
        default: .center
        }
        let vertical: VerticalAlignment = switch position.row {
        case 0: .top
        case 2: .bottom
        default: .center
        }
        return Alignment(horizontal: horizontal, vertical: vertical)
    }
}

@MainActor
final class HUDController {
    private let model = HUDModel()
    private lazy var panel: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: HUDAppearance.current.panelSize),
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
        model.appearance = .current
        panel.setContentSize(model.appearance.panelSize)
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
        panel.setFrameOrigin(Self.origin(
            for: model.appearance.position,
            in: screen.visibleFrame,
            panel: panel.frame.size
        ))
    }

    /// Pure so it can be tested without a screen: given an anchor and the usable screen
    /// area, where does the panel's bottom-left corner go? Cocoa's y grows upward.
    nonisolated static func origin(for position: HUDPosition, in screen: NSRect, panel size: NSSize) -> NSPoint {
        // Generous at the bottom, where the Dock lives even though visibleFrame excludes it,
        // and tighter at the top so the pill doesn't crowd the menu bar.
        let sideMargin: CGFloat = 40
        let bottomMargin: CGFloat = 80
        let topMargin: CGFloat = 40

        let x: CGFloat
        switch position.column {
        case 0: x = screen.minX + sideMargin
        case 2: x = screen.maxX - size.width - sideMargin
        default: x = screen.midX - size.width / 2
        }

        let y: CGFloat
        switch position.row {
        case 0: y = screen.maxY - size.height - topMargin
        case 1: y = screen.midY - size.height / 2
        default: y = screen.minY + bottomMargin
        }

        return NSPoint(x: x, y: y)
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
    @Published var appearance = HUDAppearance.current
}

struct HUDView: View {
    @ObservedObject var model: HUDModel
    /// Where the pill sits in whatever space it's handed. The real panel hugs the pill and
    /// moves itself, so it only needs the horizontal edge; a preview stands in for a whole
    /// screen, so it passes the full 2D anchor.
    var alignment: Alignment?

    private var look: HUDAppearance { model.appearance }

    private var anchor: Alignment { alignment ?? look.pillAlignment }

    var body: some View {
        phaseContent
            .font(.system(size: look.textSize.points, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(pill)
            // Both frames need the anchor. The cap alone would centre a short pill inside its
            // own 420pt box, leaving it floating off the edge it's supposed to be hugging.
            .frame(maxWidth: look.pillMaxWidth, alignment: anchor)
            .padding(HUDAppearance.bloom)
            // Anchored to its edge, growing toward the centre of the screen.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: anchor)
            .animation(transition, value: look.position)
            .animation(transition, value: model.phase)
            .animation(transition, value: model.locked)
    }

    /// Nil rather than a near-zero duration: `.instant` means genuinely no animation.
    private var transition: Animation? {
        look.transition.seconds == 0 ? nil : .smooth(duration: look.transition.seconds)
    }

    private var reveal: Animation? {
        look.reveal.seconds == 0 ? nil : .easeOut(duration: look.reveal.seconds)
    }

    /// Each phase is its own view, so swapping them crossfades instead of flashing.
    @ViewBuilder
    private var phaseContent: some View {
        switch model.phase {
        case .listening:
            listening.transition(.blurReplace)
        case .processing:
            processing.transition(.blurReplace)
        case .error(let message):
            errorRow(message).transition(.blurReplace)
        }
    }

    private var listening: some View {
        HStack(spacing: 10) {
            indicator
            Text(displayText)
                .lineLimit(1)
                .truncationMode(.head)
                .contentTransition(.interpolate)
                .animation(reveal, value: displayText)
            if model.locked {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
            }
        }
    }

    private var processing: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Cleaning up…")
        }
    }

    private func errorRow(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var indicator: some View {
        switch look.style {
        case .bars:
            LevelIndicator(level: model.level)
        case .orb:
            VoiceOrb(level: model.level)
        case .wave:
            Waveform(level: model.level)
        case .ripple:
            SonarRipple(level: model.level)
        case .halo:
            // The pill itself is the indicator; the slot stays empty
            // and the transcript takes the room.
            EmptyView()
        }
    }

    @ViewBuilder
    private var pill: some View {
        if look.style == .halo, model.phase == .listening {
            BreathingHalo(level: model.level)
        } else {
            Capsule().fill(Color.black.opacity(0.82))
        }
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
        let height = 4 + CGFloat(clampedLevel(level) * emphasis[index]) * 14
        return height
    }
}

/// A sine wave scrolling right to left, its amplitude tracking your voice.
/// Unlike the bars and the orb, this one shows the shape of the last second
/// of speech rather than only the current instant.
struct Waveform: View {
    let level: Float

    static let slotWidth: CGFloat = 34
    static let slotHeight: CGFloat = 18

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack {
                // Two waves at different wavelengths so the crests drift in and
                // out of phase; scroll speed stays constant, only amplitude moves.
                wave(time: time, speed: 2.2, wavelength: 26, opacity: 1)
                wave(time: time, speed: 1.5, wavelength: 17, opacity: 0.45)
            }
        }
        .frame(width: Self.slotWidth, height: Self.slotHeight)
        .animation(.easeOut(duration: 0.12), value: level)
    }

    private func wave(time: Double, speed: Double, wavelength: Double, opacity: Double) -> some View {
        let amplitude = Self.amplitude(level)
        return Path { path in
            let midY = Self.slotHeight / 2
            for x in stride(from: 0.0, through: Double(Self.slotWidth), by: 1) {
                // Taper the ends so the wave meets the midline at both edges
                // instead of being chopped off mid-crest.
                let taper = sin(x / Double(Self.slotWidth) * .pi)
                let offset = sin(x / wavelength * 2 * .pi - time * speed) * taper
                let point = CGPoint(x: x, y: Double(midY) + offset * Double(amplitude))
                if x == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
        }
        .stroke(
            Color(hue: Self.hue(level), saturation: 0.8, brightness: 1).opacity(opacity),
            style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
        )
    }

    /// Doubled (crest to trough) this must stay inside `slotHeight`.
    static func amplitude(_ level: Float) -> CGFloat {
        1 + CGFloat(clampedLevel(level)) * 7
    }

    /// Cyan when quiet, violet when loud.
    static func hue(_ level: Float) -> Double {
        0.52 + Double(clampedLevel(level)) * 0.3
    }
}

/// A core dot with rings pushing outward and fading. Rings spawn at a constant
/// rate — only how far they reach, and how brightly, follows your voice.
struct SonarRipple: View {
    let level: Float

    private static let size: CGFloat = 22
    private static let ringCount = 3

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<Self.ringCount, id: \.self) { index in
                    let phase = (time * 0.8 + Double(index) / Double(Self.ringCount))
                        .truncatingRemainder(dividingBy: 1)
                    Circle()
                        .strokeBorder(Self.tint(level), lineWidth: 1.4)
                        .frame(width: Self.size, height: Self.size)
                        .scaleEffect(Self.ringScale(level, phase: phase))
                        .opacity(Self.ringOpacity(level, phase: phase))
                }
                Circle()
                    .fill(Self.tint(level))
                    .frame(width: 6, height: 6)
                    .scaleEffect(Self.coreScale(level))
                    .shadow(color: Self.tint(level).opacity(0.8), radius: 3)
            }
            .frame(width: Self.size, height: Self.size)
        }
        .frame(width: Self.size, height: Self.size)
        .animation(.easeOut(duration: 0.12), value: level)
    }

    /// `phase` runs 0→1 as a ring travels out; volume sets how far it gets.
    static func ringScale(_ level: Float, phase: Double) -> CGFloat {
        let reach = 0.35 + CGFloat(clampedLevel(level)) * 0.65
        return 0.25 + CGFloat(phase) * reach
    }

    static func ringOpacity(_ level: Float, phase: Double) -> Double {
        (1 - phase) * (0.25 + Double(clampedLevel(level)) * 0.7)
    }

    static func coreScale(_ level: Float) -> CGFloat {
        0.8 + CGFloat(clampedLevel(level)) * 0.9
    }

    static func tint(_ level: Float) -> Color {
        Color(hue: 0.55 + Double(clampedLevel(level)) * 0.2, saturation: 0.75, brightness: 1)
    }
}

/// No indicator at all: the pill itself is the meter. It breathes slowly on its
/// own so it stays alive in silence, and your voice rides on top of that.
struct BreathingHalo: View {
    let level: Float

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let breath = (sin(time * 1.6) + 1) / 2
            Capsule()
                .fill(Color.black.opacity(0.82))
                .overlay(
                    Capsule().strokeBorder(
                        Self.tint(level),
                        lineWidth: Self.lineWidth(level, breath: breath)
                    )
                )
                .shadow(
                    color: Self.tint(level).opacity(0.55),
                    radius: Self.glowRadius(level, breath: breath)
                )
        }
        .animation(.easeOut(duration: 0.12), value: level)
    }

    static func lineWidth(_ level: Float, breath: Double) -> CGFloat {
        0.8 + CGFloat(breath) * 0.5 + CGFloat(clampedLevel(level)) * 2.2
    }

    /// Capped so the bloom stays inside the panel's 10pt margin around the pill.
    static func glowRadius(_ level: Float, breath: Double) -> CGFloat {
        2 + CGFloat(breath) * 2 + CGFloat(clampedLevel(level)) * 4
    }

    static func tint(_ level: Float) -> Color {
        Color(hue: 0.72 + Double(clampedLevel(level)) * 0.16, saturation: 0.85, brightness: 1)
    }
}
#endif
