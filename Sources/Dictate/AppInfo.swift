//
//  AppInfo.swift
//  Dictate
//
//  Version/build strings read straight from the bundle, so About and the
//  Settings footer can't drift out of sync with what Info.plist says.
//

#if os(macOS)
import Foundation

enum AppInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}
#endif
