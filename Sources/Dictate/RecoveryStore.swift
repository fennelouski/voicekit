#if os(macOS)
import Foundation

/// Durable, local recovery records. Audio never leaves this directory via a
/// network request. Successful retry does not remove it until the user chooses.
actor RecoveryStore {
    static let shared = RecoveryStore(directory: LearningPaths.recoverable)

    enum Kind: String, Codable, Sendable { case dictation, conversation }
    struct Record: Codable, Identifiable, Equatable, Sendable {
        let id: UUID
        let created: Date
        let source: String
        let localeIdentifier: String?
        let kind: Kind
    }
    enum StoreError: Error { case missingAudio, invalidRecord }

    let directory: URL
    private var imported = false
    private var conversationsImported = false
    private var activeConversations: Set<URL> = []
    init(directory: URL) { self.directory = directory }

    func importOnce(from scratch: URL, locale: Locale?) {
        guard !imported else { return }
        imported = true
        importInterrupted(from: scratch, locale: locale)
    }

    func importConversationsOnce(from scratch: URL) {
        guard !conversationsImported else { return }
        conversationsImported = true
        importConversations(from: scratch)
    }

    func protectConversation(_ directory: URL) { activeConversations.insert(directory.standardizedFileURL) }
    func releaseConversation(_ directory: URL) { activeConversations.remove(directory.standardizedFileURL) }

    func importConversations(from scratch: URL) {
        let directories = (try? FileManager.default.contentsOfDirectory(at: scratch, includingPropertiesForKeys: [.isSymbolicLinkKey])) ?? []
        for directory in directories {
            guard !activeConversations.contains(directory.standardizedFileURL), (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
                  let data = try? Data(contentsOf: directory.appendingPathComponent("session.json")),
                  let manifest = try? JSONDecoder().decode(ConversationScratchManifest.self, from: data) else { continue }
            var movedAll = true
            for segment in manifest.segments {
                guard segment.fileName == URL(fileURLWithPath: segment.fileName).lastPathComponent,
                      segment.fileName.hasSuffix(".caf") else { movedAll = false; continue }
                let url = directory.appendingPathComponent(segment.fileName)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                do { _ = try register(audio: url, source: segment.source,
                                      locale: manifest.localeIdentifier.map(Locale.init(identifier:)), kind: .conversation) }
                catch { movedAll = false }
            }
            if movedAll { try? FileManager.default.removeItem(at: directory) }
        }
    }

    func clearDictations() {
        for record in records() where record.kind == .dictation { try? delete(record.id) }
    }

    func exportAudio(_ id: UUID, to destination: URL) throws {
        try Data(contentsOf: audioURL(for: id), options: .mappedIfSafe).write(to: destination, options: .atomic)
    }

    func register(audio: URL, source: String, locale: Locale?, kind: Kind) throws -> Record {
        guard let values = try? audio.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true else { throw StoreError.missingAudio }
        let created = (try? audio.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
        let record = Record(id: UUID(), created: created, source: source, localeIdentifier: locale?.identifier, kind: kind)
        let folder = folder(record.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            // Write metadata before moving audio; a failed manifest must leave
            // the caller's original recording intact.
            try JSONEncoder().encode(record).write(to: folder.appendingPathComponent("record.json"), options: .atomic)
            try FileManager.default.moveItem(at: audio, to: folder.appendingPathComponent("audio.caf"))
            return record
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    func records() -> [Record] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey])) ?? []
        return folders.compactMap { url -> Record? in
            guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
                  let id = UUID(uuidString: url.lastPathComponent),
                  let data = try? Data(contentsOf: url.appendingPathComponent("record.json")),
                  let record = try? JSONDecoder().decode(Record.self, from: data), record.id == id,
                  (try? audioURL(for: id)) != nil else { return nil }
            return record
        }.sorted { $0.created > $1.created }
    }

    func audioURL(for id: UUID) throws -> URL {
        let parent = folder(id)
        guard (try? parent.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false else { throw StoreError.invalidRecord }
        let url = parent.appendingPathComponent("audio.caf")
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true else { throw StoreError.missingAudio }
        return url
    }

    func transcript(for id: UUID) -> String? {
        try? String(contentsOf: folder(id).appendingPathComponent("transcript.txt"), encoding: .utf8)
    }

    func saveTranscript(_ text: String, for id: UUID) throws {
        try Task.checkCancellation()
        _ = try audioURL(for: id) // never recreate a record deleted during retry
        try Data(text.utf8).write(to: folder(id).appendingPathComponent("transcript.txt"), options: .atomic)
    }

    func delete(_ id: UUID) throws {
        let url = folder(id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    func expireDictations(retention: TimeInterval?, keeping id: UUID? = nil, now: Date = Date()) {
        for record in records() where record.kind == .dictation && record.id != id {
            if let retention, now.timeIntervalSince(record.created) < retention { continue }
            try? delete(record.id)
        }
    }

    /// Called once on launch before a new dictation can sweep scratch audio.
    func importInterrupted(from scratch: URL, locale: Locale?) {
        let files = (try? FileManager.default.contentsOfDirectory(at: scratch, includingPropertiesForKeys: [.isRegularFileKey])) ?? []
        for file in files where file.pathExtension == "caf" {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            _ = try? register(audio: file, source: String(localized: "Interrupted dictation"), locale: locale, kind: .dictation)
        }
    }

    private func folder(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString, isDirectory: true) }
}
#endif
