import Foundation

// Data model from architecture.md §4.3–4.6. JSON keys are snake_case via explicit
// CodingKeys (no key strategies: they would also rewrite dictionary keys such as bundle IDs).

enum TalkKind: String, Codable {
    case keynote, presentation, unconference, sponsored, training, social, adhoc
}

struct Speaker: Codable, Hashable {
    var name: String
    var company: String?
    var role: String?
    var speakerURL: String?

    enum CodingKeys: String, CodingKey {
        case name, company, role
        case speakerURL = "speaker_url"
    }
}

struct Talk: Codable, Hashable, Identifiable {
    var talkID: String
    var kind: TalkKind
    var title: String
    var speakers: [Speaker]
    var track: String?
    var room: String?
    var start: String
    var end: String
    var url: String?
    var noVideo: Bool
    var privateByDefault: Bool

    var id: String { talkID }
    var startDate: Date { Fmt.parse(start) ?? .distantPast }
    var endDate: Date { Fmt.parse(end) ?? .distantPast }
    var isCurated: Bool { kind == .keynote || kind == .presentation || kind == .training }

    enum CodingKeys: String, CodingKey {
        case talkID = "talk_id", kind, title, speakers, track, room, start, end, url
        case noVideo = "no_video"
        case privateByDefault = "private_by_default"
    }
}

struct Schedule: Codable {
    var schema: String
    var event: String
    var tz: String
    var generatedUTC: String?
    var source: String?
    var talks: [Talk]

    enum CodingKeys: String, CodingKey {
        case schema, event, tz, source, talks
        case generatedUTC = "generated_utc"
    }
}

// MARK: - Manifest (§4.5). Custom encoders write explicit nulls, as in the spec example.

struct ManifestTalk: Codable {
    var talkID: String
    var kind: TalkKind
    var title: String
    var speakers: [Speaker]
    var track: String?
    var room: String?
    var url: String?
    var schedStartUTC: String
    var schedEndUTC: String
    var tz: String
    var noVideo: Bool

    enum CodingKeys: String, CodingKey {
        case talkID = "talk_id", kind, title, speakers, track, room, url, tz
        case schedStartUTC = "sched_start_utc", schedEndUTC = "sched_end_utc", noVideo = "no_video"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(talkID, forKey: .talkID)
        try c.encode(kind, forKey: .kind)
        try c.encode(title, forKey: .title)
        try c.encode(speakers, forKey: .speakers)
        try c.encode(track, forKey: .track)
        try c.encode(room, forKey: .room)
        try c.encode(url, forKey: .url)
        try c.encode(schedStartUTC, forKey: .schedStartUTC)
        try c.encode(schedEndUTC, forKey: .schedEndUTC)
        try c.encode(tz, forKey: .tz)
        try c.encode(noVideo, forKey: .noVideo)
    }

    init(talk: Talk) {
        talkID = talk.talkID
        kind = talk.kind
        title = talk.title
        speakers = talk.speakers
        track = talk.track
        room = talk.room
        url = talk.url
        schedStartUTC = Fmt.utcPlain(talk.startDate)
        schedEndUTC = Fmt.utcPlain(talk.endDate)
        tz = Fmt.confTZName
        noVideo = talk.noVideo
    }

    var asTalk: Talk {
        Talk(talkID: talkID, kind: kind, title: title, speakers: speakers, track: track, room: room,
             start: schedStartUTC, end: schedEndUTC, url: url, noVideo: noVideo,
             privateByDefault: kind == .unconference || kind == .social || kind == .adhoc)
    }
}

struct DeviceInfo: Codable {
    var label: String
    var model: String
    var os: String
    var appVersion: String

    enum CodingKeys: String, CodingKey {
        case label, model, os
        case appVersion = "app_version"
    }
}

struct ClockInfo: Codable {
    var t0UTC: String
    var t0Basis: String
    var speakerStartUTC: String?
    var speakerStartTMs: Int?

    enum CodingKeys: String, CodingKey {
        case t0UTC = "t0_utc", t0Basis = "t0_basis"
        case speakerStartUTC = "speaker_start_utc", speakerStartTMs = "speaker_start_t_ms"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(t0UTC, forKey: .t0UTC)
        try c.encode(t0Basis, forKey: .t0Basis)
        try c.encode(speakerStartUTC, forKey: .speakerStartUTC)
        try c.encode(speakerStartTMs, forKey: .speakerStartTMs)
    }
}

struct AudioGrant: Codable {
    var permitted: Bool
    var grantedBy: String?
    var how: String?
    var note: String?
    var grantedUTC: String?

    enum CodingKeys: String, CodingKey {
        case permitted, how, note
        case grantedBy = "granted_by", grantedUTC = "granted_utc"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(permitted, forKey: .permitted)
        try c.encode(grantedBy, forKey: .grantedBy)
        try c.encode(how, forKey: .how)
        try c.encode(note, forKey: .note)
        try c.encode(grantedUTC, forKey: .grantedUTC)
    }
}

struct Counts: Codable {
    var photo = 0
    var moment = 0
    var note = 0
    var voice = 0
    var audioSegment = 0

    enum CodingKeys: String, CodingKey {
        case photo, moment, note, voice
        case audioSegment = "audio_segment"
    }
}

struct Manifest: Codable {
    var schema: String
    var bundleID: String
    var talk: ManifestTalk
    var visibility: String
    var device: DeviceInfo
    var clock: ClockInfo
    var sessionAudio: AudioGrant
    var openedUTC: String
    var closedUTC: String?
    var closeReason: String?
    var counts: Counts
    var lastSeq: Int

    enum CodingKeys: String, CodingKey {
        case schema, talk, visibility, device, clock, counts
        case bundleID = "bundle_id", sessionAudio = "session_audio", openedUTC = "opened_utc"
        case closedUTC = "closed_utc", closeReason = "close_reason", lastSeq = "last_seq"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schema, forKey: .schema)
        try c.encode(bundleID, forKey: .bundleID)
        try c.encode(talk, forKey: .talk)
        try c.encode(visibility, forKey: .visibility)
        try c.encode(device, forKey: .device)
        try c.encode(clock, forKey: .clock)
        try c.encode(sessionAudio, forKey: .sessionAudio)
        try c.encode(openedUTC, forKey: .openedUTC)
        try c.encode(closedUTC, forKey: .closedUTC)
        try c.encode(closeReason, forKey: .closeReason)
        try c.encode(counts, forKey: .counts)
        try c.encode(lastSeq, forKey: .lastSeq)
    }
}

// MARK: - Event (§4.6). One line of events.jsonl. Absent fields are omitted,
// except `tag` on a `tag` event, where null means "tag cleared".

struct Event: Codable, Identifiable {
    var seq: Int
    var id: String
    var type: String
    var tsUTC: String
    var tMs: Int
    var monoMs: Int
    var appVersion: String?
    var file: String?
    var zoom: Double?
    var tag: String?
    var text: String?
    var savedUTC: String?
    var durMs: Int?
    var phase: String?
    var target: String?
    var value: String?
    var reason: String?
    var clockJumpMs: Int?

    enum CodingKeys: String, CodingKey {
        case seq, id, type, file, zoom, tag, text, phase, target, value, reason
        case tsUTC = "ts_utc", tMs = "t_ms", monoMs = "mono_ms", appVersion = "app_version"
        case savedUTC = "saved_utc", durMs = "dur_ms", clockJumpMs = "clock_jump_ms"
    }

    init(seq: Int, id: String, type: String, tsUTC: String, tMs: Int, monoMs: Int) {
        self.seq = seq
        self.id = id
        self.type = type
        self.tsUTC = tsUTC
        self.tMs = tMs
        self.monoMs = monoMs
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(seq, forKey: .seq)
        try c.encode(id, forKey: .id)
        try c.encode(type, forKey: .type)
        try c.encode(tsUTC, forKey: .tsUTC)
        try c.encode(tMs, forKey: .tMs)
        try c.encode(monoMs, forKey: .monoMs)
        try c.encodeIfPresent(appVersion, forKey: .appVersion)
        try c.encodeIfPresent(file, forKey: .file)
        try c.encodeIfPresent(zoom, forKey: .zoom)
        if type == "tag" {
            try c.encode(tag, forKey: .tag)
        } else {
            try c.encodeIfPresent(tag, forKey: .tag)
        }
        try c.encodeIfPresent(text, forKey: .text)
        try c.encodeIfPresent(savedUTC, forKey: .savedUTC)
        try c.encodeIfPresent(durMs, forKey: .durMs)
        try c.encodeIfPresent(phase, forKey: .phase)
        try c.encodeIfPresent(target, forKey: .target)
        try c.encodeIfPresent(value, forKey: .value)
        try c.encodeIfPresent(reason, forKey: .reason)
        try c.encodeIfPresent(clockJumpMs, forKey: .clockJumpMs)
    }

    var date: Date { Fmt.parse(tsUTC) ?? .distantPast }
}

// MARK: - App state (collector.json)

struct Settings: Codable {
    var dimCapture: Bool
    var offerSessionAudio: Bool
    var useSystemCamera: Bool   // not in the spec: switches Slide to UIImagePickerController

    enum CodingKeys: String, CodingKey {
        case dimCapture = "dim_capture", offerSessionAudio = "offer_session_audio"
        case useSystemCamera = "use_system_camera"
    }
}

struct ExportRecord: Codable {
    var date: String               // conference day "2026-11-16", "all", or a bundle ID
    var exportedUTC: String
    var lastSeqByBundle: [String: Int]
    var bytes: Int

    enum CodingKeys: String, CodingKey {
        case date, bytes
        case exportedUTC = "exported_utc", lastSeqByBundle = "last_seq_by_bundle"
    }
}

struct CollectorState: Codable {
    var schema: String
    var deviceLabel: String
    var plan: [String]
    var settings: Settings
    var lastRoom: String?
    var openBundle: String?        // path relative to Documents/sessions, e.g. "2026-11-16/0900_x__iphone"
    var exports: [ExportRecord]

    enum CodingKeys: String, CodingKey {
        case schema, plan, settings, exports
        case deviceLabel = "device_label", lastRoom = "last_room", openBundle = "open_bundle"
    }
}

/// A bundle found on disk (Documents/sessions/<date>/<folder>/manifest.json).
struct BundleSummary: Identifiable {
    var relPath: String
    var dateFolder: String
    var url: URL
    var manifest: Manifest
    var id: String { manifest.bundleID }
}
