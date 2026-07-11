//
//  HotkeyMonitor.swift
//  Dictate
//
//  Global push-to-talk hotkey via flagsChanged monitors. Modifier-only keys
//  (Fn, Right ⌘) don't type anything, so no event swallowing is needed.
//  Requires Accessibility trust for the global monitor.
//

#if os(macOS)
import AppKit

@MainActor
final class HotkeyMonitor {
    var hotkey: Hotkey = .fn
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isDown = false

    func start() {
        stop()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        isDown = false
    }

    private func handle(_ event: NSEvent) {
        guard event.keyCode == hotkey.keyCode else { return }
        let pressed = event.modifierFlags.contains(hotkey.flag)
        if pressed, !isDown {
            isDown = true
            onKeyDown?()
        } else if !pressed, isDown {
            isDown = false
            onKeyUp?()
        }
    }
}
#endif
