//
//  AppearancePane.swift
//  Dictate
//
//  The dictation popup: how it looks, where it sits, how fast it moves.
//  The preview here is the real HUD, driven by a fake voice — what you see is
//  exactly what shows up when you hold the hotkey.
//

#if os(macOS)
import SwiftUI

@available(macOS 26.0, *)
struct AppearancePane: View {
    @AppStorage(Settings.hudStyleKey) private var styleRaw = HUDStyle.bars.rawValue
    @AppStorage(Settings.hudPositionKey) private var positionRaw = HUDPosition.bottomCenter.rawValue
    @AppStorage(Settings.hudTextSizeKey) private var textSizeRaw = HUDTextSize.medium.rawValue
    @AppStorage(Settings.hudTransitionSpeedKey) private var transitionRaw = HUDSpeed.normal.rawValue
    @AppStorage(Settings.hudRevealSpeedKey) private var revealRaw = HUDSpeed.fast.rawValue

    /// Everything the pickers below add up to — the preview shows all of it at once.
    private var look: HUDAppearance {
        HUDAppearance(
            style: HUDStyle(rawValue: styleRaw) ?? .bars,
            textSize: HUDTextSize(rawValue: textSizeRaw) ?? .medium,
            position: HUDPosition(rawValue: positionRaw) ?? .bottomCenter,
            transition: HUDSpeed(rawValue: transitionRaw) ?? .normal,
            reveal: HUDSpeed(rawValue: revealRaw) ?? .fast
        )
    }

    var body: some View {
        // The preview lives outside the Form, so it stays put while the settings scroll
        // under it — you can watch what a control does without scrolling back up to look.
        VStack(spacing: 0) {
            HUDBackdrop {
                HUDPreview(look: look)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            form
        }
    }

    private var form: some View {
        Form {
            Section {
                Picker("Style", selection: $styleRaw.asEnum(HUDStyle.bars)) {
                    ForEach(HUDStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }

                SettingCaptionRow(
                    caption: String(localized: "The pill that floats over your screen while you dictate."),
                    title: String(localized: "Dictation Popup"),
                    explanation: String(localized: """
                        While you're dictating, a small pill floats over your screen showing what's \
                        been recognized so far and how loud you are. It never takes focus, so it \
                        can't steal your keystrokes.

                        The styles differ only in how they draw your voice: level bars are the \
                        quietest, the voice orb and sonar ripple are the liveliest, and the \
                        breathing halo drops the indicator entirely and lets the pill itself glow — \
                        which leaves the most room for the transcript.
                        """),
                    value: $styleRaw.asEnum(HUDStyle.bars)
                ) { HUDStyleDemo(style: $0) }

                Picker("Text size", selection: $textSizeRaw.asEnum(HUDTextSize.medium)) {
                    ForEach(HUDTextSize.allCases) { size in
                        Text(size.displayName).tag(size)
                    }
                }

                SettingCaptionRow(
                    caption: String(localized: "The pill grows to fit — bigger text means a taller pill."),
                    title: String(localized: "Text Size"),
                    explanation: String(localized: """
                        How large the transcript is drawn inside the pill. The pill (and the \
                        invisible window behind it) grow to fit, so nothing gets clipped at the \
                        larger sizes.

                        The transcript is always trimmed to the last stretch of what you said, so \
                        a long dictation scrolls rather than sprawling across your screen.
                        """),
                    value: $textSizeRaw.asEnum(HUDTextSize.medium)
                ) { HUDTextSizeDemo(size: $0) }
            } header: {
                SettingsLabel(String(localized: "Dictation Popup"), systemImage: "waveform", tint: SettingsTint.appearance)
            }

            Section {
                LabeledContent("Position") {
                    HUDPositionGrid(position: $positionRaw.asEnum(HUDPosition.bottomCenter))
                }

                SettingCaptionRow(
                    caption: String(localized: "Anchored to a corner or edge, the pill grows inward toward the centre of the screen."),
                    title: String(localized: "Position"),
                    explanation: String(localized: """
                        Where the pill sits on screen. Bottom centre is the default, out of the way \
                        of most windows.

                        When the pill is anchored to a side, it hugs that edge and extends toward \
                        the middle of the screen as the transcript gets longer — rather than \
                        growing out in both directions and running off the edge.
                        """),
                    value: $positionRaw.asEnum(HUDPosition.bottomCenter)
                ) { HUDPositionDemo(position: $0) }
            } header: {
                SettingsLabel(String(localized: "Placement"), systemImage: "rectangle.inset.filled", tint: SettingsTint.appearance)
            }

            Section {
                Picker("Transitions", selection: $transitionRaw.asEnum(HUDSpeed.normal)) {
                    ForEach(HUDSpeed.allCases) { speed in
                        Text(speed.displayName).tag(speed)
                    }
                }

                SettingCaptionRow(
                    caption: String(localized: "How long the pill takes to change state — listening to cleaning up."),
                    title: String(localized: "Transitions"),
                    explanation: String(localized: """
                        The pill crossfades when it changes state: from listening, to "Cleaning \
                        up…", to an error. Normal is a little over a quarter of a second, which \
                        reads as a transition rather than a flash.

                        Instant means genuinely no animation, not a very fast one — the pill simply \
                        swaps.
                        """),
                    value: $transitionRaw.asEnum(HUDSpeed.normal)
                ) { HUDTransitionDemo(speed: $0) }

                Picker("Text appears", selection: $revealRaw.asEnum(HUDSpeed.fast)) {
                    ForEach(HUDSpeed.allCases) { speed in
                        Text(speed.revealName).tag(speed)
                    }
                }

                SettingCaptionRow(
                    caption: String(localized: "How long new words take to land as you speak."),
                    title: String(localized: "Text Appears"),
                    explanation: String(localized: """
                        How quickly recognized words settle into the pill. This fires continuously \
                        while you talk, so it defaults faster than the state transitions.

                        ASAP puts words up the instant they're recognized. Slow-mo takes its sweet \
                        time about it. Neither affects how fast the text is actually inserted — \
                        this is purely how the popup reads.
                        """),
                    value: $revealRaw.asEnum(HUDSpeed.fast)
                ) { HUDRevealDemo(speed: $0) }
            } header: {
                SettingsLabel(String(localized: "Motion"), systemImage: "dial.medium", tint: SettingsTint.appearance)
            }
        }
        .formStyle(.grouped)
    }
}
#endif
