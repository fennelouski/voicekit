#if os(macOS)
import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers
import VoiceKit

@available(macOS 26.0, *)
@MainActor @Observable
final class RecoveryModel {
    private(set) var records: [RecoveryStore.Record] = []
    var selectedID: UUID?
    private(set) var text = ""
    private(set) var message: String?
    private(set) var isRetrying = false
    private let store: RecoveryStore
    private let conversationScratch: URL?
    private let transcribe: (URL, Locale?) async throws -> String
    private var task: Task<Void, Never>?
    private var generation = UUID()

    init(store: RecoveryStore = .shared, conversationScratch: URL? = LearningPaths.conversationScratch, transcribe: @escaping (URL, Locale?) async throws -> String = { url, locale in
        try await FileTranscriber.transcribe(fileAt: url, locale: locale).map(\.text).joined(separator: " ")
    }) {
        self.store = store
        self.conversationScratch = conversationScratch
        self.transcribe = transcribe
    }

    func reload() async {
        if let conversationScratch { await store.importConversations(from: conversationScratch) }
        records = await store.records()
        if !records.contains(where: { $0.id == selectedID }) { selectedID = records.first?.id }
        if let id = selectedID { text = await store.transcript(for: id) ?? "" }
        else { text = "" }
    }

    func select(_ id: UUID?) {
        cancelRetry()
        selectedID = id
        text = ""
        message = nil
        Task {
            guard let id else { return }
            let saved = await store.transcript(for: id) ?? ""
            if selectedID == id { text = saved }
        }
    }

    func retry() {
        guard !isRetrying, let id = selectedID, let record = records.first(where: { $0.id == id }) else { return }
        generation = UUID()
        let run = generation
        isRetrying = true
        message = nil
        task = Task {
            do {
                let audio = try await store.audioURL(for: id)
                let recovered = try await transcribe(audio, record.localeIdentifier.map(Locale.init(identifier:)))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                try Task.checkCancellation()
                guard generation == run else { return }
                guard !recovered.isEmpty else { throw RecoveryStore.StoreError.missingAudio }
                try await store.saveTranscript(recovered, for: id)
                guard generation == run else { return }
                text = recovered
                message = String(localized: "Recovered locally. Copy or export the text below.")
            } catch {
                if generation == run, !Task.isCancelled {
                    message = String(localized: "Could not transcribe this recording. Audio is kept; retry or export it.")
                }
            }
            if generation == run { isRetrying = false; task = nil }
        }
    }

    func cancelRetry() {
        generation = UUID()
        task?.cancel()
        task = nil
        isRetrying = false
    }

    func deleteSelected() async {
        guard let id = selectedID else { return }
        cancelRetry()
        do { try await store.delete(id); await reload() }
        catch { message = String(localized: "Could not delete this recording") }
    }

    func exportText(to url: URL) {
        do { try Data(text.utf8).write(to: url, options: .atomic) }
        catch { message = String(localized: "Could not export this text") }
    }

    func exportAudio(to url: URL) async {
        guard let id = selectedID else { return }
        do { try await store.exportAudio(id, to: url) }
        catch { message = String(localized: "Could not export this recording") }
    }
}

@available(macOS 26.0, *)
@MainActor
final class RecoveryWindowController: NSWindowController, NSWindowDelegate {
    private let model: RecoveryModel

    init(model: RecoveryModel? = nil) {
        self.model = model ?? RecoveryModel()
        let hosting = NSHostingController(rootView: RecoveryView(model: self.model))
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "Recover Recordings")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 760, height: 480))
        window.contentMinSize = NSSize(width: 620, height: 380)
        window.center()
        super.init(window: window)
        window.delegate = self
    }
    required init?(coder: NSCoder) { nil }

    func show() {
        Task { await model.reload() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func windowWillClose(_ notification: Notification) { model.cancelRetry() }
}

@available(macOS 26.0, *)
private struct RecoveryView: View {
    @Bindable var model: RecoveryModel

    var body: some View {
        HSplitView {
            List(selection: Binding(get: { model.selectedID }, set: { model.select($0) })) {
                ForEach(model.records) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.source)
                        Text(record.created, format: .dateTime.day().month().hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(record.id)
                }
            }
            .frame(minWidth: 210, idealWidth: 240, maxWidth: 280)
            VStack(alignment: .leading, spacing: 12) {
                Text("Recordings stay on this Mac. Retry uses on-device recognition and never pastes automatically.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Dictation recovery follows your retention setting. Failed conversation audio stays until you delete it.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Retry transcription") { model.retry() }.disabled(model.selectedID == nil || model.isRetrying)
                    if model.isRetrying {
                        ProgressView().controlSize(.small)
                        Button("Cancel") { model.cancelRetry() }
                    }
                }
                HStack {
                    Button("Export audio") {
                        let panel = NSSavePanel()
                        panel.nameFieldStringValue = "Recording.caf"
                        panel.allowedContentTypes = [.audio]
                        if panel.runModal() == .OK, let url = panel.url { Task { await model.exportAudio(to: url) } }
                    }.disabled(model.selectedID == nil)
                    Button("Delete", role: .destructive) { Task { await model.deleteSelected() } }.disabled(model.selectedID == nil)
                }
                if let message = model.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                if model.records.isEmpty {
                    ContentUnavailableView("No recordings to recover", systemImage: "waveform")
                } else {
                    ScrollView { Text(model.text.isEmpty ? String(localized: "Select Retry transcription to recover the text.") : model.text)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    HStack {
                        Button("Copy text") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(model.text, forType: .string)
                        }.disabled(model.text.isEmpty)
                        Button("Export text") {
                            let panel = NSSavePanel()
                            panel.nameFieldStringValue = "Recovered.txt"
                            panel.allowedContentTypes = [.plainText]
                            if panel.runModal() == .OK, let url = panel.url { model.exportText(to: url) }
                        }.disabled(model.text.isEmpty)
                    }
                }
            }.padding(16).frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
#endif
