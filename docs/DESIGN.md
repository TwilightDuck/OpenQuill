# Open Whisper Design Specification

Authored by Claude at the user's request on 10 October 2026, before onboarding implementation.

Implementation alignment: existing user choices and verified product behavior take precedence over proposed defaults. The recording default remains 3 minutes; external-field learning remains bounded to 60 seconds, a 2-second stable edit, and short substitutions up to 64 characters. Dictation pace includes pauses. An unavailable explicitly selected microphone prompts the user to choose another device rather than silently recording from the wrong input. Model setup displays actual available progress, without invented byte counts, ETA, verification stages or resumability. The keyboard shortcut remains Option-Space. Semantic light/dark colors use native dynamic NSColor providers in this SwiftPM app rather than introducing an asset-catalog compilation pipeline. Practice records only after a deliberate start, with no idle microphone monitoring. These adjustments preserve the document's visual direction while keeping the interface truthful.

Open Whisper is a quiet instrument. It shows up when you speak and gets out of the way when you don't. Every surface should feel calm, warm and exact: a warm neutral base, one teal accent, real system controls, and honest status.

**Principles**
- **Truth over reassurance.** Show the real permission, model and device state. Never imply a capability the system doesn't provide.
- **One accent, used with purpose.** Teal marks the primary action, live listening and readiness. It is never decoration.
- **Native first.** Use system controls, SF Pro, SF Symbols and SwiftUI materials. No web views and no remote assets.
- **Small and legible.** Make it compact, but never at the cost of reading it at a glance.

## Color

Define the colors as asset-catalog color sets with Any and Dark appearances. Reference them only through semantic tokens.

| Token | Light | Dark | Use |
|---|---|---|---|
| `canvas` | `#F7F5F1` | `#141816` | Window background |
| `surface` | `#FFFFFF` | `#1C211F` | Cards |
| `surfaceRaised` | `#FBFAF7` | `#242A27` | Nested cards, scratch field |
| `separator` | `#E4E0D8` | `#323936` | Card borders (1 px), dividers |
| `textPrimary` | `#1E2422` | `#ECEFEC` | Body, titles |
| `textSecondary` | `#5B6460` | `#A7B0AC` | Supporting copy |
| `textTertiary` | `#646C68` | `#879290` | Captions, metadata |
| `accent` | `#0F766E` | `#5ED3BE` | Primary buttons, listening state |
| `onAccent` | `#FFFFFF` | `#062621` | Text on accent |
| `accentSoft` | `#DCEFE8` | `#16332D` | Selected fills, ready chips |
| `accentText` | `#0B5F58` | `#7FE0CE` | Text on `accentSoft` |
| `success` | `#1E7A4C` | `#5CC98C` | Granted, installed |
| `warning` | `#8F5600` | `#E7B04A` | Unavailable device, limited support |
| `danger` | `#B42318` | `#FF7B6E` | Errors, denied |
| `overlayNotch` | `#000000` | `#000000` | Notch overlay fill |
| `overlayText` | `#F2F4F3` | `#F2F4F3` | Notch overlay text |
| `overlayTextMuted` | `#A3ABA7` | `#A3ABA7` | Notch overlay secondary text |

Contrast targets are as follows. All text tokens must reach at least 4.5:1 on `canvas`, `surface` and `surfaceRaised`, and that must be checked during implementation. The approximate design-time values are:
- `textPrimary` ≈15:1
- `textSecondary` ≈5.6:1
- `textTertiary` ≈4.9:1
- light `accent` on white ≈5.4:1
- `accentText` on `accentSoft` ≈6:1

Status is never conveyed by color alone. Always pair it with an SF Symbol and a word.

## Typography

Use the system SF Pro throughout. SF Pro Rounded (`.fontDesign(.rounded)`) is reserved for onboarding display titles and the large numbers in Statistics.

| Role | Spec |
|---|---|
| Display | 28 pt Semibold, Rounded, tracking −0.3 |
| Title | 20 pt Semibold |
| Headline | 13 pt Semibold |
| Body | 13 pt Regular, line spacing 3 |
| Callout | 12 pt Regular |
| Caption | 11 pt Medium, `textTertiary` |
| Numeric | `.monospacedDigit()` for timers, sizes and progress |

Use sentence case everywhere. Line length tops out at 520 pt for body copy.

## Spacing, radius and layout

- **Spacing scale:** 4, 8, 12, 16, 24, 32, 48. The 4 pt base unit is fixed.
- **Radii:**
  - Native control default for buttons and fields.
  - 10 pt for cards.
  - 16 pt for large onboarding panels.
  - 28 pt for the external overlay capsule.
- **Cards:** 16 pt padding, `surface` fill, 1 px `separator` border, no shadows. The only exception is the overlay, which gets a 12 pt blur at 18% black.
- **Main window:** minimum size 820×580. Content margins are 32 pt. The sidebar uses the standard `NavigationSplitView` with sections Dictate, History, Statistics, Speech profile, Vocabulary and Settings.

## Controls

- **Primary buttons:** `.borderedProminent`, tinted `accent`, `.controlSize(.large)` in onboarding. Each view has at most one, and it is bound to `.keyboardShortcut(.defaultAction)`.
- **Secondary buttons:** `.bordered`.
- **Tertiary actions** (Back, Skip): `.borderless` in `textSecondary`.
- **Fields:** native `TextField` and `TextEditor`.
- **Pickers:** `.menu` style for devices and `.segmented` for language.
- **Toggles:** native `Toggle` with `.switch` style.
- **Progress:** linear `ProgressView` for determinate work and a small spinner for indeterminate work.
- **Keyboard:** Escape cancels transient states. Command-[ goes back in onboarding.

## Icons and tone

Use SF Symbols with hierarchical rendering at the system weight. Sidebar symbols:

| Section | Symbol |
|---|---|
| Dictate | `waveform` |
| History | `clock.arrow.circlepath` |
| Statistics | `chart.bar` |
| Speech profile | `person.wave.2` |
| Vocabulary | `character.book.closed` |
| Settings | `gearshape` |

The one custom glyph is the **mouse pictogram**. It is a SwiftUI `Shape`:
- a 1.5 pt stroked mouse body
- a vertical split line
- a centre wheel drawn as a filled rounded rect, 3.5×7 pt at overlay size, filled with `accent` and given a soft 4 pt `accent` glow at 35%

It is drawn at 16×24 pt in the overlay and at 72×108 pt in onboarding.

Tone is plain, second person and short, with no exclamation marks. State facts ("Allowed", "Not connected"). Never use guilt, hype or vague promises like "secure" without specifics.

## Motion

- **Standard transition:** spring (response 0.35, damping 0.86).
- **Micro feedback:** 0.18 s ease-out.
- **Overlay unfold:** 0.30 s spring.
- **Level meter:** five bars, 3 pt wide, updated at 30 Hz with 80 ms smoothing.

When **Reduce Motion** is on:
- Springs become 0.15 s crossfades.
- There is no scale or offset movement.
- Level bars step without interpolation.
- Onboarding compositions appear static.

Nothing loops while idle.

## Listening overlay

The overlay is 280×56 pt. It is a single row with 16 pt horizontal padding and 12 pt gaps:

1. **Level meter** (left), 20 pt tall, `accent`.
2. **Status stack:** "Listening" in Headline, with the elapsed time below in Caption monospaced, for example "0:42".
3. **Spacer.**
4. **Finish hint:** the mouse pictogram with "to finish" in 12 pt Medium. If dictation was started with the keyboard, a keycap reading "⌥ Space" (rounded 5 pt, 1 px border) replaces the pictogram.

**Placement**
- **Built-in display with notch:** a black panel that unfolds downward from the notch. Its top edge is flush and square, its bottom corners have an 18 pt radius, and the 56 pt row sits fully below the notch. Text uses the `overlay*` tokens.
- **External display or no notch:** a capsule centred horizontally, 24 pt above the bottom of the screen's visible frame. It uses `.regularMaterial` with `surface` at 70%, a 1 px `separator` border and a 28 pt radius.

**States**
- **Listening.**
- **Transcribing:** spinner plus "Transcribing".
- **Inserted:** a `success` check plus "Inserted", dismissed after 0.8 s.
- **Error:** a `danger` symbol plus a short reason, for example "Microphone unavailable", dismissed after 3 s.

When the quiet-pause stop is about to fire, the timer is replaced by "Stopping…" for the final 2 s. When the recording limit is one minute away, the timer turns `warning`.

## Onboarding

Onboarding takes over the main window's detail area, with the sidebar collapsed. It is a stage, not a form.

**Frame**
- **Progress:** five short capsules at top centre, 24×4 pt each. Completed capsules are filled `accent`, the current one is 40 pt wide, and upcoming ones are `separator`. Hovering a capsule shows the stage name.
- **Skip:** "Skip setup" sits top-right.
- **Back:** "Back" sits bottom-left and is hidden on Welcome.
- **Primary action:** bottom-right.

**Stage layout:** a 260 pt composition zone, then a Display title, one Body line in `textSecondary` (maximum 2 lines), then stage controls.

**Skip setup** marks setup as skipped and opens Dictate. If essentials are missing, Dictate then shows a slim inline card: "Finish setup to start dictating — [Resume setup]". The setup guide can always be reopened from Settings → General → "Setup guide" and from Help → "Show Setup Guide…".

**Existing users**
- On upgrade, if microphone and Accessibility are granted, a model is installed, or history exists, onboarding is marked complete and never appears automatically.
- Settings, models, device UID and history are untouched.
- A reopened guide reflects live status, so experienced users can press Continue straight through.

### Welcome

- **Composition:** A rounded Mac outline drawn in `separator`. Inside it, a five-bar waveform settles into a line of text reading "Your words, typed where you are." A soft `accentSoft` circle behind the Mac suggests a boundary. It is drawn on appear; under Reduce Motion it appears static.
- **Title:** "Your voice stays on this Mac."
- **Body:** "Open Whisper turns speech into text locally. Free and open source."
- **Promise chips** (row of three `accentSoft` capsules with `accentText`):
  - "No account" (`person.crop.circle.badge.xmark`)
  - "No cloud transcription" (`icloud.slash`)
  - "No audio saved" (`waveform.slash`)
- **Caption:** "The only download is the speech model, when you choose it."
- **Primary:** "Get started".

### Permissions

- **Composition:** Two equal cards side by side, each 260×220. Each card has:
  - a large symbol in a 56 pt `accentSoft` circle (`mic` and `accessibility`)
  - a name
  - one line on why it's needed
  - a live status row
- **Title:** "Two permissions, both yours to give."
- **Microphone card**
  - Why: "To hear you while you dictate. Nothing is recorded to disk."
  - States:
    - Not determined: button "Allow Microphone".
    - Denied: `danger` "Not allowed" and button "Open Privacy Settings".
    - Granted: `success` check and "Allowed", with no button.
- **Accessibility card**
  - Why: "To type text into the app you're using."
  - States:
    - Untrusted: button "Allow Accessibility". The trust prompt is shown only on that click.
    - After the prompt: button "Open Accessibility Settings".
    - Trusted: "Allowed".
- **Status checking:** Status is polled every second while the stage is visible and on app activation. A request button is never shown for an already-granted permission. If 15 s pass after returning from System Settings and Accessibility still reads untrusted, show the Caption "Already turned on? Quit and reopen Open Whisper." with a "Quit and Reopen" button.
- **Readiness gate:** Primary "Continue" is enabled when both permissions are granted. Otherwise a tertiary "Continue without" advances, and the later stages show what's missing.

### Speech model

- **Composition:** A hero card (16 pt radius), 520 wide, for **Parakeet Ultra**, with:
  - a "Recommended" chip
  - "About 630 MB · English and Dutch/Flemish · fastest on Apple silicon"
  - a large rounded drive-to-chip illustration made from SF Symbols (`internaldrive` → `cpu`) joined by a dotted line, which fills `accent` as the download progresses

  Below the hero card is a compact row: "Use Whisper instead". The Whisper size comes from the model manifest.
- **Title:** "Choose your speech model."
- **Body:** "One download. After this, everything runs offline."
- **Primary:** "Download Parakeet Ultra (630 MB)". It changes to the Whisper equivalent if Whisper is selected.
- **Before downloading:** Check free disk space. If there isn't enough, show inline `warning`: "Needs 630 MB free; 410 MB available." The primary is disabled.
- **Downloading:**
  - A determinate bar with "214 of 630 MB · about 2 min left" in monospaced digits.
  - A secondary "Cancel".
  - Then "Verifying…" with a spinner, then a `success` "Installed".
- **Errors:** Shown inline in `danger`. Examples: "Download stopped. Check your connection." and "Verification failed. The file was removed." The button is "Try Again", which resumes when possible.
- **Already installed:** The card shows "Installed", and the primary becomes "Continue".
- **Readiness gate:** The user may Continue while a download runs. The download keeps going, and the progress capsule for this stage shows a thin determinate fill.

### Shortcuts and microphone

- **Composition:**
  - **Left:** the large mouse pictogram with a glowing wheel, captioned "Middle-click to start and finish."
  - **Right:** an "⌥ Space" keycap, 40 pt tall, captioned "Or use the keyboard."
  - **Below:** a card containing the controls.
- **Title:** "Start and stop, your way."
- **Controls:**
  - Toggle "Middle mouse button", on.
  - Shortcut recorder "Keyboard shortcut", default ⌥ Space.
  - "Microphone" menu:
    - "Automatic (MacBook Pro Microphone)" first, showing the current resolved device.
    - A divider.
    - All available inputs.
  - A live 5-bar level preview, shown only when the microphone is allowed. It is labelled "Level only — nothing is saved."
- **Unavailable device:** If the remembered UID is absent, the menu shows "AirPods Pro — not connected" with a `warning` symbol, and the Caption reads "Using Automatic until it's back." The selection is retained.
- **Primary:** "Continue".

### Practice and completion

- **Composition:**
  - A replica of the real overlay sits centred at the top, in its idle state.
  - Below it is a large scratch `TextEditor` card, 520×160, `surfaceRaised`, with the placeholder "Your words will appear here."
  - A segmented "English | Nederlands" control defaults from the system locale.
  - The prompt Caption is "Try: “Meet me at the station at nine.”" or, for Dutch, "Probeer: “Ik bel je morgen terug.”"
- **Title:** "Try it here first."
- **How it works:**
  - Middle-click or ⌥ Space works normally, and the replica overlay mirrors the live state.
  - Text inserts directly into the scratch field.
  - Practice never sends Enter, never writes History or Statistics, and the text is discarded when you leave.
- **Readiness gate:** If the microphone or model isn't ready, the scratch card is replaced with a checklist, for example "Model downloading — 62%" or "Microphone not allowed". Each item has a "Go to step" link.
- **Primary and secondary:** The primary is "Finish setup", enabled at any time. The tertiary is "Skip practice".

**Completion** happens in place:
- The scratch card settles into a compact summary of three `success` rows: "Speech model installed", "Microphone: Automatic", "Middle-click to dictate".
- Title: "You're ready."
- Body: "Dictate into any app. Edits you make there can teach Open Whisper your words."
- Primary: "Start dictating", which opens Dictate.
- Secondary link: "Review settings".

## Correction learning

Learning happens in the destination app, not in Open Whisper.

**Observation**
- After an insertion, Open Whisper watches only the focused element's AX value, around the inserted range, for 90 s.
- An edit is considered when it has been stable for 3 s.
- It must be a substitution of at most 3 words and at most 32 characters on each side.
- Secure fields are ignored.

**Activation**
- One observation creates a "Suggested" entry.
- A second matching observation, in the same app and the same language, activates it.
- Each rule is scoped to an app bundle ID and a language.

**Vocabulary → Learned**
- The list shows "original → replacement", the app, the language, and the state.
- Rules can be disabled or removed.

**Support**
- Settings → Apps lists each app as either "Learns from edits" or "Can't read edits in this app".
- That status is determined from real AX readback, never assumed.
- Copy: "Some apps don't share their text with macOS. Open Whisper won't track them, and it never records keystrokes."

## Per-app options

**Enter after insertion**
- Lives in Settings → Apps. It is off for every app by default.
- Turning it on shows the Caption "This sends the message in chat apps."
- It is never active during practice.

**Recording**
- Settings → Dictation holds the recording limit, a stepper from 1 to 30 minutes with a default of 10.
- It also holds "Stop after a quiet pause", off by default.

## Speech profile

The Speech profile describes dictation habits in neutral language. It is never a fluency or accuracy score. It covers:
- words per minute while speaking
- typical session length
- language mix
- most-corrected words
- busiest hours

## Implementation and acceptance checklist

- [ ] All colors come from asset catalog tokens. Both appearances are checked at ≥4.5:1 for text, and status always pairs a symbol with a word.
- [ ] Overlay is 280×56. The notch variant attaches flush; the external variant sits bottom-centre. Pictogram wheel is visibly accent-highlighted; keycap appears when started from the keyboard.
- [ ] Reduce Motion replaces springs with crossfades, and nothing animates while idle.
- [ ] Onboarding uses five stages with capsule progress, Back (except Welcome), Skip setup, and one default-action primary per stage.
- [ ] Permission requests fire only from button clicks. Live polling hides request buttons once a permission is granted, and denied states route to System Settings.
- [ ] No network activity before the download click. Disk-space check, real byte progress, Cancel, verification, inline errors and resumable Try Again all work.
- [ ] Download continues while the user advances, and Practice gates on model and microphone with links back.
- [ ] Device menu shows Automatic first, persists the UID, and shows an unavailable state that falls back without discarding the selection.
- [ ] Practice inserts only into the scratch field, sends no Enter, and writes no history.
- [ ] Skip leads to a Dictate resume card. The guide can be reopened from Settings and Help. Upgraded users are never interrupted and keep permissions, settings, models and history.
- [ ] Correction learning is bounded, stable, needs two matches, and is app- and language-scoped. Unsupported apps are labelled truthfully, with no global keystroke capture.
- [ ] Enter-after-insertion is per app, off by default, and carries its warning.
- [ ] No web views, remote assets, telemetry or saved audio.
