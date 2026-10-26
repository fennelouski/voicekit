import AVFoundation
import Foundation
import Testing
@testable import VoiceKit

private actor PreparationGate {
    private var opened = false
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var entered = false
    func wait() async {
        entered = true
        if opened { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func open() { opened = true; continuation?.resume(); continuation = nil }
}

struct WarmRecognitionTests {
    @Test func preparedResourceIsClaimedOnceAndNextLanguageCannotCancelIt() async throws {
        let cache = WarmPreparation<Int>()
        let gate = PreparationGate()
        let warm = await cache.warm(key: "en") { await gate.wait(); try Task.checkCancellation(); return 7 }
        let claimed = await cache.take(key: "en") { Issue.record("duplicated warm preparation"); return -1 }
        let next = await cache.warm(key: "fr") { 9 }
        await gate.open()
        #expect(try await warm.value == 7)
        #expect(try await claimed.value == 7)
        #expect(try await next.value == 9)
        let newEnglish = await cache.take(key: "en") { 11 }
        #expect(try await newEnglish.value == 11)
    }

    @Test func replacingUnclaimedPreparationCancelsItsLateResult() async throws {
        let cache = WarmPreparation<Int>()
        let gate = PreparationGate()
        let warm = await cache.warm(key: "en") { await gate.wait(); try Task.checkCancellation(); return 7 }
        _ = await cache.warm(key: "fr") { 9 }
        await gate.open()
        await #expect(throws: CancellationError.self) { try await warm.value }
        await cache.invalidate()
    }

    @Test func escapeCanCancelAClaimedColdPreparation() async throws {
        let cache = WarmPreparation<Int>()
        let gate = PreparationGate()
        let claimed = await cache.take(key: "en") { await gate.wait(); try Task.checkCancellation(); return 7 }
        claimed.cancel()
        await gate.open()
        await #expect(throws: CancellationError.self) { try await claimed.value }
    }

    @Test func openingAudioWaitsInOrderAndOverflowIsAnError() async throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        buffer.frameLength = 4
        let queue = RecognitionAudioQueue(capacity: 2)
        for value in [Float(1), Float(2)] {
            buffer.floatChannelData![0][0] = value
            let packet = try #require(CapturedAudioBuffer.copy(buffer, at: AVAudioTime(hostTime: mach_absolute_time())))
            #expect(queue.append(packet))
        }
        buffer.floatChannelData![0][0] = 99
        queue.continuation.finish()
        var values: [Float] = []
        for try await packet in queue.stream { values.append(packet.buffer.floatChannelData![0][0]) }
        #expect(values == [1, 2])

        let bounded = RecognitionAudioQueue(capacity: 1)
        let packet = try #require(CapturedAudioBuffer.copy(buffer, at: AVAudioTime(hostTime: mach_absolute_time())))
        #expect(bounded.append(packet))
        #expect(!bounded.append(packet))
        await #expect(throws: RecognitionError.self) {
            for try await _ in bounded.stream {}
        }
    }

    @Test func metricsTrackFirstBufferOnceAndFailureWithoutPayloads() throws {
        let metrics = RecognitionMetrics()
        metrics.audioArrived()
        let first = try #require(metrics.snapshot.firstBufferAt)
        metrics.audioArrived()
        metrics.analyzerReady()
        metrics.finalResult()
        metrics.fail()
        #expect(metrics.snapshot.firstBufferAt == first)
        #expect(metrics.snapshot.analyzerReadyAt! >= first)
        #expect(metrics.snapshot.pipelineFailed)
    }
}
