import Foundation

// SESSION AUDIO: NOT BUILT (stub).
//
// architecture.md §11 keeps session audio out of the MVP: "Session audio only if all of that is
// done with an hour to spare; otherwise it is left out of the build and Voice Memos covers any talk
// where permission is given." This file marks where it would go so the bundle format stays complete.
//
// If you build it (evening 2 with slack, and only after QCon or a speaker says yes):
//  1. Info.plist: add UIBackgroundModes = [audio].
//  2. Settings: show the "Offer session audio (needs permission each talk)" toggle in ExportView
//     (settings.offer_session_audio already exists in collector.json).
//  3. Capture › More › "Session audio…": a form with "Who agreed?" (speaker / organizer),
//     "How?" (in_person / written) and an optional note. Start stays disabled until both are set.
//  4. On Start: append `audio_permission` {granted_by, how, note}, update manifest.session_audio
//     {permitted: true, granted_by, how, note, granted_utc}, then `audio_start`.
//  5. Recorder: AVAudioSession .playAndRecord with [.mixWithOthers]; AVAudioEngine input tap writing
//     AAC mono 64 kbps to audio/<seq4>_audio_seg<NNN>_<HHMMSS>Z.m4a; rotate every 5 minutes and
//     append one `audio_segment` {file, dur_ms} per closed file; start only in the foreground.
//  6. Interruption began: close the segment, append `audio_gap` {reason}; ended: open a new segment.
//  7. Stop: close the segment and append `audio_stop`. Show a persistent status row while recording.
//
// Event names and fields are fixed in architecture.md §4.6, and tools/ingest.py already counts
// `audio_segment` and keeps audio out of the shareable repo.

enum SessionAudio {
    /// False in this build. The UI checks this before offering anything audio-related.
    static let isBuilt = false
}
