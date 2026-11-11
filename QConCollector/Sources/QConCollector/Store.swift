import Foundation
import SwiftUI
import UIKit

struct Slot: Identifiable {
    let start: Date
    let end: Date
    let talks: [Talk]
    var id: Date { start }
}

struct Suggestion {
    let slot: Slot
    let talk: Talk?
    let reason: String?
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
    let recordKey: String            // day key, "all" or a bundle ID
    let lastSeqs: [String: Int]      // snapshot when the zip was built
}

/// App state and every write. All mutations go through here so the UI only confirms
/// a capture after its line is on disk.
@MainActor
final class Store: ObservableObject {
    @Published private(set) var schedule: Schedule? = nil
    @Published private(set) var scheduleError: String? = nil
    @Published private(set) var scheduleSource: String = "bundled"
    @Published var state: CollectorState
    @Published private(set) var bundles: [BundleSummary] = []
    @Published private(set) var open: BundleHandle? = nil
    @Published var showCapture = false
    @Published var resumedNotice = false
    @Published var writeError: String? = nil
    @Published var reflectTalk: Talk? = nil
    @Published var pendingStart: Talk? = nil
    @Published var tab = 0
    @Published var captureLine = "Nothing captured yet"
    @Published var lastCapture: Event? = nil
    @Published var zipBusy: String? = nil
    @Published var shareItem: ShareItem? = nil
    @Published var alertMessage: String? = nil

    private(set) var slots: [Slot] = []
    private var cache: [String: BundleHandle] = [:]
    let docs: URL
    let sessionsDir: URL
    let expiry: Date?
    let installDate: Date?

    init() {
        let fm = FileManager.default
        let d = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let s = d.appendingPathComponent("sessions")
        try? fm.createDirectory(at: s, withIntermediateDirectories: true)
        docs = d
        sessionsDir = s
        let label = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        state = Store.loadState(d.appendingPathComponent("collector.json"), defaultLabel: label)
        expiry = Store.readExpiry()
        let attrs = try? fm.attributesOfItem(atPath: Bundle.main.bundlePath)
        installDate = attrs?[.creationDate] as? Date
        loadSchedule()
        refreshBundles()
        recoverOpenSession()
        saveState()
    }

    // MARK: Schedule

    func loadSchedule() {
        let decoder = JSONDecoder()
        var errors: [String] = []
        let override = docs.appendingPathComponent("schedule.json")
        if FileManager.default.fileExists(atPath: override.path) {
            do {
                schedule = try decoder.decode(Schedule.self, from: Data(contentsOf: override))
                scheduleSource = "schedule.json from Files"
            } catch {
                errors.append("schedule.json in Files could not be read: \(String(describing: error))")
            }
        }
        if schedule == nil {
            if let url = Bundle.main.url(forResource: "schedule", withExtension: "json") {
                do {
                    schedule = try decoder.decode(Schedule.self, from: Data(contentsOf: url))
                    scheduleSource = "bundled"
                } catch {
                    errors.append("Bundled schedule.json could not be read: \(String(describing: error))")
                }
            } else {
                errors.append("schedule.json is missing from the app.")
            }
        }
        scheduleError = errors.isEmpty ? nil : errors.joined(separator: "\n")
        buildSlots()
    }

    private func buildSlots() {
        guard let talks = schedule?.talks else { slots = []; return }
        let groups = Dictionary(grouping: talks, by: { $0.startDate })
        var out: [Slot] = []
        for (start, list) in groups {
            let end = list.map { $0.endDate }.max() ?? start
            let sorted = list.sorted { ($0.track ?? "~") < ($1.track ?? "~") }
            out.append(Slot(start: start, end: end, talks: sorted))
        }
        slots = out.sorted { $0.start < $1.start }
    }

    /// design-spec §3 suggestion rule.
    func suggestion(now: Date) -> Suggestion? {
        let current = slots.filter { $0.start.addingTimeInterval(-20 * 60) <= now && now < $0.end }
        var chosen: Slot? = current.max(by: { $0.start < $1.start })
        if chosen == nil { chosen = slots.first(where: { $0.start > now }) }
        guard let slot = chosen else { return nil }
        let starred = slot.talks.filter { state.plan.contains($0.talkID) }
        if starred.count == 1 {
            return Suggestion(slot: slot, talk: starred[0], reason: "Suggested because it is on your plan")
        }
        let pool = starred.isEmpty ? slot.talks.filter { $0.isCurated } : starred
        if let room = state.lastRoom, let t = pool.first(where: { $0.room == room }) {
            return Suggestion(slot: slot, talk: t, reason: "Suggested because it is in the room you were just in")
        }
        return Suggestion(slot: slot, talk: pool.first, reason: nil)
    }

    func slot(containing talkID: String) -> Slot? {
        slots.first { s in s.talks.contains { $0.talkID == talkID } }
    }

    func talk(_ id: String) -> Talk? {
        if let t = schedule?.talks.first(where: { $0.talkID == id }) { return t }
        return bundles.first(where: { $0.manifest.talk.talkID == id })?.manifest.talk.asTalk
    }

    // MARK: Bundles

    func refreshBundles() {
        let fm = FileManager.default
        var out: [BundleSummary] = []
        let days = (try? fm.contentsOfDirectory(at: sessionsDir, includingPropertiesForKeys: nil)) ?? []
        for day in days {
            let folders = (try? fm.contentsOfDirectory(at: day, includingPropertiesForKeys: nil)) ?? []
            for f in folders {
                guard let data = try? Data(contentsOf: f.appendingPathComponent("manifest.json")),
                      let m = try? JSONDecoder().decode(Manifest.self, from: data) else { continue }
                out.append(BundleSummary(relPath: "\(day.lastPathComponent)/\(f.lastPathComponent)",
                                         dateFolder: day.lastPathComponent, url: f, manifest: m))
            }
        }
        bundles = out.sorted { $0.manifest.openedUTC < $1.manifest.openedUTC }
    }

    private func touch(_ h: BundleHandle) {
        let s = BundleSummary(relPath: h.relPath, dateFolder: h.dateFolder, url: h.url, manifest: h.manifest)
        if let i = bundles.firstIndex(where: { $0.id == s.id }) {
            bundles[i] = s
        } else {
            bundles.append(s)
        }
    }

    /// This device's bundle for a talk (one bundle per talk per device).
    func summary(for talkID: String) -> BundleSummary? {
        bundles.first { $0.manifest.talk.talkID == talkID && $0.manifest.device.label == state.deviceLabel }
    }

    func handle(for talkID: String) -> BundleHandle? {
        if let o = open, o.talkID == talkID { return o }
        guard let s = summary(for: talkID) else { return nil }
        if let h = cache[s.id] { return h }
        guard let h = try? BundleHandle.load(url: s.url) else { return nil }
        cache[s.id] = h
        return h
    }

    /// Bundle for a talk, created (without opening a capture session) if missing. Used by reflections.
    func ensureHandle(for talk: Talk) -> BundleHandle? {
        if let h = handle(for: talk.talkID) { return h }
        let info = deviceInfo
        let dir = sessionsDir
        guard let h = perform({ try BundleHandle.create(talk: talk, sessionsDir: dir, device: info, now: Date()) }) else { return nil }
        cache[h.manifest.bundleID] = h
        touch(h)
        return h
    }

    private var deviceInfo: DeviceInfo {
        DeviceInfo(label: state.deviceLabel, model: Fmt.deviceModel(),
                   os: UIDevice.current.systemVersion, appVersion: Fmt.appVersion())
    }

    @discardableResult
    private func perform<T>(_ body: () throws -> T) -> T? {
        do {
            let result = try body()
            writeError = nil
            return result
        } catch {
            writeError = "Could not save. Free up space. (\(error.localizedDescription))"
            return nil
        }
    }

    // MARK: Sessions

    func requestStart(_ talk: Talk) {
        if let o = open, o.talkID != talk.talkID {
            pendingStart = talk
        } else {
            start(talk)
        }
    }

    func start(_ talk: Talk) {
        if let o = open {
            if o.talkID == talk.talkID { showCapture = true; return }
            close(o, reason: "superseded")
        }
        var opened: BundleHandle? = nil
        if let existing = handle(for: talk.talkID) {
            if perform({ try existing.append("resume") }) != nil { opened = existing }
        } else {
            let info = deviceInfo
            let dir = sessionsDir
            opened = perform({ try BundleHandle.create(talk: talk, sessionsDir: dir, device: info, now: Date()) })
        }
        guard let h = opened else { return }
        cache[h.manifest.bundleID] = h
        open = h
        touch(h)
        state.openBundle = h.relPath
        if let room = talk.room { state.lastRoom = room }
        saveState()
        lastCapture = nil
        captureLine = "Nothing captured yet"
        resumedNotice = false
        showCapture = true
    }

    func startAdhoc(name: String) {
        let now = Date()
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let talk = Talk(talkID: "adhoc-\(Fmt.adhocF.string(from: now))", kind: .adhoc,
                        title: n.isEmpty ? "Ad hoc session" : n, speakers: [], track: nil, room: nil,
                        start: Fmt.utcPlain(now), end: Fmt.utcPlain(now.addingTimeInterval(3600)),
                        url: nil, noVideo: true, privateByDefault: true)
        requestStart(talk)
    }

    private func close(_ h: BundleHandle, reason: String) {
        perform({ try h.append("session_close") { e in e.reason = reason } })
        touch(h)
        if open === h {
            open = nil
            state.openBundle = nil
            saveState()
        }
    }

    /// "End": close, leave Capture, offer a reflection.
    func end() {
        guard let h = open else { return }
        close(h, reason: "user")
        showCapture = false
        let talk = h.talk
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            self.reflectTalk = talk
        }
    }

    /// §4.2 Recovery: reopen if the scheduled end + 15 min has not passed, else close as recovered.
    private func recoverOpenSession() {
        guard let rel = state.openBundle else { return }
        guard let h = try? BundleHandle.load(url: sessionsDir.appendingPathComponent(rel)) else {
            state.openBundle = nil
            return
        }
        cache[h.manifest.bundleID] = h
        if Date() < h.schedEnd.addingTimeInterval(15 * 60) {
            perform({ try h.append("resume") })
            open = h
            resumedNotice = true
            showCapture = true
        } else {
            perform({ try h.append("session_close") { e in e.reason = "recovered" } })
            state.openBundle = nil
        }
        touch(h)
    }

    // MARK: Captures

    func moment() {
        guard let h = open, let e = perform({ try h.append("moment") }) else { return }
        lastCapture = e
        captureLine = "Moment saved at \(Fmt.offset(ms: h.talkMs(e)))."
        touch(h)
    }

    func photo(_ jpeg: Data, at ts: Date, zoom: Double, into h: BundleHandle) {
        guard let e = perform({ try h.savePhoto(jpeg, at: ts, zoom: zoom) }) else { return }
        lastCapture = e
        captureLine = "Slide saved at \(Fmt.offset(ms: h.talkMs(e)))."
        touch(h)
    }

    func addNote(_ text: String, openedAt: Date, to h: BundleHandle) {
        let saved = Fmt.utc(Date())
        guard let e = perform({ try h.append("note", at: openedAt) { e in
            e.text = text
            e.savedUTC = saved
        } }) else { return }
        if h === open {
            lastCapture = e
            captureLine = "Note saved at \(Fmt.offset(ms: h.talkMs(e)))."
        }
        touch(h)
    }

    func tag(_ target: String, _ tag: String?, in h: BundleHandle) {
        perform({ try h.append("tag") { e in
            e.target = target
            e.tag = tag
        } })
        touch(h)
    }

    func editNote(_ target: String, text: String, in h: BundleHandle) {
        perform({ try h.append("edit") { e in
            e.target = target
            e.text = text
        } })
        touch(h)
    }

    func deleteEvent(_ target: String, in h: BundleHandle) {
        perform({ try h.append("delete") { e in e.target = target } })
        touch(h)
    }

    func setVisibility(_ value: String, in h: BundleHandle) {
        perform({ try h.append("visibility") { e in e.value = value } })
        touch(h)
    }

    func undo() {
        guard let h = open, let last = lastCapture else { return }
        deleteEvent(last.id, in: h)
        lastCapture = nil
        captureLine = "Removed"
    }

    func syncStart(at date: Date) {
        guard let h = open else { return }
        perform({ try h.append("speaker_start", at: date) })
        touch(h)
    }

    /// Returns false if the file could not be saved (the temp recording is then left in tmp/).
    func saveReflection(talk: Talk, temp: URL, startedAt: Date, durMs: Int) -> Bool {
        guard let h = ensureHandle(for: talk) else { return false }
        let phase = startedAt < h.t0 ? "before" : "after"
        let e = perform({ try h.saveVoice(from: temp, startedAt: startedAt, durMs: durMs, phase: phase) })
        touch(h)
        return e != nil
    }

    // MARK: Plan and settings

    func isStarred(_ talkID: String) -> Bool { state.plan.contains(talkID) }

    func toggleStar(_ talkID: String) {
        if let i = state.plan.firstIndex(of: talkID) {
            state.plan.remove(at: i)
        } else {
            state.plan.append(talkID)
        }
        saveState()
    }

    static func loadState(_ url: URL, defaultLabel: String) -> CollectorState {
        if let data = try? Data(contentsOf: url) {
            if let s = try? JSONDecoder().decode(CollectorState.self, from: data) { return s }
            // Keep an unreadable file for inspection instead of overwriting it.
            let aside = url.deletingLastPathComponent().appendingPathComponent("collector.unreadable.json")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: url, to: aside)
        }
        return CollectorState(schema: "collector.state/1", deviceLabel: defaultLabel, plan: [],
                              settings: Settings(dimCapture: true, offerSessionAudio: false, useSystemCamera: false),
                              lastRoom: nil, openBundle: nil, exports: [])
    }

    /// Atomic: Data.write(.atomic) writes a temporary file and renames it.
    func saveState() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(state) else { return }
        do {
            try data.write(to: docs.appendingPathComponent("collector.json"), options: .atomic)
        } catch {
            writeError = "Could not save app state. Free up space."
        }
    }

    // MARK: Export bookkeeping

    var dayKeys: [String] { Array(Set(bundles.map { $0.dateFolder })).sorted() }

    func dayBundles(_ day: String) -> [BundleSummary] { bundles.filter { $0.dateFolder == day } }

    func exportedSeq(_ bundleID: String) -> Int {
        state.exports.compactMap { $0.lastSeqByBundle[bundleID] }.max() ?? 0
    }

    func newCaptures(day: String) -> Int {
        dayBundles(day).reduce(0) { sum, b in sum + max(0, b.manifest.lastSeq - exportedSeq(b.id)) }
    }

    func lastExport(day: String) -> ExportRecord? {
        state.exports.last(where: { $0.date == day || $0.date == "all" })
    }

    func shareZip(directory: URL, name: String, key: String, bundleIDs: [String]) {
        guard zipBusy == nil else { return }
        zipBusy = key
        var seqs: [String: Int] = [:]
        for b in bundles where bundleIDs.contains(b.id) { seqs[b.id] = b.manifest.lastSeq }
        let snapshot = seqs
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<URL, Error> in
                Result { try Zipper.zip(directory: directory, name: name) }
            }.value
            self.zipBusy = nil
            switch result {
            case .success(let url):
                self.shareItem = ShareItem(url: url, recordKey: key, lastSeqs: snapshot)
            case .failure:
                self.alertMessage = "Not enough space to build the zip. The same folders are in Files under On My iPhone › Collector."
            }
        }
    }

    /// Called only when the share sheet reports completion; a cancelled share records nothing.
    func recordExport(_ item: ShareItem) {
        let size = (try? item.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        state.exports.append(ExportRecord(date: item.recordKey, exportedUTC: Fmt.utc(Date()),
                                          lastSeqByBundle: item.lastSeqs, bytes: size))
        saveState()
    }

    var freeSpace: Int64? {
        (try? docs.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
    }

    var expirySoon: Bool {
        guard let e = expiry else { return false }
        return e.timeIntervalSinceNow < 48 * 3600
    }

    /// Reads ExpirationDate from embedded.mobileprovision (architecture §15: verify on device).
    static func readExpiry() -> Date? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8)) else { return nil }
        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)
        return (plist as? [String: Any])?["ExpirationDate"] as? Date
    }

    static func folderSize(_ url: URL) -> Int64 {
        var total: Int64 = 0
        guard let en = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        for case let f as URL in en {
            total += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }

    func justEnded(now: Date) -> BundleSummary? {
        var best: BundleSummary? = nil
        var bestDate = Date.distantPast
        for b in bundles where b.manifest.device.label == state.deviceLabel {
            guard let c = Fmt.parse(b.manifest.closedUTC), now.timeIntervalSince(c) < 45 * 60, c > bestDate else { continue }
            best = b
            bestDate = c
        }
        return best
    }
}
