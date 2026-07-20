//
//  ConversationSessionController.swift
//  Dictate
//
//  Runs a conversation recording session in two phases: while recording, each
//  enabled source (mic or app tap) just captures raw audio to a temp file —
//  no recognizers running. On stop, each file is transcribed sequentially
//  on-device, merged by wall-clock time into one transcript document, and the
//  audio is deleted. No HUD, no cleanup, no pasting.
//

#if os(macOS)
@preconcurrency import AVFoundation
import AppKit
import CoreAudio
import Foundation
import os
import VoiceKit

@available(macOS 26.0, *)
@MainActor
final class ConversationSessionController {
    private static let log = Logger(subsystem: "Dictate", category: "ConversationSession")

    enum State {
        case idle
        case recording
        case transcribing
    }

    /// Reports state so the menu item and status icon can follow.
    var onStateChange: ((State) -> Void)?
    private(set) var state: State = .idle
    var isRecording: Bool { state == .recording }

    /// One source's capture in flight: where its audio lands and when it started.
    private final class SourceCapture {
        let source: ConversationSource
        let url: URL
        /// Wall-clock time of the first captured sample; segment time = anchor + offset.
        var anchor: Date?
        var mic: MicRecorder?
        var tap: ProcessTapCapture?
        var task: Task<Void, Never>?

        init(source: ConversationSource, url: URL) {
            self.source = source
            self.url = url
        }
    }

    private var captures: [SourceCapture] = []
    private var events: [(date: Date, text: String)] = []
    private var tempDir: URL?
    private var sessionStarted = Date()

    func toggle() {
        switch state {
        case .idle: start()
        case .recording: stop()
        case .transcribing: break
        }
    }

    private func start() {
        let sources = Settings.conversationSources.filter(\.enabled)
        guard !sources.isEmpty else {
            Self.log.error("no enabled conversation sources")
            return
        }
        sessionStarted = Date()
        events = []
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dictate-conversation-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDir = dir
        state = .recording
        onStateChange?(.recording)

        for (index, source) in sources.enumerated() {
            let capture = SourceCapture(source: source, url: dir.appendingPathComponent("source-\(index).caf"))
            captures.append(capture)
            switch source.kind {
            case .microphone:
                startMicrophone(capture)
            case .app:
                capture.task = Task { await self.captureApp(capture) }
            }
        }
    }

    private func stop() {
        guard state == .recording else { return }
        state = .transcribing
        onStateChange?(.transcribing)

        let finished = captures
        let dir = tempDir
        captures = []
        tempDir = nil

        Task {
            // End every capture: mic engines stop, tap streams finish (which ends the
            // file writers), retry loops see the cancel.
            for capture in finished {
                capture.mic?.stop()
                capture.tap?.stop()
                capture.task?.cancel()
            }
            for capture in finished {
                await capture.task?.value
            }

            var descriptions: [String] = []
            for capture in finished {
                descriptions.append(await describe(capture.source))
            }
            let recorder = MultiInputRecorder(sources: descriptions, started: sessionStarted)
            for event in events {
                await recorder.noteEvent(event.text, at: event.date)
            }

            // Sequential on purpose: one analyzer at a time, never N at once.
            for capture in finished {
                guard let anchor = capture.anchor,
                      FileManager.default.fileExists(atPath: capture.url.path) else { continue }
                do {
                    let segments = try await FileTranscriber.transcribe(fileAt: capture.url, locale: Settings.locale)
                    for segment in segments {
                        await recorder.addSegment(
                            speaker: capture.source.name,
                            at: anchor.addingTimeInterval(segment.start ?? 0),
                            text: segment.text
                        )
                    }
                } catch {
                    await recorder.noteEvent(
                        "\(capture.source.name): transcription failed — \(error.localizedDescription)",
                        at: Date()
                    )
                }
            }

            await recorder.finish()
            if let dir { try? FileManager.default.removeItem(at: dir) }
            state = .idle
            onStateChange?(.idle)
        }
    }

    // MARK: - Capture

    private func startMicrophone(_ capture: SourceCapture) {
        guard let deviceID = AudioInputSelection.deviceID(forUID: capture.source.reference) else {
            events.append((Date(), "\(capture.source.name): microphone not connected"))
            return
        }
        let mic = MicRecorder(url: capture.url)
        do {
            try mic.start(deviceID: deviceID)
            capture.mic = mic
            capture.anchor = Date()
        } catch {
            events.append((Date(), "\(capture.source.name): capture failed — \(error.localizedDescription)"))
        }
    }

    private func captureApp(_ capture: SourceCapture) async {
        let tap = ProcessTapCapture()
        capture.tap = tap

        // The HAL only knows processes currently doing audio I/O, so keep trying —
        // "start recording, then join the call" has to work.
        var buffers: AsyncStream<AVAudioPCMBuffer>?
        while !Task.isCancelled, buffers == nil {
            if let pid = runningPID(bundleId: capture.source.reference),
               ProcessTapCapture.processObject(forPID: pid) != nil {
                do {
                    buffers = try tap.start(pid: pid)
                } catch ProcessTapCapture.CaptureError.processNotFound {
                    // Audio stopped between the check and the tap; keep waiting.
                } catch {
                    events.append((Date(), "\(capture.source.name): capture failed — \(error.localizedDescription)"))
                    return
                }
            }
            if buffers == nil {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if Task.isCancelled { return }
            }
        }
        guard let buffers else { return } // session stopped before the app played audio

        // Write off the main actor; buffer cadence can be every few milliseconds.
        let url = capture.url
        let setAnchor: @Sendable @MainActor (Date) -> Void = { capture.anchor = $0 }
        let writer = Task.detached {
            var file: AVAudioFile?
            for await buffer in buffers {
                if file == nil {
                    file = try? AVAudioFile(forWriting: url, settings: buffer.format.settings)
                    await setAnchor(Date())
                }
                try? file?.write(from: buffer)
            }
        }
        await writer.value
    }

    private func runningPID(bundleId: String) -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first?.processIdentifier
    }

    /// Footer description: "Nathan — MacBook Pro Microphone" / "Call — zoom.us".
    private func describe(_ source: ConversationSource) async -> String {
        switch source.kind {
        case .microphone:
            if let id = AudioInputSelection.deviceID(forUID: source.reference),
               let device = await AudioInputSelection.availableDevices().first(where: { $0.id == "\(id)" }) {
                return "\(source.name) — \(device.name)"
            }
            return "\(source.name) — microphone"
        case .app:
            let app = NSRunningApplication.runningApplications(withBundleIdentifier: source.reference).first
            return "\(source.name) — \(app?.localizedName ?? source.reference)"
        }
    }
}

/// Records one microphone to a file: its own engine, pinned to the device, tap
/// writing straight to disk. Capture only — recognition happens after the fact.
@available(macOS 26.0, *)
private final class MicRecorder {
    private let engine = AVAudioEngine()
    private let url: URL
    private var tapInstalled = false

    init(url: URL) {
        self.url = url
    }

    func start(deviceID: AudioDeviceID) throws {
        let inputNode = engine.inputNode

        // Pin the device BEFORE reading the format, same as SpeechRecognitionService —
        // the tap format must match the device we'll actually capture from.
        if let audioUnit = inputNode.audioUnit {
            var id = deviceID
            let err = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &id,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            if err != noErr {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(err),
                              userInfo: [NSLocalizedDescriptionKey: "Failed to set input device"])
            }
        }

        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "MicRecorder", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid audio format"])
        }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            try? file.write(from: buffer)
        }
        tapInstalled = true
        try engine.start()
    }

    func stop() {
        engine.stop()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
    }
}
#endif
