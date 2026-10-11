# Open Quill

A native, free Mac dictation app. Speech recognition, text cleanup, correction learning, history and statistics run on your Mac. A one-time model download is the only network operation the app implements. There are no accounts, API keys, telemetry or cloud transcription.

**Apple silicon · macOS 14+ · 100 speech languages with Whisper · MIT licensed**

- Middle-click or a configurable keyboard shortcut to dictate into the focused text field.
- Live transcript preview, keyboard hold-to-talk, spoken snippets and optional on-device AI cleanup.
- Personal names, correction rules, app preferences, local history and statistics.
- Adjustable 1–30 minute recordings and optional quiet-pause stopping.
- Shortcut availability is checked live. Your chosen key combination is reserved exclusively and retries after another app releases it.
- A guided setup with private practice and a remembered microphone picker.
- Searchable language selection for dictation, practice, app preferences and personal spelling rules.
- Compact listening feedback that unfolds below a MacBook notch or floats at the bottom of an external display.

This is an early source release. Build it locally using the steps below; a notarized download is not available. Open Quill is an independent project and is not affiliated with OpenAI or Wispr Flow.

## Run the app

Requires Apple silicon, macOS 14 or later, and Xcode / Swift 6.2 or later to build.

```sh
./scripts/build-app.sh
open "dist/Open Quill.app"
```

First launch opens a five-step setup: privacy, permissions, speech model, microphone and shortcuts, then a private practice field. You can skip it and reopen it from **Settings → Setup guide** or **Help → Show Setup Guide**. Practice text stays in memory and never enters another app, submits a message, or contributes to history and statistics. Existing users keep their setup and preferences. The visual specification, requested from Claude before implementation, is in [docs/DESIGN.md](docs/DESIGN.md).

Download **Parakeet Ultra** during setup or in Settings. If the files are already present, the app loads them locally on launch. Allow **Microphone** when macOS asks, and enable the app under **System Settings → Privacy & Security → Accessibility**. Refresh permissions in the app. Already allowed microphone access shows its status without another request button. Denied access offers a link to macOS privacy settings. macOS owns these permissions; the app cannot grant them itself. Some systems may also require Input Monitoring for the mouse trigger.

Local builds use a persistent self-signed development identity stored in an owner-only, separate keychain under `~/Library/Application Support/WisperFlowBuildSigning/`. The keychain password is generated locally and kept in an owner-only file in that folder. Its certificate is pinned in the app's designated requirement, so an ordinary rebuild retains the same identity. The build does not change certificate trust settings or use your login keychain. Keep this signing folder private and retain it between builds. Models and history remain in Application Support.

For existing users, the internal bundle identifier (`be.nick.wisperflow`), preferences domain and Application Support paths retain their original names. This compatibility choice preserves permissions, models and history through the Open Quill rename (formerly Open Whisper and Wisper Flow). New installations use those same internal paths; no personal files or signing identities are included in this repository.

When upgrading from an older ad-hoc build, macOS can show an enabled Accessibility switch for an identity that no longer matches. Remove only this project's **Open Quill** (previously **Open Whisper** or **Wisper Flow**) entry using −, add `dist/Open Quill.app` with +, enable it, then quit and reopen the app. **Wispr Flow** is the separate commercial app. This migration needs a fresh grant once; subsequent builds use the same certificate. The app reports actual process access, independently of the displayed macOS switch.

Select a text field in another app, click the **middle mouse button** once, speak, and click again to finish. **Option-Space** is the default keyboard alternative. Change it in **Settings → Dictation → Keyboard shortcut → Record shortcut**: press a combination that includes Command, Option or Control. Escape cancels capture; Reset restores Option-Space. Choose press-to-toggle or hold-to-talk in Keyboard behavior. The middle button always toggles independently. **Escape** cancels recording or transcription. Once text insertion begins it completes as one edit. Middle-button clicks are consumed while the trigger is enabled; disable that trigger in Settings to restore ordinary middle-click behavior. The app stays in the menu bar when its window closes.

## Choose a local model

| Model | Intended use | Approximate download |
| --- | --- | --- |
| Parakeet Ultra via FluidAudio | Fast everyday dictation in 25 European languages | 630 MB |
| Whisper large-v3 via WhisperKit | Full 100-language catalog for accuracy comparisons | 3 GB |
| Whisper large-v3 Turbo via WhisperKit | Faster Whisper decoding with the same language catalog | 1.6 GB |

These sizes are estimates. Model preparation can take longer on the first load while Core ML compiles device-specific graphs. Subsequent dictations keep the model in memory. Only one model is loaded at a time.

English is the default. Dictation preserves the spoken language rather than translating it to English. Search by language name, native name or code in the language selector; unsupported Parakeet languages are marked “Whisper required”. Choose and explicitly download a Whisper model for those languages. Global, per-app, practice and audio-file transcription validate the model’s language coverage. The interface remains in English; language recognition does not imply support for every world language or equal accuracy across accents.

Parakeet supports Bulgarian, Croatian, Czech, Danish, Dutch / Flemish, English, Estonian, Finnish, French, German, Greek, Hungarian, Italian, Latvian, Lithuanian, Maltese, Polish, Portuguese, Romanian, Russian, Slovak, Slovenian, Spanish, Swedish and Ukrainian. Auto detection is optional. Parakeet detects speech language internally; the app infers a language label from its output with Apple's local language recognizer. Its language preference filters scripts rather than forcing a decoder token. An undetermined language label stays undetermined and does not teach language-specific corrections. Whisper supports an explicit language choice and personal vocabulary hints. Automatic detection uses global vocabulary rules without mixing hints from every specific language. The runtime choice is not proof of a best model for your voice: compare a representative recording locally, particularly spontaneous Flemish speech.

Primary references: [FluidAudio Ultra measurements](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/ParakeetUltra.md), [NVIDIA Parakeet language support and benchmarks](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3), [Whisper models](https://github.com/openai/whisper), [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift). All three available models are free to run locally. Credits and licenses are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Text insertion and correction learning

The app captures the foreground app, focused field, field value and selected range before recording. If the app, field, caret, selection or text changes before insertion, the transcript is retained for copying. Standard text fields receive normal Unicode text input events directed to the captured app, preserving surrounding text and replacing the selection. This reaches input handlers in browser and Electron editors; the Accessibility selected-text setter is used when normal event delivery is unavailable. History records verified and unverified delivery separately, and an ambiguous delivery is never automatically retried. Apps that do not expose an editable field may need the optional clipboard fallback. That fallback is off by default, restores the clipboard only if nobody else changed it, and may interact with Universal Clipboard. Password fields are blocked.

After verified insertion, the app watches that field for up to 60 seconds while it remains focused. It keeps surrounding text fixed and considers only short, contiguous substitutions inside the dictated span. In an otherwise empty field it requires shared text between the original and edited dictation, so whole-message replacement is not learned. It stops tracking when context changes and learns after the edit stays stable for two seconds, without requiring a focus change. A correction seen twice activates for that app and language; conflicting replacements remain inactive for review. Vocabulary shows every learned rule and allows disabling or deleting it. You can also correct a saved transcript manually. **Vocabulary → Teach a name or term** creates an immediately active “heard as → write as” spelling rule across apps, optionally restricted to any catalog language. Explicitly taught spellings take precedence over older automatic guesses; otherwise app-specific rules take precedence over global rules. Active correction targets are also supplied to Whisper as recognition hints. Parakeet Ultra uses these rules after recognition; it does not consume the freeform recognition-hints list.

Electron apps are asked to expose their accessibility tree using Electron’s documented `AXManualAccessibility` flag. When an editable field provides text but omits the caret, the app can verify a unique, complete insertion against the original text and track that exact span. Ambiguous matches are skipped. Validated full-range readback is preferred over AXValue when available, since rich editors can expose a stale or partial value. If the target does not expose enough information, “Couldn’t confirm the text” means typing was dispatched but acceptance could not be checked: the transcript remains on Dictate and automatic correction tracking is off for that dictation. Supported fields are watched in the destination app; you do not need to edit inside Open Quill.

Learning personal vocabulary uses local replacement rules and recognition hints. It does **not** fine-tune model weights. Optional generative cleanup is a separate setting described below. Apple’s local word tokenizer supports short corrections and names in languages without spaces, including Japanese, Chinese and Thai. Rules preserve the exact text between the changed words, including repeated spaces; surrounding text must remain unchanged. Punctuation-only edits do not teach spelling rules. Replacement candidates are checked against word boundaries in the original transcript, resolved by existing rule priority and applied once without cascading. Segmentation is language-dependent and can be ambiguous; review or disable a rule if it matches an unintended name. The speech model provides punctuation and capitalization; optional spoken punctuation commands support English and Dutch. Per-app settings customize language, spoken commands and optional Enter after dictation, and learned replacements are scoped to the detected app. Complex rewrites and ambiguous edits are deliberately skipped.

**Settings → App preferences → [app] → Press Enter after dictation** is opt-in and off by default for every app, including existing saved app preferences. The setting is captured for the original app when dictation starts and applies to hotkey, time-limit and silence completion. Enter is dispatched only after the full typing/paste operation, a short queue-drain delay, and a fresh focus check. Failed, skipped, cancelled and partial insertion never sends Enter; AX-setter delivery needs verification. When readable, changed/unchanged field data can also suppress Enter. For editors without readback, a fully dispatched keyboard operation is not proof of renderer acceptance. Enter can send a message or submit a form; enable this only for apps where you want that behavior. Audio-file imports never press Enter, and a submitted field is not watched as a correction.

## Recording feedback and silence stopping

**Settings → Dictation → Input device** offers Automatic (your Mac’s system input) and the available microphones. A specific device is remembered by its persistent UID and applies to the next recording without changing the system-wide input. If it disconnects, recording reports the unavailable device instead of silently switching microphones. Use Refresh after connecting a device, or choose Automatic.

**Settings → Dictation → Mute audio while recording** is off by default. When enabled, it temporarily mutes the Mac’s default audio output and system alert output during dictation and setup practice, following output-device changes. Finishing, quiet-pause/time-limit stopping, cancellation, a start failure and normal app termination restore outputs the recording muted before transcription, without changing playback volume or unmuting an already-muted output. An explicit unmute is respected. Devices must expose macOS software mute; an unsupported output reports an error instead of recording with audio playing. Apps routed directly to a different output are outside the default routes. Force-quitting or a process crash cannot run restoration; an output disconnected before restoration may need its own mute control after reconnecting.

Choose **Settings → Dictation → Maximum recording** to set a limit from **1 to 30 minutes** (default: 3). The audio-buffer bound, automatic stop, Dictate screen and overlay all use the chosen limit, captured when recording starts. At the limit, the app transcribes and inserts automatically. Longer recordings use more memory and can take longer to transcribe. The listening panel is a persistent, nonactivating SwiftUI view: a real microphone-level history updates at 30 Hz, with fast attack and smooth release. It shows elapsed time and the recording limit without stealing the text-field focus.

**Settings → Dictation → Finish automatically after a quiet pause** is off by default. Enable it and choose 3, 5, 8, or 10 seconds. Once at least 250 ms of continuous above-threshold audio has been observed, a sustained quiet pause finishes through the same transcription/insertion path as the hotkey. This is loudness-based quiet detection, not semantic voice activity detection: background noise can keep it running, and faint speech can fall below the threshold. Choose a sensitivity preset for your microphone and room; threshold changes apply to the next recording. No silence model downloads or network calls are needed.

## Live preview, snippets and local AI cleanup

**Settings → Dictation → Show live transcript preview** is on by default. While speech is active, the app transcribes a rolling window of up to 12 seconds, waiting two seconds between passes. The listening panel shows one compact provisional line; Dictate and setup practice show more text. These words can change and never enter the destination field while recording. Stopping transcribes the entire recording for the final result. Preview uses the selected local speech model; Whisper can update slowly. Disable it to avoid extra model work. In-flight preview work is cancelled and awaited before final decoding, so the same model never decodes both concurrently. Processing statistics include time waiting for that preview and optional cleanup, ending before text delivery.

Open **Snippets → Add snippet**, save a deliberate phrase such as “my signature”, and enter the exact replacement. Say that phrase during dictation to insert its saved text, including links, Unicode and line breaks. Matching ignores case, respects language-aware word boundaries, prioritizes a longer trigger at the same position, and expands every occurrence once without cascading. Snippets apply across apps and languages; they do not execute commands. Turn an individual snippet off, edit it or delete it on the same page. Duplicate trigger phrases are rejected. Triggers allow up to 80 characters; replacements up to 10,000. Snippets are saved locally with history and survive an upgrade from the older history format.

**Settings → Local AI cleanup → Lightly polish dictation before inserting** is off by default. It uses Apple's **Foundation Models** on-device language model to tidy obvious fillers, grammar slips and explicit spoken self-corrections. It requires **macOS 26+, an eligible Apple Intelligence Mac, Apple Intelligence enabled, a ready on-device model and a supported language**. Build with Xcode 26+ to include this optional integration; older SDK builds retain normal dictation. The app never selects a cloud fallback. Apple manages provisioning of its model separately from the speech-model download. The current availability is shown in Settings. Each app can inherit the global switch or override it under App preferences.

Cleanup has a conservative prompt and a fresh session per dictation. Unavailable models/languages, cancellation, generation failures, overlong input (more than 4,000 characters) and rejected output preserve the original transcript. Validation rejects empty or excessively expanded/truncated text, changed literal numbers and missing matched snippet triggers or supplied vocabulary. This cannot guarantee identical meaning: review important text, especially if automatic Enter is enabled. Cleanup runs before spelling rules and snippet expansion, so snippet replacements stay exact. History retains both the original speech-model transcript and the final text. Ordinary dictation, snippets and spelling rules remain available on macOS 14+ without Apple Intelligence.

## Personal speech profile

The Speech profile page summarizes retained dictations: transcript language, average dictation pace including pauses, corrected transcript count, and selected English and Dutch filler phrases found in English and Dutch records. Imported audio is excluded. Word counts use Apple’s local language-aware tokenizer, including languages without spaces, and exclude punctuation-only and emoji-only tokens. Word boundaries and pace are estimates and are not directly comparable across every language. Counts are derived when a transcript loads or changes and are not saved in the history schema or recomputed while the listening meter animates. Dialect/accent is a self-described preference and does not adapt model weights. Language labels come from the selected language or local detection; the app does not automatically classify Flemish dialects. Models may remove fillers, so transcript counts are not a pronunciation, fluency, or grammar score. A small reflection tip supports clearer phrasing without pretending to grade the speaker.

## Local data

Stored under `~/Library/Application Support/WisperFlow/`:

- `Models/`: downloaded Core ML model files.
- `Tokenizer/`: local tokenizer files for Whisper.
- `history.json`: up to 1,000 transcripts, app/language labels, duration/processing statistics, correction rules and spoken snippets. The file has owner-only permissions.

Preferences live in the app's macOS UserDefaults domain. The microphone buffer is in memory, bounded to the chosen recording limit (1–30 minutes), and discarded when stopped. Audio is never saved by dictation. History and learning have separate switches. Disabling history stops new entries and statistics; existing history can be exported or deleted. A corrupt history file is preserved instead of overwritten.

## Validation

```sh
swift test
./scripts/verify-offline.sh
./scripts/verify-signing.sh
./scripts/verify-recording-mute.sh
```

The first command also checks snippet upgrade/persistence, literal multiline expansion, overlapping/disabled triggers, non-cascading replacements and protected cleanup fallback. It checks the local correction/persistence feature flow, context isolation, Unicode, conflicting substitutions, global taught-name precedence, quiet-pause timing/toggle behavior and 1/3/10/30-minute limits, speech-profile accounting including Japanese/Chinese/Thai word boundaries, literal spacing in name corrections, and punctuation-only edits. The second performs real model inference on generated English, Belgian Dutch, French, German and Spanish speech while macOS denies network access to the executable. It requires the Parakeet model to have been downloaded and the macOS Samantha, Ellen, Thomas, Anna and Mónica voices to be available. Synthetic speech is a pipeline check, not a measure of microphone quality or the user's accent.

The signing check changes a disposable copy's version, signs it again, and verifies that it satisfies the original app's identity requirement despite having a different code hash. A valid signature from a different signer must fail that requirement. This checks signing continuity; retaining a real Accessibility grant after a rebuild still needs a macOS permission and relaunch check.

The recording-mute check exercises the production mute controller against the current native audio outputs. It briefly changes mute state and restores the starting state, checking repeatable start/stop, already-muted output, explicit unmute, normal termination and unchanged volume. The outputs must support software mute. Pass `--read-only` to inspect mute and volume without changing them.

The executable also supports local file transcription and explicitly requested downloads:

```sh
"dist/Open Quill.app/Contents/MacOS/OpenQuill" --download-model --model parakeet-ultra
"dist/Open Quill.app/Contents/MacOS/OpenQuill" --transcribe /absolute/path/recording.wav --model parakeet-ultra --language nl
```

No flag performs an upload. Without `--download-model`, model loading and transcription use local files and fail locally if assets are missing. The app is signed with a local development certificate; it is not notarized for public distribution.

## Live acceptance checks

- Start/stop with a physical middle button and Option-Space; Escape discards a recording.
- Dictate English and Flemish in Notes, a browser field and your everyday editor; measure time from stop to insertion.
- Replace selected text, insert at a caret, and verify surrounding text survives.
- Change focus, type, or move the caret during transcription: insertion must be skipped.
- Correct one name twice in the same destination app/language and wait two seconds after each edit; check Vocabulary and the next dictation. Include deleting the mistaken word, pausing a second, then retyping it while the rest of the dictation stays in the field. Edits outside the span, cleared fields and appended paragraphs must not be learned.
- Reopen setup from Settings, walk through it, record and cancel practice, and verify history/statistics are unchanged. Granted permissions must have no request button. “Start dictating” and “Skip setup” must open Dictate; “Review settings” must open Settings.
- Reserve Option-Space in another app before launching Open Quill: Settings must report the keyboard shortcut unavailable, Dictate must show only working shortcuts, and releasing the competing key must restore availability without restarting. Completion must include the selected language and actual shortcut readiness.
- Select each available microphone and record in practice; reconnect a selected device and refresh. An unavailable selection must fail visibly, and Automatic must follow the system input.
- Enable Mute audio while recording, start practice, and check the output is muted only during microphone capture. Finish, cancel and quit while recording; each must restore audio. Reopen the app to check the setting persists, and verify disabled recordings leave audio alone.
- Change Maximum recording, reopen the app and verify it persists; check the overlay uses that duration.
- Enable Press Enter after dictation for a local scratch editor and verify text precedes a single newline; disable it and verify no newline. Check a different app stays disabled and that cancelled/focus-changed/partial insertion does not press Enter. Do not use a real chat for an unattended send test.
- Enable quiet-pause stopping, speak, pause for the configured delay, and verify automatic insertion. Resume speaking before the delay and verify recording continues. Disable it and verify pauses do not finish recording.
- Teach a name explicitly, restart, and dictate it in another app; review the Speech profile and language totals.
- Verify a password field is blocked and an unsupported field retains a copyable transcript.
- Test Accessibility/microphone denied, a hotkey conflict, and optional paste with a clipboard change.

These require permissions and real target apps. Source tests and audio inference do not replace those checks.
