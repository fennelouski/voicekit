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
import Carbon.HIToolbox

/// Global ⌃⌥⌘-based hotkeys via Carbon RegisterEventHotKey: the app consumes the keypress
/// (it never reaches the focused app) and no Accessibility permission is needed, unlike
/// NSEvent global monitors.
///
/// These are the app's only guaranteed controls — they keep working when the menu bar icon
/// is hidden, which is the whole reason hiding it is safe.
@MainActor
enum GlobalHotkey {
    /// ⌃⌥⌘V — recent dictations.
    static let history: UInt32 = 1
    /// ⌃⌥⌘, — settings. Mirrors ⌘, but works without a focused window or a menu bar icon.
    static let settings: UInt32 = 2

    private static var handlers: [UInt32: () -> Void] = [:]
    private static var refs: [EventHotKeyRef?] = []
    private static var installed = false

    static func register(keyCode: Int, id: UInt32, handler: @escaping () -> Void) {
        handlers[id] = handler
        installDispatcher()

        var ref: EventHotKeyRef?
        RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(controlKey | optionKey | cmdKey),
            EventHotKeyID(signature: OSType(0x4449_4354), id: id), // 'DICT'
            GetApplicationEventTarget(),
            0,
            &ref
        )
        refs.append(ref)
    }

    /// One Carbon handler for every hotkey; it reads back which one fired and dispatches.
    private static func installDispatcher() {
        guard !installed else { return }
        installed = true

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var pressed = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &pressed
            )
            let id = pressed.id
            MainActor.assumeIsolated { GlobalHotkey.handlers[id]?() }
            return noErr
        }, 1, &eventType, nil, nil)
    }
}

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
