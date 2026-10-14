import AVFoundation
import Foundation
import Testing
import VoiceKit
@testable import Dictate

private actor ReliabilityGate {
    private var waiter: CheckedContinuation<Void, Never>?
    private var open = false
    private(set) var entered = false
    func wait() async {
        entered = true
        if !open { await withCheckedContinuation { waiter = $0 } }
    }
    func release() { open = true; waiter?.resume(); waiter = nil }
}

private struct RecoveryFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var store: RecoveryStore { RecoveryStore(directory: root.appendingPathComponent("recovery")) }
    func audio(_ name: String = "source.caf", date: Date? = nil) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent(name)
        try Data("offline fixture".utf8).write(to: url)
        if let date { try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path) }
        return url
    }
    func clean() { try? FileManager.default.removeItem(at: root) }
}

struct CleanupReliabilityTests {
    @Test func deadlineReturnsWithoutWaitingForUncooperativeOperation() async throws {
        let gate = ReliabilityGate()
        let began = ContinuousClock.now
        do {
            _ = try await CleanupDeadline.run(seconds: 0.03) { await gate.wait(); return "late" }
            Issue.record("Expected deadline")
        } catch { #expect(error is CleanupDeadlineError) }
        #expect(began.duration(to: .now) < .seconds(1))
        await gate.release()
    }

    @Test func parentCancellationWinsAndSuccessfulWorkCancelsTimer() async throws {
        let gate = ReliabilityGate()
        let task = Task { try await CleanupDeadline.run(seconds: 10) { await gate.wait(); return "late" } }
        while !(await gate.entered) { await Task.yield() }
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch { #expect(error is CancellationError) }
        await gate.release()
        #expect(try await CleanupDeadline.run(seconds: 10) { 42 } == 42)
    }

    @Test func providerFailureIsTypedWithoutResponseBodies() async {
        let secret = "a private transcript and key"
        let result = await CleanupChain.run("hello world", chain: [.openAI, .claude, .local]) { _, step, _ in
            switch step {
            case .openAI: throw OpenAICompatibleError.http(429, secret)
            case .claude: throw ClaudeCleanupError.http(401, secret)
            default: throw URLError(.timedOut)
            }
        }
        #expect(result.text == "hello world")
        #expect(result.failureReasons == [.openAI: .rateLimited, .claude: .authentication, .local: .timeout])
        #expect(!OpenAICompatibleError.http(429, secret).localizedDescription.contains(secret))
        #expect(!ClaudeCleanupError.http(401, secret).localizedDescription.contains(secret))
    }

    @Test func officialModelBudgetsDoNotLeakIntoCompatibleServers() throws {
        func body(_ base: String, _ model: String) throws -> [String: Any] {
            let request = try #require(OpenAICompatibleCleanup.makeRequest(text: "short text", baseURL: base, model: model, customInstructions: ""))
            let data = try #require(request.httpBody)
            return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
        let reasoning = try body("https://api.openai.com/v1", "gpt-5")
        #expect(reasoning["max_tokens"] == nil)
        #expect(reasoning["max_completion_tokens"] as? Int == 25_000)
        #expect(reasoning["reasoning_effort"] as? String == "low")
        let plain = try body("https://api.openai.com/v1", "gpt-4.1-mini")
        #expect(plain["max_tokens"] as? Int == 1024)
        #expect(plain["reasoning_effort"] == nil)
        let custom = try body("http://localhost:11434/v1", "gpt-5")
        #expect(custom["max_tokens"] == nil && custom["max_completion_tokens"] == nil && custom["reasoning_effort"] == nil)
        let claude = ClaudeCleanup.makeRequest(text: "hello", apiKey: "fixture", model: "claude-sonnet-4-5", customInstructions: "", maxTokens: 1024)
        let claudeData = try #require(claude.httpBody)
        let payload = try #require(JSONSerialization.jsonObject(with: claudeData) as? [String: Any])
        #expect(payload["output_config"] == nil)
        #expect(payload["max_tokens"] as? Int == 1024)
    }

    @Test func configurationRedactsCredentialsAndEncodesVocabularyAsData() {
        let config = CleanupConfiguration(step: .local, model: "fixture-model", baseURL: "http://localhost:1234", apiKey: "private-key", instructions: "British spelling", vocabulary: ["OpenWhispr", "\"quoted\""])
        #expect(!String(describing: config).contains("private-key"))
        #expect(!String(reflecting: config).contains("private-key"))
        #expect(config.promptInstructions.contains("British spelling"))
        #expect(config.promptInstructions.contains("\\\"quoted\\\""))
    }
}

struct RecoveryStoreTests {
    @Test func registerReloadRetryExportDelete() async throws {
        let fixture = RecoveryFixture(); defer { fixture.clean() }
        let original = try fixture.audio()
        let store = fixture.store
        let record = try await store.register(audio: original, source: "Microphone", locale: Locale(identifier: "nl-NL"), kind: .dictation)
        #expect(!FileManager.default.fileExists(atPath: original.path))
        let reloaded = fixture.store
        #expect(await reloaded.records() == [record])
        try await reloaded.saveTranscript("Recovered text", for: record.id)
        #expect(await reloaded.transcript(for: record.id) == "Recovered text")
        let exported = fixture.root.appendingPathComponent("export.caf")
        try await reloaded.exportAudio(record.id, to: exported)
        #expect(try Data(contentsOf: exported) == Data("offline fixture".utf8))
        try await reloaded.delete(record.id)
        #expect(await reloaded.records().isEmpty)
        await #expect(throws: Error.self) { try await reloaded.saveTranscript("late", for: record.id) }
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("recovery").appendingPathComponent(record.id.uuidString).path))
    }

    @Test func retentionProtectsCurrentAndConversations() async throws {
        let fixture = RecoveryFixture(); defer { fixture.clean() }
        let store = fixture.store
        let now = Date()
        let old = try await store.register(audio: fixture.audio("old.caf", date: now.addingTimeInterval(-200)), source: "Old", locale: nil, kind: .dictation)
        let fresh = try await store.register(audio: fixture.audio("new.caf", date: now), source: "New", locale: nil, kind: .dictation)
        let meeting = try await store.register(audio: fixture.audio("meeting.caf", date: now.addingTimeInterval(-200)), source: "Call", locale: nil, kind: .conversation)
        await store.expireDictations(retention: 100, now: now)
        #expect(Set(await store.records().map(\.id)) == [fresh.id, meeting.id])
        await store.expireDictations(retention: nil, keeping: fresh.id, now: now)
        #expect(Set(await store.records().map(\.id)) == [fresh.id, meeting.id])
        await store.clearDictations()
        #expect(await store.records() == [meeting])
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("recovery").appendingPathComponent(old.id.uuidString).path))
    }

    @Test func failedArchivePreservesOriginalAndRejectsLinks() async throws {
        let fixture = RecoveryFixture(); defer { fixture.clean() }
        let original = try fixture.audio()
        let blocked = try fixture.audio("not-a-directory")
        let store = RecoveryStore(directory: blocked)
        await #expect(throws: Error.self) { try await store.register(audio: original, source: "Call", locale: nil, kind: .conversation) }
        #expect(FileManager.default.fileExists(atPath: original.path))
        let link = fixture.root.appendingPathComponent("link.caf")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        await #expect(throws: Error.self) { try await fixture.store.register(audio: link, source: "Call", locale: nil, kind: .conversation) }
        #expect(FileManager.default.fileExists(atPath: original.path))
    }

    @Test func interruptedImportsDoNotTouchActiveConversation() async throws {
        let fixture = RecoveryFixture(); defer { fixture.clean() }
        let audio = try fixture.audio()
        let manifest = ConversationScratchManifest(localeIdentifier: "en-GB", segments: [.init(fileName: "source.caf", source: "Call")])
        let store = fixture.store
        let scratch = fixture.root.appendingPathComponent("scratch")
        let session = scratch.appendingPathComponent("session")
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        let source = session.appendingPathComponent("source.caf")
        try FileManager.default.moveItem(at: audio, to: source)
        try JSONEncoder().encode(manifest).write(to: session.appendingPathComponent("session.json"))
        await store.protectConversation(session)
        await store.importConversations(from: scratch)
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(await store.records().isEmpty)
        await store.releaseConversation(session)
        await store.importConversations(from: scratch)
        #expect(await store.records().count == 1)
        #expect(await store.records().first?.localeIdentifier == "en-GB")
        #expect(!FileManager.default.fileExists(atPath: session.path))
        try await store.delete(try #require(await store.records().first).id)
    }

    @Test @MainActor func cancelledRetryCannotRecreateDeletedRecording() async throws {
        guard #available(macOS 26.0, *) else { return }
        let fixture = RecoveryFixture(); defer { fixture.clean() }
        let store = fixture.store
        _ = try await store.register(audio: fixture.audio(), source: "Call", locale: nil, kind: .conversation)
        let gate = ReliabilityGate()
        let model = RecoveryModel(store: store, conversationScratch: nil) { _, _ in await gate.wait(); return "late transcript" }
        await model.reload()
        model.retry()
        while !(await gate.entered) { await Task.yield() }
        await model.deleteSelected()
        await gate.release()
        for _ in 0..<100 { await Task.yield() }
        #expect(model.records.isEmpty && model.text.isEmpty && !model.isRetrying)
        #expect(await store.records().isEmpty)
    }
}

struct CaptureReliabilityTests {
    @Test func fileTimestampsMapAcrossCaptureGaps() throws {
        let began = Date(timeIntervalSince1970: 10_000)
        var timeline = CaptureTimeline()
        timeline.append(frames: 48_000, sampleRate: 48_000, capturedAt: began)
        timeline.append(frames: 48_000, sampleRate: 48_000, capturedAt: began.addingTimeInterval(1))
        timeline.append(frames: 48_000, sampleRate: 48_000, capturedAt: began.addingTimeInterval(10))
        #expect(timeline.spans.count == 2 && timeline.duration == 3)
        #expect(timeline.date(at: 1.5) == began.addingTimeInterval(1.5))
        #expect(timeline.date(at: 2.5) == began.addingTimeInterval(10.5))
        #expect(timeline.date(at: .infinity) == began)
        #expect(timeline.date(at: 99) == began.addingTimeInterval(11))
        #expect(try JSONDecoder().decode(CaptureTimeline.self, from: JSONEncoder().encode(timeline)) == timeline)
    }

    @Test func watchdogRebasesAfterSleepAndBoundsTotalRestarts() {
        var watchdog = CaptureWatchdog()
        let observations = [(0.0, 0.0), (100, 100), (101, 101), (103, 3), (104, 0), (105, 3), (106, 3), (107, 3)]
            .map { watchdog.shouldRestart(now: $0.0, silence: $0.1) }
        #expect(observations == [false, false, false, true, false, true, true, false])
        #expect(watchdog.exhausted)
    }

    @Test func conversationWriterConvertsInterleavedInputAndRecordsDuration() async throws {
        let fixture = RecoveryFixture(); defer { fixture.clean() }
        try FileManager.default.createDirectory(at: fixture.root, withIntermediateDirectories: true)
        let url = fixture.root.appendingPathComponent("real.caf")
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: true))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800))
        buffer.frameLength = 4800
        buffer.floatChannelData?[0].initialize(repeating: 0, count: 9600)
        let packet = try #require(CapturedAudioBuffer.copy(buffer, at: AVAudioTime(hostTime: mach_absolute_time())))
        let writer = ConversationAudioWriter(url: url)
        try await writer.append(packet)
        let timeline = await writer.finish()
        let saved = try AVAudioFile(forReading: url)
        #expect(saved.length == 4800)
        #expect(abs(timeline.duration - 0.1) < 0.00001)
        #expect(timeline.spans.count == 1)
        #expect(timeline.spans.first?.capturedAt == packet.capturedAt)
    }

    @Test func finalizerRetainsFailedSourcesAndMapsSuccessfulTiming() async throws {
        guard #available(macOS 26.0, *) else { return }
        let fixture = RecoveryFixture(); defer { fixture.clean() }
        let scratch = fixture.root.appendingPathComponent("session")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        for name in ["good.caf", "bad.caf"] { try Data("audio".utf8).write(to: scratch.appendingPathComponent(name)) }
        let began = Date()
        var timeline = CaptureTimeline()
        timeline.append(frames: 1000, sampleRate: 1000, capturedAt: began)
        timeline.append(frames: 1000, sampleRate: 1000, capturedAt: began.addingTimeInterval(20))
        let manifest = ConversationScratchManifest(localeIdentifier: "nl-NL", segments: [.init(fileName: "good.caf", source: "Good", timeline: timeline), .init(fileName: "bad.caf", source: "Bad")])
        let store = fixture.store
        let outcome = await ConversationFinalizer.finish(directory: scratch, manifest: manifest, sources: ["Good", "Bad"], started: began, events: [], recovery: store, transcriptDirectory: fixture.root.appendingPathComponent("transcripts")) { url, locale in
            #expect(locale?.identifier == "nl-NL")
            if url.lastPathComponent == "bad.caf" { throw URLError(.cannotDecodeContentData) }
            return [.init(text: "hello", isFinal: true, start: 1.5)]
        }
        let transcript = try String(contentsOf: #require(outcome.transcript), encoding: .utf8)
        #expect(transcript.contains("Good:** hello") && transcript.contains("capture gap (19.0 seconds)"))
        #expect(transcript.contains("Bad: transcription incomplete; audio retained"))
        #expect(outcome.retainedAudio)
        #expect(await store.records().map(\.source) == ["Bad"])
        #expect(!FileManager.default.fileExists(atPath: scratch.path))
    }

    @Test func transcriptWriteFailureKeepsEvenSuccessfullyRecognizedAudio() async throws {
        guard #available(macOS 26.0, *) else { return }
        let fixture = RecoveryFixture(); defer { fixture.clean() }
        let scratch = fixture.root.appendingPathComponent("session")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: scratch.appendingPathComponent("source.caf"))
        let blocked = try fixture.audio("blocked-directory")
        let store = fixture.store
        let outcome = await ConversationFinalizer.finish(directory: scratch, manifest: .init(localeIdentifier: nil, segments: [.init(fileName: "source.caf", source: "Call")]), sources: ["Call"], started: Date(), events: [], recovery: store, transcriptDirectory: blocked) { _, _ in [.init(text: "saved words", isFinal: true)] }
        #expect(outcome.transcript == nil && outcome.retainedAudio)
        #expect(await store.records().count == 1)
    }
}
