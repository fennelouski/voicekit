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

## Local Apple platform checks

`Scripts/check.sh` is the verification entrypoint. It runs directly on a development Mac and
requires macOS 26+, Xcode 26+, Python 3, XcodeGen (`brew install xcodegen`), and an installed
iOS 26+ iPhone simulator. Package resolution may download source dependencies on a fresh
checkout. No hosted CI service, GitHub Actions minutes, billing setup, cloud secrets, or
paid signing certificate is required.

```sh
Scripts/check.sh        # both platforms; the pre-push hook runs this command
Scripts/check.sh macos  # desktop suites, bundle validation, timing-report tests
Scripts/check.sh ios    # generate the project and run keyboard tests on a simulator
```

Every run checks shell syntax and staged/unstaged whitespace, records the commit and dirty
working-tree status, and saves `check.log` plus `summary.txt` in a unique directory under
`build/checks/`. A failed step returns a nonzero exit status and names the failing step in the
summary. A platform-specific pass covers only that platform. The default full run covers:

- macOS deterministic SwiftPM suites, with hardware/ASR tests disabled.
- Debug app assembly with ad-hoc signing, bundle signature/structure/permission/license/localization validation.
- The Python timing-report regression suite, retained from the former workflow.
- XcodeGen project generation and iOS keyboard simulator tests with signing disabled.

The versioned `.githooks/pre-push` hook blocks pushes if the full local check fails. Enable it
once for each clone (configured in this working repository on October 26, 2026):

```sh
git config --local core.hooksPath .githooks
```

The checks use the current working tree, including uncommitted files; the report records that
state. They do not certify a different revision being pushed. Run from the intended checkout
before pushing. Microphone/ASR measurements remain a separate explicit opt-in below.

GitHub Actions has been retired for this project. The hosted workflow was disabled on
October 26, 2026, and its original configuration is retained for reference at
[`.github/disabled-workflows/apple-platform-checks.yml`](../.github/disabled-workflows/apple-platform-checks.yml),
outside the active workflows directory. The earlier
[hosted run](https://github.com/fennelouski/voicekit/actions/runs/38617069096) stopped before
assigning runners; local verification replaces that dependency entirely.

### Local entrypoint verification (October 26, 2026)

`Scripts/check.sh` completed both platforms with Xcode 27.1 / Swift 6.4: 261 macOS tests
passed, four hardware/ASR tests were explicitly skipped, all three Python tests passed, and
all seven iOS keyboard tests passed on iOS 27.1. The ad-hoc app bundle passed validation for
signature, structure, permission disclosures, licenses, and all 40 locales. Shell syntax and
both whitespace checks passed. The report is in `build/checks/20261026T175558Z-e5F2fd/`.
Invoking the pre-push hook with XcodeGen absent from PATH returned exit 1 at preflight and
saved a failure summary, verifying that prerequisite failures block the hook.

### Local CI-equivalent rerun (October 18, 2026)

With Xcode 27.1 / Swift 6.4, `swift test` reported 265 tests across the three test targets:
261 passed and four opt-in hardware/ASR tests were skipped. The debug app built with ad-hoc
signing and passed bundle validation, including all 40 locales. All three Python timing-report
tests passed. XcodeGen generated the iOS project, and `Scripts/test-ios.sh` passed all seven
keyboard tests on an iPhone 18 Pro with iOS 27.0, with signing disabled. Workflow validation
with actionlint 1.7.12, shell syntax checks, and `git diff --check` passed. This historical run
preceded the move to the local verification entrypoint. The earlier record below is retained
for context.

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
produce an issue instead of being counted as measured recovery. They are not run by the default local checks.

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
files; native review remains advisable. The canonical privacy policy and website mirror were published together with Dictate 1.5.0
on October 26, 2026; see [deployment verification](releases/1.5.0-deployment.md).

See [dictation latency](dictation-latency.md) for warm preparation, fast local defaults, and local measurement commands added October 15, 2026.
