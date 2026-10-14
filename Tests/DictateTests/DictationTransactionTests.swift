import Foundation
import Testing
import VoiceKit
@testable import Dictate

/// Gates intentionally ignore task cancellation, modelling a provider or cold
/// start that returns late. Tests release every gate before they finish.
private actor TransactionGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var entered = false
    private var opened = false

    func wait() async {
        entered = true
        if opened { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        opened = true
        continuation?.resume()
        continuation = nil
    }
}

@available(macOS 26.0, *)
private actor TransactionRecognition: DictationRecognition {
    var startGate: TransactionGate?
    var stopGate: TransactionGate?
    var backup: URL?
    var text = "hello there"
    private var transcript: AsyncStream<TranscriptionResult>.Continuation?
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var cancels = 0

    init(startGate: TransactionGate? = nil, stopGate: TransactionGate? = nil, backup: URL? = nil, text: String = "hello there") {
        self.startGate = startGate
        self.stopGate = stopGate
        self.backup = backup
        self.text = text
    }

    func startRecognition(locale: Locale?, inputDeviceID: UInt32?, backupDirectory: URL?) async throws -> RecognitionSession {
        starts += 1
        await startGate?.wait()
        let (stream, continuation) = AsyncStream<TranscriptionResult>.makeStream()
        transcript = continuation
        return RecognitionSession(transcript: stream, level: AsyncStream { $0.finish() },
                                  audioBuffers: AsyncStream { $0.finish() }, backupURL: backup)
    }

    func stopRecognition() async -> URL? {
        stops += 1
        await stopGate?.wait()
        if !text.isEmpty { transcript?.yield(.init(text: text, isFinal: true)) }
        transcript?.finish()
        return backup
    }

    func cancelRecognition() async -> URL? {
        cancels += 1
        transcript?.finish()
        return backup
    }

    func silenceDuration() -> TimeInterval { 0 }
    func restartCapture() -> Bool { true }
}

@MainActor
private final class TransactionHUD: DictationHUD {
    var listening = false
    var events: [String] = []
    func show() { events.append("show") }
    func hide() { listening = false; events.append("hide") }
    func update(text: String) { events.append("text") }
    func update(level: Float) {}
    func setLocked(_ locked: Bool) {}
    func setProcessing() { listening = false; events.append("processing") }
    func setListening() { listening = true; events.append("listening") }
    func showError(_ message: String) { events.append(message) }
}

@available(macOS 26.0, *)
@MainActor
private final class TransactionHarness {
    let recognition: TransactionRecognition
    let hud = TransactionHUD()
    var options = DictationOptions(chain: [.local])
    var focusedProcess: Int32 = 100
    var focusedField = "original field"
    var focusedWindow = "original window"
    var pasted: [(String, Int32)] = []
    var copied: [String] = []
    var history: [String] = []
    var completed = 0

    init(recognition: TransactionRecognition = TransactionRecognition()) { self.recognition = recognition }

    func controller(
        cleanup: @escaping (String, CleanupMode, [Correction]) async throws -> String = { text, _, _ in text },
        recover: @escaping (URL, Locale?) async -> String? = { _, _ in nil },
        prepareInsertion: @escaping @MainActor () async throws -> Void = {}
    ) -> DictationController {
        DictationController(
            service: recognition, hud: hud, captureOptions: { self.options },
            captureDestination: {
                let pid = self.focusedProcess
                let field = self.focusedField
                let window = self.focusedWindow
                return InsertionDestination(processID: pid, applicationName: "Test editor") {
                    self.focusedProcess == pid && self.focusedField == field && self.focusedWindow == window
                }
            },
            prepareInsertion: prepareInsertion, insert: { text, destination in
                InsertionGate.insert(text, into: destination, copy: { self.copied.append($0) }, paste: {
                    self.pasted.append(($0, $1)); return true
                })
            }, runStep: cleanup, recover: recover,
            saveHistory: { self.history.append($0.text) }, recordCompleted: { self.completed += 1 },
            recoveryStore: nil, sweepRecovery: { _ in }
        )
    }
}

@MainActor
struct DictationTransactionTests {
    private func eventually(_ predicate: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !(await predicate()), ContinuousClock.now < deadline { await Task.yield() }
        #expect(await predicate(), "transaction did not settle")
        try #require(await predicate())
    }

    @Test(arguments: ["application", "field", "window"])
    func slowCleanupCannotPasteIntoAChangedDestination(_ change: String) async throws {
        guard #available(macOS 26.0, *) else { return }
        let gate = TransactionGate()
        let harness = TransactionHarness()
        let controller = harness.controller { text, _, _ in await gate.wait(); return text }
        controller.toggleManual()
        try await eventually { harness.hud.listening }
        controller.toggleManual()
        try await eventually { await gate.entered }
        switch change {
        case "application": harness.focusedProcess = 200
        case "field": harness.focusedField = "another field"
        default: harness.focusedWindow = "another window"
        }
        await gate.open()
        try await eventually { !controller.hasCancellableWork }
        #expect(harness.pasted.isEmpty)
        #expect(harness.copied == ["hello there "])
        #expect(harness.history == ["hello there"])
        #expect(harness.hud.events.contains { $0.contains("Focus changed") })
    }

    @Test func sameDestinationPastesOnceToTheCapturedProcess() async throws {
        guard #available(macOS 26.0, *) else { return }
        let harness = TransactionHarness()
        let controller = harness.controller()
        controller.toggleManual()
        try await eventually { harness.hud.listening }
        controller.toggleManual()
        try await eventually { !controller.hasCancellableWork }
        #expect(harness.pasted.count == 1)
        #expect(harness.pasted.first?.0 == "hello there ")
        #expect(harness.pasted.first?.1 == 100)
        #expect(harness.copied.isEmpty)
    }

    @Test func escapeDuringColdStartClosesTheLateSessionAndKeepsStartsExclusive() async throws {
        guard #available(macOS 26.0, *) else { return }
        let gate = TransactionGate()
        let recognition = TransactionRecognition(startGate: gate)
        let harness = TransactionHarness(recognition: recognition)
        let controller = harness.controller()
        controller.toggleManual()
        try await eventually { await gate.entered }
        #expect(controller.cancel())
        controller.hotkeyDown()
        #expect(await recognition.starts == 1)
        await gate.open()
        try await eventually { !controller.isCapturing }
        #expect(await recognition.cancels == 1)
        #expect(!harness.hud.events.contains("listening"))
        #expect(harness.history.isEmpty && harness.pasted.isEmpty && harness.copied.isEmpty)
        #expect(!controller.cancel())
    }

    @Test func escapeDuringRecordingStopsCaptureAndDeletesTheCancelledAudio() async throws {
        guard #available(macOS 26.0, *) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("audio".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let recognition = TransactionRecognition(backup: url)
        let harness = TransactionHarness(recognition: recognition)
        let controller = harness.controller()
        controller.toggleManual()
        try await eventually { harness.hud.listening }
        #expect(controller.cancel())
        try await eventually { !controller.isCapturing }
        #expect(await recognition.cancels == 1)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(harness.history.isEmpty && harness.pasted.isEmpty && harness.copied.isEmpty)
        #expect(harness.completed == 0)
    }

    @Test func escapeDuringFinalizationDropsTheLateFinalTranscript() async throws {
        guard #available(macOS 26.0, *) else { return }
        let gate = TransactionGate()
        let harness = TransactionHarness(recognition: TransactionRecognition(stopGate: gate))
        let controller = harness.controller()
        controller.toggleManual()
        try await eventually { harness.hud.listening }
        controller.toggleManual()
        try await eventually { await gate.entered }
        #expect(controller.cancel())
        await gate.open()
        try await eventually { !controller.isCapturing }
        #expect(harness.pasted.isEmpty && harness.copied.isEmpty && harness.history.isEmpty)
        #expect(harness.completed == 0)
    }

    @Test func escapeCancelsTheEntireBacklogAndAProviderReturningLateCannotBlockANewDictation() async throws {
        guard #available(macOS 26.0, *) else { return }
        let gate = TransactionGate()
        let harness = TransactionHarness()
        let controller = harness.controller { text, _, _ in await gate.wait(); return text }
        controller.toggleManual()
        try await eventually { harness.hud.listening }
        controller.toggleManual()
        try await eventually { await gate.entered }
        controller.toggleManual()
        try await eventually { harness.hud.listening }
        controller.toggleManual()
        try await eventually { !controller.isCapturing }
        #expect(controller.cancel())

        // The new transaction bypasses the retired queue even though the first
        // provider still hasn't cooperated. It does no AI work in this fixture.
        harness.options.chain = []
        controller.toggleManual()
        try await eventually { harness.hud.listening }
        controller.toggleManual()
        try await eventually { harness.pasted.count == 1 }
        let settledEvents = harness.hud.events
        await gate.open()
        // Await both old jobs' completion, not just the cancellation flag.
        try await eventually { !controller.hasOutstandingWork }
        #expect(harness.pasted.count == 1)
        #expect(harness.history.count == 1)
        #expect(harness.completed == 1)
        #expect(harness.copied.isEmpty)
        #expect(harness.hud.events == settledEvents)
    }

    @Test func escapeDuringRecoveryDiscardsItsLateResultAndDeletesItsFile() async throws {
        guard #available(macOS 26.0, *) else { return }
        let gate = TransactionGate()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("audio".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let harness = TransactionHarness(recognition: TransactionRecognition(backup: url, text: ""))
        let controller = harness.controller(recover: { _, _ in await gate.wait(); return "recovered words" })
        controller.toggleManual()
        try await eventually { harness.hud.listening }
        controller.toggleManual()
        try await eventually { await gate.entered }
        #expect(controller.cancel())
        await gate.open()
        try await eventually { !FileManager.default.fileExists(atPath: url.path) }
        #expect(harness.pasted.isEmpty && harness.copied.isEmpty && harness.history.isEmpty)
    }
}

@MainActor
struct InsertionGateTests {
    @Test func anUnverifiableTargetOrAPasteFailureLeavesTextForManualPaste() {
        var copies: [String] = []
        var pasteAttempts = 0
        let missing = InsertionGate.insert("hello", into: nil, copy: { copies.append($0) }, paste: { _, _ in
            pasteAttempts += 1; return true
        })
        #expect(missing == .copiedBecauseDestinationUnknown)
        #expect(pasteAttempts == 0)
        let target = InsertionDestination(processID: 100, applicationName: "editor", matchesFocus: { true })
        let failed = InsertionGate.insert("world", into: target, copy: { copies.append($0) }, paste: { _, _ in false })
        #expect(failed == .copiedBecausePasteUnavailable)
        #expect(copies == ["hello", "world"])
    }
}

struct EscapeKeyGateTests {
    @Test func idleEscapePassesThroughAndHeldEscapeCannotCancelTheNextRecording() {
        var gate = EscapeKeyGate()
        var cancelled = 0
        let handled1 = gate.handle(keyDown: true, isRepeat: false, cancel: { false })
        #expect(!handled1)
        let handled2 = gate.handle(keyDown: true, isRepeat: false, cancel: { cancelled += 1; return true })
        #expect(handled2)
        let handled3 = gate.handle(keyDown: true, isRepeat: true, cancel: { cancelled += 1; return true })
        #expect(handled3)
        #expect(cancelled == 1)
        let handled4 = gate.handle(keyDown: false, isRepeat: false, cancel: { false })
        #expect(handled4)
        let handled5 = gate.handle(keyDown: true, isRepeat: true, cancel: { cancelled += 1; return true })
        #expect(!handled5)
        #expect(cancelled == 1)
        let handled6 = gate.handle(keyDown: true, isRepeat: false, cancel: { cancelled += 1; return true })
        #expect(handled6)
        #expect(cancelled == 2)
    }
}

private actor CancellationStepLog {
    private(set) var steps: [CleanupMode] = []
    func append(_ step: CleanupMode) { steps.append(step) }
}

struct CleanupCancellationTests {
    @Test func cancellingAnInFlightStepNeverCallsTheFallback() async throws {
        let log = CancellationStepLog()
        let task = Task {
            await CleanupChain.run("hello there", chain: [.local, .onDevice]) { text, step, _ in
                await log.append(step)
                try await Task.sleep(for: .seconds(60))
                return text
            }
        }
        let deadline = ContinuousClock.now + .seconds(3)
        while await log.steps.isEmpty, ContinuousClock.now < deadline { await Task.yield() }
        task.cancel()
        let result = await task.value
        #expect(result.isCancelled)
        #expect(!result.allFailed)
        #expect(result.usedStep == nil)
        #expect(await log.steps == [.local])
    }

    @Test func aCancellationErrorFromAStepIsNotTreatedAsAnOrdinaryProviderFailure() async {
        let log = CancellationStepLog()
        let result = await CleanupChain.run("hello there", chain: [.local, .onDevice]) { _, step, _ in
            await log.append(step)
            throw CancellationError()
        }
        #expect(result.isCancelled)
        #expect(!result.allFailed)
        #expect(result.failed.isEmpty)
        #expect(await log.steps == [.local])
    }
}

@MainActor
struct DictationDeadlineTests {
    private func eventually(_ predicate: () async -> Bool) async throws {
        let limit = ContinuousClock.now + .seconds(3)
        while !(await predicate()), ContinuousClock.now < limit { await Task.yield() }
        #expect(await predicate())
        try #require(await predicate())
    }

    @Test func slowNoncooperativeCleanupFallsBackOnceAtTotalDeadline() async throws {
        guard #available(macOS 26.0, *) else { return }
        let gate = TransactionGate()
        let harness = TransactionHarness()
        harness.options.cleanupDeadline = 0.03
        let controller = harness.controller { text, _, _ in await gate.wait(); return text.uppercased() }
        controller.toggleManual()
        try await eventually { harness.hud.listening }
        controller.toggleManual()
        try await eventually { !controller.hasCancellableWork }
        #expect(harness.pasted.map(\.0) == ["hello there "])
        #expect(harness.history == ["hello there"])
        await gate.open()
        for _ in 0..<100 { await Task.yield() }
        #expect(harness.pasted.count == 1)
    }

    @Test func focusIsRecheckedAfterWaitingForPreviousPaste() async throws {
        guard #available(macOS 26.0, *) else { return }
        let gate = TransactionGate()
        let harness = TransactionHarness()
        let controller = harness.controller(prepareInsertion: { await gate.wait() })
        controller.toggleManual()
        try await eventually { harness.hud.listening }
        controller.toggleManual()
        try await eventually { await gate.entered }
        harness.focusedField = "another field"
        await gate.open()
        try await eventually { !controller.hasCancellableWork }
        #expect(harness.pasted.isEmpty)
        #expect(harness.copied == ["hello there "])
    }

    @Test func escapeWhilePasteWaitsDropsHistoryAndLateCommit() async throws {
        guard #available(macOS 26.0, *) else { return }
        let gate = TransactionGate()
        let harness = TransactionHarness()
        let controller = harness.controller(prepareInsertion: { await gate.wait() })
        controller.toggleManual()
        try await eventually { harness.hud.listening }
        controller.toggleManual()
        try await eventually { await gate.entered }
        #expect(controller.cancel())
        await gate.open()
        try await eventually { !controller.hasOutstandingWork }
        #expect(harness.pasted.isEmpty && harness.copied.isEmpty && harness.history.isEmpty)
    }
}
