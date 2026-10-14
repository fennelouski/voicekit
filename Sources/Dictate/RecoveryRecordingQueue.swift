#if os(macOS)
import Foundation

/// Protect queued recovery audio until its cleanup job has consumed it.
struct RecoveryRecordingQueue {
    private var pending: Set<URL> = []

    mutating func enqueue(_ url: URL?) {
        if let url { pending.insert(url) }
    }

    mutating func complete(_ url: URL?, failed: Bool, active: URL?) -> [URL] {
        if let url { pending.remove(url) }
        var keep = pending
        if failed, let url { keep.insert(url) }
        if let active { keep.insert(active) }
        return Array(keep)
    }
}
#endif
