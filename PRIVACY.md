# Dictate Privacy Policy

Effective date: July 15, 2026

This is the canonical Privacy Policy for Dictate. The website mirrors it verbatim at
https://nathanfennel.com/dictate/privacy — keep the two in sync when editing.

## Summary

Dictate is built to keep your voice and your words on your Mac. By default, everything happens
on-device. We run no servers that receive your audio or text, we use no analytics, and the app does
not phone home. The only time anything leaves your Mac is if you deliberately turn on an optional
cloud cleanup feature and supply your own API key.

## Who we are

Dictate is made by Nathan Fennel. Contact: nathan@100apps.studio.

## What Dictate processes on your device

- **Microphone audio.** Captured only while you are actively dictating (holding the hotkey, or
  after a tap that locks dictation on). Speech is transcribed on-device using Apple's
  SpeechTranscriber and SpeechAnalyzer. Dictate never sends your audio off the device.
- **Transcribed text.** Inserted into the app that has focus, using the macOS Accessibility and
  clipboard features.
- **Dictation history.** The last hour of dictations is kept in memory so you can recall it with
  Control-Option-Command-V. It is never written to disk and clears when the app quits.
- **Learning log.** When enabled, Dictate stores a small file in your Application Support folder
  containing statistics and correction pairs (a misheard word and your fix). It never stores full
  transcripts. Reverting a correction removes it.
- **Conversation transcripts.** If you turn this on, Dictate writes speaker-labeled transcripts of
  your dictation sessions to local files on your Mac. They stay on your Mac.
- **Accessibility.** To insert text and to learn from your edits, Dictate reads the contents of the
  focused text field through the Accessibility API. Password and other secure text fields are never
  read.

## Optional cloud cleanup

Dictate can polish a transcript before inserting it. The on-device options (Apple Intelligence) keep
everything local. If you choose a cloud provider (Claude, OpenAI, Google, Groq, OpenRouter, or a
custom OpenAI-compatible server) and enter your own API key, then your transcribed text, and only
the text, never the audio, is sent to that provider to be rewritten. That provider processes it
under its own terms and privacy policy. We are not a party to that exchange and receive no copy. If
a cloud request fails, the local transcript is used unchanged. Your API keys are stored in the macOS
Keychain.

## What we collect

Nothing. Dictate has no accounts, no analytics, no telemetry, no advertising, and no crash reporting
to us. We do not receive your audio, your transcripts, your corrections, or your usage. Any crash
reports handled by macOS follow Apple's policies and are not sent to us unless you choose to share
them.

## Data storage and deletion

The local data described above lives in your user Library and Keychain. Quitting the app clears the
in-memory history. Deleting the app together with its Application Support folder removes everything
Dictate created.

## Children

Dictate is not directed to children under 13, and we do not knowingly collect information from them.
We collect nothing from anyone.

## Changes to this policy

We may update this policy. Material changes will be reflected here with a new effective date.

## Contact

Questions about privacy: nathan@100apps.studio.
