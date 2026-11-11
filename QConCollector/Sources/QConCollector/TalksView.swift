import SwiftUI

/// design-spec §5: browse the schedule, star the plan, open any talk.
struct TalksView: View {
    @EnvironmentObject var store: Store
    @State private var day = ""
    @State private var query = ""

    private var days: [String] {
        Array(Set((store.schedule?.talks ?? []).map { Fmt.dayKey($0.startDate) })).sorted()
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.schedule == nil {
                    NoScheduleView()
                } else {
                    list
                }
            }
            .navigationTitle("Talks")
        }
        .onAppear {
            if day.isEmpty {
                let today = Fmt.dayKey(Date())
                day = days.contains(today) ? today : (days.first ?? "")
            }
        }
    }

    private var list: some View {
        List {
            if query.isEmpty {
                Picker("Day", selection: $day) {
                    ForEach(days, id: \.self) { d in
                        Text(Fmt.dayName(d)).tag(d)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                ForEach(store.slots.filter { Fmt.dayKey($0.start) == day }) { slot in
                    Section("\(Fmt.slotF.string(from: slot.start))–\(Fmt.slotF.string(from: slot.end))") {
                        ForEach(slot.talks) { t in
                            TalkRow(talk: t)
                        }
                    }
                }
                let adhoc = store.dayBundles(day).filter { $0.manifest.talk.kind == .adhoc }
                if !adhoc.isEmpty {
                    Section("Ad hoc") {
                        ForEach(adhoc) { b in
                            TalkRow(talk: b.manifest.talk.asTalk)
                        }
                    }
                }
            } else {
                Section("Results") {
                    ForEach(matches) { t in
                        TalkRow(talk: t)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, prompt: "Title, speaker or track")
    }

    private var matches: [Talk] {
        (store.schedule?.talks ?? []).filter { t in
            t.title.localizedCaseInsensitiveContains(query)
                || (t.track ?? "").localizedCaseInsensitiveContains(query)
                || t.speakers.contains { $0.name.localizedCaseInsensitiveContains(query) }
        }
        .sorted { $0.startDate < $1.startDate }
    }
}

struct TalkRow: View {
    @EnvironmentObject var store: Store
    let talk: Talk

    var body: some View {
        NavigationLink {
            TalkReviewView(talk: talk)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(talk.title).font(.body).lineLimit(2)
                    Text(Fmt.speakerLine(talk.speakers)).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    Text([Fmt.kindLabel(talk), talk.room ?? "", talk.noVideo ? "No official video" : ""]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    if let s = store.summary(for: talk.talkID) {
                        CountsLine(counts: s.manifest.counts)
                    }
                }
                Spacer(minLength: 4)
                if talk.kind != .adhoc {
                    Button {
                        store.toggleStar(talk.talkID)
                    } label: {
                        Image(systemName: store.isStarred(talk.talkID) ? "star.fill" : "star")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(store.isStarred(talk.talkID) ? "Remove from plan" : "Add to plan")
                }
            }
        }
        .swipeActions(edge: .leading) {
            Button("Capture") { store.requestStart(talk) }
                .tint(Theme.tint)
        }
    }
}
