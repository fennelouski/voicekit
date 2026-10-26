# VoiceKit

On-device speech recognition and audio input for Apple platforms. Wraps Apple's SpeechTranscriber/SpeechAnalyzer pipeline into async-stream-based APIs with a protocol abstraction layer for swappable backends.

Speech recognition stays on-device. Optional cleanup providers receive text only when configured; see [Privacy](PRIVACY.md).

## Dictate — the app

This repo also ships **Dictate**, a macOS menu bar app built on VoiceKit: hold **Fn** anywhere, speak, release — your words are typed into whatever app has focus. Recognition is entirely on-device, with optional bring-your-own-key cloud cleanup.

```sh
Scripts/make-app.sh && open build/Dictate.app
```

Requires macOS 26 to run and Xcode 26 to build. On first launch, grant **Accessibility** (for the global hotkey and paste), **Microphone**, and **Speech Recognition** when prompted. Then set System Settings → Keyboard → "Press 🌐 key to" → **Do Nothing**, so Apple's built-in dictation doesn't fight the Fn hotkey.

- **Hold Fn** (or Right ⌘, configurable): push-to-talk — release to insert.
- **Quick tap**: locks dictation on; tap again to stop and insert.
- **Escape**: cancels the current dictation and all outstanding cleanup/paste jobs. Cancelled text is not copied or added to history; its recovery audio and session transcript are discarded. Dictations that already finished remain in history.
- A floating HUD shows mic level and the live transcript while you speak. The meter comes in five styles: **Level bars**, a **Voice orb** that swells and warms with your voice, a scrolling **Waveform**, a **Sonar ripple**, or a **Breathing halo** that lights the pill itself instead of drawing a meter.
- **Fast local insertion is the default.** Recognition prepares ahead of the hotkey without recording idle audio. Local filler removal, vocabulary, learned corrections, and spoken formatting run before paste. **AI polishing is opt-in** in Settings → Cleanup, including on upgrade; saved provider configurations are retained. When enabled, cleanup runs as an ordered chain: **Apple Intelligence** (on-device), **Claude**, **OpenAI**, **Gemini**, **Groq**, **OpenRouter**, or a **custom OpenAI-compatible server** (Ollama, LM Studio, llama.cpp, MLX, vLLM). The first successful step wins; an unavailable model or missing key falls through. Custom instructions apply to every model. Cloud cleanup sends the transcript, relevant learned spelling hints, and explicit vocabulary, never audio; API keys live in the Keychain. A custom server keeps text on-device only when it runs on this Mac. Empty, incomplete, duplicated, or implausibly rewritten output falls through to the next provider or the original text.
- Cleanup jobs capture their model, URL, instructions, and credentials when recording starts. A two-second default total AI deadline uses local fallback if polishing takes too long (configurable up to 30 seconds). Recent Dictations shows safe failure categories and a link to settings.
- **Recover Recordings…** in the menu offers local retry, audio/text export, and deletion. Interrupted and failed dictations follow the recovery retention setting. Failed conversation source audio stays until explicitly deleted; successful audio is deleted only after the transcript document saves. Retry never pastes automatically.
- Local timing logs and a p50/p95 report measure capture startup, recognition finalization, cleanup, and paste-event posting. See [latency measurement](docs/dictation-latency.md).
- **Vocabulary** in Settings → Input stores up to 64 exact spellings, with removal and JSON/text import/export. Matching words get their preferred casing locally and cleanup receives spelling hints. This does not bias the current Apple speech recognizer.
- **Learns from your edits**: fix a misheard word after insertion and Dictate notices (via Accessibility), remembers the correction, and applies it automatically once it has been seen twice — reverting a correction unlearns it. Learned pairs also steer the AI cleanup prompt. Each dictation appends one compact JSONL line (stats and correction pairs, never full transcripts) to `~/Library/Application Support/Dictate/learning-log.jsonl`, entirely on-device.
- **⌃⌥⌘V**: opens recent dictations, including raw text and cleanup stages. Click one to copy it; press Esc (or click elsewhere) to dismiss. History is saved locally, enabled by default, with a one-month retention window and a 100-entry cap. Change retention, disable saving, or clear history in Settings → Privacy.
- Text insertion preserves the clipboard’s available formats and items, and never restores over a newer copy. Consecutive dictations add a separating space for spaced languages; Chinese and Japanese endings keep their natural spacing. The app, window, and text field are captured when dictation starts and checked before insertion. If focus changed or the target cannot be verified, text stays in history and on the clipboard for manual paste. Dictate never activates a different app to deliver a delayed result.
- Settings: hotkey, language, microphone, cleanup chain, learning, dictation popup style, menu bar icon (optional — hotkeys work without it; reopen the app to get Settings back), launch at login.

Ready-to-install macOS releases are [signed and notarized](https://github.com/fennelouski/voicekit/releases). [Download Dictate](https://nathanfennel.com/downloads/Dictate.dmg).

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

**"Dictate.app can't be opened" (Gatekeeper).** Official releases are signed and notarized. Download a fresh copy from the official release page if verification fails. Local builds use your available signing identity and require their own permission grants; they are not notarized unless you run the packaging workflow.

**The hotkey does nothing.** The global key monitor needs Accessibility permission and only works after it's granted. If you granted it directly in System Settings (outside Dictate's onboarding), quit and relaunch Dictate.

## Privacy

Recognition and local filler removal run entirely on-device. History, correction statistics, recovery audio, and conversation transcripts are local data, controlled in Settings → Privacy. Optional cloud cleanup receives transcripts and learned correction hints; keys live in the Keychain. Speech and speaker models may need initial downloads, and distributed macOS builds check for updates through Sparkle. See the [privacy policy](PRIVACY.md) for storage and deletion details.

## Project research

[Recording and insertion transactions](docs/recording-insertion-transactions.md) describes destination checks, Escape cancellation, and verification.

[OpenWhispr learnings](docs/openwhispr-learnings.md) records the source revision reviewed, improvements applied here, and a prioritized roadmap for model support, vocabulary, capture recovery, insertion, meetings, testing, and distribution.

## License

MIT — see [LICENSE](LICENSE).


## Reliability verification

Run `swift test` for deterministic regressions; microphone/ASR integration is explicitly
opt-in with `VOICEKIT_HARDWARE_TESTS=1`. Separate macOS and iOS CI, isolated UI previews,
bundle validation, and a local `VoiceKitEvaluate` tool are documented in
[reliability verification](docs/reliability-verification.md). That document records measured
results and remaining app compatibility, speech corpus, localization, and release checks.
