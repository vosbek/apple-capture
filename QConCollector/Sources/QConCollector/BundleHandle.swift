import Foundation

/// One session bundle on disk (architecture §4.4): manifest.json + append-only events.jsonl + media.
/// Every capture appends one line and flushes it before the UI confirms.
final class BundleHandle {
    let url: URL
    let dateFolder: String
    private(set) var manifest: Manifest
    private(set) var events: [Event]
    private var monoBase: UInt64
    private var lastWall: Date?
    private var lastMonoMs: Int?

    static let schema = "collector.bundle/1"

    var relPath: String { "\(dateFolder)/\(url.lastPathComponent)" }
    var talk: Talk { manifest.talk.asTalk }
    var talkID: String { manifest.talk.talkID }
    var label: String { manifest.device.label }
    var t0: Date { Fmt.parse(manifest.clock.t0UTC) ?? Date() }
    var schedEnd: Date { Fmt.parse(manifest.talk.schedEndUTC) ?? t0.addingTimeInterval(3600) }
    var lastSeq: Int { events.map { $0.seq }.max() ?? 0 }
    var isPrivate: Bool { manifest.visibility == "private" }

    /// The last speaker_start in the file wins (§4.6).
    var speakerStart: Date? { events.last(where: { $0.type == "speaker_start" })?.date }

    private init(url: URL, dateFolder: String, manifest: Manifest, events: [Event]) {
        self.url = url
        self.dateFolder = dateFolder
        self.manifest = manifest
        self.events = events
        // mono_ms continues from the wall-clock time since the bundle opened (best estimate after relaunch).
        let opened = Fmt.parse(manifest.openedUTC) ?? Date()
        let elapsedNs = UInt64(max(0, Date().timeIntervalSince(opened)) * 1_000_000_000)
        let now = Fmt.monoNow()
        self.monoBase = now > elapsedNs ? now - elapsedNs : 0
    }

    // MARK: Create and load

    static func folderName(talk: Talk, start: Date, device: String) -> String {
        "\(Fmt.hhmmF.string(from: start))_\(String(talk.talkID.prefix(48)))__\(device)"
    }

    /// Creates the folder, writes manifest.json and the session_open line.
    static func create(talk: Talk, sessionsDir: URL, device: DeviceInfo, now: Date) throws -> BundleHandle {
        let isAdhoc = talk.kind == .adhoc
        let start = isAdhoc ? now : talk.startDate
        let dateFolder = Fmt.dayKey(start)
        let folder = folderName(talk: talk, start: start, device: device.label)
        let url = sessionsDir.appendingPathComponent(dateFolder).appendingPathComponent(folder)
        let fm = FileManager.default
        try fm.createDirectory(at: url.appendingPathComponent("photos"), withIntermediateDirectories: true)
        try fm.createDirectory(at: url.appendingPathComponent("voice"), withIntermediateDirectories: true)

        let manifest = Manifest(
            schema: schema,
            bundleID: "\(dateFolder)_\(folder)",
            talk: ManifestTalk(talk: talk),
            visibility: talk.privateByDefault || isAdhoc ? "private" : "shareable",
            device: device,
            clock: ClockInfo(t0UTC: Fmt.utcPlain(start), t0Basis: isAdhoc ? "opened" : "scheduled_start",
                             speakerStartUTC: nil, speakerStartTMs: nil),
            sessionAudio: AudioGrant(permitted: false, grantedBy: nil, how: nil, note: nil, grantedUTC: nil),
            openedUTC: Fmt.utc(now),
            closedUTC: nil,
            closeReason: nil,
            counts: Counts(),
            lastSeq: 0)
        let handle = BundleHandle(url: url, dateFolder: dateFolder, manifest: manifest, events: [])
        handle.monoBase = Fmt.monoNow()
        try handle.writeManifest()
        _ = try handle.append("session_open", at: now) { e in e.appVersion = device.appVersion }
        return handle
    }

    static func load(url: URL) throws -> BundleHandle {
        let data = try Data(contentsOf: url.appendingPathComponent("manifest.json"))
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        let events = readEvents(url.appendingPathComponent("events.jsonl"))
        let dateFolder = url.deletingLastPathComponent().lastPathComponent
        let handle = BundleHandle(url: url, dateFolder: dateFolder, manifest: manifest, events: events)
        handle.recount()   // events.jsonl wins over the manifest
        return handle
    }

    /// Reads events.jsonl; a line that does not decode (for example a truncated last line) is skipped.
    static func readEvents(_ url: URL) -> [Event] {
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        var out: [Event] = []
        for line in text.split(separator: "\n") {
            if let d = line.data(using: .utf8), let e = try? decoder.decode(Event.self, from: d) {
                out.append(e)
            }
        }
        return out
    }

    // MARK: Append

    /// Appends one event line and flushes it to disk. `at` is the time the action happened.
    @discardableResult
    func append(_ type: String, at ts: Date = Date(), configure: (inout Event) -> Void = { _ in }) throws -> Event {
        let seq = lastSeq + 1
        let nowWall = Date()
        let mono = monoMs()
        var e = Event(seq: seq, id: "\(label)-\(Fmt.seq4(seq))", type: type, tsUTC: Fmt.utc(ts),
                      tMs: Fmt.ms(ts.timeIntervalSince(t0)), monoMs: mono)
        configure(&e)
        if let lw = lastWall, let lm = lastMonoMs {
            let drift = Fmt.ms(nowWall.timeIntervalSince(lw)) - (mono - lm)
            if abs(drift) > 5000 { e.clockJumpMs = drift }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        var line = try encoder.encode(e)
        line.append(0x0A)
        try appendLine(line)
        lastWall = nowWall
        lastMonoMs = mono
        events.append(e)
        applyToManifest(e)
        try? writeManifest()   // convenience header; events.jsonl is the record
        return e
    }

    private func monoMs() -> Int {
        let now = Fmt.monoNow()
        if now < monoBase { monoBase = now }   // device rebooted since the bundle opened
        return Int((now - monoBase) / 1_000_000)
    }

    private func appendLine(_ data: Data) throws {
        let fileURL = url.appendingPathComponent("events.jsonl")
        let fm = FileManager.default
        if !fm.fileExists(atPath: fileURL.path) {
            guard fm.createFile(atPath: fileURL.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let fh = try FileHandle(forWritingTo: fileURL)
        defer { try? fh.close() }
        _ = try fh.seekToEnd()
        try fh.write(contentsOf: data)
        try fh.synchronize()
    }

    private func applyToManifest(_ e: Event) {
        switch e.type {
        case "speaker_start":
            manifest.clock.speakerStartUTC = e.tsUTC
            manifest.clock.speakerStartTMs = e.tMs
        case "visibility":
            if let v = e.value { manifest.visibility = v }
        case "session_close":
            manifest.closedUTC = e.tsUTC
            manifest.closeReason = e.reason
        case "resume":
            manifest.closedUTC = nil
            manifest.closeReason = nil
        default:
            break
        }
        recount()
    }

    private func recount() {
        let deleted = Set(events.filter { $0.type == "delete" }.compactMap { $0.target })
        var c = Counts()
        for e in events where !deleted.contains(e.id) {
            switch e.type {
            case "photo": c.photo += 1
            case "moment": c.moment += 1
            case "note": c.note += 1
            case "voice": c.voice += 1
            case "audio_segment": c.audioSegment += 1
            default: break
            }
        }
        manifest.counts = c
        manifest.lastSeq = lastSeq
    }

    func writeManifest() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(manifest)
        try data.write(to: url.appendingPathComponent("manifest.json"), options: .atomic)
    }

    // MARK: Media

    /// Writes the JPEG first, then the `photo` event that names it.
    func savePhoto(_ jpeg: Data, at ts: Date, zoom: Double) throws -> Event {
        let seq = lastSeq + 1
        let rel = "photos/\(Fmt.seq4(seq))_photo_\(Fmt.utcTimeF.string(from: ts))Z.jpg"
        try jpeg.write(to: url.appendingPathComponent(rel), options: .atomic)
        return try append("photo", at: ts) { e in
            e.file = rel
            e.zoom = zoom
        }
    }

    /// Moves a finished recording into voice/ and writes the `voice` event.
    func saveVoice(from temp: URL, startedAt: Date, durMs: Int, phase: String) throws -> Event {
        let seq = lastSeq + 1
        let rel = "voice/\(Fmt.seq4(seq))_voice_\(Fmt.utcTimeF.string(from: startedAt))Z.m4a"
        let dest = url.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: temp, to: dest)
        return try append("voice", at: startedAt) { e in
            e.file = rel
            e.durMs = durMs
            e.phase = phase
        }
    }

    func fileURL(_ rel: String?) -> URL? {
        guard let rel = rel else { return nil }
        return url.appendingPathComponent(rel)
    }

    // MARK: Resolved view for the UI (tags, edits and deletes applied)

    struct Item: Identifiable {
        var event: Event
        var tag: String?
        var text: String?
        var id: String { event.id }
    }

    func items() -> [Item] {
        var deleted = Set<String>()
        var tags: [String: String?] = [:]
        var edits: [String: String] = [:]
        for e in events {
            guard let target = e.target else { continue }
            switch e.type {
            case "delete": deleted.insert(target)
            case "tag": tags[target] = .some(e.tag)
            case "edit": edits[target] = e.text ?? ""
            default: break
            }
        }
        let shown: Set<String> = ["photo", "moment", "note", "voice", "speaker_start"]
        var out: [Item] = []
        for e in events where shown.contains(e.type) && !deleted.contains(e.id) {
            var tag = e.tag
            if let t = tags[e.id] { tag = t }
            out.append(Item(event: e, tag: tag, text: edits[e.id] ?? e.text))
        }
        return out.sorted { $0.event.tsUTC < $1.event.tsUTC }
    }

    /// Offset of an event from the talk start (speaker_start if synced, else scheduled start).
    func talkMs(_ e: Event) -> Int {
        let base = speakerStart ?? t0
        return Fmt.ms(e.date.timeIntervalSince(base))
    }
}
