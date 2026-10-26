# Dictation latency

Implemented October 15, 2026. These are code changes and measurement tools, not a measured
microphone-to-editor speedup claim. The installed 1.4.0 release does not contain these changes.

## Default path

After terms acceptance and existing microphone/speech permission grants, Dictate prepares the
selected locale's SpeechTranscriber, assets, format, and SpeechAnalyzer with `prepareToAnalyze`.
This never opens the microphone or prompts for permission. Onboarding grants and preference
changes trigger preparation; each stopped recording prepares the next one. Changing locale
replaces only unclaimed preparation. An active recording owns its own analyzer. Apple can reclaim
resources; a completed preparation is not a promise that model pages remain resident forever.

The hotkey captures the insertion destination and recording options, opens a fresh audio engine,
and starts capture independently of pending speech preparation. The requested tap size is 1,024
frames (~21ms at 48kHz), but hardware controls the actual delivered size. Engine buffers are copied
before leaving the callback. A FIFO holds at most 512 packets while preparation catches up. It
never silently drops opening speech: overflow, conversion, result, or finalization failure marks
the pipeline failed. On stop, failed analysis recovers the complete safety recording if available;
without a usable backup it inserts nothing rather than a partial transcript. A model download can
still make a cold stop/recovery slow. Keep the selected language's assets installed before measuring.

Normal stop closes capture, drains buffered audio into the recognizer, finalizes it, and drains
final results before insertion. Conversation transcript saving/diarization runs separately. Escape
cancels claimed preparation and feeding, cancels finalization, and retires the entire insertion
backlog. All existing destination checks, process-directed paste events, and clipboard safeguards
remain. No later AI output replaces text that has already been pasted.

By default, only local filler removal, vocabulary spelling, enabled learned corrections, and
spoken formatting precede paste. AI polishing requires the new explicit switch in Settings →
Cleanup, including after upgrading. Existing provider chains, keys, and instructions are retained.
When enabled, a fresh Apple Intelligence session prewarms while recording if the chain includes
it. Relevant spelling hints are appended as JSON data when the final transcript is known. Model
sessions are not shared across dictations. The total AI wait budget defaults to two seconds;
settings offer 1/2/5/10/30 seconds. The deadline begins when a queued job starts polishing, not at
key release. Timeout uses local text once; late results cannot insert. Slow earlier jobs, recovery,
and recognition finalization can still add latency. History persistence happens after posting the
paste event. The previous paste's 400ms clipboard interval applies only to closely queued pastes.

Library compatibility: `SpeechRecognitionService()` still reports preparation errors before
returning a session. Dictate opts into `captureWhilePreparing: true` and checks the returned
`RecognitionMetrics` before accepting text. Other hosts can opt in only if they handle deferred
failure/backup recovery. `prepareRecognition(locale:)` is available independently.

## Local measurements

Unified logging uses subsystem `Dictate`, category `Latency`. Events contain a random transaction
ID, a fixed stage, and monotonic milliseconds. They contain no audio, transcript, app/window name,
file path, or credentials and are not uploaded. Capture timestamps are emitted when stop finishes,
so log ordering differs from the measured ordering. Negative stop-relative timestamps identify
capture events before stop. The request timestamp includes destination capture and option loading.

To measure a build containing these changes, record at least 20 short phrases per scenario, then:

```sh
python3 Scripts/measure-latency.py --last 15m
python3 Scripts/measure-latency.py --last 1h --json > /tmp/dictate-latency.json
```

The default query selects the `Dictate` process, excluding SwiftPM test processes. For an explicit
saved log or compact stream, including a synthetic verification fixture:

```sh
/usr/bin/log show --last 15m --style ndjson \
  --predicate 'process == "Dictate" AND subsystem == "Dictate" AND category == "Latency"' \
  > /tmp/dictate-latency.ndjson
python3 Scripts/measure-latency.py --input /tmp/dictate-latency.ndjson --json
python3 Scripts/test-measure-latency.py
```

The report gives sample count, nearest-rank p50/p95/max for request→first buffer, stop→recognition
finished, queue wait, AI processing/deadline, insertion wait, and stop→paste events posted. Warm
means preparation completed before this recording claimed it; cold means it did not. Reports
separate those cases and report cancellations/manual-copy outcomes without counting them as
successful pastes. No matching events exits 2, never a fabricated zero-latency result.

Compare fresh launch, subsequent recordings, language change, sleep/wake, built-in microphone,
and Bluetooth input separately. Repeat with polishing off/on and rapid successive recordings.
Check the first and last spoken words for truncation. Exercise Escape during cold startup,
recognizer finalization, AI work, and queued insertion; switch application/window/field during
polishing to verify manual-copy fallback. Verify real insertion in representative editors manually
or through an instrumented test editor: posting keyboard events is not delivery acknowledgement.
Use the same phrases, hardware, locale, and conditions when comparing with a baseline build.

Deterministic tests cover preparation reuse/invalidation/ownership/cancellation, early-buffer
ordering and overflow, timing reports, default opt-in policy, failed-pipeline recovery, local-only
insertion, deadlines, Escape, and destination changes. They do not substitute for real microphone,
ASR quality, or editor insertion measurements. Hardware tests remain explicit opt-in.

API references: [SpeechAnalyzer preparation and retention](https://developer.apple.com/documentation/Speech/SpeechAnalyzer),
[Foundation Models prewarming](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/prewarm%28promptprefix%3A%29).

## Verification of this implementation

- SwiftPM: 265 registered cases, 261 executed successfully and four hardware/ASR cases explicitly skipped.
- iOS keyboard simulator: seven tests passed.
- Timing report: three parser/percentile/outcome tests passed, including duplicate events and cancelled/manual-copy exclusion. An empty report exits 2.
- Development app bundle built and passed structure, signature, permission, notice, and 40-locale checks.
- The isolated cleanup preview verified the default-off toggle, two-second budget, preserved provider chain, and return to local insertion. It did not start recording or replace the installed app.
- Timing events from simulated transaction tests were read from unified logging. The production-process query returned no live samples, as expected with the unchanged installed release. No hardware speedup or editor delivery acknowledgement has been measured.
