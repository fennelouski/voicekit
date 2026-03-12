# VoiceKit

On-device speech recognition and audio input for Apple platforms. Wraps Apple's SpeechTranscriber/SpeechAnalyzer pipeline into async-stream-based APIs with a protocol abstraction layer for swappable backends.

No audio or transcript leaves the device.

## Installation

Add VoiceKit via Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/nathanfennel/VoiceKit.git", from: "1.0.0"),
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
    // Fast path: nonisolated, no actor hop — sub-millisecond UI updates
    let estimated = mapper.estimatePosition(
        for: segment.text,
        afterCharPosition: currentPosition
    )
    highlightUpTo(estimated)

    // Slow path: conservative match confirms position on the actor
    let timestamp = ProcessInfo.processInfo.systemUptime
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

### Tracking

| Type | Description |
|------|-------------|
| `PositionMapper` | Actor mapping transcript words to character positions in a script. Scored candidate matching with context awareness. |
| `PositionMapper.Configuration` | Tuning parameters: windows, thresholds, filler words. Conforms to `Codable`. |
| `SentenceMapper` | Detects sentence boundaries for keyboard navigation. |

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

**iOS** (`Info.plist`):
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

## License

MIT
