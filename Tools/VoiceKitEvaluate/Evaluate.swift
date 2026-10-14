import Foundation
import VoiceKit
#if os(macOS)
import Speech
#endif

struct EvaluationFixture: Codable {
    let id: String
    let audio: String
    let expected: String
    let locale: String
    let category: String
}
struct EvaluationMeasurement: Codable {
    let id: String
    let category: String
    let run: Int
    let status: String
    let reason: String?
    let elapsedSeconds: Double?
    let text: String?
    let score: EvaluationMetrics.Score?
    let wordErrorRate: Double?
    let characterErrorRate: Double?
}
struct EvaluationReport: Encodable {
    let schemaVersion = 1
    let generatedAt: Date
    let operatingSystem: String
    let measurements: [EvaluationMeasurement]
}

@main
enum Evaluate {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let manifest = value("--fixtures", in: arguments), let output = value("--output", in: arguments) else {
            print("Usage: VoiceKitEvaluate --fixtures manifest.json --output report.json [--runs 2] [--allow-model-download] [--require-measurements]")
            exit(arguments.contains("--help") ? 0 : 2)
        }
        let runs = Int(value("--runs", in: arguments) ?? "2") ?? 0
        guard (1...10).contains(runs) else { print("--runs must be between 1 and 10"); exit(2) }
        let file = URL(fileURLWithPath: manifest)
        do {
            let fixtures = try JSONDecoder().decode([EvaluationFixture].self, from: Data(contentsOf: file))
            guard !fixtures.isEmpty, Set(fixtures.map(\.id)).count == fixtures.count,
                  fixtures.allSatisfy({ $0.expected.count <= 10_000 }) else { print("Empty, duplicate, or oversized fixtures"); exit(2) }
            var measurements: [EvaluationMeasurement] = []
            for fixture in fixtures {
                let audio = file.deletingLastPathComponent().appendingPathComponent(fixture.audio)
                for run in 1...runs {
                    measurements.append(await measure(fixture, audio: audio, run: run, allowDownload: arguments.contains("--allow-model-download")))
                }
            }
            let report = EvaluationReport(generatedAt: Date(), operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString, measurements: measurements)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(report).write(to: URL(fileURLWithPath: output), options: .atomic)
            let measured = measurements.filter { $0.status == "measured" }.count
            print("\(measured) measured; \(measurements.count - measured) skipped or failed. Report: \(output)")
            if arguments.contains("--require-measurements"), measured != measurements.count { exit(2) }
        } catch { print("Could not read fixtures or save evaluation report"); exit(2) }
    }
    private static func value(_ flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
    private static func measure(_ fixture: EvaluationFixture, audio: URL, run: Int, allowDownload: Bool) async -> EvaluationMeasurement {
        func skipped(_ reason: String) -> EvaluationMeasurement {
            .init(id: fixture.id, category: fixture.category, run: run, status: "skipped", reason: reason,
                  elapsedSeconds: nil, text: nil, score: nil, wordErrorRate: nil, characterErrorRate: nil)
        }
        guard FileManager.default.fileExists(atPath: audio.path) else { return skipped("audio_missing") }
#if os(macOS)
        guard #available(macOS 26.0, *) else { return skipped("requires_macos_26") }
        // No prompts from the evaluation tool. Authorization must already exist.
        guard SpeechRecognitionService.authorizationStatus() == .authorized else { return skipped("speech_permission_missing") }
        let locale = Locale(identifier: fixture.locale)
        let model = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        if !allowDownload {
            do {
                if try await AssetInventory.assetInstallationRequest(supporting: [model]) != nil { return skipped("speech_assets_missing") }
            } catch { return skipped("speech_assets_unavailable") }
        }
        let began = ContinuousClock.now
        do {
            let text = try await FileTranscriber.transcribe(fileAt: audio, locale: locale).map(\.text).joined(separator: " ")
            guard text.count <= 10_000 else { throw RecognitionError.recognitionUnavailable }
            let elapsed = began.duration(to: .now).components
            let score = EvaluationMetrics.score(reference: fixture.expected, hypothesis: text)
            return .init(id: fixture.id, category: fixture.category, run: run, status: "measured", reason: nil,
                         elapsedSeconds: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18,
                         text: text, score: score, wordErrorRate: score.wordErrorRate, characterErrorRate: score.characterErrorRate)
        } catch {
            return .init(id: fixture.id, category: fixture.category, run: run, status: "failed", reason: "transcription_failed",
                         elapsedSeconds: nil, text: nil, score: nil, wordErrorRate: nil, characterErrorRate: nil)
        }
#else
        return skipped("requires_macos_26")
#endif
    }
}
