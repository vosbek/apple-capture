# QCon Collector: UI design spec

For the builder. Read with `architecture.md` (data model, bundle format, event types) and the Claude Design mockup "QCon Collector" (artboards 1 Now, 2 Capture, 2b Capture dim, 3 Talk review, 4 Export, 5 Capture on iPad). Where this spec and the mockup differ, this spec wins.

## 1. Conditions of use

The app is used in a darkened ballroom, seated, phone in one hand, attention on the stage. That sets the rules:

- **Glance and tap.** The two frequent actions (Slide, Moment) are large targets in the bottom third of the screen, reachable by the thumb of the holding hand, and distinguishable by position alone: Moment left, Slide right. They never move.
- **Nothing blocks.** No confirmation dialogs during a talk. Every action is undoable for a few seconds instead.
- **Feedback without looking.** Each capture gives a distinct haptic: Slide `.impact(.medium)`, Moment `.impact(.rigid)` twice, Note saved `.notification(.success)`.
- **Dark room.** Capture uses a dim appearance by default: black ground, low-contrast fills, no white surfaces. All other screens are light.
- **Lock and return.** Matt locks the phone between captures. On unlock the app is still on Capture with the camera live within about a second.
- **Offline is normal.** The app makes no network requests. There is no connectivity indicator and no offline error.

## 2. Structure

```
TabView
 ├─ Now            NavigationStack → Talk review
 ├─ Talks          NavigationStack → Talk review
 └─ Export         NavigationStack
fullScreenCover:  Capture   (from Now, Talks row swipe, or Talk review "Resume capture")
sheets on Capture: Note (medium detent), Session audio grant, Switch talk
sheet on Now / Talk review: Reflect (medium detent)
```

Native components throughout: `TabView`, `NavigationStack`, `List` with `.insetGrouped` style, `Section`, `Button`, `Toggle`, `Picker(.segmented)`, `.sheet` with `presentationDetents`, `ShareLink` or `UIActivityViewController`, `.confirmationDialog`, `.swipeActions`. The only custom view is the camera preview (`UIViewRepresentable` over `AVCaptureVideoPreviewLayer`).

**Type and colour.** System font with Dynamic Type; text styles only (`.largeTitle`, `.title3`, `.headline`, `.body`, `.subheadline`, `.footnote`). Timer and offsets use `.monospacedDigit()`. One accent colour, a blue (`#1857B8` light, `#8AB4F8` dim), set as the app tint. Black for the Moment button. Greys from system colours (`.secondary`, `Color(.systemGroupedBackground)`, `Color(.separator)`). No other hues; state is carried by words and position, not colour. Minimum target 44 × 44 pt everywhere.

**Size classes.** Compact width (iPhone, iPad in Slide Over): the phone layouts below. Regular width (iPad): Now, Talks and Export use the same lists with the system's wider margins; Capture switches to the two-pane layout in section 8.

## 3. Now

**Purpose.** Start capturing the right talk with one tap; reflect on the talk that just ended.

**Layout, top to bottom.**

1. Caption with day, date and time (`MON NOV 16 · 10:28 AM`), then large title "Now". Trailing toolbar button "+ Ad hoc" starts an ad hoc private session.
2. Section "Just ended" (only when a session closed within the last 45 minutes): one row with the talk title, a line of counts ("Keynote · 14 slides · 6 moments · 2 notes"), and a **Reflect** button (56 pt high, tinted). Tapping the row opens Talk review. Tapping Reflect opens the Reflect sheet (section 7).
3. Section "Next" or "Now" with the slot time and a relative label ("starts in 7 min", or "started 12 min ago"): the suggested talk as a card with track name, title (up to two lines), speaker, company, room, a one-line reason for the suggestion, and a full-width **Start capture** button (56 pt, filled, tint).
4. Section "Also in this slot": the slot's other curated talks and any unconference, one row each (title on one line; speaker and room beneath). Tapping a row starts capture for that talk. Sponsored talks are folded into a last row, "2 sponsored talks · <rooms>", which expands in place (`DisclosureGroup`). A slot holds up to six parallel sessions plus an unconference, so this section scrolls.
5. Tab bar.

**Suggestion rule** (`suggest(now, schedule, state) -> Talk?`):

1. The current slot is the one where `start − 20 min ≤ now < end`. If none, the next slot today; if none today, the first slot of the next conference day.
2. Among that slot's talks: a starred talk if exactly one is starred; else a talk whose room equals `state.last_room`; else the first curated talk by track name. Sponsored talks and unconferences are never suggested unless starred.
3. The reason line says which rule fired: "Suggested because it is on your plan", "Suggested because it is in the room you were just in", or no reason line.

**Controls.** Start capture opens the Capture cover and writes `session_open`. If a bundle for that talk already exists on this device, the button reads "Resume capture" and writes `resume`.

**States.**

| State | What shows |
|---|---|
| Before the conference | "Next" shows Monday's keynote with "in 2 days". Start capture is enabled, so the app can be rehearsed. |
| Slot in progress, nothing open | Section title "Now"; label "started 12 min ago"; button "Start capture". Offsets still count from the scheduled start. |
| Session open (returned to Now without ending) | A row at the top, "Capturing: <title>", with the timer and "Return". Start capture on other talks asks, in a confirmation dialog, "End <title> and start this one?" |
| Break or lunch | "Just ended" plus "Next". |
| After the last slot of the day | "Just ended" if recent; then a row "Export today" that switches to the Export tab; then "Next: Tuesday 9:00 AM". |
| No schedule or unreadable `schedule.json` | Empty state (`ContentUnavailableView`): "No schedule loaded", with the file's parse error in the description and one button, "Start ad hoc session". The app remains fully usable through ad hoc sessions. |
| Talk with `no_video: true` | A line under the speaker: "No official video. Capture more." |

**Ad hoc session.** From the toolbar button. An alert with one text field ("Name, for example Lunch table: platform teams"). Creates a talk of kind `adhoc`, `talk_id` `adhoc-<YYYYMMDD>-<HHMM>`, `visibility: private`, `t0` at the open time.

## 4. Capture (iPhone)

**Purpose.** Slide photo, moment marker, quick note, talk timer. Used for 50 to 70 minutes at a time.

**Layout, top to bottom** (portrait only; the screen does not rotate, photos are stored with the device orientation).

1. **Top bar** (44 pt): "End" at the leading edge; the timer centred; a More button (ellipsis in a circle) at the trailing edge. End sits at the top, out of the thumb's way, on purpose.
2. **Talk line**: title on one line, truncated; beneath it speaker, kind or track, room.
3. **Status row** (only when needed, 32 pt): session audio state ("Session audio on · 23:39 · Speaker said yes, in person"), or the Sync start prompt (below).
4. **Camera preview**: fills the remaining height, 16 pt corner radius. Overlays: slide count (top leading), last photo thumbnail (bottom leading, 52 pt; tap opens the photo full screen with Delete), zoom presets (bottom centre, 44 pt circles).
5. **Last-capture row**: "Moment saved at +22:58. Tag it?" with Undo, then four equal tag buttons (44 pt high): Idea, For us, Follow up, Question.
6. **Note** button, full width, 54 pt.
7. **Moment** and **Slide** buttons, side by side, each half the width and about 172 pt high. Moment on the left (black, or dark grey in dim), Slide on the right (tint).
8. Bottom safe area.

**Timer.**

| Situation | Timer shows | Secondary |
|---|---|---|
| Before scheduled start | "−4:10" | "starts 10:35" |
| After scheduled start, no Sync start | minutes and seconds since scheduled start | "N min left" (to scheduled end) |
| After Sync start | minutes and seconds since `speaker_start` | "N min left" |
| Past scheduled end | continues counting | "over by N min" |

**Sync start.** From 5 minutes before to 10 minutes after the scheduled start, and while no `speaker_start` exists, the status row shows a full-width button: "Speaker started: sync timer". One tap writes `speaker_start` and resets the timer to 0:00. After that window it is in the More menu as "Set talk start to now" and "Adjust talk start…" (a stepper in 15-second steps, which writes a new `speaker_start` with the adjusted time).

**Controls.**

| Control | Action | Event written | Feedback |
|---|---|---|---|
| Slide | Captures a photo at the current zoom. No review step. | `photo` | Medium haptic; preview blinks; thumbnail and count update; last-capture row reads "Slide saved at +mm:ss" |
| Volume up or down | Same as Slide (stretch goal; verify on device) | `photo` | Same |
| Moment | Marks the instant | `moment` | Double rigid haptic; count on the button increments; last-capture row offers tags for 5 seconds, then stays without the prompt |
| Tag button | Tags the last moment; tapping the selected tag clears it | `tag` | Selected tag is filled |
| Undo | Removes the last capture (photo, moment or note) | `delete` | Row reads "Removed" |
| Note | Opens the Note sheet | `note` on save | Success haptic on save |
| Zoom presets | Sets zoom to the device's optical steps (for example 1×, 2×, 5×; built from the lenses the device has). Pinch on the preview for anything between. Zoom persists for the session. | none | Selected preset is filled |
| Tap on preview | Focus and exposure at that point, so the bright slide is metered rather than the dark room | none | Focus square |
| End | Closes the session and shows Talk review with the Reflect sheet offered | `session_close` | |
| More | Menu: Session audio… (only if enabled in Export), Set talk start to now, Adjust talk start…, Switch talk…, Dim appearance on or off | | |

**Note sheet.** Medium detent, text editor focused, keyboard up. Title "Note at +mm:ss" using the time the sheet opened. Buttons: Cancel, Save. Swiping the sheet down with text in it saves; it never discards typed text. The system keyboard's dictation key is available for whispered notes.

**Switch talk.** For walking into the wrong room: a list of the slot's talks. Choosing one closes this session (`session_close`, reason `superseded`) and opens the other. Captures already made stay with the first talk; moving them is a PC-side fix.

**Session audio (optional build).** More › Session audio… opens a form: "Who agreed?" (Speaker / QCon staff), "How?" (In person / In writing), an optional note, and the sentence "Record only with permission. QCon's terms do not allow recording sessions without it." The Start button is disabled until both pickers are set. Starting writes `audio_permission` then `audio_start`, and shows the status row with a steady dot, the elapsed recording time and the grant. Stop is in the same menu. If recording stops unexpectedly (interruption, error), the status row changes to "Session audio stopped at +mm:ss · Resume" and a local notification is posted if the app is in the background.

**Camera lifecycle.** The capture session starts when Capture appears and stops when the scene becomes inactive. After 60 seconds with no touch the preview is replaced by the last photo and the text "Tap to wake camera", to save battery; Moment and Note stay live. The idle timer is left on so the phone auto-locks as usual.

**States.**

| State | What shows |
|---|---|
| Just opened, nothing captured | Slide count "0 slides"; no thumbnail; last-capture row reads "Nothing captured yet"; tag buttons disabled |
| Capturing | As in the mockup |
| Camera permission denied | Preview area shows "Camera access is off" and a button "Open Settings". Moment and Note work. Slide is disabled. |
| Camera unavailable (in use, hardware error) | Preview area shows "Camera unavailable" and "Try again". Other controls work. |
| Write failed (disk full or file error) | A banner pinned above the preview: "Could not save. Free up space." It stays until a write succeeds. The failed capture is not shown as saved. Free space under 500 MB shows a standing warning, "Low storage: N MB left". |
| Clock doubt (wall clock jumped against the monotonic clock by more than 5 s) | No visible change. A `clock_jump` note is added to the next event as `"clock_jump_ms"` for ingest to handle. |
| Relaunched after a crash or kill | Capture reopens directly if the talk's scheduled end plus 15 minutes has not passed, with a one-line row: "Resumed. Nothing was lost." |
| Session audio on | Status row as described |

**Dim appearance.** On by default (`settings.dim_capture`). Applies `.preferredColorScheme(.dark)` to the cover with pure black ground, and uses tinted dark fills for the big buttons instead of bright ones. With it off, Capture uses the light scheme shown in artboard 2. The app does not change screen brightness.

## 5. Talks

**Purpose.** Browse the schedule, star the plan, reach any talk's review.

**Layout.** Large title "Talks". A segmented day picker (Mon, Tue, Wed, Thu, Fri) that opens on today. A list with one section per time slot (header "10:35–11:25"). Each row: title (two lines), speaker and company, track and room. Trailing: a star button (filled when planned); a count badge such as "14 · 6 · 2" (slides, moments, notes) once captured. A section "Ad hoc" at the end of each day lists ad hoc sessions.

**Controls.** Tap row: Talk review. Star: adds or removes the talk in `plan`. Leading swipe: "Capture" (starts or resumes). Search field (`.searchable`) over title, speaker and track.

**States.** No schedule: the same empty state as Now. A day with no captures simply shows no badges. A talk with `no_video` shows "No official video" in the secondary line.

## 6. Talk review

**Purpose.** See what was captured for one talk on this device; fix it; add a reflection.

**Layout.**

1. Navigation bar: back; trailing "Talk page" (opens the talk URL in Safari, the app's only link out).
2. Header: title, speakers, then a line with kind or track, day, time and room, and a line with the start basis and counts ("Speaker started 9:03 AM (synced) · 14 slides · 6 moments · 2 notes").
3. Facts list: Session audio ("Off, no permission" / "Recorded with permission: speaker, in person"), Official video ("Expected Dec 21" / "No official video"), Visibility (a toggle "Keep private", on and locked for unconference and ad hoc kinds until Matt turns it off deliberately through a confirmation dialog).
4. Timeline: one row per event in time order. Leading column: talk-relative offset (`+mm:ss`, monospaced digits; "Before" and "After" for events outside the talk). Photos appear as thumbnails, with consecutive photos within 20 seconds grouped in one row. Moments show their tag. Notes show their text, wrapping. Reflections show duration, time and a play button.
5. Bottom buttons: "Resume capture" (bordered) and "Add reflection" (filled).

**Controls.** Tap a photo: full screen, pinch to zoom, Delete. Tap a note: edit in a sheet (`edit` event). Tap a moment: choose a tag (`tag` event). Swipe a row: Delete (`delete` event; no confirmation, since the file is kept until ingest).

**States.** Not captured: header and facts, then an empty state "Nothing captured for this talk" with "Start capture". Session still open: a banner row "Capturing now · Return". Captured only on the other device: the same as not captured; this screen shows only this device's bundle, and the header says "On this iPhone".

## 7. Reflect sheet

**Purpose.** Record Matt's own account of the talk while it is fresh. This is the system's main audio input.

**Layout.** Medium detent. Title "Reflect: <talk title>". Three prompts as plain text: "What was the claim?", "What would we do with it?", "Who should hear it?". A large record button (72 pt), an elapsed-time label, and a level meter. Buttons: Discard, Save.

**Behaviour.** Record starts on tap, in the foreground, with `AVAudioRecorder` (AAC mono). A soft limit of 3 minutes shows "Wrap up"; recording stops at 5 minutes. Save writes the file and a `voice` event with `phase` `after` (or `before` if the talk has not started). Several reflections per talk are allowed. An interruption (call, Siri) ends and saves the recording.

**Where it is offered.** Now ("Just ended" row), Talk review, and automatically after End. It is not on the Capture screen: a microphone open during a session is session recording, which the default design does not do.

**States.** Microphone permission denied: the sheet shows "Microphone access is off", "Open Settings", and a text field so the reflection can be typed instead (saved as a `note` with offset "After").

## 8. Capture on iPad

**Purpose.** The iPad is the note-taking device, used flat or with a keyboard. It can also mark moments and take the occasional photo.

**Layout** (regular width, landscape or portrait). Two panes.

- **Leading pane (flexible width):** header with title, speaker, room and time, and "End talk" at the trailing edge. Below it, the session log: one row per event on this iPad, with three columns (offset; kind in small capitals; text), newest at the bottom, scrolled to the end. Pinned at the bottom: a single-line text field with the current offset shown before it. Return saves the line as a `note` stamped with the time of its first keystroke, clears the field and keeps focus. Under the field, one line listing the keyboard shortcuts.
- **Trailing pane (360 pt):** the timer (large) with minutes left and the synced start time; the camera preview (250 pt high) with zoom presets; the Slide button (64 pt high); the Moment button (fills the remaining height, at least 120 pt); the last-capture row and tag buttons in a two-by-two grid.

In portrait the trailing pane keeps its width and the log narrows. In compact width (Slide Over or Split View at one third) the iPhone layout is used.

**Keyboard shortcuts** (`.keyboardShortcut`): Return saves the note; Command-M marks a moment; Command-P takes a slide photo; Command-1 to Command-4 tag the last moment; Command-Period ends the talk after a confirmation dialog.

**Appearance.** Follows `settings.dim_capture` like the iPhone. The mockup shows the light version.

**States.** The same set as the iPhone Capture screen. The log's empty state is one line: "Notes and moments from this iPad appear here."

## 9. Export

**Purpose.** Get each day's bundles off the device every evening; show whether the device is healthy.

**Layout.**

1. Caption with day, date, time; large title "Export".
2. Section "Only on this phone": one card per conference day that has captures newer than its last export. Day name, a line of totals (sessions, slides, reflections, size), the status ("Not exported yet" or "12 new captures since Mon 9:14 PM"), and a full-width button "Share <day> as .zip". A footer explains the three ways out: OneDrive from the share sheet; Files under On My iPhone › Collector; USB with the Apple Devices app on Windows.
3. Section "Exported": one row per fully exported day with a check mark, the export time and size, and "Again".
4. Section "This device": App expires (date, time and days left); Free space; Device label (editable; `iphone` or `ipad` by default from the device idiom); toggle "Dim capture screen" (default on); toggle "Offer session audio (needs permission each talk)" (default off; absent if the feature was not built).

**Export behaviour.** The button builds `collector_<YYYY-MM-DD>_<device>.zip` from `Documents/sessions/<date>/` with `NSFileCoordinator` (`.forUploading`), shows a progress row while it does, then presents the share sheet. When the share sheet reports completion, an `ExportRecord` is written. If Matt cancels the share sheet, nothing is recorded. An open session is included as it stands; the zip is a snapshot, and exporting the same day again later produces a superset that ingest handles.

**States.**

| State | What shows |
|---|---|
| Nothing captured yet | Empty state: "Nothing to export yet." The "This device" section still shows. |
| Building the zip | Button replaced by a progress view and "Preparing 214 MB…" |
| Zip failed (no space) | Alert: "Not enough space to build the zip. The same folders are in Files under On My iPhone › Collector." |
| Everything exported | Section "Only on this phone" is replaced by one line: "Everything is exported." |
| Expiry within 48 hours | The App expires row turns bold with "Export today"; the Export tab shows a badge |
| Expiry unknown | "App expires: unknown (installed <date>)" |

## 10. Accessibility and text

- Every icon-only control has an accessibility label ("More", "Play reflection", "Zoom 2×, selected").
- The big buttons are labelled with their action and current count ("Moment. 6 marked").
- Dynamic Type is supported up to the accessibility sizes on list screens; on Capture the big buttons keep their size and the talk line truncates.
- Reduce Motion: no preview blink; the count change is the feedback.
- Wording is fixed and short. Labels used: Start capture, Resume capture, End, Slide, Moment, Note, Reflect, Add reflection, Sync timer, Share <day> as .zip, Undo, Keep private. Tags: Idea, For us, Follow up, Question.

## 11. Out of scope for this build

Editing the schedule in the app; moving captures between talks; viewing the other device's captures; any sync; on-device transcription or OCR; rating talks; widgets, Live Activities and lock-screen controls (each extension costs an app slot under free signing).
