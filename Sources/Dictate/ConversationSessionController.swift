// Conversation capture writes per-source segments. File-relative recognition
// timestamps map through captured spans; failed audio is retained for recovery.
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
    enum State { case idle, starting, recording, transcribing }
    var onStateChange: ((State) -> Void)?
    var onRecoveryNeeded: (() -> Void)?
    private(set) var state: State = .idle
    var isRecording: Bool { state == .recording }

    private final class SourceCapture {
        let source: ConversationSource
        let index: Int
        var mic: MicRecorder?
        var tap: ProcessTapCapture?
        var task: Task<Void, Never>?
        init(source: ConversationSource, index: Int) { self.source = source; self.index = index }
    }
    private var captures: [SourceCapture] = []
    private var events: [(date: Date, text: String)] = []
    private var directory: URL?
    private var manifest = ConversationScratchManifest(localeIdentifier: nil, segments: [])
    private var started = Date()
    private var generation = UUID()

    func toggle() {
        switch state {
        case .idle: start()
        case .recording: stop()
        case .starting, .transcribing: break
        }
    }

    private func start() {
        let sources = Settings.conversationSources.filter(\.enabled)
        guard !sources.isEmpty else { return }
        generation = UUID()
        let run = generation
        let locale = Settings.locale?.identifier
        state = .starting
        onStateChange?(.starting)
        Task {
            await RecoveryStore.shared.importConversationsOnce(from: LearningPaths.conversationScratch)
            guard generation == run, state == .starting else { return }
            let dir = LearningPaths.conversationScratch.appendingPathComponent(UUID().uuidString, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                await RecoveryStore.shared.protectConversation(dir)
                directory = dir
                manifest = ConversationScratchManifest(localeIdentifier: locale, segments: [])
                try saveManifest()
            } catch {
                if let directory { await RecoveryStore.shared.releaseConversation(directory) }
                self.directory = nil
                state = .idle; onStateChange?(.idle); onRecoveryNeeded?(); return
            }
            started = Date()
            events = []
            state = .recording
            onStateChange?(.recording)
            for (index, source) in sources.enumerated() {
                let capture = SourceCapture(source: source, index: index)
                captures.append(capture)
                capture.task = Task { await captureSource(capture, generation: run) }
            }
        }
    }

    private func stop() {
        guard state == .recording, let directory else { return }
        state = .transcribing
        onStateChange?(.transcribing)
        let stopped = captures
        Task {
            // Finish the streams before cancelling reconnect loops; writers drain
            // their bounded queues so the final buffered audio is not thrown away.
            for capture in stopped { capture.mic?.stop(); capture.tap?.stop(); capture.task?.cancel() }
            for capture in stopped { await capture.task?.value }
            let snapshot = manifest
            let outcome = await ConversationFinalizer.finish(directory: directory, manifest: snapshot,
                sources: stopped.map { "\($0.source.name) — \($0.source.reference)" }, started: started, events: events)
            if let transcript = outcome.transcript { NSWorkspace.shared.activateFileViewerSelecting([transcript]) }
            await RecoveryStore.shared.releaseConversation(directory)
            self.directory = nil
            captures = []
            state = .idle
            onStateChange?(.idle)
            if outcome.retainedAudio { onRecoveryNeeded?() }
        }
    }

    private func captureSource(_ capture: SourceCapture, generation run: UUID) async {
        var restarts = 0
        while !Task.isCancelled, generation == run, state == .recording {
            var stream: AsyncStream<CapturedAudioBuffer>?
            do {
                switch capture.source.kind {
                case .microphone:
                    guard let device = AudioInputSelection.deviceID(forUID: capture.source.reference) else {
                        events.append((Date(), "\(capture.source.name): microphone disconnected")); return
                    }
                    let mic = MicRecorder()
                    capture.mic = mic
                    stream = try mic.start(deviceID: device)
                case .app:
                    while !Task.isCancelled, stream == nil, generation == run, state == .recording {
                        if let pid = NSRunningApplication.runningApplications(withBundleIdentifier: capture.source.reference).first?.processIdentifier,
                           ProcessTapCapture.processObject(forPID: pid) != nil {
                            let tap = ProcessTapCapture()
                            capture.tap = tap
                            do { stream = try tap.start(pid: pid) }
                            catch ProcessTapCapture.CaptureError.processNotFound {
                                tap.stop(); capture.tap = nil
                                try? await Task.sleep(for: .seconds(2))
                            }
                        } else { try? await Task.sleep(for: .seconds(2)) }
                    }
                }
            } catch {
                capture.mic?.stop(); capture.tap?.stop()
                events.append((Date(), "\(capture.source.name): capture failed")); return
            }
            guard let stream, let directory, !Task.isCancelled, generation == run, state == .recording else {
                capture.mic?.stop(); capture.tap?.stop(); return
            }
            let segment = ConversationAudioSegment(fileName: "source-\(capture.index)-\(UUID().uuidString).caf", source: capture.source.name)
            manifest.segments.append(segment)
            do { try saveManifest() }
            catch {
                // No journal means a crash would strand this recording. Stop
                // before capturing audio which cannot be discovered later.
                capture.mic?.stop(); capture.tap?.stop()
                events.append((Date(), "\(capture.source.name): could not save the recovery journal")); return
            }
            let writer = ConversationAudioWriter(url: directory.appendingPathComponent(segment.fileName))
            let writerTask = Task { @concurrent in
                var failed = false
                for await packet in stream {
                    do { try await writer.append(packet) }
                    catch { failed = true; break }
                }
                return (await writer.finish(), failed)
            }
            let watchdog = Task {
                var previousTick = ProcessInfo.processInfo.systemUptime
                var wakeUntil: TimeInterval = 0
                while !Task.isCancelled, generation == run, state == .recording {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    let now = ProcessInfo.processInfo.systemUptime
                    if now - previousTick > 5 { wakeUntil = now + 6 }
                    previousTick = now
                    if now < wakeUntil { continue }
                    let silence = capture.mic?.silenceDuration ?? capture.tap?.silenceDuration ?? 0
                    if silence > 6 { capture.mic?.stop(); capture.tap?.stop(); return }
                }
            }
            let (timeline, failed) = await writerTask.value
            watchdog.cancel()
            capture.mic?.stop(); capture.tap?.stop()
            capture.mic = nil; capture.tap = nil
            if let index = manifest.segments.firstIndex(where: { $0.fileName == segment.fileName }) {
                manifest.segments[index].timeline = timeline
                try? saveManifest()
            }
            if failed { events.append((Date(), "\(capture.source.name): audio write failed; captured audio retained")); return }
            guard !Task.isCancelled, generation == run, state == .recording else { return }
            restarts += 1
            events.append((Date(), "\(capture.source.name): capture interrupted"))
            guard restarts <= 3 else { events.append((Date(), "\(capture.source.name): reconnection limit reached")); return }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func saveManifest() throws {
        guard let directory else { return }
        try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("session.json"), options: .atomic)
    }
}

@available(macOS 26.0, *)
private final class MicRecorder {
    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<CapturedAudioBuffer>.Continuation?
    private var tapInstalled = false
    private let delivery = CaptureDeliveryClock()
    var silenceDuration: TimeInterval { delivery.silence }

    func start(deviceID: AudioDeviceID) throws -> AsyncStream<CapturedAudioBuffer> {
        let input = engine.inputNode
        if let unit = input.audioUnit {
            var id = deviceID
            let error = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                            &id, UInt32(MemoryLayout<AudioDeviceID>.size))
            guard error == noErr else { throw RecognitionError.engineStartFailed(NSError(domain: NSOSStatusErrorDomain, code: Int(error))) }
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw RecognitionError.recognitionUnavailable }
        let (stream, continuation) = AsyncStream<CapturedAudioBuffer>.makeStream(bufferingPolicy: .bufferingNewest(64))
        self.continuation = continuation
        let delivery = self.delivery
        delivery.reset()
        do {
            try input.installTapSafely(onBus: 0, bufferSize: 4096, format: format) { buffer, time in
                delivery.beat()
                if let packet = CapturedAudioBuffer.copy(buffer, at: time) { continuation.yield(packet) }
            }
            tapInstalled = true
            try engine.start()
        } catch { stop(); throw error }
        return stream
    }
    func stop() {
        engine.stop()
        if tapInstalled { engine.inputNode.removeTapSafely(onBus: 0); tapInstalled = false }
        continuation?.finish()
        continuation = nil
    }
}
#endif
