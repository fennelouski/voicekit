#if os(macOS)
import AppKit
import ApplicationServices

/// Captured before recording starts. Validation reads focus identity and role,
/// never the field's text. All AX references stay on the main actor.
@MainActor
final class InsertionDestination {
    let processID: pid_t
    let applicationName: String
    private let matchesFocus: () -> Bool

    init(processID: pid_t, applicationName: String, matchesFocus: @escaping () -> Bool) {
        self.processID = processID
        self.applicationName = applicationName
        self.matchesFocus = matchesFocus
    }

    var isCurrent: Bool { matchesFocus() }

    static func capture() -> InsertionDestination? {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
              let launched = app.launchDate,
              let element = focusedElement(in: app.processIdentifier), isTextInput(element),
              let window = attribute(kAXWindowAttribute, of: element) else { return nil }
        let pid = app.processIdentifier
        return InsertionDestination(processID: pid, applicationName: app.localizedName ?? "") {
            guard let current = NSWorkspace.shared.frontmostApplication,
                  current.processIdentifier == pid, current.launchDate == launched,
                  let focused = focusedElement(in: pid), isTextInput(focused),
                  let currentWindow = attribute(kAXWindowAttribute, of: focused) else { return false }
            return CFEqual(element, focused) && CFEqual(window, currentWindow)
        }
    }

    private static func focusedElement(in pid: pid_t) -> AXUIElement? {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.2)
        guard let value = attribute(kAXFocusedUIElementAttribute, of: application),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.2)
        return element
    }

    private static func isTextInput(_ element: AXUIElement) -> Bool {
        let role = attribute(kAXRoleAttribute, of: element) as? String
        let subrole = attribute(kAXSubroleAttribute, of: element) as? String
        guard role != "AXSecureTextField", subrole != "AXSecureTextField" else { return false }
        if let enabled = attribute(kAXEnabledAttribute, of: element) as? Bool, !enabled { return false }
        // Terminals expose AXTextArea even though their value isn't settable.
        // Unknown or non-text controls fail closed to manual paste.
        return [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role ?? "")
    }

    private static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}

enum InsertionResult: Equatable {
    case pasted
    case copiedBecauseFocusChanged
    case copiedBecauseDestinationUnknown
    case copiedBecausePasteUnavailable

    var message: String? {
        switch self {
        case .pasted: return nil
        case .copiedBecauseFocusChanged:
            return String(localized: "Focus changed — text copied; press ⌘V to paste")
        case .copiedBecauseDestinationUnknown:
            return String(localized: "Couldn't verify text field — text copied; press ⌘V to paste")
        case .copiedBecausePasteUnavailable:
            return String(localized: "Couldn't paste — press ⌘V to paste")
        }
    }
}

/// One synchronous decision immediately before insertion: no suspension between
/// focus verification and posting the paste to the captured process.
@MainActor
enum InsertionGate {
    static func insert(
        _ text: String, into destination: InsertionDestination?,
        copy: (String) -> Void, paste: (String, pid_t) -> Bool
    ) -> InsertionResult {
        guard let destination else {
            copy(text)
            return .copiedBecauseDestinationUnknown
        }
        guard destination.isCurrent else {
            copy(text)
            return .copiedBecauseFocusChanged
        }
        guard paste(text, destination.processID) else {
            copy(text)
            return .copiedBecausePasteUnavailable
        }
        return .pasted
    }
}
#endif
