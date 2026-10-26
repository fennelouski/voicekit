# Reliability verification and remaining release checks

Implemented October 14, 2026. This follows the [OpenWhispr transfer roadmap](openwhispr-learnings.md).

## Implemented behavior

- Recording snapshots locale, microphone, formatting, cleanup chain, model, URL, instructions,
  credentials, and vocabulary. Credentials stay in memory and Keychain; configuration descriptions
  redact them. Turning off learning/transcript saving/recovery takes effect on outstanding work.
- AI polishing is opt-in, with a two-second default total deadline (configurable up to 30 seconds). A late noncooperative model cannot commit after the
  timeout or Escape. Timeout inserts the local fallback once. Cancellation inserts nothing.
- Known official OpenAI reasoning models use completion-token budgets and low reasoning effort;
  ordinary official models use bounded output tokens. Compatible servers keep minimal requests.
  Claude effort is limited to known supported families. This is a conservative request policy,
  not a complete registry of model capabilities. Model IDs remain editable.
- Auth, access, quota, missing model, timeout, unreachable, invalid, empty, and incomplete output
  failures are safe history categories. Provider response bodies are not retained or shown.
  Requests use an ephemeral session with no cookies/cache and refuse HTTP redirects.
- Queued paste waits through the previous paste's 400ms clipboard interval, then checks the
  transaction and destination again. The interval is compatibility time, not proof that an editor
  consumed the clipboard. Same-field caret changes and actual paste acknowledgement remain
  compatibility work described in [transaction details](recording-insertion-transactions.md).
- Recovery is available from the menu and Privacy settings, and interrupted audio is discovered
  on launch. Retry uses local file recognition and never auto-inserts. Export audio/text or delete
  a record explicitly. Cancelling/selecting another record/deleting prevents late retry commits.
- Failed dictations follow the configured retention; default retention ends on the next completed
  dictation. Extended durations are checked at launch, settings changes, completion, and every
  five minutes while running. Turning off the safety copy deletes dictation recovery records.
- Conversation audio has durable per-session journals and per-source segments. Active sessions
  are excluded from recovery imports. Capture timestamps map file offsets to wall time across
  gaps; gaps are annotated in completed transcripts. Sleep rebases delivery health; restart
  attempts are bounded. Failed sources or failed transcript saving preserve their audio until
  explicit deletion. Recovery import retries durable archive failures without moving live files.
- Audio conversion considers interleaving and both input/output format changes, rounds capacity
  upward, and supplies each input buffer once. Conversation writers serialize file access and
  convert to the file's actual processing format.
- Vocabulary offers exact casing, term removal, JSON/newline import, and JSON export. Budgets are
  64 terms, 80 characters per term, 4,096 characters total. Learned corrections remain separate,
  individually removable, and only relevant bounded hints reach cleanup. Native speech bias is
  not enabled: Apple documents contextual vocabulary for DictationTranscriber, while this app
  retains SpeechTranscriber. A backend change needs measured accuracy/latency evidence.

The provider policy follows [OpenAI's request reference](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create)
and [Claude effort support](https://platform.claude.com/docs/en/build-with-claude/effort).
The vocabulary distinction follows [Apple's contextualStrings documentation](https://developer.apple.com/documentation/speech/analysiscontext/contextualstrings).

## Continuous and local checks

`.github/workflows/ci.yml` runs separate macOS SwiftPM/bundle and iOS keyboard simulator jobs.
It uses read-only repository permission, a pinned checkout action, and no signing/cloud secrets.
Hosted macOS 26 runners provide the required SDK generation; see
[GitHub's runner announcement](https://github.blog/changelog/2026-02-26-macos-26-is-now-generally-available-for-github-hosted-runners/).
The workflow has been created locally; it has not yet executed on GitHub.

```sh
swift test
BUILD_CONFIGURATION=debug CODE_SIGN_IDENTITY=- Scripts/make-app.sh
Scripts/validate-app.sh build/Dictate.app
(cd iOS && xcodegen generate)
Scripts/test-ios.sh
Scripts/preview-ui.sh recovery
Scripts/preview-ui.sh vocabulary
```

The preview uses a separate app identifier and synthetic, isolated temporary data. It does not
install hotkeys, access the microphone, run the updater, or terminate normal Dictate instances.
UI inspection verified recovery layout/retry and vocabulary layout/add. During the first inspection,
the UI tool reopened a normal development bundle after closing a same-identifier preview; the
installed app was restored. The separate preview identity now prevents that path.

Verification results in this working tree:

- SwiftPM reported **255 cases: 251 executed successfully, 4 hardware/ASR cases explicitly skipped**
  (125 VoiceKit cases including the four skips, 126 Dictate cases, 4 evaluator metric cases).
- **7 iOS keyboard tests passed** on an iOS 26.5 simulator with signing disabled.
- Development app bundle built and passed signature/structure/permission/notice/40-locale checks.
- Shell syntax and `git diff --check` passed.
- Evaluator smoke test emitted `audio_missing` skips and exited **2** in strict mode; no ASR
  quality or latency measurements were produced.

Integration tests are opt-in rather than silently returning success without using speech hardware:

```sh
VOICEKIT_HARDWARE_TESTS=1 swift test --filter 'LiveCaptureRecoveryTests|FileTranscriberTests'
```

Use an already authorized Mac, installed speech assets, an unmuted speaker/microphone loopback,
and an idle microphone. These tests can synthesize audible speech, open hardware, create a
private aggregate device, and download missing Apple speech assets. Missing opted-in prerequisites
produce an issue instead of being counted as measured recovery. They are not run by default CI.

## Reproducible speech evaluation

`VoiceKitEvaluate` links only VoiceKit. A manifest is an array of `id`, relative `audio`, `expected`,
`locale`, and `category` objects. IDs must be unique; text scoring is capped at 10,000 characters.

```json
[
  {"id":"name-01","audio":"name-01.caf","expected":"OpenWhispr uses Kubernetes.",
   "locale":"en-US","category":"technical-names"}
]
```

```sh
Scripts/make-evaluation-fixtures.sh  # synthetic smoke speech, not a real corpus
swift run VoiceKitEvaluate --fixtures build/evaluation-fixtures/manifest.json \
  --output build/evaluation-report.json --runs 2 --require-measurements
```

The evaluator never requests speech authorization. Missing permission, files, or assets produce
explicit skip records; failed transcription produces a failed record. Asset downloads require the
explicit `--allow-model-download` flag. Strict mode exits 2 if any run is skipped or failed.
Reports stay local and contain actual recognized text, OS version, run index, total file
transcription time, word/character edit counts and error rates. Metrics normalize case and NFC;
WER uses Apple's word tokenizer, CER excludes punctuation/whitespace. Empty references use a
denominator of one so inserted speech remains visible. No accuracy threshold is imposed yet.

Sequential runs provide a repeatability baseline, not guaranteed cold/warm model isolation.
They do not measure microphone start, first streaming word, stop/finalization, cleanup or actual
paste latency. Record those separately during signed-app trials. Add consented real recordings
for brief/whispered speech, pauses, noise, technical names, multilingual/unspaced speech,
literal questions, self-correction, multiple speakers, speaker bleed and double-talk before
changing VAD, AEC, ASR backends, or speaker identity behavior. Do not commit personal recordings.

## Distribution and localization

Resolved source dependencies are FluidAudio 0.15.5 and Sparkle 2.9.4. Bundle assembly includes
OpenWhispr attribution plus FluidAudio/Sparkle/VBx/fastcluster licenses. Packaging forces a release
build and validates the bundle before notarization. This task did not notarize, upload, replace an
installed build, or publish an appcast. The installed app was restored after the preview incident.

The current FluidAudio online diarizer loads `pyannote_segmentation.mlmodelc` and
`wespeaker_v2.mlmodelc`. The [model card](https://huggingface.co/FluidInference/speaker-diarization-coreml)
identifies these as legacy conversions, separate from the newer Community-1 artifact set.
Its [notice](https://huggingface.co/FluidInference/speaker-diarization-coreml/blob/main/NOTICE.md)
requires evaluating legacy provenance separately. The referenced upstream segmentation is MIT;
WeSpeaker embedding is CC-BY-4.0. Attribution links are in `ThirdParty/Diarization-MODEL-NOTICE.md`.
No weights are bundled. Verify the exact downloaded artifact revision/hash and matching notices
before redistributing model files or changing models; the library version alone does not pin
mutable hosted weights. Updater signature/ticket validation and permission continuity after a
real signed update remain release checks.

Forty locale bundles are structurally complete via English fallback. New/updated UI copy has not
been fully translated: `Scripts/localize.py --check` currently reports **87 missing keys per
non-English locale (3,132 locale-key instances)**. This is recorded translation work, not a passing
translation audit. The speech-permission disclosure was corrected across the 33 source-language
files; native review remains advisable. The canonical privacy policy changed; its website mirror
still needs publication with the next website update.

See [dictation latency](dictation-latency.md) for warm preparation, fast local defaults, and local measurement commands added October 15, 2026.
