//
//  SettingInfo.swift
//  Dictate
//
//  The caption line under a control and the "?" that opens the setting's demo.
//  The demo edits a draft, so you can play with a setting without committing to it.
//

#if os(macOS)
import SwiftUI

/// A setting's caption with a trailing info button — the standard row under a control
/// whose effect is easier to show than to describe.
struct SettingCaptionRow<Value: Equatable, Demo: View>: View {
    let caption: String
    let title: String
    let explanation: String
    @Binding var value: Value
    @ViewBuilder let demo: (Binding<Value>) -> Demo

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            SettingInfoButton(title: title, explanation: explanation, value: $value, demo: demo)
        }
    }
}

struct SettingInfoButton<Value: Equatable, Demo: View>: View {
    let title: String
    let explanation: String
    @Binding var value: Value
    @ViewBuilder let demo: (Binding<Value>) -> Demo

    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
        // Without .plain the button's hit area swallows the whole Form row.
        .buttonStyle(.plain)
        .accessibilityLabel(String(format: String(localized: "Learn more about %@"), title))
        .popover(isPresented: $showing, arrowEdge: .trailing) {
            SettingInfoPopover(title: title, explanation: explanation, value: $value, demo: demo)
        }
    }
}

private struct SettingInfoPopover<Value: Equatable, Demo: View>: View {
    private enum Tab: Hashable {
        case demo
        case about
    }

    let title: String
    let explanation: String
    @Binding var value: Value
    @ViewBuilder let demo: (Binding<Value>) -> Demo

    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .demo
    /// What the demo actually edits. Seeded from the live value, written back only on Save.
    @State private var draft: Value

    init(
        title: String,
        explanation: String,
        value: Binding<Value>,
        @ViewBuilder demo: @escaping (Binding<Value>) -> Demo
    ) {
        self.title = title
        self.explanation = explanation
        self._value = value
        self.demo = demo
        self._draft = State(initialValue: value.wrappedValue)
    }

    private var isDirty: Bool { draft != value }

    var body: some View {
        VStack(spacing: 14) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("", selection: $tab) {
                Text("Demo").tag(Tab.demo)
                Text("About").tag(Tab.about)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // Both tabs share a floor so switching between them doesn't resize the popover
            // out from under the pointer.
            Group {
                switch tab {
                case .demo:
                    demo($draft)
                case .about:
                    Text(explanation)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 220, alignment: .top)

            Divider()

            HStack {
                Spacer()
                if isDirty {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Save") {
                        value = draft
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(16)
        .frame(width: 380)
    }
}
#endif
