# QCon Collector: starter build

Built from `qcon-pipeline/docs/architecture.md` and `design-spec.md`. The repo assumes you cloned it to
`C:\devl\workspace\apple-capture` (WSL path `/mnt/c/devl/workspace/apple-capture`); adjust paths if not.
Two folders, plus `setup/windows/` for the toolchain:

| Folder | What it is | State |
|---|---|---|
| `QConCollector/` | The iOS app, an xtool SwiftPM project (iPhone + iPad, iOS 17+) | Written, **never compiled**: there was no Swift toolchain where it was built. Expect a handful of compile errors on the first `xtool dev build`. |
| `qcon-pipeline/` | The PC workspace (`qcon-sf-2026/` in the architecture): ingest, publish gate, schedule builder, transcription, Claude Code commands and subagents, vault and kb skeletons | Python tested: **33 tests pass** (Python 3.13, Linux), also with Pillow and PyYAML absent |

```
QConCollector/
  Package.swift              tools 6.0, iOS 17, Swift 5 language mode (avoids strict-concurrency errors)
  xtool.yml                  bundleID, infoPath, resources: [Resources/schedule.json], iconPath
  Support/Info.plist         partial plist: camera + mic strings, UIFileSharingEnabled, LSSupportsOpeningDocumentsInPlace
  Resources/schedule.json    119 talks, built by qcon-pipeline/tools/build_schedule.py
  Resources/AppIcon.png
  Sources/QConCollector/
    CollectorApp.swift       app, tab view, shared bits (haptics, no-schedule state)
    Models.swift             Talk/Schedule/Manifest/Event/CollectorState (Codable, snake_case)
    Formats.swift            UTC + conference-time formatting, monotonic clock, device model
    BundleHandle.swift       one bundle on disk: append-only events.jsonl, atomic manifest, media
    Store.swift              all state and every write; suggestion rule; recovery; export log
    NowView.swift            Now tab
    TalksView.swift          Talks tab (day picker, stars, search, swipe to capture)
    CaptureView.swift        Capture cover: iPhone layout + iPad two-pane, note sheet, timer, switch talk
    Camera.swift             embedded AVCapture camera + UIImagePickerController fallback
    ReflectSheet.swift       voice reflections (AVAudioRecorder, AAC mono)
    TalkReviewView.swift     Talk review (timeline, edit, tag, delete, play, share talk)
    ExportView.swift         Export tab: zip per day / all, share sheet, device health, settings
    SessionAudio.swift       STUB: session audio not built (architecture §11), with the build steps
qcon-pipeline/
  CLAUDE.md                  workspace rules for Claude Code
  .claude/commands/          qcon-ingest, -read, -enrich, -brief, -themes, -publish, -reconcile, -status
  .claude/agents/            slide-reader, speaker-researcher, repo-inspector, brief-writer, claim-checker
  tools/                     ingest.py, publish_gate.py, build_schedule.py, transcribe.py (optional),
                             status.py, reconcile.py, downscale.py
  docs/                      architecture.md and design-spec.md (the contract)
  templates/                 brief.md (architecture §7.2), sources.yaml example
  tests/                     pytest suite with a synthetic bundle builder (conftest.py)
  inbox/ vault/ kb/          skeleton (git-ignored except .gitkeep); vault/schedule/ dataset + schedule.json
```

---

## Evening by evening (architecture §11)

### Evening 1, Wed Nov 11: toolchain, app on both devices, Capture writes valid bundles

1. **Toolchain first (90 minutes max).** Run `setup\windows\1-windows-setup.ps1` (admin PowerShell), then
   `bash setup/windows/2-wsl-setup.sh` in Ubuntu, then `xtool setup` with the Xcode 27.1 .xip
   (xtool, Swift 6.4 toolchain, Xcode 27.1 SDK, usbmuxd, usbipd). Confirm with `xtool sdk status` and
   `xtool auth status`. Run `xtool setup` / `xtool auth login` here, at home, never on the trip.
2. **Copy the project into WSL** (build in the Linux filesystem, not on `/mnt/c`; it is much faster):
   ```bash
   # in WSL; adjust the Windows path to where you cloned the repo
   mkdir -p ~/ios
   rsync -a --delete --exclude .build --exclude xtool \
     /mnt/c/devl/workspace/apple-capture/QConCollector/ ~/ios/QConCollector/
   cd ~/ios/QConCollector
   ```
   Re-run the same `rsync` after editing on the Windows side, or edit in WSL directly (VS Code Remote-WSL).
3. **Set the bundle ID once** in `xtool.yml` (`bundleID: com.<you>.qconcollector`) and never change it
   again: a new ID is a new app with empty data.
4. **Compile without a device until it builds:**
   ```bash
   xtool dev build            # compiles and packs the .app; no device, no signing
   ```
   Fix errors top-down; see "Verify first when compiling" below for the likely spots.
5. **Install on the iPhone, then the iPad:**
   ```powershell
   # Windows (admin PowerShell): attach the device to WSL (or run setup\windows\3-attach-iphone.ps1)
   usbipd list
   usbipd attach --wsl --busid <BUSID>
   ```
   ```bash
   xtool devices              # find the UDID
   xtool dev run -u <UDID>    # build, sign, install, launch (`xtool dev` alone does the same)
   ```
   First time per device: tap Trust, enable Developer Mode, then Settings › General › VPN & Device
   Management › your Apple ID › Trust. `AFCClient.Error.muxError` → xtool issue #19 workaround.
6. **Fake 10-minute talk on the iPhone:** Now › + Ad hoc, or start Monday's keynote (it is startable
   before the conference). Take 3 slides, 3 moments (tag one), 1 note, tap Sync, End, record a
   reflection.
7. **Gate G1:** Files › On My iPhone › Collector › sessions › `<date>` › bundle folder shows
   `manifest.json`, `events.jsonl`, `photos/`, `voice/`. Detach the device (`usbipd detach --busid <BUSID>`)
   and copy the folder to the PC with the Apple Devices app, then on the PC:
   ```bash
   python3 tools/ingest.py /path/to/that/folder   # from qcon-pipeline/; "talk_id ... sync yes"
   ```
   If the app is not on a device by the end of the evening, stop and set up the fallback (below).
   If the embedded camera misbehaves, turn on Export › "Use system camera for slides" (no rebuild)
   and move on.

### Evening 2, Thu Nov 12: review, reflections, export, recovery, iPad

All of this is already in the code; the evening is for making it work on the devices.
1. Talks tab: star your plan for Mon–Wed; check the Now suggestion picks a starred talk.
2. Talk review: edit a note, tag a moment, swipe-delete a photo, play a reflection.
3. Export: "Share Mon as .zip" → Save to OneDrive (or Files). Check the "App expires" row shows a
   date (if it says "unknown", see §15 below).
4. Crash recovery: start a session, force-quit the app, relaunch: Capture should reopen with
   "Resumed. Nothing was lost." and `events.jsonl` should show a `resume` line.
5. iPad: install, capture the same fake talk with typed notes (Return saves each line).
6. **Gate G2:** both devices capture the same talk; both zips ingest on the PC and merge into one
   `vault/talks/<talk_id>/timeline.jsonl` with `devices: ipad, iphone` and a measured skew.
   This is the go/no-go for using the app at QCon.
7. Session audio: only if everything above works with an hour to spare (see `SessionAudio.swift`).
   Recommendation: skip it; Voice Memos covers a talk where a speaker says yes.

### Evening 3, Fri Nov 13: schedule, ingest proof, dress rehearsal, fallback

1. Rebuild the schedule from a fresh dataset (the site says it may change):
   ```bash
   cd qcon-pipeline
   python3 tools/build_schedule.py vault/schedule/qconsf-2026-schedule.json \
     -o vault/schedule/schedule.json --app ../QConCollector/Resources/schedule.json
   ```
   Then rsync and rebuild the app. On site, a newer `schedule.json` dropped into
   Files › On My iPhone › Collector replaces the bundled one without a rebuild (Export shows which is used).
2. Dress rehearsal: 50 minutes, dim room, slides on a TV, both devices, phone locked between captures.
   Note battery use and photo size; check photos are legible and upright on the PC.
3. `python3 tools/ingest.py` on the rehearsal zips; fix the three worst problems; freeze the code.
4. Set up the fallback Shortcut regardless (below) and do one fallback ingest.
5. **Gate G3:** rehearsal bundle ingests cleanly; photos legible; battery noted.

### Sat Nov 14, morning: reinstall for a fresh 7-day signature

```bash
xtool dev run -u <IPHONE_UDID>
xtool dev run -u <IPAD_UDID>
xtool ds profiles list          # expiration date must be on or after Nov 21
```
Open the app on both. Do not touch xtool sign-in again until home. Never delete the app (its data
goes with it); if it expires, the data stays on the device until you re-sign.

### At QCon, each evening
Export › Share <day> as .zip → OneDrive, on both devices.

### After the trip
```bash
cd ~/qcon-sf-2026            # copy of qcon-pipeline/; put the zips in inbox/
python3 -m pip install -r requirements.txt
claude                       # then, in order:
/qcon-ingest
/qcon-read all
/qcon-enrich all
/qcon-brief all              # then review each brief; set status: reviewed, reviewed_by
/qcon-themes
/qcon-publish all-reviewed   # commits in kb/; you push
/qcon-status
/qcon-reconcile <talk_id>    # from Dec 21, per talk
```

---

## No-app fallback (architecture §13)

Set up on evening 3 even if the app works.

- **Camera:** Settings › Camera › Formats › **Most Compatible** for the trip, so photos are JPEG and
  `ingest.py` can read their EXIF time with the standard library (HEIC falls back to file time).
- **Shortcut "Collector line"** on the Action Button (verify each action on your iOS version):
  1. Ask for Input (Text), prompt "Note (empty or . = moment)".
  2. Current Date → Format Date: ISO 8601, include time.
  3. Text: `<Formatted Date> | <Provided Input>`
  4. Append to Text File: `collector-notes.txt` in Files › On My iPhone (make a new line each time).
- At the start of each talk, run it and type `TALK <slug or a few title words>` (for example
  `TALK harness`). That line also counts as the speaker start, so type it when the speaker begins.
  `idea`, `for us`, `follow up`, `question` make tagged moments; anything else is a note.
- **Voice Memos** for reflections, titled with a few words of the talk title. Share › Save to Files.
- On the PC: put the notes file in `inbox/fallback/`, photos in `inbox/fallback/photos/`, voice files
  in `inbox/fallback/voice/`, your planned talk ids (one per line) in `vault/plan.txt`, then
  `python3 tools/ingest.py --fallback`. Captures that match no talk go to a private
  `unassigned-<date>` talk and are listed in the report. Fallback and app captures of the same talk merge.

---

## Bundle format decisions (where the spec left room)

- `manifest.json` is rewritten (atomically) after every event, not only at open/sync/close, so its
  counts stay current. Null fields are written as `null`. `events.jsonl` still wins at ingest.
- A `tag` event with `"tag": null` clears the moment's tag ("tapping the selected tag clears it").
- "Adjust talk start" writes a new `speaker_start` whose `ts_utc` is the adjusted time (not the tap
  time); the last `speaker_start` line in the file wins.
- Ad hoc sessions: `talk_id` `adhoc-YYYYMMDD-HHMM` in conference time, `t0_basis: opened`, scheduled
  end = open + 60 min (used only for the recovery window), always private.
- Reflections: AAC mono, 44.1 kHz, 64 kbps; recorded to tmp/ and moved into `voice/` on Save.
- `mono_ms` uses Darwin `CLOCK_MONOTONIC` (keeps counting in sleep). After a relaunch it continues
  from wall-clock time since `opened_utc`; after a reboot it restarts, which ingest reports.
- Zips: a day zip's top folder is the date (`2026-11-16/<bundle>/...`), "all" zips start at
  `sessions/`, a talk zip at the bundle folder. Ingest finds bundles at any depth.
- Ingest adds `talk_ms`, `bundle`, `ref` (S01, N1, M1, V1) and `vault_file` to timeline lines.
  Refs are kept in `refs.json` so a later ingest never renumbers what a brief cites (a photo that
  arrives late gets the next number rather than its time-order number).

## Deviations from the spec, and why

1. **App size:** about 3,000 non-blank Swift lines, not 1,000–1,500. Every evening 1–2 item is in,
   plus the iPad two-pane Capture and the picker fallback; cutting more would have moved work to your
   evenings. Files are small and plain (no generics beyond one helper, no macros, no SwiftData).
2. **Camera:** the embedded `AVCaptureSession` camera (zoom presets from the lens switch-over factors,
   pinch, tap to focus/expose) is the default; `UIImagePickerController` is available at runtime via
   Export › "Use system camera for slides" (new `settings.use_system_camera` key in `collector.json`).
3. **Session audio not built** (architecture §11 says leave it out unless evening 2 has slack). Stub
   with build steps in `SessionAudio.swift`; no `UIBackgroundModes`; the Export toggle is absent.
4. "Adjust talk start…" stepper → two menu items, "Move talk start 15 s earlier / later".
5. After End, the Reflect sheet opens directly (Talk review is one tap away from Now › Just ended).
6. Not built from the design spec: preview blink, 60-second camera sleep ("Tap to wake camera"),
   volume-button shutter, grouping of photos within 20 s in Talk review, pinch-zoom in the photo
   viewer, Export tab "Preparing N MB" uses folder sizes computed when the tab opens, iPad tag
   buttons are one row of four (not 2×2).
7. **Privacy at ingest is stricter than the gate rule:** a talk is private if *any* of its bundles is
   private (the architecture says "all"); `talk.json` records both and the gate fails on either.
8. `notes.md` is written deterministically by `ingest.py` (with refs and transcripts), not assembled
   by `/qcon-read`.
9. Claude Code setup is in `.claude/commands/` (as the task asked) rather than `.claude/skills/`
   (architecture §9). Contracts are the same.
10. Extra small tools: `status.py` (for /qcon-status), `reconcile.py` (the Dec 21 arithmetic),
    `downscale.py` (publish copies of cited slides, EXIF stripped).
11. Lenses: copy `qcon-pipeline/templates/lenses.example.yaml` to `qcon-pipeline/vault/lenses.yaml`
    (git-ignored) and replace the examples with your own initiatives before `/qcon-brief`.

## Verify first when compiling (most likely failures, in order)

1. **`Package.swift` `swiftLanguageModes: [.v5]`.** If the toolchain rejects it, delete that line and
   add `swiftSettings: [.swiftLanguageMode(.v5)]` to the target. Without Swift 5 mode, expect many
   Sendable/actor errors.
2. **`Formats.swift` `clock_gettime_nsec_np(CLOCK_MONOTONIC)`.** If it does not compile, use
   `mach_continuous_time()` scaled by `mach_timebase_info` (also counts during sleep).
3. **`Camera.swift`**: `videoRotationAngle` / `isVideoRotationAngleSupported` (iOS 17 API), the photo
   delegate signature, `virtualDeviceSwitchOverVideoZoomFactors`.
4. **`CaptureView.swift`**: `MagnifyGesture` (iOS 17), `.keyboardShortcut` on `TagButton`,
   `.onChange(of:) { old, new in }` (iOS 17 form). **`TalkReviewView.swift`**: `if let` inside
   `.toolbar { }`. **`Store.swift`**: the `Task.detached { () -> Result<URL, Error> in ... }` closure.
5. **Schedule loads:** Now shows Monday's keynote "in N days". "No schedule loaded" means
   `Resources/schedule.json` did not reach the .app root; check `xtool.yml` `resources:`.
6. **Photos are upright on the PC** in both portrait and landscape (rotation mapping in
   `CameraController.rotationAngle` is reasoned, not tested), and zoom presets match the Camera app.
7. **Files app** shows On My iPhone › Collector › sessions.

## Known unverified

Everything in `QConCollector/` (not compiled, not run). In particular:
- Swift 6.4 toolchain accepting the package as written; deprecation warnings expected for
  `AVAudioSession.recordPermission` / `requestRecordPermission`.
- `NSFileCoordinator(.forUploading)` zip of a folder off the main thread, and `UIActivityViewController`
  completion inside a SwiftUI sheet on iPad (export is only recorded when the share completes).
- The share sheet's OneDrive target with a 200+ MB zip.
- Keyboard shortcuts and focus on the iPad note field; layout on the smallest iPhone you use.
- The fallback Shortcut's exact actions (ISO 8601 date format, empty input, Append to Text File).
- `tools/transcribe.py` was not run (faster-whisper not installed here); GPU setup in WSL is the
  part most likely to need adjusting.
- Python tools tested on Linux only; on Windows-native Python install `tzdata` (in requirements.txt);
  WSL is the tested path.
- Claude Code commands and agents are written but have not been run end to end.

Architecture §15 device checks (dress rehearsal):
- The app can read its signature expiry from `embedded.mobileprovision` under xtool (Export shows
  "App expires"); if not it shows "unknown (installed <date>)": add seven days by hand.
- The shutter sound follows the silent switch.
- Volume buttons as shutter via `AVCaptureEventInteraction` (not built; stretch goal).
- Files can still browse the app's folder after the signature expires.
- Photo size and battery drain per talk.
