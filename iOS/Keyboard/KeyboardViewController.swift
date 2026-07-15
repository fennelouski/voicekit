//
//  KeyboardViewController.swift
//  DictateKeyboard
//
//  A dictation-only keyboard. Tap the orb, talk, tap again — the transcript is cleaned
//  locally, polished by Apple Intelligence, and typed into whatever field you were in.
//  Nothing leaves the device.
//
//  Deliberately not a keyboard: no letter rows, no key-styled chrome. The orb is the whole
//  interface; the globe key hands you back to the stock keyboard for typing.
//

import os
import SwiftUI
import UIKit
import VoiceKit

private let log = Logger(subsystem: "com.voicekit.Dictate.keyboard", category: "dictation")

final class KeyboardViewController: UIInputViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let model = KeyboardModel(
            hasFullAccess: hasFullAccess,
            // Only draw our own globe when the system isn't already providing one, or it
            // shows up twice in the bottom-left corner.
            needsSwitchKey: needsInputModeSwitchKey,
            insert: { [unowned self] text in textDocumentProxy.insertText(text) },
            nextKeyboard: { [unowned self] in advanceToNextInputMode() }
        )

        let host = UIHostingController(rootView: KeyboardView(model: model))
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)

        // The system gives an input view no intrinsic height, so name one. High rather than
        // required: the system still owns the final say during rotation.
        let height = view.heightAnchor.constraint(equalToConstant: 240)
        height.priority = .defaultHigh

        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            height,
        ])
        host.didMove(toParent: self)
    }
}

// MARK: - Model

@MainActor
@Observable
final class KeyboardModel {
    /// `starting` exists so the orb can't be tapped twice while the speech model loads —
    /// stopping a session that hasn't started yet is the one race worth designing out.
    enum Phase { case idle, starting, listening, polishing }

    private(set) var phase: Phase = .idle
    private(set) var preview = ""
    private(set) var status: String?
    private(set) var level: Float = 0

    let hasFullAccess: Bool
    let needsSwitchKey: Bool

    private let insert: (String) -> Void
    private let nextKeyboardAction: () -> Void

    private let service = SpeechRecognitionService()
    private var accumulator = TranscriptAccumulator()
    private var transcriptTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?

    init(
        hasFullAccess: Bool,
        needsSwitchKey: Bool,
        insert: @escaping (String) -> Void,
        nextKeyboard: @escaping () -> Void
    ) {
        self.hasFullAccess = hasFullAccess
        self.needsSwitchKey = needsSwitchKey
        self.insert = insert
        self.nextKeyboardAction = nextKeyboard
    }

    func nextKeyboard() { nextKeyboardAction() }

    func toggle() {
        switch phase {
        case .idle: start()
        case .listening: stop()
        case .starting, .polishing: break
        }
    }

    private func start() {
        accumulator.reset()
        preview = ""
        status = nil
        phase = .starting

        Task {
            do {
                let session = try await service.startRecognition()
                transcriptTask = Task { [weak self] in
                    for await result in session.transcript {
                        guard let self else { return }
                        accumulator.add(result)
                        preview = accumulator.preview
                    }
                }
                levelTask = Task { [weak self] in
                    for await value in session.level {
                        self?.level = value
                    }
                    self?.level = 0
                }
                phase = .listening
            } catch {
                phase = .idle
                level = 0
                log.error("startRecognition failed: \(error, privacy: .public)")
                status = Self.message(for: error)
            }
        }
    }

    private func stop() {
        phase = .polishing

        Task {
            await service.stopRecognition()
            // stopRecognition finishes the streams, so this settles the last committed segment.
            await transcriptTask?.value
            transcriptTask = nil
            levelTask = nil
            level = 0

            let raw = accumulator.committed.isEmpty ? accumulator.preview : accumulator.committed
            let output = await DictationPipeline.run(raw: raw) { text in
                try await AICleanup.clean(text)
            }
            if !output.text.isEmpty { insert(output.text) }

            status = output.polishFailed ? "Apple Intelligence unavailable — typed as dictated" : nil
            preview = ""
            phase = .idle
        }
    }

    private static func message(for error: Error) -> String {
        switch error {
        case RecognitionError.notAuthorized:
            return "Open Dictate and allow microphone and speech access"
        case RecognitionError.localeNotSupported:
            return "This language isn't supported on-device"
        case RecognitionError.modelDownloadFailed:
            return "Speech model download failed — open Dictate on Wi-Fi"
        // Surface the underlying reason: a keyboard extension is exactly where an audio
        // session gets refused, and the OS error names why.
        case RecognitionError.engineStartFailed(let underlying):
            return "Couldn't start the microphone — \(underlying.localizedDescription)"
        default:
            return "Couldn't start dictation"
        }
    }
}

// MARK: - View

struct KeyboardView: View {
    let model: KeyboardModel

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 14) {
                statusLine
                Spacer(minLength: 0)
                if model.hasFullAccess {
                    orbButton(reach: geo.size.width)
                } else {
                    fullAccessNotice
                }
                Spacer(minLength: 0)
                if model.needsSwitchKey { globe }
            }
            .padding(.vertical, 14)
            .frame(width: geo.size.width, height: geo.size.height)
            // Keep the ripple's outer rings inside the keyboard instead of bleeding into
            // the text field above.
            .clipped()
        }
    }

    private var statusLine: some View {
        Text(model.status ?? (model.preview.isEmpty ? hint : model.preview))
            .font(.callout)
            .foregroundStyle(model.status != nil ? Color.orange : (model.preview.isEmpty ? Color.secondary : Color.primary))
            // Errors carry the full OS reason; let them wrap and shrink rather than truncate.
            .lineLimit(model.status != nil ? 6 : 2)
            .minimumScaleFactor(0.7)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .center)
            .padding(.horizontal, 16)
    }

    private var hint: String {
        switch model.phase {
        case .idle: return "Tap to dictate"
        case .starting: return "Starting…"
        case .listening: return "Listening… tap to stop"
        case .polishing: return "Polishing with Apple Intelligence…"
        }
    }

    /// Speech RMS rarely clears ~0.4, so the raw level leaves the orb idling near rest.
    /// A square-root gain lifts ordinary talking into the orb's visible swell range.
    private var orbLevel: Float {
        guard model.phase == .listening else { return 0 }
        return min(1, sqrt(model.level) * 1.25)
    }

    private func orbButton(reach: CGFloat) -> some View {
        Button(action: model.toggle) {
            VoiceOrb(level: orbLevel, size: 92)
                .background { OrbRipple(level: orbLevel, reach: reach) }
                .opacity(model.phase == .starting || model.phase == .polishing ? 0.5 : 1)
                .overlay {
                    if model.phase == .starting || model.phase == .polishing {
                        ProgressView().tint(.white)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(model.phase == .starting || model.phase == .polishing)
        .accessibilityLabel(model.phase == .listening ? "Stop dictation" : "Start dictation")
    }

    private var fullAccessNotice: some View {
        Text("Turn on Full Access for Dictate in Settings → General → Keyboard → Keyboards. The mic can't open without it.")
            .font(.footnote)
            .foregroundStyle(Color.orange)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
    }

    private var globe: some View {
        HStack {
            Button(action: model.nextKeyboard) {
                Image(systemName: "globe")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.secondary)
            }
            .accessibilityLabel("Next keyboard")
            Spacer()
        }
        .padding(.horizontal, 24)
    }
}

/// Concentric rings breathing out from behind the orb to the keyboard's edges. Ambient
/// at rest, brighter and further-reaching as you get louder.
///
/// ponytail: continuous animation while the keyboard is up. Cheap (a few strokes), but if
/// battery ever shows up, gate the TimelineView on the listening phase.
struct OrbRipple: View {
    let level: Float
    /// Outer diameter a ring reaches at full travel — pass the keyboard width for edge-to-edge.
    let reach: CGFloat

    private let orbDiameter: CGFloat = 92
    private let ringCount = 4

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<ringCount, id: \.self) { index in
                    let phase = (time * 0.45 + Double(index) / Double(ringCount))
                        .truncatingRemainder(dividingBy: 1)
                    let diameter = orbDiameter + CGFloat(phase) * (reach - orbDiameter)
                    Circle()
                        .strokeBorder(tint, lineWidth: 2)
                        .frame(width: diameter, height: diameter)
                        .opacity((1 - phase) * (0.12 + Double(clampedLevel(level)) * 0.5))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var tint: Color {
        Color(hue: 0.72 + Double(clampedLevel(level)) * 0.16, saturation: 0.85, brightness: 1)
    }
}
