import AppKit
import Testing
@testable import Dictate

@MainActor
struct ClipboardTransactionTests {
    private func withPasteboard(_ body: (NSPasteboard, ClipboardTransaction) throws -> Void) rethrows {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        try body(pasteboard, ClipboardTransaction(pasteboard: pasteboard))
    }

    @Test func restoresAllFormatsAndMultipleItems() {
        withPasteboard { pasteboard, transaction in
            let first = NSPasteboardItem()
            first.setString("original", forType: .string)
            let rtf = Data("{\\rtf1 original}".utf8)
            first.setData(rtf, forType: .rtf)
            first.setString("<b>original</b>", forType: .html)
            let second = NSPasteboardItem()
            let image = Data([1, 2, 3, 4])
            second.setData(image, forType: .png)
            second.setString("file:///tmp/example.txt", forType: .fileURL)
            pasteboard.writeObjects([first, second])

            #expect(transaction.write("dictated text"))
            transaction.restore()
            let items = pasteboard.pasteboardItems ?? []
            #expect(items.count == 2)
            #expect(items.first?.string(forType: .string) == "original")
            #expect(items.first?.data(forType: .rtf) == rtf)
            #expect(items.first?.string(forType: .html) == "<b>original</b>")
            #expect(items.last?.data(forType: .png) == image)
            #expect(items.last?.string(forType: .fileURL) == "file:///tmp/example.txt")
        }
    }

    @Test func overlappingDictationsRestoreTheUsersOriginalClipboard() {
        withPasteboard { pasteboard, transaction in
            pasteboard.setString("user copy", forType: .string)
            transaction.write("first dictation")
            transaction.write("second dictation")
            transaction.restore()
            #expect(pasteboard.string(forType: .string) == "user copy")
        }
    }

    @Test func neverOverwritesANewerCopyEvenWhenItsTextMatches() {
        withPasteboard { pasteboard, transaction in
            pasteboard.setString("original", forType: .string)
            transaction.write("dictation")
            pasteboard.clearContents()
            let item = NSPasteboardItem()
            item.setString("dictation", forType: .string)
            item.setString("<b>new user copy</b>", forType: .html)
            pasteboard.writeObjects([item])
            transaction.restore()
            #expect(pasteboard.string(forType: .html) == "<b>new user copy</b>")
        }
    }

    @Test func aCopyBetweenDictationsBecomesTheNewSnapshot() {
        withPasteboard { pasteboard, transaction in
            pasteboard.setString("original", forType: .string)
            transaction.write("first")
            pasteboard.clearContents()
            pasteboard.setString("new user copy", forType: .string)
            transaction.write("second")
            transaction.restore()
            #expect(pasteboard.string(forType: .string) == "new user copy")
        }
    }

    @Test func restoresEmptyClipboardAndDiscardKeepsManualPaste() {
        withPasteboard { pasteboard, transaction in
            pasteboard.clearContents()
            transaction.write("temporary")
            transaction.restore()
            #expect((pasteboard.pasteboardItems ?? []).isEmpty)
            transaction.write("manual paste")
            transaction.discard()
            transaction.restore()
            #expect(pasteboard.string(forType: .string) == "manual paste")
        }
    }
}
