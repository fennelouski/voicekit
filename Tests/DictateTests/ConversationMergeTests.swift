//
//  ConversationMergeTests.swift
//  DictateTests
//
//  The merge logic behind conversation recording: segments from several named
//  sources ordered by timestamp, events inline, and the multi-source footer.
//

import Foundation
import Testing
@testable import Dictate

struct ConversationMergeTests {
    private let utc = TimeZone(identifier: "UTC")!
    private let base = Date(timeIntervalSince1970: 1_752_860_000) // fixed instant

    private func entry(_ speaker: String?, _ offset: TimeInterval, _ text: String) -> ConversationMerge.Entry {
        .init(speaker: speaker, date: base.addingTimeInterval(offset), text: text)
    }

    @Test func rendersInTimestampOrderAcrossSources() {
        // Arrival order is per-source; the render must interleave by time.
        let rendered = ConversationMerge.render([
            entry("Nathan", 0, "first"),
            entry("Nathan", 10, "third"),
            entry("Wife", 5, "second"),
            entry("Zoom call", 15, "fourth"),
        ], timeZone: utc)

        let positions = ["first", "second", "third", "fourth"].compactMap { rendered.range(of: $0)?.lowerBound }
        #expect(positions == positions.sorted())
        #expect(rendered.contains("**[17:33:20] Nathan:** first"))
        #expect(rendered.contains("**[17:33:25] Wife:** second"))
    }

    @Test func sameInstantKeepsArrivalOrder() {
        let rendered = ConversationMerge.render([
            entry("A", 0, "alpha"),
            entry("B", 0, "beta"),
        ], timeZone: utc)
        let a = rendered.range(of: "alpha")!.lowerBound
        let b = rendered.range(of: "beta")!.lowerBound
        #expect(a < b)
    }

    @Test func eventsRenderInlineWithoutSpeaker() {
        let rendered = ConversationMerge.render([
            entry("Nathan", 0, "hello"),
            entry(nil, 5, "Zoom call: capture failed — no audio"),
            entry("Nathan", 10, "goodbye"),
        ], timeZone: utc)
        #expect(rendered.contains("*[17:33:25] Zoom call: capture failed — no audio*"))
        let event = rendered.range(of: "capture failed")!.lowerBound
        #expect(rendered.range(of: "hello")!.lowerBound < event)
        #expect(event < rendered.range(of: "goodbye")!.lowerBound)
    }

    @Test func footerListsEverySource() {
        let started = base
        let stopped = base.addingTimeInterval(3723)
        let footer = TranscriptFooter.render(
            sources: ["Nathan — MacBook Pro Microphone", "Call — zoom.us"],
            started: started, stopped: stopped, timeZone: utc
        )
        #expect(footer.contains("- **Source:** Nathan — MacBook Pro Microphone"))
        #expect(footer.contains("- **Source:** Call — zoom.us"))
        #expect(footer.contains("- **Duration:** 1h 02m 03s"))
    }

    @Test func footerWhileStillRecording() {
        let footer = TranscriptFooter.render(sources: ["Me — Built-in"], started: base, stopped: nil, timeZone: utc)
        #expect(footer.contains("- **Stopped:** still recording"))
        #expect(!footer.contains("Duration"))
    }

    @Test func recorderWritesMergedDocument() async throws {
        guard #available(macOS 26.0, *) else { return }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dictate-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let recorder = MultiInputRecorder(directory: dir, sources: ["Me — Built-in", "Guest — USB"])
        await recorder.addSegment(speaker: "Guest", at: base.addingTimeInterval(5), text: "responding")
        await recorder.addSegment(speaker: "Me", at: base, text: "opening line")
        await recorder.finish()

        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        #expect(files.count == 1)
        #expect(files[0].lastPathComponent.hasPrefix("Conversation "))
        let contents = try String(contentsOf: files[0], encoding: .utf8)
        // Later arrival, earlier timestamp: "opening line" must render first.
        #expect(contents.range(of: "opening line")!.lowerBound < contents.range(of: "responding")!.lowerBound)
        #expect(contents.contains("- **Source:** Me — Built-in"))
        #expect(contents.contains("- **Source:** Guest — USB"))
    }
}

// Serialized: both tests mutate the same UserDefaults key.
@Suite(.serialized)
struct ConversationSourceTests {
    @Test func rosterRoundTripsThroughSettings() {
        let key = Settings.conversationSourcesKey
        let saved = UserDefaults.standard.string(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }

        let roster = [
            ConversationSource(kind: .microphone, reference: "uid-123", name: "Nathan"),
            ConversationSource(kind: .app, reference: "us.zoom.xos", name: "Call", enabled: false),
        ]
        Settings.saveConversationSources(roster)
        #expect(Settings.conversationSources == roster)
    }

    @Test func corruptRosterReadsAsEmpty() {
        let key = Settings.conversationSourcesKey
        let saved = UserDefaults.standard.string(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }

        UserDefaults.standard.set("not json {", forKey: key)
        #expect(Settings.conversationSources.isEmpty)
        UserDefaults.standard.removeObject(forKey: key)
        #expect(Settings.conversationSources.isEmpty)
    }
}
