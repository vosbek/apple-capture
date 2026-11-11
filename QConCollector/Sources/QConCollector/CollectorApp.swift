import SwiftUI
import UIKit

@main
struct CollectorApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        TabView(selection: $store.tab) {
            NowView()
                .tabItem { Label("Now", systemImage: "clock") }
                .tag(0)
            TalksView()
                .tabItem { Label("Talks", systemImage: "list.bullet") }
                .tag(1)
            ExportView()
                .tabItem { Label("Export", systemImage: "square.and.arrow.up") }
                .badge(store.expirySoon ? 1 : 0)
                .tag(2)
        }
        .tint(Theme.tint)
        .fullScreenCover(isPresented: $store.showCapture) {
            CaptureView().environmentObject(store)
        }
        .sheet(item: $store.reflectTalk) { talk in
            ReflectSheet(talk: talk).environmentObject(store)
        }
        .confirmationDialog(
            Text("End \(store.open?.manifest.talk.title ?? "this session") and start this one?"),
            isPresented: Binding(get: { store.pendingStart != nil },
                                 set: { if !$0 { store.pendingStart = nil } }),
            titleVisibility: .visible,
            presenting: store.pendingStart
        ) { talk in
            Button("End and start \(talk.title)") { store.start(talk) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Export", isPresented: Binding(get: { store.alertMessage != nil },
                                              set: { if !$0 { store.alertMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.alertMessage ?? "")
        }
    }
}

/// Shown when no schedule could be loaded. The app stays usable through ad hoc sessions.
struct NoScheduleView: View {
    @EnvironmentObject var store: Store
    @State private var askName = false
    @State private var name = ""

    var body: some View {
        ContentUnavailableView {
            Label("No schedule loaded", systemImage: "calendar.badge.exclamationmark")
        } description: {
            Text(store.scheduleError ?? "")
        } actions: {
            Button("Start ad hoc session") { askName = true }
                .buttonStyle(.borderedProminent)
        }
        .alert("Ad hoc session", isPresented: $askName) {
            TextField("Name, for example Lunch table: platform teams", text: $name)
            Button("Start") { store.startAdhoc(name: name); name = "" }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// Small shared pieces.
struct CountsLine: View {
    let counts: Counts
    var body: some View {
        Text("\(counts.photo) · \(counts.moment) · \(counts.note)")
            .font(.footnote.monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityLabel("\(counts.photo) slides, \(counts.moment) moments, \(counts.note) notes")
    }
}

@MainActor
enum Haptics {
    static func slide() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func saved() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func moment() {
        let g = UIImpactFeedbackGenerator(style: .rigid)
        g.impactOccurred()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            g.impactOccurred()
        }
    }
}
