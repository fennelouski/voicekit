//
//  make-icon.swift
//  Dictate
//
//  Renders the app icon: the voice orb from the dictation HUD, on a macOS squircle.
//  Run via Scripts/make-icon.sh, which turns the PNG into Scripts/AppIcon.icns.
//
//  Palette is lifted from VoiceKit's VoiceOrb so the icon matches the orb the
//  user actually sees while dictating.
//

import SwiftUI
import UniformTypeIdentifiers

private struct OrbIcon: View {
    /// macOS insets an 824pt squircle in 1024 with transparent margins. iOS fills the whole
    /// square — the system masks its own corners, and a home-screen icon can't be transparent.
    var fullBleed = false

    private let canvas: CGFloat = 1024
    private let inset: CGFloat = 100
    private var squircle: CGFloat { canvas - inset * 2 }
    private var base: CGFloat { fullBleed ? canvas : squircle }
    private var corner: CGFloat { squircle * 0.225 }
    // Slightly smaller orb at full bleed so its bloom keeps clear of the edges.
    private var orb: CGFloat { base * (fullBleed ? 0.52 : 0.62) }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(hue: 0.70, saturation: 0.55, brightness: 0.16),
                Color(hue: 0.80, saturation: 0.70, brightness: 0.07),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // A soft top sheen, the way Apple's own icons catch light.
    private var sheenGradient: LinearGradient {
        LinearGradient(colors: [.white.opacity(0.10), .clear], startPoint: .top, endPoint: .center)
    }

    private var shape: AnyShape {
        fullBleed
            ? AnyShape(Rectangle())
            : AnyShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }

    var body: some View {
        ZStack {
            shape
                .fill(backgroundGradient)
                .overlay(shape.fill(sheenGradient))
                .frame(width: base, height: base)

            // Clip the orb's bloom and glow to the background silhouette so the halo doesn't
            // leak past the icon edge.
            orbBody
                .frame(width: base, height: base)
                .clipShape(shape)
        }
        .frame(width: canvas, height: canvas)
    }

    private var orbBody: some View {
        ZStack {
            // Outer bloom.
            Circle()
                .fill(Color(hue: 0.82, saturation: 0.9, brightness: 1))
                .frame(width: orb * 1.5, height: orb * 1.5)
                .blur(radius: orb * 0.28)
                .opacity(0.55)

            // Base sphere.
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hue: 0.64, saturation: 0.85, brightness: 0.98),
                            Color(hue: 0.84, saturation: 0.92, brightness: 0.78),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: orb, height: orb)

            // Churning blobs, clipped to the sphere — the orb look.
            ZStack {
                blob(hue: 0.60, dx: -0.16, dy: -0.14, scale: 0.85)
                blob(hue: 0.74, dx: 0.18, dy: 0.10, scale: 0.9)
                blob(hue: 0.88, dx: 0.04, dy: 0.20, scale: 0.7)
            }
            .frame(width: orb, height: orb)
            .blur(radius: orb * 0.06)
            .clipShape(Circle())

            // Rim + specular highlight.
            Circle()
                .strokeBorder(Color.white.opacity(0.28), lineWidth: orb * 0.012)
                .frame(width: orb, height: orb)

            Circle()
                .fill(Color.white.opacity(0.5))
                .frame(width: orb * 0.26, height: orb * 0.18)
                .blur(radius: orb * 0.08)
                .offset(x: -orb * 0.18, y: -orb * 0.22)
        }
        .shadow(color: Color(hue: 0.84, saturation: 0.9, brightness: 1).opacity(0.6),
                radius: orb * 0.22)
    }

    private func blob(hue: Double, dx: CGFloat, dy: CGFloat, scale: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color(hue: hue, saturation: 0.95, brightness: 1),
                        Color(hue: hue, saturation: 0.95, brightness: 0.5),
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: orb * 0.45
                )
            )
            .frame(width: orb * scale, height: orb * scale)
            .offset(x: orb * dx, y: orb * dy)
    }
}

@main
struct IconGen {
    @MainActor
    static func main() {
        let args = CommandLine.arguments.dropFirst()
        let fullBleed = args.contains("--ios")
        let outPath = args.first(where: { !$0.hasPrefix("--") }) ?? "icon.png"
        let renderer = ImageRenderer(content: OrbIcon(fullBleed: fullBleed))
        renderer.scale = 2 // 1024 content → 2048px, supersampled

        guard let cg = renderer.cgImage else {
            FileHandle.standardError.write(Data("ImageRenderer produced no image\n".utf8))
            exit(1)
        }
        let url = URL(fileURLWithPath: outPath)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            FileHandle.standardError.write(Data("couldn't create \(outPath)\n".utf8))
            exit(1)
        }
        CGImageDestinationAddImage(dest, cg, nil)
        CGImageDestinationFinalize(dest)
        print("wrote \(cg.width)x\(cg.height) → \(outPath)")
    }
}
