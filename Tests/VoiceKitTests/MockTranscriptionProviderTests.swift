//
//  MockTranscriptionProviderTests.swift
//  VoiceKitTests
//
//  Tests for MockTranscriptionProvider.
//

import Testing
@testable import VoiceKit

struct MockTranscriptionProviderTests {

    @Test func yieldsControlledSegments() async throws {
        let mock = MockTranscriptionProvider()
        let stream = try await mock.startTranscription(locale: nil)

        // Feed segments from another task
        Task {
            await mock.yield(TranscriptionResult(text: "Hello", isFinal: false))
            await mock.yield(TranscriptionResult(text: "Hello world", isFinal: true))
            await mock.finish()
        }

        var results: [TranscriptionResult] = []
        for await result in stream {
            results.append(result)
        }

        #expect(results.count == 2)
        #expect(results[0].text == "Hello")
        #expect(results[0].isFinal == false)
        #expect(results[1].text == "Hello world")
        #expect(results[1].isFinal == true)
    }

    @Test func stopTranscriptionFinishesStream() async throws {
        let mock = MockTranscriptionProvider()
        let stream = try await mock.startTranscription(locale: nil)

        Task {
            await mock.yield(TranscriptionResult(text: "test", isFinal: false))
            await mock.stopTranscription()
        }

        var count = 0
        for await _ in stream {
            count += 1
        }

        #expect(count == 1)
    }

    @Test func activeTracking() async throws {
        let mock = MockTranscriptionProvider()
        let isActiveBefore = await mock.active
        #expect(isActiveBefore == false)

        _ = try await mock.startTranscription(locale: nil)
        let isActiveDuring = await mock.active
        #expect(isActiveDuring == true)

        await mock.stopTranscription()
        let isActiveAfter = await mock.active
        #expect(isActiveAfter == false)
    }
}
