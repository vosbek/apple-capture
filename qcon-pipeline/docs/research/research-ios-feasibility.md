# QCon SF capture app: iOS feasibility research

Researched 2026-11-10. Trip: leave Nov 14, QCon SF Nov 16–20, 2026. Constraints: Windows + WSL, xtool, free Apple ID ("Password" login), iPhone + iPad on iOS/iPadOS 26.x, about three evenings to build.

Labels used throughout:
- **[Confirmed]**: read in source code or in a primary document (Apple, vendor, QCon).
- **[Reported]**: secondary sources such as blogs, forum users or benchmarks.
- **[Inference]**: my reasoning. Not verified, so test it on a device.

---

## 0. Read this first: QCon's terms forbid recording sessions

This is not a technical constraint, but it changes the plan more than anything else in this document.

- **[Confirmed]** QCon SF 2026 Terms & Conditions, paragraph 24: *"If you like, you may take your own still-photos/screenshots during the Event and share them on social media. **You are not permitted to record or otherwise make your own video of any session.** Conference participants violating this policy may be sanctioned or expelled from the Event without a refund…"* ([qconsf.com/terms-conditions/nov2026](https://qconsf.com/terms-conditions/nov2026))
- **[Confirmed]** Paragraph 25: paying attendees get "most" session recordings "within approximately 5 weeks after the conference", viewable for about 12 months, with "downloading of the videos is not permitted". The FAQ gives a start date of **December 21, 2026** ([FAQ](https://qconsf.com/faq/nov2026)).
- **[Confirmed]** The FAQ also says: "If the speaker agreed to share their slides, they will be made available in the schedule and on the presentation page within days." The registration page lists a "Download option for most presentation slides" ([registration](https://qconsf.com/registration/event/nov2026)).
- **[Inference]** "Record … any session" reads as covering audio, not only video. At best the wording is ambiguous. Covertly recording whole talks with the phone in a pocket is the case most likely to be read as a violation, and the stated penalty is expulsion. A corporate attendee should not take that risk on an ambiguous reading.

**What this means for the design.** Make full-talk audio a feature that is **off by default** and turned on per talk, used only with explicit permission (written OK from QCon staff, or a speaker who says yes). Build the minimum viable product around what is allowed:
- photos of slides (explicitly allowed),
- timestamped bookmarks,
- text notes,
- short voice notes in Matt's own voice (dictated commentary, not the speaker),
- tagging each capture to a talk.

After the conference, the bookmark timestamps (stored as an offset from talk start) map onto the official recordings (around Dec 21) and the speakers' slide PDFs. The technical answers below still cover full-talk audio, in case permission is granted.

---

## A. xtool specifics (from the source)

Cloned `xtool-org/xtool` at commit `a2875dd` (2026-11-07) into `/tmp/claude-0/-home-claude/c5575ee4-acf8-5698-9638-6c49135cdaf5/scratchpad/qcon/xtool-src`. Key files:
- `Sources/PackLib/PackSchema.swift`: the xtool.yml schema.
- `Sources/PackLib/Planner.swift`: default Info.plist and the merge logic.
- `Sources/PackLib/Packer.swift`: icon handling and forced keys.
- `Sources/XKit/DeveloperServices/...`: signing, capabilities, profiles.
- `Documentation/xtool.docc/Control.md` and `Appex.md`.

Current prerequisites per `Installation-Linux.md` [Confirmed]: Swift 6.4 toolchain, `usbmuxd`, and **Xcode 27.1 .xip** for SDK generation. For WSL, use USBIPD passthrough or the iTunes-relay workaround from issue #19 if you hit `AFCClient.Error.muxError`.

### xtool.yml schema [Confirmed, `PackSchema.swift`]
The entire schema is below. There are no inline Info.plist keys; plist keys go in a separate plist file referenced by `infoPath`.
```yaml
version: 1                     # required, only v1 exists
bundleID: com.matt.qconcap     # or orgID: com.matt  (one of the two required)
product: QConCap               # which SwiftPM library product is the app (needed if >1 product)
infoPath: Support/Info.plist   # partial plist, MERGED over xtool's defaults (your keys win)
entitlementsPath: Support/App.entitlements   # optional
iconPath: Resources/AppIcon.png              # must be .png (validated); ideally 1024x1024
resources:                     # files copied to the ROOT of the .app
  - Resources/schedule.json
extensions:                    # app extensions (Foundation NSExtension style only)
  - product: QConCapWidget
    infoPath: Support/Widget-Info.plist      # required for extensions
    bundleID: ...              # optional
    resources: [...]           # optional
    entitlementsPath: ...      # optional
skipLSP: true                  # optional
```

### Defaults xtool generates [Confirmed, `Planner.swift` and `Packer.swift`]
- **Apps:**
  - `UIDeviceFamily = [1, 2]`, so **iPhone and iPad are supported by default**.
  - `UISupportedInterfaceOrientations = [Portrait]` on iPhone.
  - On iPad (`~ipad`): all four orientations.
  - `UILaunchScreen = {}`.
  - `MinimumOSVersion` comes from `platforms: [.iOS(...)]` in Package.swift.
  - `CFBundleDisplayName` and `CFBundleName` default to the product name.
- **Always forced at pack time:**
  - `UIRequiredDeviceCapabilities = [arm64]`
  - `LSRequiresIPhoneOS = true`
  - `CFBundleSupportedPlatforms`
- **Icon:** `iconPath` is copied to the bundle root and set as `CFBundleIconFile`. That is the legacy single-PNG mechanism; there is no asset catalog. It works for a personal app.
- **Resources:** SwiftPM `resources: [.process/.copy]` work through `Bundle.module`. The `resources:` list in xtool.yml copies files to the `.app` root.
- **Extensions:** supported as Foundation `NSExtension` (for example widgets). ExtensionKit is not supported yet (issue #138). **Not needed for this app**, and each extension costs an App ID and app slot under free provisioning.

### Can the needed keys be set? Yes, all of them [Confirmed]
They are ordinary Info.plist keys, set through `infoPath`. xtool merges any dictionary with `{ $1 }`, so your file wins. `Support/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>            <string>QCon Cap</string>
    <key>UIBackgroundModes</key>              <array><string>audio</string></array>
    <key>NSMicrophoneUsageDescription</key>   <string>Records talk audio and your voice notes.</string>
    <key>NSCameraUsageDescription</key>       <string>Captures slide photos.</string>
    <key>NSSpeechRecognitionUsageDescription</key> <string>Optional on-device transcription of your notes.</string>
    <key>UIFileSharingEnabled</key>           <true/>
    <key>LSSupportsOpeningDocumentsInPlace</key> <true/>
    <!-- only if you add the on-device HTTP export server: -->
    <key>NSLocalNetworkUsageDescription</key> <string>Lets your PC download captures over Wi-Fi.</string>
</dict>
</plist>
```
```yaml
# xtool.yml
version: 1
bundleID: com.matt.qconcap
infoPath: Support/Info.plist
iconPath: Resources/AppIcon.png
```
Notes:
- **[Confirmed]** `UIBackgroundModes=audio` is a plain Info.plist key. xtool does not inspect it, and it is not an entitlement, so the signing pipeline never touches it.
- **[Confirmed]** No `entitlementsPath` is needed for anything in this app.
- **[Confirmed, `DeveloperServicesAddAppOperation.swift`]** On a free team, xtool **silently filters out** entitlements whose capability is marked paid-only (`isFree: false`). Examples: push (`aps-environment`), Sign in with Apple, Associated Domains, Network Extensions, Personal VPN, Multipath, SiriKit, Wi-Fi Aware. Entitlements it marks free: App Groups (max 1 group on a free team), HealthKit, HomeKit, Inter-App Audio, Data Protection, Wireless Accessory. iCloud is not in xtool's entitlement table at all, so it is not supported.
- **[Confirmed, `Control.md` and `ProvisioningIdentifiers.swift`]** The real installed bundle ID becomes `XTL-<first segment of your identity id>.com.matt.qconcap`. The prefix is stable for the same Apple ID, so reinstalls update in place.
- **[Confirmed, `DeveloperServicesFetchProfileOperation.swift`]** **Every `xtool dev` / install deletes the old "XTL profile" and creates a new one**, covering all registered iOS devices. So **expiry counts from your last install**, not your first. `xtool ds profiles list` prints `expiration date`, so use it to verify.
- **[Confirmed, `DeveloperServicesFetchCertificateOperation.swift`]** On a free team, if xtool lacks the locally stored signing key (for example a fresh machine or `xtool setup` on another PC), it **revokes the existing certificates** (after a confirmation prompt) and makes a new one. **[Inference, widely reported by sideloading tools]:** revoking the development certificate can stop already-installed apps from launching. Don't re-run setup on another machine mid-trip, and decline the revocation prompt if one appears.
- **[Confirmed, `First-app.tutorial`]** First-run steps on each device: tap "Trust" for pairing, enable Developer Mode, then Settings > General > VPN & Device Management > your Apple ID > Trust.

---

## B. Free Apple ID provisioning limits

| Item | Value | Status / source |
|---|---|---|
| App validity | **7 days**, then the app "deactivates" | [Confirmed] Apple DTS (Quinn): "Yes. That's another limitation of free provisioning" ([forum 724896](https://developer.apple.com/forums/thread/724896)); Expo: "expire 7 days after they are created" ([expo.dev](https://expo.dev/blog/apple-developer-program-explained-free-vs-paid)) |
| Active apps per device | **3** | [Reported] forum poster plus Expo; DTS confirmed a paid account removes the restriction |
| New App IDs | **10 per rolling 7 days** | [Reported] same forum thread, not confirmed by Apple. xtool reuses one ID per app, so this is a non-issue unless you churn bundle IDs |
| Devices | up to 3 registered | [Reported] Expo |
| Not available | iCloud (CloudKit, Documents, KVS), push notifications, Sign in with Apple, Associated Domains, Apple Pay, IAP, NFC, Network Extensions | [Reported] Expo; consistent with xtool's `isFree:false` table [Confirmed]. Apple's official table ([supported-capabilities-ios](https://developer.apple.com/help/account/reference/supported-capabilities-ios/)) has an "Apple Developer" (free) column, but its check marks didn't survive scraping |
| Available | **Background Modes**, App Groups (1), HealthKit, HomeKit, Keychain sharing, Maps (no routing), local notifications | [Reported] Expo; App Groups etc. [Confirmed] in xtool source |

**Is background audio allowed on a free account?** Yes, with high confidence. Expo lists Background Modes as working on free accounts [Reported]. Technically it is only the `UIBackgroundModes` Info.plist key, which no provisioning profile validates; "Background Modes" in Xcode is a UI wrapper around that key [Inference, high confidence]. The one exception is the separate `push-to-talk` / VoIP style entitlements, which aren't needed here.

**When the profile expires mid-trip:**
- **[Confirmed]** The app won't launch (DTS: "apps … deactivate after 7 days").
- **[Inference, high confidence]** The sandbox data (Documents, Library) is **left on the device**. Re-installing the same bundle ID with a fresh profile (`xtool dev`) reactivates the app with the data intact. **Do not delete the app to "fix" it**, because deleting removes its data.
- **[Unknown, test before relying on it]** Whether the Files app can still browse "On My iPhone > QCon Cap" while the app is expired.
- **Mitigation:** export every evening (see F), and set the install time so expiry falls after Nov 20.

**Install on Nov 13 → expires when?** 7 × 24 h from the moment of the last `xtool dev`.
- Install Nov 13 at 21:00 ET → expires about **Nov 20, 21:00 ET (18:00 PT)**. That is the last conference day, so it is cutting it close.
- **Better:** reinstall on the **morning of Nov 14** before leaving (for example 07:00 ET) → about **Nov 21, 07:00 ET**. That covers the whole trip.
- Install the iPhone and iPad back to back. xtool regenerates the profile per install. [Inference: an already-installed copy keeps its embedded profile until that profile's own expiry. Check the dates with `xtool ds profiles list`.]
- If the Windows machine is a laptop that travels, you can re-sign mid-trip. Otherwise there is no recovery until home.

---

## C. Audio capture (only if recording is permitted; also used for short voice notes)

**Recording with the screen locked [Confirmed pattern]:**
- Needed: `UIBackgroundModes=[audio]`, plus `AVAudioSession` category `.record` or `.playAndRecord`.
- Activate the session and start recording **while in the foreground**. Capture then continues when locked or backgrounded.
- WebKit's source also gates background mic capture on exactly this key ([bb issue citing WebKit source](https://github.com/get-bb/bb/issues/5698); [WebKit bug 226620](https://bugs.webkit.org/show_bug.cgi?id=226620)).
- **[Confirmed by system log text, iOS 12.4+/13]** An app **cannot start** recording from the background: "…is in the background and doesn't have the entitlement to start recording in the background" ([forum 120038](https://developer.apple.com/forums/thread/120038)). Always start in the foreground.

**Interruptions (calls, Siri, alarms):**
- Observe `AVAudioSession.interruptionNotification`: on `.began`, pause; on `.ended`, check `.shouldResume` and then reactivate and resume.
- **[Reported failure]** `setActive(true)` after a phone call **while backgrounded** can fail with `'!int'` (560557684) ([forum 813278](https://developer.apple.com/forums/thread/813278)).
- **[Reported fix]** RisingStack found that `.playAndRecord` with `options: [.mixWithOthers]` let them reliably resume after calls even in the background ([blog](https://blog.risingstack.com/reliable-background-recording-on-ios-watchos/)). Use `.mixWithOthers`.
- **[Reported bug]** `AVAudioRecorder.pause()` followed by `.record()` after an interruption can **lose the audio before the interruption** ([forum 781778](https://developer.apple.com/forums/thread/781778)).
- **Design response:** on `.began`, **finalize the current segment** (stop); on `.ended`, open a **new** segment. Also log an `interruption` event in the session timeline.
- **Practical mitigation:** turn on Focus / Do Not Disturb during talks so calls don't ring through. Also show a local notification / Live-Activity-style alert if recording stopped (local notifications are allowed on free accounts).

**Route changes:** observe `AVAudioSession.routeChangeNotification`. If AirPods connect or disconnect, the input mic changes; log it. With `.playAndRecord`, avoid `.allowBluetooth` (HFP) so the session stays on the built-in mic.

**Recommended engine: `AVAudioEngine` with one continuous input tap writing to rotating `AVAudioFile` segments [Inference / design].**
- The engine never stops between segments, so there is no gap and no "restart from background" problem.
- Segment every **5 minutes**. `AVAudioRecorder` with stop/start rotation also works, but starting a new recorder while backgrounded risks the "cannot start in background" rule above.
- **Why segment [Inference, well-known behavior]:** an `.m4a` file's index (moov atom) is written on close. If the app is killed or the phone dies before `stop()`, a single 50-minute `.m4a` can be unreadable. With 5-minute segments, the worst case is losing 5 minutes. (Alternative: write `.caf`, which is append-friendly and recoverable.)
- **Format:** AAC-LC, mono, 48 kHz (or 44.1), **48–64 kbps**. Speech is fine at 32 kbps, but Whisper benefits from more headroom. Some AAC encoder bitrate/sample-rate combinations are rejected (for example a high bitrate at a low sample rate), so test settings on the device.

**File size [arithmetic]:**

| Bitrate | Per hour | Per 50-min talk | 6 h/day | 3 days |
|---|---|---|---|---|
| 32 kbps | 14.4 MB | 12 MB | 86 MB | 260 MB |
| 64 kbps | 28.8 MB | 24 MB | 173 MB | 520 MB |

**Battery [Reported, not authoritative]:**
- Screen-off recording is about **3–5%/hour** on recent iPhones ([oreateai](https://learn.oreateai.com/learn/iphone-voice-memos-dont-have-a-time-limit-but-here-is-what-stops-them)). Another report: 4 h of lossless ≈ 30–40% on iPhone 15+ ([audioutils](https://audioutils.com/blog/how-to-record-audio-on-iphone)).
- **Estimate [Inference]:** 6 h/day of recording ≈ **20–35%**. Add photos and screen-on time, and expect a battery pack to be needed by late afternoon.
- The screen is the main cost, so keep the in-app UI minimal and lock the phone.
- No on-device transcription during capture (see D) saves a lot.

---

## D. On-device transcription on iOS 26

| | SpeechAnalyzer + SpeechTranscriber (iOS 26) | SFSpeechRecognizer (iOS 10+) |
|---|---|---|
| On-device | **Yes, always**: "transcription is entirely on device but the models need to be fetched" via `AssetInventory` [Confirmed, WWDC25-277] | Optional (`requiresOnDeviceRecognition`); can use Apple servers |
| Long-form | **Yes**: "good for long-form and distant audio, such as lectures, meetings" [Confirmed] | Designed for short dictation (historically about 1-minute limits on server mode) |
| File input | `analyzer.analyzeSequence(from: AVAudioFile)` [Confirmed] | `SFSpeechURLRecognitionRequest` |
| Timestamps | `attributeOptions: [.audioTimeRange]`, sample-accurate `CMTimeRange` per run [Confirmed] | Per-segment timestamps |
| English | Yes; launch list: EN, ES, FR, DE, IT, PT, JA, KO, ZH, Cantonese [Reported, addpipe] | Yes |
| Background | **Not documented** [Confirmed absent in WWDC25-277]. `audio` background mode keeps the app alive only while actively recording. Post-hoc batch transcription when backgrounded needs `BGContinuedProcessingTask` (iOS 26), which the OS can kill [Reported: RisingStack, thinkscribe] | Same constraints |
| Accuracy / speed | Community tests: top-3 for English, about 2.2× faster than Whisper Large-v3 [Reported, gigazine/addpipe]. No diarization | Older Siri model, lower accuracy |

Sources: [WWDC25-277](https://developer.apple.com/videos/play/wwdc2025/277/), [addpipe](https://blog.addpipe.com/apple-speechanalyzer-api/), [thinkscribe](https://thinkscribe.ai/en/blog/offline-speech-to-text-iphone-how-it-works).

**Verdict: record only during the trip, and transcribe on the PC.** Reasons:
- On-device transcription adds battery and heat cost, background-execution fragility, a model download step, and build time.
- It gives no speaker diarization.
- Whisper on the PC is better and does diarize.
- **Optional low-cost win:** transcribe Matt's own **short voice notes** in the foreground right after recording, using `SpeechTranscriber` with `analyzeSequence(from:)`, so notes are searchable on the phone. Treat it as a stretch goal for evening 3 at most.
- Note: `NSSpeechRecognitionUsageDescription` is only needed if you use the Speech framework.

---

## E. Slide capture

| Option | Fit for projected slides in a dark room |
|---|---|
| **`UIImagePickerController(.camera)`** or a minimal `AVCapturePhotoOutput` view | **Recommended.** One tap, standard tap-to-focus/expose (tap the slide so the bright screen is metered instead of the dark room). Keep the original, and stamp the filename plus a JSON sidecar with the ISO-8601 time. `PhotosPicker` only picks existing photos, so it's useful as an import path, not for capture |
| **`VNDocumentCameraViewController`** (VisionKit) | Live quad detection, perspective correction and "document" exposure normalization [Reported, boardsnap]. It's a full-screen modal flow (scan, keep, save) and can't be embedded [Reported]. Document filters can wreck diagrams and photos on slides [Inference]. A projected slide is a high-contrast bright quad, so detection will probably work [Inference]. Too slow per slide when slides change every 30 s |
| **Vision OCR** | `VNRecognizeTextRequest` (iOS 13+) and the new **`RecognizeDocumentsRequest`** (iOS 26) return structure: paragraphs, lists, tables, detected URLs and emails, 26 languages [Confirmed, [WWDC25-272](https://developer.apple.com/videos/play/wwdc2025/272/)]. Also new: `DetectLensSmudgeRequest` |

**Recommendation:** plain camera only, with no on-device OCR. Claude Code reads images directly, so OCR and slide understanding happen on the PC for free. If you want deskewing, do it PC-side with OpenCV (or skip it; Claude handles angled slides). Speakers' official slide PDFs usually arrive "within days" (QCon FAQ) and beat any photo.

---

## F. Getting data off the device (no iCloud)

| Path | Works on free account? | Windows reliability | Notes |
|---|---|---|---|
| **Files app exposure** (`UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`) | Yes, Info.plist only | n/a (on-device) | App's `Documents/` shows under **On My iPhone/iPad** [Confirmed, Apple doc text quoted by [appcoda](https://appcoda.com/files-app-integration/)]. From Files you can zip, move to OneDrive/Google Drive, and so on |
| **Apple Devices app (Windows), Files section, USB** | Yes. Requires an app "that works with File Sharing" (`UIFileSharingEnabled`) | **High.** Official Apple path, USB cable, drag a folder out | [Confirmed, [support.apple.com/HT214072](https://support.apple.com/HT214072)]. **Gotcha [Inference]:** while the device is bound to WSL via `usbipd attach`, Windows can't see it, so detach first |
| **Share sheet → zip of session folder** | Yes | **High.** Send to OneDrive/Google Drive/email/Teams/"Save to Files" | Build the zip in-app (`NSFileCoordinator` with `.forUploading` produces a zip of a directory, the standard trick) or let Files compress it |
| AirDrop to PC | No | n/a | Windows doesn't support AirDrop |
| On-device HTTP server (NWListener, GCDWebServer) | Yes | Medium. Same Wi-Fi needed; conference/hotel Wi-Fi often isolates clients | **[Confirmed, TN3179]** *listening* for TCP does not need local-network permission, but outgoing local connections do. App must be in the foreground. Nice to have, not needed |
| Upload to a GitHub repo / private endpoint | Yes, plain HTTPS | Medium. Depends on venue Wi-Fi; a token on the device | Overkill for 3 evenings; also puts possibly restricted content in a repo |

**Most reliable for a Windows user:**
1. **Daily:** share sheet → zip → OneDrive (or Google Drive), from the hotel each evening. This is the off-device backup.
2. **At home:** Apple Devices app via USB as the bulk/full-quality path.
3. Files-app exposure underpins both and costs two plist keys.

**iPhone + iPad together:** yes [Inference, straightforward].
- Each device writes its own session folder with `deviceID`, and every event is stamped with **UTC ISO-8601 wall-clock time** plus a monotonic offset.
- Both devices sync time over the network, typically within about a second [Inference], which is fine for slide-to-audio alignment.
- For belt and braces, tap "Bookmark: talk start" on both devices at the same moment.
- A PC script merges by timestamp.
- Free provisioning installs the same app on both (each uses one of its 3 app slots), and xtool's profile covers all registered devices [Confirmed].

---

## G. Alternatives, honestly assessed

**1. PWA in Safari: not viable for locked-screen recording.**
- [Confirmed in WebKit source per bb#5698] WebKit mutes mic capture when the page is hidden unless the *host app* declares `UIBackgroundModes=audio`. A web page can't declare that.
- Home-screen PWAs: "Add to Home Screen: Microphone stopped working" (WebKit bug 226620 comment, 2024).
- Multiple reports that capture stops on lock ([SO 79810064](https://stackoverflow.com/questions/79810064/reactjs-web-app-cannot-access-microphone-when-mobile-device-is-locked)).
- A PWA is fine for photos, notes and bookmarks with the screen on, and has no 7-day expiry.

**2. Voice Memos + Camera + Shortcuts: a strong fallback.**
- Voice Memos records with the screen locked (Apple's own app, robust to interruptions).
- **On-device transcript** on iPhone 12+ (iOS 18+), English supported, searchable, with a live transcript view [Confirmed, [Apple Support](https://support.apple.com/guide/iphone/view-a-transcription-iph00953a982/ios)]. Export is **copy-only** (no file and no timestamps) [Reported].
- Audio exports via Share → Save to Files.
- Camera photos carry EXIF timestamps.
- A Shortcut bound to the Action Button or Back Tap can append "`<current date ISO> | <talk> | <typed note>`" to a Note or text file for bookmarks. [Inference: built from standard actions; verify which "append" action works best for you.]
- **What you lose versus a custom app:**
  - one-tap tagging of every capture to a talk (you rename memos and sort photos afterwards),
  - bookmarks inside the audio timeline (you reconstruct them from memo start time plus shortcut timestamps),
  - one self-describing session bundle (instead: 3 apps' exports to merge),
  - segment-level crash safety (Voice Memos is robust in practice).
- **What you gain:** zero build risk and no 7-day expiry.
- **The QCon recording rule applies to Voice Memos equally.**

---

## H. PC-side processing on Windows (assumption: NVIDIA RTX GPU, not verified)

**CUDA under WSL2 [Confirmed, [NVIDIA WSL guide](https://docs.nvidia.com/cuda/wsl-user-guide/index.html)]:**
- Install **only the Windows NVIDIA driver**: "Do not install any Linux display driver in WSL."
- WSL 2 is required.
- CUDA 13.x supports Turing (RTX 20-series) and later.

| Tool | Speed (reported) | Diarization | Notes |
|---|---|---|---|
| **faster-whisper** (CTranslate2) | SYSTRAN benchmark, 13-min clip on RTX 3070 Ti: large FP16 ~63 s (~12× real time, **~5 min per hour**); batched (batch=8) ~17 s (**~1.3 min per hour**); INT8 ~2.9 GB VRAM [Reported via [dev.to](https://dev.to/jovan_chan_9500711396d4e6/faster-whisper-vs-whispercpp-vs-whisperx-2026-o29)] | No | Simplest high-throughput option; word timestamps available |
| **WhisperX** | "70× realtime with large-v2" (project claim), <8 GB VRAM [Confirmed claim, [README](https://github.com/m-bain/whisperX)] | **Yes**: pyannote `speaker-diarization-community-1`; needs a **Hugging Face token** and accepting the model's user agreement; `--diarize --hf_token … --min_speakers/--max_speakers` | Requires CUDA toolkit 12.8; forced alignment gives accurate word timings. **Best fit**: talks are 1 speaker plus Q&A |
| **whisper.cpp** | No NVIDIA numbers in sources; builds with `-DGGML_CUDA=1` | No (only basic tinydiarize) | Good for no-Python setups; fine on CPU too |

**Estimate [Inference]:** 15 talks × 50 min ≈ 12.5 h of audio, so about **15–60 min of GPU time total** with WhisperX/faster-whisper. CPU-only would be hours, but still overnight-feasible.

**Cloud APIs (Oct–Nov 2026 list prices) [Reported]:**
- AssemblyAI Universal-2: $0.15/h + $0.02/h diarization.
- Deepgram Nova-3: about $0.26/h, or about $0.38/h with diarization.
- OpenAI gpt-4o-mini-transcribe: $0.18/h. `gpt-4o-transcribe-diarize` is deprecated, with removal on Feb 26, 2027.
- 12.5 h therefore costs **about $2–5**.
- Sources: [forasoft](https://www.forasoft.com/blog/article/speaker-diarization-api-comparison), [transcriptionindex](https://transcriptionindex.com/transcription-apis/), [aistall](https://aistall.blog/blog/the-per-minute-transcription-price-is-an-estimate/).
- **Caveat [Inference]:** sending conference audio to a third-party API may conflict with both QCon's terms and an employer's data-handling policy. Local WhisperX avoids that.

---

## Recommendations

### Minimum viable collector (fits 3 evenings)
One SwiftUI app, no extensions, no entitlements file. The Info.plist from section A, `UIDeviceFamily [1,2]` (default), installed on the iPhone and the iPad.

1. **Talk picker:** `schedule.json` (scrape the QCon schedule on the PC beforehand), bundled through `resources:`. Auto-select the talk by current time, with a manual override. The active talk ID is stamped on every capture.
2. **Capture buttons:**
   - Photo (camera)
   - Bookmark (one tap, optional 1-word tag)
   - Text note
   - Voice note (foreground, short, Matt's own voice)
   - Each writes to `Documents/<date>/<talkID>/` and appends one line to `events.jsonl`: `{ts_utc, device, talk, type, file, note}`.
3. **Full-talk audio (feature-flagged, off by default):** use only with permission. `AVAudioEngine` tap, `.playAndRecord` + `.mixWithOthers`, AAC mono 64 kbps, 5-minute segments, interruption → close and reopen segment, start in the foreground only, and log every gap.
4. **Export:**
   - Files-app exposure (two plist keys).
   - A "Share today as .zip" button.
   - The Apple Devices USB path works automatically.
5. **PC side:** `ingest.py` unzips, merges devices by `ts_utc`, and builds a per-talk folder. Then:
   - WhisperX transcribes (only where audio exists),
   - Claude Code reads the photos, notes, bookmarks, official slides and, from Dec 21, the official recordings,
   - and writes `talks/<talk>.md`.

**Suggested evening split:**
- **Evening 1 (Nov 10–11):** xtool skeleton, plist, camera, bookmarks, notes, `events.jsonl`, Files exposure. Install on both devices.
- **Evening 2:** schedule picker, voice notes, zip/share export. If audio is wanted: the segmented recorder plus a locked-screen test of at least 60 min, a call-interruption test, and a check that segments are playable.
- **Evening 3 (Nov 13):** PC ingest script, full dress rehearsal (a fake "talk" at home), then a **final reinstall on the morning of Nov 14** and a check with `xtool ds profiles list`.

### Risks (ranked)
1. **Policy:** QCon T&C ¶24 forbids attendees recording sessions, with expulsion as a possible penalty. Audio becomes opt-in with permission. Photos are explicitly allowed. Official video arrives about Dec 21.
2. **7-day expiry mid-trip:** an install before about 07:00 ET Nov 14 risks dying on Nov 20. Reinstall on Nov 14 morning and verify the expiration date. If the app dies, data stays on the device, but you can't open it until you re-sign at home. Don't delete the app.
3. **Certificate revocation:** running `xtool setup` / auth elsewhere can revoke the free certificate and kill installed apps. Don't touch xtool auth during the trip.
4. **Data loss before export:** a crash, a dead battery or a lost phone. Mitigations: segmenting, an evening zip to OneDrive, two devices.
5. **Background audio edge cases** (if used): failure to resume after a call while locked, and starting a recording from the background. Mitigations: `.mixWithOthers`, Do Not Disturb, new segment per interruption, a local notification when capture stops.
6. **Build time:** xtool/WSL/USB friction (muxError, usbipd) eats an evening. Keep the scope to the MVP and skip OCR, on-device transcription and the HTTP server.
7. **Free-tier slots:** 3 apps per device. Remove other sideloaded dev apps if needed.
8. **Battery:** about 20–35%/day for 6 h of audio (estimate). Carry a battery pack, and keep screen-on time low.

### Fallback if the app isn't ready by Nov 14
- **Camera app** for slides. EXIF timestamps are enough to align later.
- **Notes (or a Shortcut on the Action Button / Back Tap)** for timestamped bookmarks: `ISO time | talk | note`.
- **Voice Memos** for your own spoken notes between talks (on-device transcript, copy-only).
- Full talks recorded **only where explicitly permitted**.
- **After the trip:** Photos export via the Apple Devices app or OneDrive, the speakers' official slide PDFs (within days), and the official recordings (about Dec 21). Claude Code merges everything by timestamp and synthesizes the knowledge repo. You lose only convenience: per-capture talk tagging and a single bundle.
