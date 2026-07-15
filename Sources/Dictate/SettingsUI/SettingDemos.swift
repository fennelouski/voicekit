//
//  SettingDemos.swift
//  Dictate
//
//  One interactive demo per setting whose effect is easier to show than to describe.
//  Every demo is the same shape: a preview card on top, the control that drives it
//  underneath. Nothing here touches the network, the microphone, or the real HUD.
//

#if os(macOS)
import SwiftUI
import VoiceKit

// MARK: - Shared chrome

/// A fill alone all but vanishes against the popover's own background, so the card carries a
/// hairline border to keep its edges legible in both appearances.
private var demoCard: some View {
    RoundedRectangle(cornerRadius: 12)
        .fill(.quaternary)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
}

private func demoCaption(_ text: String) -> some View {
    Text(text)
        .font(.caption2)
        .textCase(.uppercase)
        .foregroundStyle(.secondary)
}

// MARK: - The live HUD

/// Synthetic voice level for the HUD previews: a fast swell for syllables riding a slow one for
/// phrases, so the pill breathes like speech instead of pulsing like a metronome. Every indicator
/// clamps its input, but a preview pinned at either end shows nothing — this stays inside 0.05…0.95.
func previewLevel(at time: Double) -> Float {
    let syllables = (sin(time * 3.1) + 1) / 2
    let phrases = (sin(time * 0.7) + 1) / 2
    return Float(0.05 + syllables * phrases * 0.9)
}

/// The real `HUDView`, driven by a fake voice and a looping dictation: words land one at a
/// time, it goes to "Cleaning up…", then starts over. One loop demonstrates the style, the
/// type size, the position, the transition speed and the reveal speed all at once.
struct HUDPreview: View {
    var look: HUDAppearance
    /// The hotkey demo keeps it silent until you actually press the key.
    var speaking = true

    @StateObject private var model = HUDModel()
    @State private var start = Date()
    @State private var step = 0

    private static let words = ["Ship", "this", "on", "Thursday."]
    /// Each word, a beat on the full sentence, then two beats of cleanup.
    private static let steps = words.count + 4

    private let levelTick = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()
    private let clock = Timer.publish(every: 0.55, on: .main, in: .common).autoconnect()

    var body: some View {
        // The backdrop stands in for a whole screen, so the pill moves in both axes here —
        // unlike in the real panel, where the panel itself does the vertical work.
        HUDView(model: model, alignment: look.screenAlignment)
            .onAppear { model.appearance = look }
            .onChange(of: look) { _, new in model.appearance = new }
            .onReceive(levelTick) { now in
                let listening = model.phase == .listening
                model.level = speaking && listening
                    ? previewLevel(at: now.timeIntervalSince(start))
                    : 0
            }
            .onReceive(clock) { _ in advance() }
    }

    private func advance() {
        guard speaking else {
            step = 0
            model.phase = .listening
            model.text = ""
            return
        }
        step = (step + 1) % Self.steps
        if step <= Self.words.count {
            model.phase = .listening
            model.text = Self.words.prefix(step).joined(separator: " ")
        } else if step == Self.words.count + 1 {
            model.phase = .listening // hold on the finished sentence
        } else {
            model.phase = .processing
        }
    }
}

/// Start from what's actually saved, then override the one thing this demo edits — so the
/// preview shows your real type size and speeds while you audition a new style.
private func look(overriding change: (inout HUDAppearance) -> Void) -> HUDAppearance {
    var look = HUDAppearance.current
    change(&look)
    return look
}

/// A 3×3 anchor picker, the way display-arrangement controls work.
struct HUDPositionGrid: View {
    @Binding var position: HUDPosition

    var body: some View {
        Grid(horizontalSpacing: 5, verticalSpacing: 5) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { column in
                        cell(HUDPosition.at(row: row, column: column))
                    }
                }
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private func cell(_ target: HUDPosition) -> some View {
        let selected = position == target
        return Button {
            position = target
        } label: {
            RoundedRectangle(cornerRadius: 3)
                .fill(selected ? Color.accentColor : Color.primary.opacity(0.10))
                .frame(width: 26, height: 16)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(target.displayName)
        .help(target.displayName)
    }
}

/// Stands in for a desktop, so the HUD's white-on-black pill has something to sit against.
struct HUDBackdrop<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(10)
            // Fixed, not a minimum: HUDView expands to fill whatever it's given, so a
            // minHeight here would let it swallow the whole pane. Tall enough that a
            // top/middle/bottom anchor still reads as movement.
            .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 150)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.16, green: 0.17, blue: 0.28),
                        Color(red: 0.31, green: 0.21, blue: 0.35),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
    }
}

// MARK: - Appearance

struct HUDStyleDemo: View {
    @Binding var style: HUDStyle

    var body: some View {
        VStack(spacing: 20) {
            HUDBackdrop {
                HUDPreview(look: look { $0.style = style })
            }

            Picker("", selection: $style) {
                ForEach(HUDStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct HUDTextSizeDemo: View {
    @Binding var size: HUDTextSize

    var body: some View {
        VStack(spacing: 20) {
            HUDBackdrop {
                HUDPreview(look: look { $0.textSize = size })
            }

            Picker("", selection: $size) {
                ForEach(HUDTextSize.allCases) { size in
                    Text(size.displayName).tag(size)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Speed of the state changes — listening → cleaning up. Watch the pill swap contents.
struct HUDTransitionDemo: View {
    @Binding var speed: HUDSpeed

    var body: some View {
        VStack(spacing: 20) {
            HUDBackdrop {
                HUDPreview(look: look { $0.transition = speed })
            }

            Picker("", selection: $speed) {
                ForEach(HUDSpeed.allCases) { speed in
                    Text(speed.displayName).tag(speed)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Speed of the transcript landing in the pill, word by word.
struct HUDRevealDemo: View {
    @Binding var speed: HUDSpeed

    var body: some View {
        VStack(spacing: 20) {
            HUDBackdrop {
                HUDPreview(look: look { $0.reveal = speed })
            }

            Picker("", selection: $speed) {
                ForEach(HUDSpeed.allCases) { speed in
                    Text(speed.revealName).tag(speed)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A stand-in screen with the pill parked at the chosen anchor. The pill hugs its edge and
/// grows inward, so you can see it reach toward the middle rather than off the screen.
struct HUDPositionDemo: View {
    @Binding var position: HUDPosition

    var body: some View {
        VStack(spacing: 20) {
            ZStack(alignment: screenAlignment) {
                LinearGradient(
                    colors: [
                        Color(red: 0.16, green: 0.17, blue: 0.28),
                        Color(red: 0.31, green: 0.21, blue: 0.35),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5, height: 5)
                    Capsule()
                        .fill(Color.white.opacity(0.55))
                        .frame(width: 52, height: 4)
                }
                .padding(.horizontal, 9)
                .frame(height: 18)
                .background(Capsule().fill(Color.black.opacity(0.82)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
                .padding(10)
                .animation(.smooth(duration: 0.3), value: position)
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )

            HUDPositionGrid(position: $position)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var screenAlignment: Alignment {
        HUDAppearance(position: position).screenAlignment
    }
}

// MARK: - Hotkey

struct HotkeyDemo: View {
    @Binding var hotkey: Hotkey
    @State private var holding = false

    var body: some View {
        VStack(spacing: 20) {
            HUDBackdrop {
                HUDPreview(look: .current, speaking: holding)
                    .opacity(holding ? 1 : 0)
                    .overlay {
                        if !holding {
                            Text("Hold \(hotkey.displayName) below")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.65))
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: holding)
            }

            HStack(spacing: 10) {
                ForEach(Hotkey.allCases) { key in
                    keyCap(key)
                }
            }

            Picker("", selection: $hotkey) {
                ForEach(Hotkey.allCases) { key in
                    Text("Hold \(key.displayName)").tag(key)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The chosen key is the only one you can press — holding it is the whole point of the demo.
    private func keyCap(_ key: Hotkey) -> some View {
        let chosen = key == hotkey
        let pressed = chosen && holding
        return Text(key.displayName)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .frame(width: 76, height: 42)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(chosen ? Color.accentColor.opacity(pressed ? 0.85 : 0.28)
                                 : Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
            )
            .offset(y: pressed ? 2 : 0)
            .opacity(chosen ? 1 : 0.45)
            .animation(.easeOut(duration: 0.12), value: pressed)
            .animation(.easeInOut, value: chosen)
            .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity) {
                // Never fires: the press is the gesture, there is nothing to do on completion.
            } onPressingChanged: { pressing in
                holding = chosen && pressing
            }
    }
}

// MARK: - Cleanup

let cleanupDemoSample = "um so like i was thinking we could uh ship this on friday, no wait, thursday"

/// Canned results. A demo must never spend an API call or wake Apple Intelligence just to
/// show what a mode does.
func cleanupDemoResult(_ mode: CleanupMode) -> String {
    switch mode {
    case .off:
        return "so like i was thinking we could ship this on friday, no wait, thursday"
    default:
        return "I was thinking we could ship this on Thursday."
    }
}

func cleanupDemoNote(_ mode: CleanupMode) -> String {
    switch mode {
    case .off:
        return "Filler words go; everything else lands exactly as you said it."
    case .onDevice:
        return "Punctuation and false starts fixed, entirely on this Mac."
    case .local:
        return "Same, on a model you host yourself. Nothing leaves your machine."
    default:
        let name = mode.provider?.displayName ?? "the provider"
        return "Same, plus any custom instructions you give it. The transcript goes to \(name); a typical dictation costs a fraction of a cent."
    }
}

/// Walks the user's actual chain and shows what would happen to a real sentence: which steps
/// get skipped for want of a key, which one does the work, and which never get reached.
/// Read-only — it reports the chain rather than editing it, so the popover just says Done.
@available(macOS 26.0, *)
struct CleanupChainDemo: View {
    @Binding var chain: [CleanupMode]

    /// The first step that's actually configured — the one that would clean your text.
    private var winner: CleanupMode? {
        chain.first { configured($0) }
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                demoCaption("You said")
                Text(cleanupDemoSample)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Divider()

                if chain.isEmpty {
                    Text("Cleanup is off — only filler words are removed.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(chain.enumerated()), id: \.element) { index, step in
                        row(step, index: index)
                    }
                }

                Divider()

                demoCaption("Dictate inserts")
                Text(cleanupDemoResult(winner ?? .off))
                    .font(.callout)
                    .fontWeight(.medium)

                if winner == nil, !chain.isEmpty {
                    Text("Every step failed, so your transcript goes in unchanged — and you get told.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(demoCard)
        }
    }

    private func row(_ step: CleanupMode, index: Int) -> some View {
        let isWinner = step == winner
        let reached = winner.flatMap { chain.firstIndex(of: $0) }.map { index <= $0 } ?? true

        let icon: String
        let tint: Color
        let note: String
        if isWinner {
            icon = "checkmark.circle.fill"
            tint = .green
            note = "cleans your text"
        } else if !reached {
            icon = "minus.circle"
            tint = .secondary
            note = "not needed"
        } else {
            icon = "arrow.turn.down.right"
            tint = .orange
            note = skipReason(step)
        }

        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 16)
            Text(step.chainName)
                .font(.callout)
                .fontWeight(isWinner ? .medium : .regular)
            Text("— \(note)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .opacity(reached ? 1 : 0.5)
    }

    private func configured(_ step: CleanupMode) -> Bool {
        switch step {
        case .off:
            return false
        case .onDevice:
            return AICleanup.isAvailable
        case .local:
            return !Settings.model(for: .local).isEmpty
        default:
            guard let provider = step.provider else { return false }
            return !(Settings.apiKey(for: provider) ?? "").isEmpty
        }
    }

    private func skipReason(_ step: CleanupMode) -> String {
        switch step {
        case .onDevice: return "unavailable on this Mac — skipped"
        case .local: return "no model set — skipped"
        default: return "no API key — skipped"
        }
    }
}

struct CleanupModeDemo: View {
    @Binding var mode: CleanupMode

    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                demoCaption("You said")
                Text(cleanupDemoSample)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Image(systemName: "arrow.down")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)

                demoCaption("Dictate inserts")
                Text(cleanupDemoResult(mode))
                    .font(.callout)
                    .fontWeight(.medium)

                Divider()

                Text(cleanupDemoNote(mode))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(demoCard)
            .animation(.easeInOut, value: mode)

            Picker("", selection: $mode) {
                ForEach(CleanupMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Learning

struct LearningDemo: View {
    @Binding var enabled: Bool

    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                beat("You said", "\"open cloud code\"", icon: "mic.fill", tint: .secondary)
                beat("Dictate inserted", "open cloud code", icon: "text.cursor", tint: .secondary)
                beat("You fixed it to", "open Claude Code", icon: "pencil", tint: .orange)

                Divider()

                beat(
                    "Next time you say it",
                    enabled ? "open Claude Code" : "open cloud code",
                    icon: enabled ? "checkmark.circle.fill" : "arrow.counterclockwise",
                    tint: enabled ? .green : .secondary
                )
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(demoCard)
            .animation(.easeInOut, value: enabled)

            Toggle("Learn from my edits", isOn: $enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func beat(_ label: String, _ text: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                demoCaption(label)
                Text(text)
                    .font(.callout)
                    .fontWeight(tint == .green ? .medium : .regular)
            }
        }
    }
}

// MARK: - Conversation transcripts

struct TranscriptsDemo: View {
    @Binding var enabled: Bool

    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(enabled ? SettingsTint.privacy : .secondary)
                    Text("conversation-2026-07-12.txt")
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundStyle(enabled ? .primary : .secondary)
                }

                Divider()

                if enabled {
                    line("Speaker 1", "Should we ship on Thursday?")
                    line("Speaker 2", "Let's do it.")
                } else {
                    Text("Nothing is written to disk.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }

                Divider()

                Text("Audio is never stored, and speaker labels stay in the file — they never reach the text you paste.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(demoCard)
            .animation(.easeInOut, value: enabled)

            Toggle("Save conversation transcripts", isOn: $enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func line(_ speaker: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(speaker + ":")
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundStyle(SettingsTint.privacy)
            Text(text)
                .font(.callout)
        }
    }
}

// MARK: - Menu bar icon

struct MenuBarIconDemo: View {
    @Binding var shown: Bool

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    Spacer()
                    Image(systemName: "mic.fill")
                        .foregroundStyle(Color.accentColor)
                        .opacity(shown ? 1 : 0)
                        .scaleEffect(shown ? 1 : 0.6)
                    Image(systemName: "wifi")
                    Image(systemName: "battery.75percent")
                    Text("9:41")
                        .font(.system(size: 12, weight: .medium))
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                        )
                )
                .animation(.easeInOut, value: shown)

                if shown {
                    Text("Click the icon for Settings, the Welcome Guide, and recent dictations.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    // The whole point: hiding the icon costs you nothing, because every
                    // control is a shortcut that works with or without it.
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Dictate runs invisibly. Everything still works:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        shortcut("Your hotkey", "dictate")
                        shortcut("⌃⌥⌘V", "recent dictations")
                        shortcut("⌃⌥⌘,", "these settings")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .background(demoCard)

            Toggle("Show menu bar icon", isOn: $shown)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func shortcut(_ keys: String, _ does: String) -> some View {
        HStack(spacing: 6) {
            Text(keys)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                        )
                )
            Text(does)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
#endif
