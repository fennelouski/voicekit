//
//  LaunchAtLogin.swift
//  Dictate
//
//  Thin wrapper over SMAppService.mainApp, shared by onboarding and Settings —
//  the source of truth is the system, not a default, so callers re-read
//  `isEnabled` after every change attempt rather than trusting the request.
//

#if os(macOS)
import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Attempts the change; returns the actual resulting state (macOS can refuse).
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {}
        return isEnabled
    }
}
#endif
