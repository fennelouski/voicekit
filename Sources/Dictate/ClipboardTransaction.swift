#if os(macOS)
import AppKit

/// Owns the temporary clipboard used for paste. A change by another app ends our
/// ownership, even if the new clipboard happens to contain the same text.
@MainActor
final class ClipboardTransaction {
    private let pasteboard: NSPasteboard
    private var snapshot: [[NSPasteboard.PasteboardType: Data]] = []
    private var ownedChangeCount: Int?

    init(pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
    }

    @discardableResult
    func write(_ text: String) -> Bool {
        if ownedChangeCount != pasteboard.changeCount {
            snapshot = (pasteboard.pasteboardItems ?? []).map { item in
                var representations: [NSPasteboard.PasteboardType: Data] = [:]
                for type in item.types {
                    if let data = item.data(forType: type) { representations[type] = data }
                }
                return representations
            }
        }
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            discard()
            return false
        }
        ownedChangeCount = pasteboard.changeCount
        return true
    }

    func restore() {
        defer { discard() }
        guard ownedChangeCount == pasteboard.changeCount else { return }
        let items = snapshot.map { representations in
            let item = NSPasteboardItem()
            for (type, data) in representations { item.setData(data, forType: type) }
            return item
        }
        pasteboard.clearContents()
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }

    /// Manual-paste fallback must leave the transcript on the clipboard.
    func discard() {
        snapshot = []
        ownedChangeCount = nil
    }
}
#endif
