# VoiceKit

On-device speech recognition and audio input for Apple platforms. Wraps Apple's SpeechTranscriber/SpeechAnalyzer pipeline into async-stream-based APIs with a protocol abstraction layer for swappable backends.

No audio or transcript leaves the device.

## Dictate — the app

This repo also ships **Dictate**, a macOS menu bar app built on VoiceKit: hold **Fn** anywhere, speak, release — your words are typed into whatever app has focus. Like Wispr Flow, but 100% on-device.

```sh
Scripts/make-app.sh && open build/Dictate.app
```

Requires macOS 26 to run and Xcode 26 to build. On first launch, grant **Accessibility** (for the global hotkey and paste), **Microphone**, and **Speech Recognition** when prompted. Then set System Settings → Keyboard → "Press 🌐 key to" → **Do Nothing**, so Apple's built-in dictation doesn't fight the Fn hotkey.

- **Hold Fn** (or Right ⌘, configurable): push-to-talk — release to insert.
- **Quick tap**: locks dictation on; tap again to stop and insert.
- A floating HUD shows mic level and the live transcript while you speak. The meter comes in five styles: **Level bars**, a **Voice orb** that swells and warms with your voice, a scrolling **Waveform**, a **Sonar ripple**, or a **Breathing halo** that lights the pill itself instead of drawing a meter.
- Filler words ("um", "uh", …) are stripped automatically. Cleanup has four modes in Settings: **Off**, **Apple Intelligence** (on-device polish), **Claude** — an opt-in, bring-your-own-key mode that sends the transcript (and nothing else) to the Anthropic API for frontier-grade rewriting — or **Custom local model** — any OpenAI-compatible server (Ollama, LM Studio, llama.cpp, MLX, vLLM) via a base URL and model name, fully local. Custom instructions apply to both. The Claude key is stored in the Keychain; if any cleanup request fails, the local transcript is inserted unchanged.
- **Learns from your edits**: fix a misheard word after insertion and Dictate notices (via Accessibility), remembers the correction, and applies it automatically once it has been seen twice — reverting a correction unlearns it. Learned pairs also steer the AI cleanup prompt. Each dictation appends one compact JSONL line (stats and correction pairs, never full transcripts) to `~/Library/Application Support/Dictate/learning-log.jsonl`, entirely on-device.
- **⌃⌥⌘V**: pops up the last hour of dictations — click one to copy it to the clipboard, press Esc (or click elsewhere) to dismiss. History is in-memory only and clears when the app quits.
- Settings: hotkey, language, microphone, cleanup mode, learning, dictation popup style, menu bar icon (optional — hotkeys work without it; reopen the app to get Settings back), launch at login.

## Dictate — the iOS keyboard

The same pipeline as a custom keyboard: tap the mic, talk, tap again. The transcript is
transcribed on-device (SpeechAnalyzer), polished on-device by Apple Intelligence
(FoundationModels), and typed into whatever field you were in.

```sh
cd iOS && xcodegen generate && open DictateiOS.xcodeproj
```

Requires iOS 26 and a device with Apple Intelligence. The Xcode project is generated from
`iOS/project.yml` — edit that, not the `.xcodeproj`.

It's a dictation keyboard, not a full keyboard: mic, globe, delete. The globe key gets you
back to the stock keyboard for typing. After installing, open the app once to grant
Microphone and Speech Recognition (an extension can't prompt for those itself), then enable
the keyboard in Settings → General → Keyboard → Keyboards and turn on **Full Access** —
without it the extension can't open the mic. If Apple Intelligence is unavailable or fails,
the locally cleaned transcript is typed as dictated rather than lost.

## Installation

Add VoiceKit via Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/fennelouski/voicekit.git", branch: "main"),
]
```

Then add `"VoiceKit"` to your target's dependencies.

## Platform Requirements

| Platform | Minimum (package) | Speech Recognition |
|----------|-------------------|--------------------|
| macOS    | 15.0              | 26.0+              |
| iOS      | 17.0              | 26.0+              |
| visionOS | 1.0               | 26.0+              |

`PositionMapper`, `SentenceMapper`, and audio utilities work on the lower deployment targets. `SpeechRecognitionService` requires macOS 26+ / iOS 26+ and is gated with `@available`.

## Quick Start

### Pattern A: Simple Dictation

Transcribe speech to text. The recognition service handles permissions, audio session, engine setup, and teardown.

```swift
import VoiceKit

let speechService = SpeechRecognitionService()
let session = try await speechService.startRecognition(locale: .current)

for await segment in session.transcript {
    print(segment.text)          // cumulative transcript
    if segment.isFinal {
        print("Committed.")
    }
}

await speechService.stopRecognition()
```

### Pattern B: Voice-Following (Teleprompter)

Map spoken words to positions in a reference script. The speaker reads aloud; your app highlights or scrolls to match.

```swift
import VoiceKit

let mapper = PositionMapper(scriptText: scriptBody)
let speechService = SpeechRecognitionService()
let session = try await speechService.startRecognition()

for await segment in session.transcript {
    let timestamp = ProcessInfo.processInfo.systemUptime

    // Optimistic estimate for immediate highlighting; doesn't advance state
    let estimated = await mapper.estimatePosition(for: segment.text, timestamp: timestamp)
    highlightUpTo(estimated)

    // Conservative match: advances only on confirmed matches
    if let confirmed = await mapper.processSegment(segment.text, timestamp: timestamp) {
        highlightUpTo(confirmed)
    }
}
```

### Pattern C: Mic Level Only

Show a level meter without speech recognition. Lighter weight, no Speech framework.

```swift
import VoiceKit

let micService = MicLevelService()
let stream = try await micService.startCapture()

for await level in stream {
    updateLevelBar(level)  // 0.0 ... 1.0
}

await micService.stopCapture()
```

## Protocol Abstraction

VoiceKit defines a `TranscriptionProvider` protocol so you can swap speech backends:

```swift
public protocol TranscriptionProvider: Sendable {
    func startTranscription(locale: Locale?) async throws -> AsyncStream<TranscriptionResult>
    func stopTranscription() async
}
```

`SpeechRecognitionService` conforms to this protocol. For testing, use `MockTranscriptionProvider`:

```swift
let mock = MockTranscriptionProvider()
let stream = try await mock.startTranscription(locale: nil)

Task {
    await mock.yield(TranscriptionResult(text: "Hello world", isFinal: true))
    await mock.finish()
}
```

## API Reference

### Recognition

| Type | Description |
|------|-------------|
| `SpeechRecognitionService` | Actor wrapping Apple's SpeechTranscriber pipeline. Conforms to `TranscriptionProvider`. |
| `RecognitionSession` | Returned by `startRecognition()`. Contains `transcript`, `level`, and `audioBuffers` streams. |
| `TranscriptionResult` | A recognized segment: `text`, `isFinal`, optional `confidence`. |
| `RecognitionError` | Error cases: `notAuthorized`, `localeNotSupported`, `engineStartFailed`, etc. |
| `TranscriptAccumulator` | Folds a result stream into text: finals accumulate, volatile overlays for live preview. |
| `TranscriptCleaner` | Strips filler words and repairs capitalization for dictated text. |

### Tracking

| Type | Description |
|------|-------------|
| `PositionMapper` | Actor mapping transcript words to character positions in a script. Scored candidate matching with context awareness. |
| `PositionMapper.Configuration` | Tuning parameters: windows, thresholds, filler words. Conforms to `Codable`. |
| `SentenceMapper` | Detects sentence boundaries for keyboard navigation. |

### Learning

| Type | Description |
|------|-------------|
| `CorrectionExtractor` | Word-diffs inserted text against the user's edited version, yielding `Correction` pairs. |
| `CorrectionStore` | Persisted correction counts: applies pairs seen twice, unlearns reverted ones, feeds prompt hints. |

### Audio

| Type | Description |
|------|-------------|
| `MicLevelService` | Lightweight actor for mic level capture without speech recognition. |
| `BufferConverter` | Converts `AVAudioPCMBuffer` between formats with cached converter. |
| `AudioInputInfo` | Current default audio input device info. |
| `AudioInputSelection` | Enumerate and apply audio input device selection. |
| `RMSCalculator` | Shared RMS level computation utility. |

### Protocols

| Type | Description |
|------|-------------|
| `TranscriptionProvider` | Protocol for swappable speech backends. |
| `MockTranscriptionProvider` | Controllable provider for testing without audio hardware. |

## Entitlements

Your app must request microphone access:

**macOS** (`.entitlements`):
```xml
<key>com.apple.security.device.audio-input</key>
<true/>
```

**Info.plist** (iOS; also required for macOS apps, sandboxed or not):
```xml
<key>NSMicrophoneUsageDescription</key>
<string>Used for voice input</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>Used for on-device speech-to-text</string>
```

## Error Handling

| Scenario | Error | Recovery |
|----------|-------|----------|
| Permission denied | `.notAuthorized` | Show in-app message directing user to Settings |
| Unsupported locale | `.localeNotSupported` | Fall back to system default locale |
| Audio engine failure | `.engineStartFailed` | Retry or show error |
| Model download failed | `.modelDownloadFailed` | Retry or check network |
| Stream ends | Stream completes | Restart recognition in a loop |

## Troubleshooting

**I spoke, released the key, and nothing was inserted.** A quick tap (under ~0.35 s) locks dictation **on** — hands-free mode, shown by a lock icon in the pill. Tap the hotkey again to stop and insert. Holding the key inserts on release.

**macOS asks for permissions again after every rebuild.** Permission grants are tied to the app's code signature, and ad-hoc signatures change on every build. `Scripts/make-app.sh` signs with your Apple Development (or Developer ID) certificate when one is present, so grants survive rebuilds. If it prints `Signed ad-hoc (no Apple Development identity found)`, sign into Xcode → Settings → Accounts to get a free development certificate, then rebuild.

**"Dictate.app can't be opened" (Gatekeeper).** Apps you build locally aren't quarantined and open normally. A pre-built copy from someone else isn't notarized: right-click the app → Open → Open to run it anyway.

**The hotkey does nothing.** The global key monitor needs Accessibility permission and only works after it's granted. If you granted it directly in System Settings (outside Dictate's onboarding), quit and relaunch Dictate.

## Privacy

Recognition, filler-word cleanup, and correction learning are entirely on-device. The recent-dictations history (⌃⌥⌘V) is held in memory only and is gone when the app quits. Learned corrections (`corrections.json`) and the dictation log (`learning-log.jsonl`, stats and correction pairs only — never transcripts) live in `~/Library/Application Support/Dictate/`, never in this repo. The only network calls are the two opt-in cleanup modes: **Claude** (your API key, stored in the Keychain) and **Custom local model** (your server). Both receive the transcript and nothing else, and both are off by default.

## Roadmap

Not here yet: screenshots/demo GIF, notarized releases, Homebrew cask, CONTRIBUTING.md.

## License

MIT — see [LICENSE](LICENSE).
