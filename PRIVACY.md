# Dictate Privacy Policy

Effective date: October 14, 2026

This is the canonical Privacy Policy for Dictate. The website mirrors it verbatim at
https://nathanfennel.com/dictate/privacy — keep the two in sync when editing.

## Summary

Dictate is built to keep your voice and your words on your Mac. By default, everything happens
on-device. We run no servers that receive your audio or text, we use no analytics, and the app does
not upload recordings. Optional cleanup sends text, relevant learned spelling hints, and your explicit vocabulary to the provider you
configure. Model downloads and software update checks also use the network, without sending your
audio or transcripts.

## Who we are

Dictate is made by Nathan Fennel. Contact: nathan@100apps.studio.

## What Dictate processes on your device

- **Microphone audio.** Captured only while you are actively dictating (holding the hotkey, or
  after a tap that locks dictation on). Speech is transcribed on-device using Apple's
  SpeechTranscriber and SpeechAnalyzer. Dictate never sends your audio off the device.
- **Safety copy of the audio.** While you are dictating, Dictate also writes the audio to a file in
  your Application Support folder. It exists so that a dictation which fails to transcribe — an
  unplugged microphone, a stalled recognizer — can be transcribed from the recording instead of
  lost. The file is deleted as soon as your text is inserted. A recording kept because it could
  not be transcribed is deleted when your next dictation finishes. Queued recordings remain
  protected until their processing finishes. An advanced setting can extend retention to an
  hour, a day, or a week for diagnosing a faulty microphone. It is never uploaded. Turn it off, or change how long recordings
  are kept, under Settings → Privacy → Recovery. Escape cancels outstanding dictation work
  and discards its recovery files after capture closes, regardless of the retention setting.
- **Transcribed text.** Dictate captures the focused app, window, and text-field identity when
  dictation starts, then checks it before posting paste events to that app. This check reads
  Accessibility metadata, not the field's text. If focus changed or the target cannot be
  verified, the transcript is copied for manual paste and retained according to history
  settings. Cancelled dictation jobs do not copy or insert their results.
- **Dictation history.** Recent dictations, including raw text and cleanup stages, are saved
  locally so you can recall them with Control-Option-Command-V. Saving is enabled by default,
  with one-month retention and a 100-entry cap. Change retention, disable saving, or clear
  history in Settings → Privacy. Quitting the app does not delete saved history.
- **Learning log.** When enabled, Dictate stores a small file in your Application Support folder
  containing statistics and correction pairs (a misheard word and your fix). It never stores full
  transcripts. Reverting a correction reduces its automatic-use count; correction statistics
  and earlier log entries can still retain the pair.
- **Explicit vocabulary.** Names and exact spellings you add are stored locally in `vocabulary.json`.
  Matching words receive your preferred casing locally. Vocabulary is also included as JSON data
  in cleanup instructions, including requests to a remote provider you configure. It is separate
  from learned corrections; manage, remove, import, or export it in Settings → Input → Vocabulary.
- **Conversation transcripts.** Dictate writes speaker-labeled transcripts of dictation sessions
  to local files on your Mac. This is enabled by default and can be turned off in Settings →
  Privacy. Separate conversation recording captures the sources you choose when you start it.
  These transcripts stay on your Mac. Cancelling a dictation with Escape removes that
  dictation session's transcript file; completed sessions are unaffected.
- **Conversation recording audio and recovery.** Selected microphones and apps are written to
  local, journaled audio segments while recording. Audio is deleted only after its transcription
  succeeds and the transcript document is saved. Failed sources, interrupted captures, and
  audio whose transcript could not be saved stay on this Mac until you delete them in
  Recover Recordings. These conversation files do not use the shorter dictation recovery
  retention setting. Recovery metadata records capture date, source label, recognition locale,
  and recording kind. A recovery retry saves text locally and never pastes automatically.
- **Accessibility.** To insert text and to learn from your edits, Dictate reads the contents of the
  focused text field through the Accessibility API. Password and other secure text fields are never
  read.

## Local performance logs

Dictate writes local macOS performance logs containing random transaction identifiers, fixed
processing-stage names, and elapsed milliseconds. They contain no audio, transcript, application
or window names, file paths, or credentials. These timing logs are not uploaded. Speech model
preparation may run while idle after permission grants; it does not open or record the microphone.

## Optional cloud cleanup

Fast local insertion is the macOS default. AI polishing requires explicit opt-in in Cleanup settings, including after upgrading; saved provider configurations are retained. Dictate can polish a transcript before inserting it. The on-device options (Apple Intelligence) keep
everything local. If you choose a cloud provider (Claude, OpenAI, Google, Groq, OpenRouter, or a
custom OpenAI-compatible server), your transcribed text, relevant learned correction hints, and explicit vocabulary, never
the audio, are sent to that provider to be cleaned. Cloud providers require your own API key;
custom servers may not require one. Custom cleanup instructions are sent as well. A custom server can be local or
remote; text stays on this Mac only if that server runs on this Mac. That provider processes it
under its own terms and privacy policy. We are not a party to that exchange and receive no copy. If
a cloud request fails, the local transcript is used unchanged. Your API keys are stored in the macOS
Keychain. Each recorded job captures its provider, model, URL, instructions, and key in memory
so later settings changes do not reroute pending text. Keys are not written to history or recovery
metadata. Failure details use safe categories instead of retaining provider response bodies.

## Model downloads and software updates

Apple speech models may need to download before recognition is available. Speaker diarization
can also download its model assets. Distributed macOS builds use Sparkle to check for and download
software updates. These requests expose normal network information such as your IP address to
the hosting service; they do not include microphone audio, transcripts, or correction history.

## What we collect

Nothing. Dictate has no accounts, no analytics, no telemetry, no advertising, and no crash reporting
to us. We do not receive your audio, your transcripts, your corrections, or your usage. Any crash
reports handled by macOS follow Apple's policies and are not sent to us unless you choose to share
them.

## Data storage and deletion

Saved history, learned corrections, explicit vocabulary, correction statistics, learning logs, recovery audio, and
transcript files live under `~/Library/Application Support/Dictate/`. Conversation recording also
uses durable audio segments and a session journal while it captures and transcribes selected sources. Settings → Privacy
provides controls for history, corrections, recovery audio, and transcript saving. Disabling
transcript saving does not delete existing transcript documents; remove those in the Transcripts
folder if desired.

Delete failed conversation recordings explicitly in Recover Recordings. Turning off the dictation
safety copy deletes dictation recovery files; it does not delete failed conversation audio.

To remove saved app data, quit Dictate and delete its Application Support folder and any transcript
documents you saved elsewhere. API keys are separate Keychain items: clear them in provider
settings before uninstalling, or remove the corresponding `studio.100apps.Dictate` items in
Keychain Access. App preferences are stored separately by macOS. Quitting or deleting the app
alone does not remove all of these files or keys.

## Children

Dictate is not directed to children under 13, and we do not knowingly collect information from them.
We collect nothing from anyone.

## Changes to this policy

We may update this policy. Material changes will be reflected here with a new effective date.

## Contact

Questions about privacy: nathan@100apps.studio.
