#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VoiceKit

@available(macOS 26.0, *)
struct VocabularySection: View {
    private let store: VocabularyStore
    init(store: VocabularyStore? = nil) { self.store = store ?? .shared }

    @State private var terms: [String] = []
    @State private var newTerm = ""
    @State private var error: String?

    var body: some View {
        Section("Vocabulary") {
            Text("Names and technical terms with the spelling you want. Matching words get their exact casing locally. Cleanup models also receive spelling hints; this does not change speech recognition.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("Exact spelling", text: $newTerm).onSubmit(add)
                Button("Add", action: add).disabled(newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ForEach(terms, id: \.self) { term in
                HStack {
                    Text(term)
                    Spacer()
                    Button("Remove", role: .destructive) { save(terms.filter { $0 != term }) }
                        .accessibilityLabel("Remove \(term)")
                }
            }
            HStack {
                Button("Import") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.json, .plainText]
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        do {
                            let data = try Data(contentsOf: url)
                            guard data.count <= 64_000 else { throw VocabularyStore.ValidationError.tooLong }
                            let imported = (try? JSONDecoder().decode([String].self, from: data))
                                ?? String(decoding: data, as: UTF8.self).components(separatedBy: .newlines).filter { !$0.isEmpty }
                            save(terms + imported)
                        } catch { self.error = String(localized: "Could not import vocabulary") }
                    }
                }
                Button("Export") {
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.json]
                    panel.nameFieldStringValue = "Vocabulary.json"
                    if panel.runModal() == .OK, let url = panel.url {
                        do { try JSONEncoder().encode(terms).write(to: url, options: .atomic) }
                        catch { self.error = String(localized: "Could not export vocabulary") }
                    }
                }.disabled(terms.isEmpty)
            }
            Text("Up to 64 terms, 80 characters each, and 4,096 characters total.")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
        }.onAppear { terms = store.terms }
    }
    private func add() { if save(terms + [newTerm]) { newTerm = "" } }
    @discardableResult private func save(_ values: [String]) -> Bool {
        do { try store.setTerms(values); terms = store.terms; error = nil; return true }
        catch { self.error = String(localized: "Check vocabulary limits and remove blank or multiline terms"); return false }
    }
}
#endif
