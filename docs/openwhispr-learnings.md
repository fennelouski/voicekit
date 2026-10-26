# OpenWhispr learnings applied to VoiceKit

Reviewed October 14, 2026. Source revision: `2516e6e000b866a06099f69fd851b914069653d4` (a shallow checkout of upstream `main`). VoiceKit started from local commit `93e477ca868b04eb689fc1516fe11dd951379011` with a clean working tree. Links below pin upstream files to this revision rather than following changing defaults.

## What to take from the project

OpenWhispr's strongest transferable asset is its regression history: recording and paste are full transactions, cleanup must prove it produced usable text, and model/provider differences should be explicit. VoiceKit already has a useful native architecture: a small library, actor-owned recognition, recovery recordings, staged history, correction learning, and app-specific UI. Preserve those boundaries while bringing over the failure cases and product lessons.

This is a source-level comparison, not a benchmark of OpenWhispr's runtime. Upstream files and tests were inspected; OpenWhispr was not installed, launched, or measured. The changes here adapt ideas and selected validation/spacing logic into native Swift. The upstream MIT notice is included in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).

## Transfer matrix

“Applied” means code or copy changed in this working tree. Other rows are explicit follow-up work, not implemented features.

| Learning | Status | VoiceKit application | Upstream evidence |
|---|---|---|---|
| Cleanup is a transform with an explicit input boundary | Applied | CleanupPrompt is shared across Apple Intelligence and optional providers; transcript and correction data are JSON-encoded. Custom instructions now reach the on-device step. | [prompt registry](https://github.com/OpenWhispr/openwhispr/blob/2516e6e000b866a06099f69fd851b914069653d4/src/config/prompts/index.ts) |
| Never paste truncated generation | Applied | Both HTTP parsers reject incomplete finish reasons and let the existing chain fall back. Missing finish metadata remains compatible with minimal local servers. | [request completion policy](https://github.com/OpenWhispr/openwhispr/blob/2516e6e000b866a06099f69fd851b914069653d4/src/services/ai/chatRequestBody.ts) |
| Word overlap alone does not detect an echoed answer | Applied | Detect doubled cleaned transcripts while allowing real repetitions and adjacent stutters. Word tokenization now handles punctuation and unspaced scripts. | [cleanup validation](https://github.com/OpenWhispr/openwhispr/blob/2516e6e000b866a06099f69fd851b914069653d4/src/utils/cleanupOutput.ts) |
| Reasoning is not dictation output | Applied | Nested/case-varied think blocks are removed; unfinished blocks fail instead of becoming inserted text. | [reasoning sanitizer](https://github.com/OpenWhispr/openwhispr/blob/2516e6e000b866a06099f69fd851b914069653d4/src/helpers/stripThinking.js) |
| Preserve clipboard formats and respect newer copies | Applied | Snapshot available data for every pasteboard item; restore only while the pasteboard change count is still ours. Cover overlapping dictations and matching-text copies. | [clipboard transaction](https://github.com/OpenWhispr/openwhispr/blob/2516e6e000b866a06099f69fd851b914069653d4/src/helpers/clipboard.js) |
| Errors must survive processing-state transitions | Applied | Manual-paste failures survive the cleanup queue; errors from earlier queued jobs are retained. An old error-dismissal timer cannot hide a newly started recording. | [paste recovery regression](https://github.com/OpenWhispr/openwhispr/blob/2516e6e000b866a06099f69fd851b914069653d4/test/helpers/useAudioRecordingPasteRecovery.test.js) |
| Recovery audio belongs to a particular pending job | Applied | Queued recovery files are protected from earlier cleanup sweeps; the existing retention policy applies after each job completes. | [recording spool](https://github.com/OpenWhispr/openwhispr/blob/2516e6e000b866a06099f69fd851b914069653d4/src/helpers/recordingSpool.js) |
| Spacing depends on the writing system | Applied | Shared insertion spacing avoids extra ASCII spaces after Chinese/Japanese text and CJK punctuation, while preserving Korean word spaces and explicit newlines. | [spacing policy](https://github.com/OpenWhispr/openwhispr/blob/2516e6e000b866a06099f69fd851b914069653d4/src/helpers/smartSpacing.js) |
| Provider URLs need predictable normalization | Applied | Full chat-completions endpoints work without duplication; provider-specific paths survive. Unsupported schemes, missing hosts, embedded credentials, queries, and fragments are rejected. | [endpoint resolution](https://github.com/OpenWhispr/openwhispr/blob/2516e6e000b866a06099f69fd851b914069653d4/src/services/ai/inferenceProviders/openai.ts) |
| Privacy describes actual routes and retained data | Applied to repository copy | README, provider notes, privacy settings, and PRIVACY.md now describe persisted history, correction hints, custom remote endpoints, model downloads, and updates. The website mirror needs a separate publish. | [retention contract](https://github.com/OpenWhispr/openwhispr/blob/2516e6e000b866a06099f69fd851b914069653d4/src/helpers/retentionSettings.js) |
| Keep streaming preview separate from committed text | Keep existing; extend tests | TranscriptAccumulator and service finalization already distinguish finals and previews. Add recordings proving final words are not lost on rapid release or a stalled result stream. | [streaming finalization regressions](https://github.com/OpenWhispr/openwhispr/blob/2516e6e000b866a06099f69fd851b914069653d4/test/helpers/audioManagerStreamingFinalization.test.js) |
| Do not reject speech just because it was brief | Keep existing | OpenWhispr gates unusable containers by actual audio data, not elapsed time. Preserve VoiceKit frame-based recovery checks and the tap/hold behavior; do not add a minimum-duration speech cutoff. | [recording guard](https://github.com/OpenWhispr/openwhispr/blob/2516e6e000b866a06099f69fd851b914069653d4/src/helpers/recordingGuard.js) |
| VAD for meetings and dictation needs different policy | Evaluate with fixtures | Do not transplant Whisper-specific RMS or VAD thresholds into SpeechAnalyzer. Benchmark whispered speech, pauses, one-word dictation, and background sound before filtering audio. | [context-specific VAD](https://github.com/OpenWhispr/openwhispr/blob/2516e6e000b866a06099f69fd851b914069653d4/src/helpers/whisperVadConfig.js) |
| Watch audio delivery independently of audio loudness | Applied; hardware trials remain | Monotonic delivery clocks, sleep/wake rebasing, session generations, per-source health and bounded total restarts now cover dictation and conversations. Validate device and output changes on hardware. | [system audio watchdog](https://github.com/OpenWhispr/openwhispr/blob/2516e6e000b866a06099f69fd851b914069653d4/src/helpers/meetingSystemAudioWatchdog.js) |
| Repair the audio timeline across explicit capture gaps | Applied | Captured host-clock spans map file timestamps through gaps. Completed conversations annotate capture gaps instead of shifting later speech earlier. | [sample timeline](https://github.com/OpenWhispr/openwhispr/blob/2516e6e000b866a06099f69fd851b914069653d4/src/helpers/meetingAudioTimeline.js) |
| Cancel the session and all late work as one operation | Applied to dictation | Escape cancels active capture and the insertion backlog; per-transaction checks suppress late results, provider fallback, history, and clipboard writes. Cancelled recovery audio and session transcripts are discarded. | [cancellation regressions](https://github.com/OpenWhispr/openwhispr/blob/2516e6e000b866a06099f69fd851b914069653d4/test/helpers/audioManagerCancelLifecycle.test.js) |
| Start cold features only when needed and release idle models | Measure first | Keep SpeechAnalyzer out of long-form capture and retain sequential file transcription. Measure FluidAudio loading/unloading and idle RSS before adding background models or detectors. | [lazy resource findings](https://github.com/OpenWhispr/openwhispr/blob/2516e6e000b866a06099f69fd851b914069653d4/CHANGELOG.md) |
| Provider capability metadata beats one request shape | Conservative policy applied; full registry optional | Known official model families receive supported effort/token parameters; compatible custom servers retain minimal requests. Editable model IDs are preserved. Broader capability/context metadata needs model-specific evaluation. | [model registry](https://github.com/OpenWhispr/openwhispr/blob/2516e6e000b866a06099f69fd851b914069653d4/src/models/ModelRegistry.ts) |
| Different tasks deserve different time and token budgets | Applied | Cleanup has a 30-second total deadline, cancellation and bounded provider output budgets. Late work cannot commit; requests are not blindly retried. Meeting summaries remain separate optional work. | [task deadlines](https://github.com/OpenWhispr/openwhispr/blob/2516e6e000b866a06099f69fd851b914069653d4/src/helpers/llmRequestTimeout.js) |
| Explain provider failures without leaking provider response bodies | Applied | Safe auth/access/quota/model/timeout/unreachable/output categories appear in history with Open Settings and redacted Copy Details. Later successful fallback stays quiet; raw response bodies are discarded. | [provider errors](https://github.com/OpenWhispr/openwhispr/blob/2516e6e000b866a06099f69fd851b914069653d4/src/helpers/providerHttpErrors.js) |
| Spelling vocabulary should reach the recognizer as well as cleanup | Vocabulary applied; native ASR bias deferred | Exact-casing terms, removal, import/export and bounded cleanup hints are implemented. Apple documents contextualStrings for DictationTranscriber; the current SpeechTranscriber backend is retained until an alternative is measured. | [dictionary budgets](https://github.com/OpenWhispr/openwhispr/blob/2516e6e000b866a06099f69fd851b914069653d4/src/utils/dictionaryPromptCap.js) |
| A dictated vocabulary list can be a hallucinated prompt echo | Conditional on new ASR backends | When adding Whisper or cloud ASR hints, detect dictionary echoes against the exact bounded prompt actually sent, and retry without hints. Do not filter normal Apple transcripts with uncalibrated thresholds. | [echo filter](https://github.com/OpenWhispr/openwhispr/blob/2516e6e000b866a06099f69fd851b914069653d4/src/utils/dictionaryEchoFilter.js) |
| Alternative local ASR can cover unsupported OS/language needs | Product decision | Add optional Whisper/Parakeet adapters behind TranscriptionProvider, with file transcription, download verification, language metadata, GPU/CPU fallback, and offline tests. Keep heavy runtimes out of the core library. | [local transcription models](https://github.com/OpenWhispr/openwhispr/blob/2516e6e000b866a06099f69fd851b914069653d4/src/helpers/localTranscriptionModels.js) |
| Interrupted recordings need discoverable recovery | Applied | Launch discovery and Recover Recordings offer local retry, audio/text export and deletion. Failed conversation sources survive transcription/save errors; active sessions are protected from imports. Retry never auto-inserts. | [interrupted spooling](https://github.com/OpenWhispr/openwhispr/blob/2516e6e000b866a06099f69fd851b914069653d4/src/helpers/recordingSpool.js) |
| Meeting system audio and microphone can contain the same voice | Next meetings work | Test speaker bleed and double-talk with actual headphones/speakers. Add optional AEC/echo suppression and distinguish source labels from speaker identities; never drop genuine local speech solely due to correlation. | [echo leakage detector](https://github.com/OpenWhispr/openwhispr/blob/2516e6e000b866a06099f69fd851b914069653d4/src/helpers/meetingEchoLeakDetector.js) |
| Meeting detection should obey preferences and avoid idle work | Optional feature | If automatic meeting prompts are added, corroborate external microphone use with a meeting app, exclude our own capture, respect notification toggles, and stop detectors when disabled. | [detector preferences](https://github.com/OpenWhispr/openwhispr/blob/2516e6e000b866a06099f69fd851b914069653d4/src/helpers/meetingDetectionPreferencePolicy.js) |
| Translation and selection editing need separate intent contracts | Optional feature | Use separate actions/hotkeys and output validation. An explanation about selected text must open in a panel; replacing it would destroy the selection. Screenshots would require explicit opt-in. | [selection editing](https://github.com/OpenWhispr/openwhispr/blob/2516e6e000b866a06099f69fd851b914069653d4/src/helpers/selectionEditing.js) |
| History should preserve the original and show what failed | Failure/pruning applied; extra tools optional | History keeps raw and applied stages, safe failure reasons and immediate persisted pruning. Audio retry/export has a recovery window. Additional text re-cleanup, history search/export and explicit insertion retry remain optional features. | [cleanup/history regression](https://github.com/OpenWhispr/openwhispr/blob/2516e6e000b866a06099f69fd851b914069653d4/test/services/cleanupOutputValidation.test.js) |
| Permission recovery belongs inside the product | Refine existing flow | Keep guided onboarding and clipboard fallback; add a focused end-to-end self-test for microphone, model availability, hotkey delivery, and paste with direct settings links. | [permission guide](https://github.com/OpenWhispr/openwhispr/blob/2516e6e000b866a06099f69fd851b914069653d4/src/components/onboarding/usePermissionGuide.ts) |
| Benchmarks should exercise real recordings and race conditions | Harness/races applied; real corpus pending | Added local WER/CER/file-latency evaluation, synthetic smoke fixture generation, explicit hardware skips, and deadline/recovery/cancellation races. Real recordings, streaming/paste latency and signed-app device compatibility remain release measurements. | [recording harness](https://github.com/OpenWhispr/openwhispr/blob/2516e6e000b866a06099f69fd851b914069653d4/test/helpers/harness/audioRecorder.js) |
| Ship runtime/license checks and desktop/mobile CI separately | Local checks/bundle/notices applied; distribution checks remain | `Scripts/check.sh` runs macOS/iOS tests and bundle validation locally; a pre-push hook gates pushes. Source dependencies are locked; runtime/license notices ship with the app. Model provenance, signed-update permission continuity, translation review and notarized updater artifacts remain release checks. | [CI scopes](https://github.com/OpenWhispr/openwhispr/blob/2516e6e000b866a06099f69fd851b914069653d4/.github/workflows/ci-changes.yml) |

## Changes in this pass

- **Clipboard transactions:** `ClipboardTransaction` restores all readable item representations and uses `NSPasteboard.changeCount` to identify ownership. Tests use unique pasteboards, leaving the user's clipboard alone. Text insertion still posts Command-V; a successful event post is not an acknowledgement from the target editor.
- **One cleanup contract:** `CleanupPrompt` handles the transform instructions, examples, custom preferences, JSON transcript boundary, and learned spelling data for every model. This boundary helps the model distinguish content from instructions; it is not a guarantee that a model cannot be distracted. Output validation and fallback remain essential.
- **Output validation:** HTTP finish reasons identify incomplete generations; `CleanupOutput` safely removes nested reasoning. `TranscriptCleaner` catches whole-transcript duplication, keeps intentional repetitions, and uses native Unicode word tokenization. The existing overlap rule remains a heuristic: it does not prove semantic equivalence or catch every deletion or paraphrase.
- **iOS parity:** the keyboard pipeline validates wording before insertion rather than accepting any nonempty polish. The public on-device cleanup API validates too, protecting consumers outside the macOS chain.
- **Queue lifecycle:** `RecoveryRecordingQueue` protects recordings that later jobs still need; failure messages survive the processing queue; scheduled error dismissal is cancelled when a new recording begins.
- **International insertion:** `DictationSpacing` is shared between the macOS app and iOS keyboard. It does not infer a user's entire language from one character; it makes the narrow decision of whether an ending requires an ASCII separator.
- **Provider configuration:** endpoint normalization accepts complete chat URLs and preserves vendor prefixes. A rejected configuration remains a failed chain step, so the transcript still has a fallback. Query-based custom authentication is not supported; use the API-key field and headers.
- **Privacy accuracy:** history actually persists to disk, cleanup can send learned hints, remote custom servers are not on-device, and update/model downloads are network requests. Repository copy now says this. The published website mirror has not been changed by this task.

## Implementation roadmap status

1. **Recording/insertion transaction implemented.** Destination checks, Escape cancellation,
   stale-result exclusion and clipboard ownership are in place. Queued insertion now waits
   through clipboard settling and rechecks cancellation/focus. See [transaction details](recording-insertion-transactions.md).
2. **Recovery and capture reliability implemented.** Recovery retry/export/delete, interrupted
   discovery, durable conversation journals, timestamp mapping, gap notes, bounded restarts,
   and failed-source retention are in place. Real route-change/sleep trials remain.
3. **Full job configuration implemented.** Models, URLs, credentials, instructions and vocabulary
   join the existing recording/formatting snapshots. Privacy-disable preferences win immediately.
4. **Provider reliability implemented.** Total deadlines, cancellation, safe failure categories,
   redirect refusal and conservative supported-parameter/output policies are in place. Model
   quality and budgets still need real transcripts; a complete capability registry is optional.
5. **Terminology controls implemented.** Explicit bounded vocabulary, exact casing, import/export,
   individual correction removal and relevant hints are in place. Recognition bias remains
   deferred because the documented Apple API is for a different recognizer module.
6. **Local verification implemented.** `Scripts/check.sh` and a pre-push hook run macOS/iOS
   suites and bundle/license checks. Isolated UI previews, explicit hardware skips and a local
   evaluation harness are in place. GitHub Actions is disabled. Real speech corpus, signed-app
   compatibility, translation review,
   updater/notarization trials and publishing the corrected privacy mirror remain release work.
7. **Additional product features remain decisions.** Alternative ASR, calibrated VAD/AEC, speaker
   fingerprints, automatic meeting prompts, summaries, translation and selection editing require
   separate intent/data contracts and measured benefits. They are not prerequisites for the
   reliability changes and have not been added speculatively.

## Latest verification and limits

See [reliability verification](reliability-verification.md) for commands, detailed ownership rules,
measurement formats and remaining release checks. SwiftPM reports **255 cases: 251 executed
successfully and four hardware/ASR cases explicitly skipped**. The iOS keyboard simulator suite
passed **7 tests**. The development app bundle validates, recovery/vocabulary UI was inspected
with isolated fixtures, and the strict evaluator smoke run reports missing audio and exits 2.
No actual ASR quality/latency measurements or arbitrary-app paste acknowledgements are claimed.

The earlier transaction pass passed 227 registered macOS cases and seven iOS cases; the current
suite adds deadline, recovery, file-save failure, timestamp, converter-format, vocabulary, and
metric regressions. These require neither microphone access nor cloud credentials. Hardware
suites now require explicit opt-in rather than returning success without exercising hardware.

No cloud API calls or new cloud defaults were introduced. Upstream's Whisper/VAD thresholds,
account/organization system and connector features are optional product scope. Their transferable
reliability lessons are captured here. New UI copy currently uses English fallback; the current
translation audit is explicitly incomplete. The canonical privacy website mirror has not been
published by this task.

## Manual checks before a release

1. Copy rich text, an image, and multiple file URLs; dictate into a real editor and paste the original clipboard elsewhere. Repeat while copying a new item during the restore interval.
2. Queue several recordings with slow cleanup; make a later recording return no live transcript and confirm recovery can still read its audio. Turn off recovery and confirm the deliberate deletion action wins over retention.
3. Revoke Accessibility and dictate. Confirm the manual-paste message remains visible, the transcript is in history/clipboard, and the next recording is not hidden by the old error's timer.
4. Switch app, window, and field while cloud cleanup is pending. Confirm no automatic paste occurs in the new destination, the manual-paste message remains visible, and the transcript is available in history/clipboard. Then repeat without changing focus and confirm one paste in the captured process.
5. Measure old/new cleanup prompts on dictated questions, self-corrections, technical names, multilingual speech, and literal markup. Parser tests do not establish real-model accuracy or latency.
