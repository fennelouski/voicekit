//
//  VoiceOrb.swift
//  VoiceKit
//
//  The dictation orb: blurred blobs orbiting inside a clipped circle, churning
//  continuously. Volume swells it, warms its colour, and widens its glow.
//
//  Shared so the macOS HUD, the app icon, and the iOS keyboard all show the same
//  thing while you talk — the orb is the app's face, and it should be one face.
//

import SwiftUI

/// Clamp a mic level into `[0, 1]`. NaN or out-of-range samples collapse to silence,
/// so every level → geometry mapping downstream stays inside the slot it draws into.
public func clampedLevel(_ level: Float) -> Float {
    level.isFinite ? min(1, max(0, level)) : 0
}

/// Voice-reactive orb driven by mic level. `size` is the only thing that changes between
/// the 22pt HUD dot and the big keyboard button — everything else scales from it, so
/// the two read as the same orb.
public struct VoiceOrb: View {
    let level: Float
    let size: CGFloat

    public init(level: Float, size: CGFloat = 22) {
        self.level = level
        self.size = size
    }

    public var body: some View {
        let level = clampedLevel(level)
        // Blur and stroke are authored against the 22pt HUD orb; scale them with size
        // so a big orb looks like the small one enlarged, not a thin-lined balloon.
        let scale = size / 22
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle().fill(Self.baseGradient(level))
                // Orbit speeds stay constant; only the radius grows with level.
                // Scaling time by level would jump the phase and snap the blobs.
                blob(hue: 0.60, speed: 0.9, phase: 0, level: level, time: time)
                blob(hue: 0.74, speed: -0.7, phase: 2.1, level: level, time: time)
                blob(hue: Self.hotHue(level), speed: 1.3, phase: 4.2, level: level, time: time)
            }
            .blur(radius: 3 * scale)
            .clipShape(Circle())
            .overlay(
                Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5 * scale)
            )
            .frame(width: size, height: size)
            .scaleEffect(Self.orbScale(level))
            .shadow(color: Self.glowColor(level), radius: Self.glowRadius(level) * scale)
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.12), value: self.level)
    }

    private func blob(hue: Double, speed: Double, phase: Double, level: Float, time: Double) -> some View {
        let angle = time * speed + phase
        let orbit = size * (0.06 + CGFloat(clampedLevel(level)) * 0.24)
        return Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color(hue: hue, saturation: Self.saturation(level), brightness: 1),
                        Color(hue: hue, saturation: 0.95, brightness: 0.5),
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.45
                )
            )
            .frame(width: size * 0.85, height: size * 0.85)
            .offset(x: cos(angle) * orbit, y: sin(angle) * orbit)
    }

    // MARK: - Level → geometry and colour (pure, tested)

    public static func orbScale(_ level: Float) -> CGFloat {
        0.85 + CGFloat(clampedLevel(level)) * 0.55
    }

    public static func glowRadius(_ level: Float) -> CGFloat {
        3 + CGFloat(clampedLevel(level)) * 13
    }

    /// Calm violet when quiet, hot magenta when loud. Stops short of red,
    /// which reads as an error rather than a level.
    public static func hotHue(_ level: Float) -> Double {
        0.72 + Double(clampedLevel(level)) * 0.16
    }

    public static func saturation(_ level: Float) -> Double {
        0.55 + Double(clampedLevel(level)) * 0.45
    }

    private static func baseGradient(_ level: Float) -> LinearGradient {
        LinearGradient(
            colors: [
                Color(hue: 0.62, saturation: saturation(level), brightness: 0.95),
                Color(hue: hotHue(level), saturation: 0.9, brightness: 0.7),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private static func glowColor(_ level: Float) -> Color {
        Color(hue: hotHue(level), saturation: 0.9, brightness: 1)
            .opacity(0.35 + Double(clampedLevel(level)) * 0.45)
    }
}
