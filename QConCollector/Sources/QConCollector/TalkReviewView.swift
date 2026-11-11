import AVFoundation
import SwiftUI
import UIKit

final class ReflectionPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var playing: URL? = nil
    private var player: AVAudioPlayer?

    func toggle(_ url: URL) {
        if playing == url {
            stop()
            return
        }
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.delegate = self
        p.play()
        player = p
        playing = url
    }

    func stop() {
        player?.stop()
        player = nil
        playing = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { self.stop() }
    }
}

/// design-spec §6: what this device captured for one talk; fix it; add a reflection.
struct TalkReviewView: View {
    let talk: Talk
    @EnvironmentObject var store: Store
    @StateObject private var player = ReflectionPlayer()
    @State private var viewing: Event? = nil
    @State private var editing: Event? = nil
    @State private var editText = ""
    @State private var tagging: Event? = nil
    @State private var confirmPublic = false

    var body: some View {
        let h = store.handle(for: talk.talkID)
        let items = h?.items() ?? []
        List {
            header(h)
            facts(h)
            if let h = h, !items.isEmpty {
                Section("On this \(store.state.deviceLabel == "ipad" ? "iPad" : "iPhone")") {
                    ForEach(items) { item in
                        row(item, h)
                            .swipeActions {
                                Button("Delete", role: .destructive) { store.deleteEvent(item.id, in: h) }
                            }
                    }
                }
            } else {
                Section {
                    Text("Nothing captured for this talk").foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(talk.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let s = talk.url, let url = URL(string: s) {
                ToolbarItem(placement: .topBarTrailing) { Link("Talk page", destination: url) }
            }
            if let h = h {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.shareZip(directory: h.url, name: "collector_\(h.manifest.bundleID).zip",
                                       key: h.manifest.bundleID, bundleIDs: [h.manifest.bundleID])
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share this talk as .zip")
                    .disabled(store.zipBusy != nil)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button {
                    store.requestStart(talk)
                } label: {
                    Text(h == nil ? "Start capture" : "Resume capture").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                Button {
                    store.reflectTalk = talk
                } label: {
                    Text("Add reflection").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.bar)
        }
        .sheet(item: $viewing) { e in
            if let h = h, let url = h.fileURL(e.file) {
                PhotoViewer(url: url) { store.deleteEvent(e.id, in: h) }
            }
        }
        .sheet(item: $editing) { e in
            NoteSheet(title: "Edit note", text: $editText,
                      onSave: {
                          if let h = h { store.editNote(e.id, text: editText, in: h) }
                          editing = nil
                      },
                      onCancel: { editing = nil })
        }
        .confirmationDialog("Tag this moment", isPresented: Binding(
            get: { tagging != nil }, set: { if !$0 { tagging = nil } }), titleVisibility: .visible) {
            ForEach(TagOption.all) { opt in
                Button(opt.label) {
                    if let h = h, let e = tagging { store.tag(e.id, opt.key, in: h) }
                }
            }
            Button("No tag") {
                if let h = h, let e = tagging { store.tag(e.id, nil, in: h) }
            }
        }
        .confirmationDialog("Make this session shareable?", isPresented: $confirmPublic, titleVisibility: .visible) {
            Button("Make shareable") {
                if let h = h { store.setVisibility("shareable", in: h) }
            }
        } message: {
            Text("Unconference, social and ad hoc sessions are private by default under the Code of Conduct. The publish gate still requires your review.")
        }
    }

    private func header(_ h: BundleHandle?) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(talk.title).font(.title3.bold())
                Text(Fmt.speakerLine(talk.speakers)).font(.subheadline)
                Text([Fmt.kindLabel(talk), Fmt.dayShort(talk.startDate), Fmt.clock(talk.startDate), talk.room ?? ""]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary)
                if let h = h {
                    let c = h.manifest.counts
                    let basis = h.speakerStart.map { "Speaker started \(Fmt.clock($0)) (synced)" } ?? "Scheduled start (not synced)"
                    Text("\(basis) · \(c.photo) slides · \(c.moment) moments · \(c.note) notes")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if store.open?.talkID == talk.talkID {
                    Button("Capturing now · Return") { store.showCapture = true }
                        .padding(.top, 4)
                }
            }
        }
    }

    private func facts(_ h: BundleHandle?) -> some View {
        Section {
            LabeledContent("Session audio", value: "Off, no permission")
            LabeledContent("Official video", value: talk.noVideo ? "No official video" : "Expected Dec 21")
            if let h = h {
                Toggle("Keep private", isOn: Binding(
                    get: { h.isPrivate },
                    set: { newValue in
                        if newValue {
                            store.setVisibility("private", in: h)
                        } else if talk.privateByDefault || talk.kind == .adhoc || talk.kind == .social {
                            confirmPublic = true
                        } else {
                            store.setVisibility("shareable", in: h)
                        }
                    }))
            }
        }
    }

    @ViewBuilder
    private func row(_ item: BundleHandle.Item, _ h: BundleHandle) -> some View {
        let e = item.event
        let rel = h.talkMs(e)
        let offset = e.type == "voice" ? (e.phase == "before" ? "Before" : "After") : (rel < 0 ? "Before" : Fmt.offset(ms: rel))
        HStack(alignment: .top, spacing: 10) {
            Text(offset)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            switch e.type {
            case "photo":
                if let url = h.fileURL(e.file) {
                    Button { viewing = e } label: { Thumbnail(url: url, size: 64) }
                        .buttonStyle(.borderless)
                }
                Spacer()
            case "moment":
                Button {
                    tagging = e
                } label: {
                    Text("Moment" + (TagOption.label(item.tag).map { " · \($0)" } ?? ""))
                }
                .buttonStyle(.borderless)
                Spacer()
            case "note":
                Button {
                    editText = item.text ?? ""
                    editing = e
                } label: {
                    Text(item.text ?? "").foregroundStyle(.primary).multilineTextAlignment(.leading)
                }
                .buttonStyle(.borderless)
                Spacer()
            case "voice":
                let secs = (e.durMs ?? 0) / 1000
                Text("Reflection \(secs / 60):\(String(format: "%02ld", secs % 60)) · \(Fmt.clock(e.date))")
                Spacer()
                if let url = h.fileURL(e.file) {
                    Button {
                        player.toggle(url)
                    } label: {
                        Image(systemName: player.playing == url ? "stop.circle" : "play.circle").font(.title2)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(player.playing == url ? "Stop reflection" : "Play reflection")
                }
            default:
                Text("Speaker started").foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}
