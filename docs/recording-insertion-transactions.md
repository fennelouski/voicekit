# Recording and insertion transactions

Implemented October 14, 2026 as the first follow-up to the OpenWhispr roadmap.

## User-visible behavior

- A dictation records its intended destination **when recording starts**, before showing the HUD or awaiting permissions/models. Capture includes the process ID and launch date, focused window, and text-field identity. Password fields, disabled controls, non-text focus, missing Accessibility permission, and unavailable metadata are not verified targets.
- Immediately before insertion, the same app lifetime, window, and text field must still be focused. Dictate never activates or switches to the original app. If the match fails, it retains the finished transcript in history when history is enabled, copies it for manual paste, and shows a focus-change message.
- Verified paste events are addressed to the captured process ID. A later app activation cannot redirect the events to another process. Posting an event is not confirmation that a third-party editor accepted the paste.
- Escape cancels both the current dictation and **all outstanding dictation cleanup jobs**. It works during cold start, capture, finalization, offline recovery, provider cleanup, and queue waits. The cancelled jobs cannot subsequently insert, replace the clipboard, append history, increment completed-dictation counts, or count learned correction usage.
- Cancellation deletes the cancelled session's recovery audio when capture closes (queued, already-closed recordings are discarded promptly), and removes its optional conversation transcript. It does not delete previously completed history/transcripts or undo text already pasted.
- The next recording can start once capture teardown has settled. New jobs bypass the retired queue, so a cleanup provider ignoring cancellation cannot hold them behind an old request. Its late response still cannot commit.
- Escape passes through to other apps while Dictate has no cancellable work. An Escape that cancelled work is consumed through key-up, including repeats, to avoid cancelling a subsequent dictation. If the macOS event tap cannot be created, the fallback global monitor still cancels but cannot swallow another app's Escape.

## Ownership and cancellation

`DictationTransaction` supplies an identity, cancellation flag, current task, captured destination, and file-discard callbacks. The main actor owns the transaction registry and every UI, clipboard, and insertion decision. Cancellation marks all tokens synchronously before cancelling their tasks. Checks after every suspended cleanup/recovery operation and immediately before commit are required even when a provider ignores task cancellation.

A cancelled cold start keeps the recognition service exclusive until it returns or throws and is torn down. Stream consumers check their transaction before touching the accumulator/HUD. Watchdog callbacks cannot stop a replacement session. Cancelling analyzer finalization targets the captured analyzer rather than whatever analyzer the service might use later.

`CleanupChain` reports cancellation separately from failure. It never tries the next provider or returns a fallback as a successful cleanup after cancellation. URLSession requests run in the owned cleanup task, so cancelling that task propagates to its request. File recovery explicitly cancels its analyzer and result collector. Conversation recorder cancellation prevents late metadata, segments, model installation, and finish callbacks from recreating a discarded file. Session filenames include a unique suffix so cancelling one session cannot delete another recorded in the same second.

`InsertionGate` has no suspension between verifying the destination and posting the process-addressed events. `ClipboardTransaction` continues to restore existing formats only while it owns the clipboard. A destination mismatch uses an explicit manual-copy path and cancels any pending clipboard restore.

Recording, formatting, locale, vocabulary, and full immutable provider model/key/URL/instruction options are captured at start. Optional AI polishing has a two-second default total deadline (configurable up to 30 seconds) that retires late model results. Before committing a queued insertion, the controller waits through the preceding clipboard settling interval and rechecks cancellation/focus. The existing Accessibility correction observer also rechecks the insertion destination before its delayed field snapshot, and excludes secure subroles.

## Verification

The deterministic tests run the real `DictationController` with injectable recognition, HUD, cleanup/recovery, insertion, history, and recovery-sweep boundaries. They do not open the microphone, modify the general clipboard, change user preferences, or delete production recovery files. Controlled gates model services that return late despite cancellation.

Covered cases:

- Changed app, field, or window during slow cleanup: manual copy/history; zero paste events.
- Unchanged destination: exactly one paste to the captured PID.
- Unverifiable destination and failed event posting: manual copy.
- Escape during startup: late recognition is closed; overlapping starts remain prohibited.
- Escape during capture/finalization: no history, clipboard, or paste side effects; recovery audio discarded.
- Escape during file recovery: late transcript is discarded.
- Escape with active/queued cleanup: entire backlog cancelled; a new job completes before the old provider returns; no stale HUD update or duplicate paste.
- Provider cancellation: no fallback provider is invoked and cancellation is not reported as cleanup failure.
- Idle/repeated Escape handling, unique session transcript ownership, and late recorder callbacks after cancellation.
- Pre-cancelled recognition/recovery stops before permissions, microphone setup, or file access. Pending learned corrections can be previewed without recording automatic-use statistics.

Verification completed:

- `swift build`: succeeded.
- Initial transaction pass: `swift test` reported **227 cases** (119 VoiceKit, 108 Dictate).
- Latest follow-up: **255 SwiftPM cases, 251 executed successfully and four explicitly skipped**; see [reliability verification](reliability-verification.md).
- `xcodebuild test` on the iPhone 17 Pro / iOS 26.5 simulator: **7 keyboard pipeline tests passed** after the shared recognition/recovery changes.
- `git diff --check`: clean.

Hardware/model integration tests now require explicit opt-in and report skips by default. Lifecycle/gate/deadline tests are deterministic and exercise cancellation without those prerequisites.

## Remaining release checks

Actual Accessibility identities and process-addressed paste delivery still need a signed-app compatibility pass in native editors, browsers/contenteditable fields, terminals, and remote desktops. Apps that do not expose reliable text-field/window metadata intentionally use manual paste. Verify Escape with Fn/Right Command held, secure input enabled, multiple displays/Spaces, and revoked permissions. Verify microphone shutdown and model cancellation with real devices and cold downloads.

The guard checks the field/window, not a saved caret or selection range. Moving the caret or editing within the **same field** while cleanup runs still uses that field's current caret. Synchronous focus checking and event posting cannot establish an atomic transaction with an arbitrary third-party application: that would require editor acknowledgement or a targeted insertion API. No automatic retry or app activation is introduced here.

The macOS event tap and process-directed event APIs follow Apple's [event tap documentation](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)) and [CGEvent API](https://developer.apple.com/documentation/coregraphics/cgevent).

See [dictation latency](dictation-latency.md) for warm preparation, fast local defaults, and local measurement commands added October 15, 2026.
