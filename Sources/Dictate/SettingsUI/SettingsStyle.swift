//
//  SettingsStyle.swift
//  Dictate
//
//  The small design system behind the settings window: one hue per area, a label
//  that tints only its icon, and the bridge from @AppStorage's raw strings to enums.
//

#if os(macOS)
import SwiftUI

/// Each area of settings owns a hue. The tint colours the *icon only* — the text stays in the
/// standard label colour — so the window reads as calm at a glance while each section is still
/// recognisable by its colour. Same idiom as System Settings.
enum SettingsTint {
    static let hotkey = Color.blue
    static let input = Color.green
    static let insertion = Color.teal
    static let cleanup = Color.purple
    static let appearance = Color.pink
    static let learning = Color.orange
    static let privacy = Color.indigo
    static let system = Color.gray
}

/// A settings row or section header: title in the standard text colour, icon in its area's tint.
///
/// A plain `Label` renders its icon in the accent colour, which would make every row in the
/// window the same shade of blue.
struct SettingsLabel: View {
    let title: String
    let systemImage: String
    let tint: Color

    init(_ title: String, systemImage: String, tint: Color) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(tint)
        }
    }
}

extension Binding where Value == String {
    /// Bridges a raw-value `@AppStorage` binding to the enum that pickers and demos want,
    /// falling back when the stored string is missing or no longer a case we recognise.
    func asEnum<E: RawRepresentable>(_ fallback: E) -> Binding<E> where E.RawValue == String {
        // Spelled out: inside an extension on Binding<String>, a bare `Binding` means Self.
        Binding<E>(
            get: { E(rawValue: wrappedValue) ?? fallback },
            set: { wrappedValue = $0.rawValue }
        )
    }
}
#endif
