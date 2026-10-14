#if os(macOS)
import AppKit
import Carbon.HIToolbox

/// Consume Escape only when it actually cancelled a dictation. A held Escape
/// remains ours through key-up, so repeats cannot cancel a subsequent session.
struct EscapeKeyGate {
    private var consumedDown = false

    mutating func handle(keyDown: Bool, isRepeat: Bool, cancel: () -> Bool) -> Bool {
        if !keyDown {
            let consume = consumedDown
            consumedDown = false
            return consume
        }
        if consumedDown { return true }
        guard !isRepeat, cancel() else { return false }
        consumedDown = true
        return true
    }
}

@MainActor
final class EscapeMonitor {
    // AppDelegate owns this through HotkeyMonitor for the app's lifetime and
    // stops it before termination; the unretained callback cannot outlive it.
    var onEscape: (() -> Bool)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var gate = EscapeKeyGate()
    private var globalFallback: Any?
    private var localFallback: Any?

    func start() {
        stop()
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<EscapeMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                // This source is installed exclusively on the main run loop.
                return MainActor.assumeIsolated {
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        if let tap = monitor.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                        return Unmanaged.passUnretained(event)
                    }
                    guard event.getIntegerValueField(.keyboardEventKeycode) == kVK_Escape else {
                        return Unmanaged.passUnretained(event)
                    }
                    let consumed = monitor.handle(
                        keyDown: type == .keyDown,
                        isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                    )
                    return consumed ? nil : Unmanaged.passUnretained(event)
                }
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        if let tap, let source = CFMachPortCreateRunLoopSource(nil, tap, 0) {
            self.source = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        } else {
            // Keep cancellation usable if event-tap creation fails. A global
            // NSEvent monitor can observe but cannot consume another app's key.
            globalFallback = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                MainActor.assumeIsolated { _ = self?.handle(event) }
            }
            localFallback = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                let consumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
                return consumed ? nil : event
            }
        }
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        if let globalFallback { NSEvent.removeMonitor(globalFallback) }
        if let localFallback { NSEvent.removeMonitor(localFallback) }
        tap = nil
        source = nil
        globalFallback = nil
        localFallback = nil
        gate = EscapeKeyGate()
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard event.keyCode == kVK_Escape else { return false }
        return handle(keyDown: event.type == .keyDown, isRepeat: event.isARepeat)
    }

    private func handle(keyDown: Bool, isRepeat: Bool) -> Bool {
        gate.handle(keyDown: keyDown, isRepeat: isRepeat) { onEscape?() ?? false }
    }
}
#endif
