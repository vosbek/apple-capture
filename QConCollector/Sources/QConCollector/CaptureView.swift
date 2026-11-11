import ImageIO
import SwiftUI
import UIKit

struct TagOption: Identifiable {
    let key: String
    let label: String
    let shortcut: KeyEquivalent
    var id: String { key }
    static let all = [
        TagOption(key: "idea", label: "Idea", shortcut: "1"),
        TagOption(key: "for_us", label: "For us", shortcut: "2"),
        TagOption(key: "follow_up", label: "Follow up", shortcut: "3"),
        TagOption(key: "question", label: "Question", shortcut: "4"),
    ]
    static func label(_ key: String?) -> String? { all.first { $0.key == key }?.label }
}

/// design-spec §4 (iPhone) and §8 (iPad, regular width). Full-screen cover.
struct CaptureView: View {
    @EnvironmentObject var store: Store
    @StateObject private var camera = CameraController()
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var showNote = false
    @State private var noteText = ""
    @State private var noteOpenedAt = Date()
    @State private var noteCancelled = false
    @State private var showSwitch = false
    @State private var showSystemCamera = false
    @State private var promptUntil = Date.distantPast
    @State private var viewing: Event? = nil
    @State private var pinchStart: CGFloat? = nil
    @State private var confirmEnd = false
    @State private var line = ""
    @State private var lineStarted: Date? = nil
    @FocusState private var lineFocused: Bool

    private var dim: Bool { store.state.settings.dimCapture }
    private var systemCamera: Bool { store.state.settings.useSystemCamera }

    var body: some View {
        Group {
            if let h = store.open {
                if hSize == .regular {
                    ipadLayout(h)
                } else {
                    phoneLayout(h)
                }
            } else {
                VStack(spacing: 12) {
                    Text("No session is open.")
                    Button("Close") { store.showCapture = false }
                }
            }
        }
        .background((dim ? Color.black : Color(.systemBackground)).ignoresSafeArea())
        .preferredColorScheme(dim ? .dark : .light)
        .tint(dim ? Theme.tintDim : Theme.tint)
        .onAppear {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            if !systemCamera { camera.start() }
        }
        .onDisappear { camera.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if !systemCamera { camera.start() }
            } else {
                camera.stop()
            }
        }
        .sheet(isPresented: $showNote, onDismiss: noteDismissed) {
            NoteSheet(title: "Note at \(noteOffset)", text: $noteText,
                      onSave: { showNote = false },
                      onCancel: { noteCancelled = true; showNote = false })
        }
        .sheet(isPresented: $showSwitch) {
            SwitchTalkSheet().environmentObject(store)
        }
        .sheet(item: $viewing) { e in
            if let h = store.open, let url = h.fileURL(e.file) {
                PhotoViewer(url: url) { store.deleteEvent(e.id, in: h) }
            }
        }
        .fullScreenCover(isPresented: $showSystemCamera) {
            SystemCameraPicker { data in
                showSystemCamera = false
                if let data = data, let h = store.open {
                    store.photo(data, at: Date(), zoom: 1, into: h)
                    if store.writeError == nil { Haptics.slide() }
                }
            }
            .ignoresSafeArea()
        }
        .confirmationDialog("End this talk?", isPresented: $confirmEnd) {
            Button("End", role: .destructive) { store.end() }
        }
    }

    private var noteOffset: String {
        guard let h = store.open else { return "" }
        let base = h.speakerStart ?? h.t0
        return Fmt.offset(ms: Fmt.ms(noteOpenedAt.timeIntervalSince(base)))
    }

    // MARK: iPhone

    private func phoneLayout(_ h: BundleHandle) -> some View {
        VStack(spacing: 8) {
            HStack {
                Button("End") { store.end() }
                    .frame(minWidth: 44, minHeight: 44)
                Spacer()
                TimerText(handle: h)
                Spacer()
                moreMenu(h)
            }
            talkLine(h)
            statusRow(h)
            cameraArea(h)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            lastCaptureRow(h)
            Button {
                openNote()
            } label: {
                Label("Note", systemImage: "square.and.pencil")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .frame(height: 54)
            HStack(spacing: 10) {
                momentButton(h)
                slideButton(h)
            }
            .frame(height: 172)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func talkLine(_ h: BundleHandle) -> some View {
        let t = h.talk
        return VStack(spacing: 2) {
            Text(t.title).font(.headline).lineLimit(1)
            Text([Fmt.speakerLine(t.speakers), Fmt.kindLabel(t), t.room ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func moreMenu(_ h: BundleHandle) -> some View {
        Menu {
            Button("Set talk start to now") { store.syncStart(at: Date()) }
            Button("Move talk start 15 s earlier") { store.syncStart(at: (h.speakerStart ?? h.t0).addingTimeInterval(-15)) }
            Button("Move talk start 15 s later") { store.syncStart(at: (h.speakerStart ?? h.t0).addingTimeInterval(15)) }
            Button("Switch talk…") { showSwitch = true }
            Toggle("Dim appearance", isOn: Binding(
                get: { store.state.settings.dimCapture },
                set: { store.state.settings.dimCapture = $0; store.saveState() }))
            // Session audio is not built in this version (see SessionAudio.swift).
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title2)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("More")
    }

    private func statusRow(_ h: BundleHandle) -> some View {
        TimelineView(.periodic(from: .now, by: 5)) { ctx in
            VStack(spacing: 6) {
                if let err = store.writeError {
                    Text(err).font(.footnote.bold())
                        .frame(maxWidth: .infinity)
                        .padding(6)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                }
                if let free = store.freeSpace, free < 500_000_000 {
                    Text("Low storage: \(free / 1_000_000) MB left").font(.footnote.bold())
                }
                if store.resumedNotice {
                    Text("Resumed. Nothing was lost.").font(.footnote)
                }
                if h.speakerStart == nil && h.manifest.talk.kind != .adhoc
                    && ctx.date >= h.t0.addingTimeInterval(-300) && ctx.date <= h.t0.addingTimeInterval(600) {
                    Button {
                        store.syncStart(at: Date())
                    } label: {
                        Text("Speaker started: sync timer")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func cameraArea(_ h: BundleHandle) -> some View {
        let lastPhoto = h.items().last(where: { $0.event.type == "photo" })
        return ZStack {
            Color.black
            if systemCamera {
                Text("System camera: Slide opens the camera.")
                    .font(.footnote).foregroundStyle(.white)
            } else {
                switch camera.status {
                case .running:
                    CameraPreview(camera: camera)
                        .gesture(MagnifyGesture()
                            .onChanged { v in
                                if pinchStart == nil { pinchStart = camera.zoom }
                                camera.setZoom((pinchStart ?? 1) * v.magnification)
                            }
                            .onEnded { _ in pinchStart = nil })
                case .denied:
                    VStack(spacing: 10) {
                        Text("Camera access is off").foregroundStyle(.white)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                case .unavailable:
                    VStack(spacing: 10) {
                        Text("Camera unavailable").foregroundStyle(.white)
                        Button("Try again") { camera.start() }.buttonStyle(.bordered)
                    }
                case .idle:
                    ProgressView()
                }
            }
            VStack {
                HStack {
                    Text("\(h.manifest.counts.photo) slides")
                        .font(.footnote.monospacedDigit())
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                }
                Spacer()
                HStack(alignment: .bottom) {
                    if let p = lastPhoto, let url = h.fileURL(p.event.file) {
                        Button { viewing = p.event } label: { Thumbnail(url: url, size: 52) }
                            .accessibilityLabel("Last photo")
                    } else {
                        Color.clear.frame(width: 52, height: 52)
                    }
                    Spacer()
                    if !systemCamera {
                        HStack(spacing: 8) {
                            ForEach(camera.presets) { p in
                                zoomButton(p)
                            }
                        }
                    }
                    Spacer()
                    Color.clear.frame(width: 52, height: 52)
                }
            }
            .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func zoomButton(_ p: ZoomPreset) -> some View {
        let selected = abs(camera.zoom - p.factor) < 0.05
        return Button {
            camera.setZoom(p.factor)
        } label: {
            Text(p.label)
                .font(.footnote.bold())
                .frame(width: 44, height: 44)
                .background(Circle().fill(selected ? Color.white : Color.black.opacity(0.55)))
                .foregroundStyle(selected ? Color.black : Color.white)
        }
        .accessibilityLabel("Zoom \(p.label)\(selected ? ", selected" : "")")
    }

    private func lastCaptureRow(_ h: BundleHandle) -> some View {
        let last = store.lastCapture
        let isMoment = last?.type == "moment"
        let currentTag = isMoment ? h.items().first(where: { $0.id == last?.id })?.tag : nil
        return VStack(spacing: 6) {
            HStack {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(store.captureLine + (isMoment && ctx.date < promptUntil ? " Tag it?" : ""))
                        .font(.subheadline).lineLimit(1)
                }
                Spacer()
                Button("Undo") { store.undo() }
                    .disabled(last == nil)
            }
            HStack(spacing: 6) {
                ForEach(TagOption.all) { opt in
                    TagButton(label: opt.label, selected: currentTag == opt.key, enabled: isMoment) {
                        if let id = last?.id {
                            store.tag(id, currentTag == opt.key ? nil : opt.key, in: h)
                        }
                    }
                    .keyboardShortcut(opt.shortcut, modifiers: .command)
                }
            }
        }
    }

    private func momentButton(_ h: BundleHandle) -> some View {
        Button {
            store.moment()
            if store.writeError == nil {
                Haptics.moment()
                promptUntil = Date().addingTimeInterval(5)
            }
        } label: {
            VStack(spacing: 4) {
                Text("Moment").font(.title2.bold())
                Text("\(h.manifest.counts.moment)").font(.headline.monospacedDigit())
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 16).fill(dim ? Color(white: 0.22) : Color.black))
        }
        .buttonStyle(.plain)
        .keyboardShortcut("m", modifiers: .command)
        .accessibilityLabel("Moment. \(h.manifest.counts.moment) marked")
    }

    private func slideButton(_ h: BundleHandle) -> some View {
        Button {
            takeSlide(h)
        } label: {
            VStack(spacing: 4) {
                Text("Slide").font(.title2.bold())
                Text("\(h.manifest.counts.photo)").font(.headline.monospacedDigit())
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 16).fill(dim ? Theme.tint.opacity(0.75) : Theme.tint))
        }
        .buttonStyle(.plain)
        .disabled(!systemCamera && camera.status != .running)
        .keyboardShortcut("p", modifiers: .command)
        .accessibilityLabel("Slide. \(h.manifest.counts.photo) taken")
    }

    private func takeSlide(_ h: BundleHandle) {
        if systemCamera {
            showSystemCamera = true
            return
        }
        let ts = Date()
        let zoom = camera.displayZoom
        camera.capture(orientation: UIDevice.current.orientation) { data in
            guard let data = data else {
                store.writeError = "Photo failed. Try again."
                return
            }
            store.photo(data, at: ts, zoom: zoom, into: h)
            if store.writeError == nil { Haptics.slide() }
        }
    }

    private func openNote() {
        noteOpenedAt = Date()
        noteText = ""
        noteCancelled = false
        showNote = true
    }

    /// Swiping the sheet down with text in it saves; only Cancel discards.
    private func noteDismissed() {
        let t = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !noteCancelled, !t.isEmpty, let h = store.open else { return }
        store.addNote(t, openedAt: noteOpenedAt, to: h)
        if store.writeError == nil { Haptics.saved() }
    }

    // MARK: iPad (regular width): log + note field on the left, controls on the right

    private func ipadLayout(_ h: BundleHandle) -> some View {
        let items = h.items().filter { $0.event.type != "speaker_start" }
        let t = h.talk
        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.title).font(.title3.bold()).lineLimit(2)
                        Text([Fmt.speakerLine(t.speakers), t.room ?? "", Fmt.clock(t.startDate)]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    moreMenu(h)
                    Button("End talk") { confirmEnd = true }
                        .keyboardShortcut(".", modifiers: .command)
                }
                statusRow(h)
                ScrollViewReader { proxy in
                    List {
                        if items.isEmpty {
                            Text("Notes and moments from this iPad appear here.").foregroundStyle(.secondary)
                        }
                        ForEach(items) { item in
                            LogRow(item: item, offset: Fmt.offset(ms: h.talkMs(item.event)))
                                .id(item.id)
                        }
                    }
                    .listStyle(.plain)
                    .onChange(of: items.count) { _, _ in
                        if let lastItem = items.last { proxy.scrollTo(lastItem.id, anchor: .bottom) }
                    }
                }
                HStack {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(Fmt.offset(ms: Fmt.ms(ctx.date.timeIntervalSince(h.speakerStart ?? h.t0))))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    TextField("Note", text: $line)
                        .textFieldStyle(.roundedBorder)
                        .focused($lineFocused)
                        .submitLabel(.return)
                        .onSubmit { saveLine(h) }
                        .onChange(of: line) { _, new in
                            if new.isEmpty { lineStarted = nil } else if lineStarted == nil { lineStarted = Date() }
                        }
                }
                Text("Return saves the note · ⌘M moment · ⌘P slide · ⌘1–4 tag · ⌘. end")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(spacing: 10) {
                TimerText(handle: h)
                cameraArea(h).frame(height: 250)
                slideButton(h).frame(height: 64)
                momentButton(h).frame(minHeight: 120, maxHeight: .infinity)
                lastCaptureRow(h)
            }
            .frame(width: 360)
        }
        .padding()
        .onAppear { lineFocused = true }
    }

    private func saveLine(_ h: BundleHandle) {
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty {
            store.addNote(t, openedAt: lineStarted ?? Date(), to: h)
        }
        line = ""
        lineStarted = nil
        lineFocused = true
    }
}

struct LogRow: View {
    let item: BundleHandle.Item
    let offset: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(offset).font(.body.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(item.event.type.uppercased()).font(.caption2.bold()).foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(item.text ?? TagOption.label(item.tag) ?? item.event.file ?? "").font(.body)
        }
    }
}

struct TagButton: View {
    let label: String
    let selected: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        if selected {
            Button(action: action) { text }
                .buttonStyle(.borderedProminent)
                .disabled(!enabled)
        } else {
            Button(action: action) { text }
                .buttonStyle(.bordered)
                .disabled(!enabled)
        }
    }

    private var text: some View {
        Text(label).font(.subheadline).lineLimit(1).minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 36)
    }
}

struct TimerText: View {
    let handle: BundleHandle
    var compact = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let parts = TimerText.describe(now: ctx.date, handle: handle)
            if compact {
                Text("\(parts.main) · \(parts.detail)")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    Text(parts.main).font(.title3.monospacedDigit().bold())
                    Text(parts.detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// design-spec §4 timer table.
    static func describe(now: Date, handle: BundleHandle) -> (main: String, detail: String) {
        let end = handle.schedEnd
        let minutesLeft = Int(end.timeIntervalSince(now) / 60)
        let detail = minutesLeft >= 0 ? "\(minutesLeft) min left" : "over by \(-minutesLeft) min"
        if let ss = handle.speakerStart {
            return (String(Fmt.offset(ms: Fmt.ms(now.timeIntervalSince(ss))).dropFirst()), detail)
        }
        let t0 = handle.t0
        if now < t0 {
            return (Fmt.offset(ms: Fmt.ms(now.timeIntervalSince(t0))), "starts \(Fmt.clock(t0))")
        }
        return (String(Fmt.offset(ms: Fmt.ms(now.timeIntervalSince(t0))).dropFirst()), detail)
    }
}

struct NoteSheet: View {
    let title: String
    @Binding var text: String
    let onSave: () -> Void
    let onCancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .focused($focused)
                .padding(.horizontal)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                    ToolbarItem(placement: .confirmationAction) { Button("Save", action: onSave) }
                }
        }
        .presentationDetents([.medium, .large])
        .task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            focused = true
        }
    }
}

struct SwitchTalkSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let h = store.open, let slot = store.slot(containing: h.talkID) ?? store.suggestion(now: Date())?.slot {
                    ForEach(slot.talks.filter { $0.talkID != h.talkID }) { t in
                        Button {
                            dismiss()
                            store.start(t)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.title).foregroundStyle(.primary)
                                Text([Fmt.speakerLine(t.speakers), t.room ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Text("No other talks in this slot.")
                }
            }
            .navigationTitle("Switch talk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

struct PhotoViewer: View {
    let url: URL
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let img = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: img).resizable().scaledToFit()
                } else {
                    Text("Photo not found").foregroundStyle(.white)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct Thumbnail: View {
    let url: URL
    var size: CGFloat = 52
    @State private var image: UIImage? = nil

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground)
            if let image = image {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: url) {
            image = await Thumbs.load(url)
        }
    }
}

enum Thumbs {
    static let cache = NSCache<NSURL, UIImage>()

    static func load(_ url: URL) async -> UIImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 240,
        ]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let img = UIImage(cgImage: cg)
        cache.setObject(img, forKey: url as NSURL)
        return img
    }
}
