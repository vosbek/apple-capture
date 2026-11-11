import SwiftUI

/// design-spec §3: start the right talk in one tap; reflect on the one that just ended.
struct NowView: View {
    @EnvironmentObject var store: Store
    @State private var askAdhoc = false
    @State private var adhocName = ""

    var body: some View {
        NavigationStack {
            Group {
                if store.schedule == nil {
                    NoScheduleView()
                } else {
                    TimelineView(.everyMinute) { ctx in
                        content(now: ctx.date)
                    }
                }
            }
            .navigationTitle("Now")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("+ Ad hoc") { askAdhoc = true }
                }
            }
            .alert("Ad hoc session", isPresented: $askAdhoc) {
                TextField("Name, for example Lunch table: platform teams", text: $adhocName)
                Button("Start") { store.startAdhoc(name: adhocName); adhocName = "" }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Ad hoc sessions are private.")
            }
        }
    }

    private func content(now: Date) -> some View {
        List {
            Text(Fmt.caption(now))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)

            if let h = store.open {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Capturing: \(h.manifest.talk.title)").font(.headline).lineLimit(1)
                            TimerText(handle: h, compact: true)
                        }
                        Spacer()
                        Button("Return") { store.showCapture = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }

            if let ended = store.justEnded(now: now) {
                let talk = ended.manifest.talk.asTalk
                let c = ended.manifest.counts
                Section("Just ended") {
                    NavigationLink {
                        TalkReviewView(talk: talk)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(talk.title).font(.headline).lineLimit(2)
                            Text("\(Fmt.kindLabel(talk)) · \(c.photo) slides · \(c.moment) moments · \(c.note) notes")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        store.reflectTalk = talk
                    } label: {
                        Label("Reflect", systemImage: "mic")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if let s = store.suggestion(now: now) {
                Section {
                    if let t = s.talk {
                        SuggestionCard(talk: t, reason: s.reason)
                    } else {
                        Text("Nothing suggested for this slot. Pick a talk below.")
                    }
                } header: {
                    Text(slotHeader(s.slot, now: now))
                }
                let others = s.slot.talks.filter { $0.talkID != s.talk?.talkID }
                let main = others.filter { $0.kind != .sponsored }
                let sponsored = others.filter { $0.kind == .sponsored }
                if !others.isEmpty {
                    Section("Also in this slot") {
                        ForEach(main) { t in
                            OtherTalkRow(talk: t)
                        }
                        if !sponsored.isEmpty {
                            DisclosureGroup("\(sponsored.count) sponsored talks · \(rooms(sponsored))") {
                                ForEach(sponsored) { t in
                                    OtherTalkRow(talk: t)
                                }
                            }
                        }
                    }
                }
                if Fmt.dayKey(s.slot.start) != Fmt.dayKey(now) && !store.dayBundles(Fmt.dayKey(now)).isEmpty {
                    Section {
                        Button("Export today") { store.tab = 2 }
                    }
                }
            } else {
                Section {
                    Text("No more sessions in the schedule.")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func rooms(_ talks: [Talk]) -> String {
        Array(Set(talks.compactMap { $0.room })).sorted().joined(separator: ", ")
    }

    private func slotHeader(_ slot: Slot, now: Date) -> String {
        let range = "\(Fmt.slotF.string(from: slot.start))–\(Fmt.slotF.string(from: slot.end))"
        let minutes = Int(slot.start.timeIntervalSince(now) / 60)
        if minutes <= 0 {
            return "Now · \(range) · started \(-minutes) min ago"
        }
        if minutes < 90 {
            return "Next · \(range) · starts in \(minutes) min"
        }
        if Fmt.dayKey(slot.start) == Fmt.dayKey(now) {
            return "Next · \(range)"
        }
        let days = Int(ceil(slot.start.timeIntervalSince(now) / 86400))
        return "Next · \(Fmt.dayShort(slot.start)) \(range) · in \(days) day\(days == 1 ? "" : "s")"
    }
}

struct SuggestionCard: View {
    @EnvironmentObject var store: Store
    let talk: Talk
    let reason: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Fmt.kindLabel(talk)).font(.subheadline).foregroundStyle(.secondary)
            Text(talk.title).font(.title3).bold().lineLimit(2)
            Text(Fmt.speakerLine(talk.speakers)).font(.subheadline)
            if let room = talk.room {
                Text(room).font(.subheadline).foregroundStyle(.secondary)
            }
            if talk.noVideo {
                Text("No official video. Capture more.").font(.footnote).bold()
            }
            if let r = reason {
                Text(r).font(.footnote).foregroundStyle(.secondary)
            }
            Button {
                store.requestStart(talk)
            } label: {
                Text(store.summary(for: talk.talkID) == nil ? "Start capture" : "Resume capture")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 6)
        }
        .padding(.vertical, 4)
    }
}

struct OtherTalkRow: View {
    @EnvironmentObject var store: Store
    let talk: Talk

    var body: some View {
        Button {
            store.requestStart(talk)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(talk.title).font(.body).lineLimit(1).foregroundStyle(.primary)
                Text([Fmt.speakerLine(talk.speakers), talk.room ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(minHeight: 44)
        }
    }
}
