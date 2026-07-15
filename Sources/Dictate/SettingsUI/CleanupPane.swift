//
//  CleanupPane.swift
//  Dictate
//
//  Cleanup is an ordered chain of attempts, not one choice. Reorder the steps, and the first
//  one that works cleans your text. Each provider in the chain gets its own config section.
//

#if os(macOS)
import SwiftUI
import VoiceKit

@available(macOS 26.0, *)
struct CleanupPane: View {
    @AppStorage(Settings.cleanupChainKey) private var chainRaw = Settings.encodeChain(Settings.cleanupChain)
    @AppStorage(Settings.cleanupInstructionsKey) private var cleanupInstructions = ""

    private var chain: [CleanupMode] { Settings.decodeChain(chainRaw) }

    /// Steps not already in the chain — you can't queue the same provider twice.
    private var unused: [CleanupMode] {
        CleanupMode.chainable.filter { !chain.contains($0) }
    }

    var body: some View {
        Form {
            Section {
                if chain.isEmpty {
                    Text("Cleanup is off. Filler words are still removed — that costs nothing and never needs a model.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(chain.enumerated()), id: \.element) { index, step in
                    stepRow(step, at: index)
                }

                if !unused.isEmpty {
                    Menu {
                        ForEach(unused) { step in
                            Button(step.chainName) { append(step) }
                        }
                    } label: {
                        Label("Add a step", systemImage: "plus")
                    }
                    .fixedSize()
                }

                SettingCaptionRow(
                    caption: String(localized: "Tried top to bottom. The first step that works cleans your text."),
                    title: String(localized: "Cleanup Chain"),
                    explanation: String(localized: """
                        Cleanup punctuates, capitalizes, and resolves the false starts you make \
                        when you change your mind mid-sentence. ("Um" and "uh" are stripped no \
                        matter what — that costs nothing and never needs a model.)

                        Out of the box this is just Apple Intelligence: free, on-device, no key, \
                        nothing leaves your Mac.

                        Each step is tried in order, and the first one that works wins. A step \
                        with no API key isn't an error — it simply isn't the step that cleans \
                        your text, and Dictate moves on to the next one.

                        Add a cloud provider and it goes *above* Apple Intelligence, because the \
                        on-device pass almost always succeeds — anything underneath it would \
                        never get a turn. So the ones you add are tried first, and on-device \
                        catches whatever they missed.

                        You only ever see "cleanup failed" if *every* step failed — and even then \
                        your transcript is inserted unchanged rather than lost.
                        """),
                    value: Binding(get: { chain }, set: { chainRaw = Settings.encodeChain($0) })
                ) { CleanupChainDemo(chain: $0) }
            } header: {
                SettingsLabel(String(localized: "Cleanup Chain"), systemImage: "wand.and.sparkles", tint: SettingsTint.cleanup)
            }

            // One config block per provider actually in the chain, in the order they run.
            ForEach(chain.compactMap(\.provider)) { provider in
                ProviderConfigSection(provider: provider)
            }

            if chain.contains(.onDevice) {
                Section {
                    Text(AICleanup.isAvailable
                         ? String(localized: "Polishes punctuation and removes false starts, entirely on this Mac. Free, and needs no key.")
                         : String(localized: "Apple Intelligence isn't available on this Mac, so this step will always be skipped."))
                        .font(.caption)
                        .foregroundStyle(AICleanup.isAvailable ? Color.secondary : Color.orange)
                } header: {
                    SettingsLabel(String(localized: "Apple Intelligence"), systemImage: "apple.logo", tint: SettingsTint.cleanup)
                }
            }

            if !chain.isEmpty {
                Section {
                    TextField("Custom instructions (optional)", text: $cleanupInstructions, axis: .vertical)
                        .lineLimit(2...5)
                    Text("Applied by whichever step ends up cleaning your text — \"use British spelling\", \"keep my bullet points\", and so on.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    SettingsLabel(String(localized: "Instructions"), systemImage: "text.quote", tint: SettingsTint.cleanup)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func stepRow(_ step: CleanupMode, at index: Int) -> some View {
        HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 12, alignment: .trailing)

            SettingsLabel(step.chainName, systemImage: step.systemImage, tint: SettingsTint.cleanup)

            if let warning = warning(for: step) {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer(minLength: 8)

            Button { move(from: index, to: index - 1) } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(index == 0)

            Button { move(from: index, to: index + 1) } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(index == chain.count - 1)

            Button { remove(step) } label: {
                Image(systemName: "minus.circle")
            }
            .foregroundStyle(.red)
        }
        .buttonStyle(.borderless)
    }

    /// Say up front which steps will be skipped, rather than letting them fail silently.
    private func warning(for step: CleanupMode) -> String? {
        switch step {
        case .onDevice:
            return AICleanup.isAvailable ? nil : String(localized: "unavailable")
        case .local:
            return Settings.model(for: .local).isEmpty ? String(localized: "no model set") : nil
        default:
            guard let provider = step.provider else { return nil }
            let key = Settings.apiKey(for: provider) ?? ""
            return key.isEmpty ? String(localized: "no key — will be skipped") : nil
        }
    }

    private func move(from: Int, to: Int) {
        var updated = chain
        guard updated.indices.contains(from), updated.indices.contains(to) else { return }
        let step = updated.remove(at: from)
        updated.insert(step, at: to)
        chainRaw = Settings.encodeChain(updated)
    }

    private func append(_ step: CleanupMode) {
        chainRaw = Settings.encodeChain(CleanupChain.adding(step, to: chain))
    }

    private func remove(_ step: CleanupMode) {
        chainRaw = Settings.encodeChain(chain.filter { $0 != step })
    }
}

/// One provider's key, model, and connection test. Owns its own state so several can sit on
/// the same screen without stepping on each other.
@available(macOS 26.0, *)
private struct ProviderConfigSection: View {
    let provider: AIProvider

    @AppStorage(Settings.localModelBaseURLKey) private var localBaseURL = "http://localhost:11434/v1"

    @State private var apiKey = ""
    @State private var model = ""
    @State private var test = TestState.idle

    private enum TestState {
        case idle
        case testing
        case success
        case failure(String)
    }

    var body: some View {
        Section {
            if provider.requiresKey {
                SecureField("API key", text: $apiKey)
                    .onChange(of: apiKey) { _, newValue in
                        KeychainStore.set(newValue, forKey: provider.keychainAccount)
                        test = .idle
                    }

                if let keyURL = provider.keyURL {
                    Link("Get a \(provider.displayName) key", destination: keyURL)
                        .font(.caption)
                }
            }

            if provider.editableBaseURL {
                TextField("Server URL", text: $localBaseURL, prompt: Text(provider.baseURL))
                    .onChange(of: localBaseURL) { _, _ in test = .idle }
            }

            if provider == .claude {
                // The one provider whose model IDs we pin, so it gets a real list.
                Picker("Model", selection: $model) {
                    ForEach(ClaudeModel.allCases) { model in
                        Text(model.displayName).tag(model.rawValue)
                    }
                }
                .onChange(of: model) { _, newValue in save(newValue) }
            } else {
                TextField("Model", text: $model, prompt: Text(provider.modelPrompt))
                    .onChange(of: model) { _, newValue in
                        save(newValue)
                        test = .idle
                    }
                Text("Model IDs change often — type whichever one you want to use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            testRow

            Text(provider.privacyNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            SettingsLabel(
                provider.displayName.capitalized,
                systemImage: provider.editableBaseURL ? "desktopcomputer" : "cloud",
                tint: SettingsTint.cleanup
            )
        }
        .task {
            apiKey = Settings.apiKey(for: provider) ?? ""
            model = Settings.model(for: provider)
        }
    }

    private var isTesting: Bool {
        if case .testing = test { return true }
        return false
    }

    private var configured: Bool {
        let hasModel = !model.trimmingCharacters(in: .whitespaces).isEmpty
        return provider.requiresKey ? hasModel && !apiKey.isEmpty : hasModel
    }

    @ViewBuilder
    private var testRow: some View {
        HStack {
            Button(provider.requiresKey ? String(localized: "Test key") : String(localized: "Test connection")) { runTest() }
                .disabled(!configured || isTesting)
            switch test {
            case .idle:
                EmptyView()
            case .testing:
                ProgressView()
                    .controlSize(.small)
            case .success:
                Label("It works", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failure(let message):
                Label(message, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }

    private func save(_ value: String) {
        UserDefaults.standard.set(value, forKey: Settings.modelKey(for: provider))
    }

    private func runTest() {
        test = .testing
        Task {
            do {
                _ = try await CleanupService.clean("Um, so this is, uh, a test.", provider: provider)
                test = .success
            } catch {
                test = .failure(error.localizedDescription)
            }
        }
    }
}
#endif
