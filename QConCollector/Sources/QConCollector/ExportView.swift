import SwiftUI
import UIKit

/// Zips a directory with no dependencies: NSFileCoordinator's .forUploading hands back a zip
/// of a directory. The zip contains the directory itself as its top-level folder.
enum Zipper {
    static func zip(directory: URL, name: String) throws -> URL {
        let fm = FileManager.default
        let dest = fm.temporaryDirectory.appendingPathComponent(name)
        try? fm.removeItem(at: dest)
        var coordError: NSError? = nil
        var copyError: Error? = nil
        // REVIEW: fine while the SDK imports this accessor as a plain noescape block. If the compiler says "mutation of captured var 'copyError' in concurrently-executing code", store the error in a small final class box instead.
        NSFileCoordinator().coordinate(readingItemAt: directory, options: [.forUploading], error: &coordError) { zipURL in
            do {
                try fm.copyItem(at: zipURL, to: dest)
            } catch {
                copyError = error
            }
        }
        if let e = coordError { throw e }
        if let e = copyError { throw e }
        return dest
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    let onComplete: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        vc.completionWithItemsHandler = { _, completed, _, _ in onComplete(completed) }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// design-spec §9: get each day off the device every evening; show device health.
struct ExportView: View {
    @EnvironmentObject var store: Store
    @State private var sizes: [String: Int64] = [:]
    @State private var labelDraft = ""

    var body: some View {
        NavigationStack {
            List {
                Text(Fmt.caption(Date())).font(.footnote).foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                let days = store.dayKeys
                let pending = days.filter { store.newCaptures(day: $0) > 0 }
                let done = days.filter { store.newCaptures(day: $0) == 0 }
                if days.isEmpty {
                    Section { Text("Nothing to export yet.") }
                } else if pending.isEmpty {
                    Section { Text("Everything is exported.") }
                } else {
                    Section {
                        ForEach(pending, id: \.self) { day in
                            dayCard(day)
                        }
                    } header: {
                        Text("Only on this \(store.state.deviceLabel == "ipad" ? "iPad" : "phone")")
                    } footer: {
                        Text("Three ways out: OneDrive from the share sheet; Files under On My iPhone › Collector; USB with the Apple Devices app on Windows (detach the device from WSL first).")
                    }
                }
                if !done.isEmpty {
                    Section("Exported") {
                        ForEach(done, id: \.self) { day in
                            HStack {
                                Image(systemName: "checkmark")
                                VStack(alignment: .leading) {
                                    Text(Fmt.dayName(day) + " " + day)
                                    if let r = store.lastExport(day: day), let d = Fmt.parse(r.exportedUTC) {
                                        Text("\(Fmt.dayShort(d)) \(Fmt.clock(d)) · \(Fmt.bytes(Int64(r.bytes)))")
                                            .font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button("Again") { share(day: day) }
                                    .buttonStyle(.borderless)
                                    .disabled(store.zipBusy != nil)
                            }
                        }
                    }
                }
                if !days.isEmpty {
                    Section {
                        Button {
                            store.shareZip(directory: store.sessionsDir, name: "collector_all_\(store.state.deviceLabel).zip",
                                           key: "all", bundleIDs: store.bundles.map { $0.id })
                        } label: {
                            if store.zipBusy == "all" {
                                ProgressView()
                            } else {
                                Text("Share all sessions as .zip")
                            }
                        }
                        .disabled(store.zipBusy != nil)
                    }
                }
                deviceSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Export")
            .onAppear {
                computeSizes()
                labelDraft = store.state.deviceLabel
            }
            .sheet(item: $store.shareItem) { item in
                ShareSheet(url: item.url) { completed in
                    if completed { store.recordExport(item) }
                    store.shareItem = nil
                }
            }
        }
    }

    private func dayCard(_ day: String) -> some View {
        let bundles = store.dayBundles(day)
        let slides = bundles.reduce(0) { $0 + $1.manifest.counts.photo }
        let voices = bundles.reduce(0) { $0 + $1.manifest.counts.voice }
        let size = sizes[day].map { Fmt.bytes($0) } ?? "…"
        let status: String
        if let r = store.lastExport(day: day), let d = Fmt.parse(r.exportedUTC) {
            status = "\(store.newCaptures(day: day)) new captures since \(Fmt.dayShort(d)) \(Fmt.clock(d))"
        } else {
            status = "Not exported yet"
        }
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(Fmt.dayName(day)) \(day)").font(.headline)
            Text("\(bundles.count) sessions · \(slides) slides · \(voices) reflections · \(size)")
                .font(.subheadline).foregroundStyle(.secondary)
            Text(status).font(.subheadline)
            Button {
                share(day: day)
            } label: {
                if store.zipBusy == day {
                    HStack {
                        ProgressView()
                        Text("Preparing \(size)…")
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    Text("Share \(Fmt.dayName(day)) as .zip").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.zipBusy != nil)
        }
        .padding(.vertical, 4)
    }

    private func share(day: String) {
        store.shareZip(directory: store.sessionsDir.appendingPathComponent(day),
                       name: "collector_\(day)_\(store.state.deviceLabel).zip",
                       key: day, bundleIDs: store.dayBundles(day).map { $0.id })
    }

    private func computeSizes() {
        var out: [String: Int64] = [:]
        for day in store.dayKeys {
            out[day] = Store.folderSize(store.sessionsDir.appendingPathComponent(day))
        }
        sizes = out
    }

    private var deviceSection: some View {
        Section("This device") {
            if let e = store.expiry {
                let hours = Int(e.timeIntervalSinceNow / 3600)
                VStack(alignment: .leading, spacing: 2) {
                    LabeledContent("App expires", value: "\(Fmt.dayShort(e)) \(Fmt.clock(e)) · \(hours / 24) d \(hours % 24) h left")
                        .fontWeight(store.expirySoon ? .bold : .regular)
                    if store.expirySoon {
                        Text("Export today").font(.footnote.bold())
                    }
                }
            } else {
                LabeledContent("App expires", value: "unknown (installed \(store.installDate.map { Fmt.dayShort($0) + " " + Fmt.clock($0) } ?? "?"))")
            }
            LabeledContent("Free space", value: store.freeSpace.map { Fmt.bytes($0) } ?? "unknown")
            HStack {
                Text("Device label")
                Spacer()
                TextField("iphone", text: $labelDraft)
                    .onSubmit {
                        let clean = labelDraft.lowercased().filter { $0.isLetter || $0.isNumber }
                        if !clean.isEmpty {
                            store.state.deviceLabel = clean
                            store.saveState()
                        }
                        labelDraft = store.state.deviceLabel
                    }
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Toggle("Dim capture screen", isOn: Binding(
                get: { store.state.settings.dimCapture },
                set: { store.state.settings.dimCapture = $0; store.saveState() }))
            Toggle("Use system camera for slides", isOn: Binding(
                get: { store.state.settings.useSystemCamera },
                set: { store.state.settings.useSystemCamera = $0; store.saveState() }))
            // "Offer session audio" is absent because session audio is not built (SessionAudio.swift).
            LabeledContent("Schedule", value: store.scheduleSource)
            if let err = store.scheduleError {
                Text(err).font(.footnote).foregroundStyle(.secondary)
            }
            LabeledContent("Version", value: Fmt.appVersion())
        }
    }
}
