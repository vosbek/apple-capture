import AVFoundation
import SwiftUI
import UIKit

/// Voice reflection recorder: AVAudioRecorder, AAC mono, foreground only (design-spec §7).
final class ReflectionRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var elapsed: TimeInterval = 0
    @Published var level: Double = 0
    @Published var autoStopped = false        // set on interruption or at the 5-minute limit

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private(set) var startedAt = Date()
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("reflection.m4a")

    static let softLimit: TimeInterval = 180
    static let hardLimit: TimeInterval = 300

    var permissionDenied: Bool { AVAudioSession.sharedInstance().recordPermission == .denied }

    func requestPermission(_ done: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { ok in
            DispatchQueue.main.async { done(ok) }
        }
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
        try? FileManager.default.removeItem(at: tempURL)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let r = try AVAudioRecorder(url: tempURL, settings: settings)
        r.delegate = self
        r.isMeteringEnabled = true
        guard r.record() else { throw CocoaError(.fileWriteUnknown) }
        recorder = r
        startedAt = Date()
        elapsed = 0
        autoStopped = false
        isRecording = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if raw == AVAudioSession.InterruptionType.began.rawValue {
                self?.autoStop()
            }
        }
    }

    private func tick() {
        guard let r = recorder, isRecording else { return }
        r.updateMeters()
        let db = Double(r.averagePower(forChannel: 0))     // -160...0
        level = max(0, min(1, (db + 50) / 50))
        elapsed = r.currentTime
        if elapsed >= ReflectionRecorder.hardLimit { autoStop() }
    }

    private func autoStop() {
        guard isRecording else { return }
        autoStopped = true
    }

    /// Stops and returns the duration in ms, or nil if nothing was recording.
    func stop() -> Int? {
        guard let r = recorder, isRecording else { return nil }
        let duration = r.currentTime
        r.stop()
        cleanup()
        return Int(duration * 1000)
    }

    func discard() {
        recorder?.stop()
        cleanup()
        try? FileManager.default.removeItem(at: tempURL)
    }

    private func cleanup() {
        timer?.invalidate()
        timer = nil
        if let o = observer { NotificationCenter.default.removeObserver(o) }
        observer = nil
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

struct ReflectSheet: View {
    let talk: Talk
    @EnvironmentObject var store: Store
    @StateObject private var rec = ReflectionRecorder()
    @Environment(\.dismiss) private var dismiss
    @State private var denied = false
    @State private var typed = ""
    @State private var message: String? = nil
    @State private var pendingDur: Int? = nil    // stopped but not yet saved (retry keeps it)

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What was the claim?")
                    Text("What would we do with it?")
                    Text("Who should hear it?")
                }
                .font(.body)
                .foregroundStyle(.secondary)

                if denied {
                    Text("Microphone access is off").font(.headline)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    TextField("Type the reflection instead", text: $typed, axis: .vertical)
                        .lineLimit(3...8)
                        .textFieldStyle(.roundedBorder)
                } else {
                    HStack(spacing: 16) {
                        Button {
                            toggle()
                        } label: {
                            Image(systemName: rec.isRecording ? "stop.fill" : "mic.fill")
                                .font(.title)
                                .foregroundStyle(Color.white)
                                .frame(width: 72, height: 72)
                                .background(Circle().fill(rec.isRecording ? Color.black : Theme.tint))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(rec.isRecording ? "Stop recording" : "Record reflection")
                        VStack(alignment: .leading, spacing: 6) {
                            Text(Fmt.offset(ms: Int(rec.elapsed * 1000)).replacingOccurrences(of: "+", with: ""))
                                .font(.title2.monospacedDigit())
                            if rec.elapsed >= ReflectionRecorder.softLimit {
                                Text("Wrap up").font(.headline)
                            }
                            ProgressView(value: rec.level)
                        }
                    }
                }
                if let m = message {
                    Text(m).font(.footnote.bold())
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Reflect: \(talk.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") {
                        rec.discard()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(rec.isRecording)
        .onAppear { denied = rec.permissionDenied }
        .onChange(of: rec.autoStopped) { _, stopped in
            if stopped { save() }
        }
    }

    private func toggle() {
        if rec.isRecording {
            save()
            return
        }
        rec.requestPermission { ok in
            if !ok {
                denied = true
                return
            }
            do {
                try rec.start()
                message = nil
            } catch {
                message = "Could not start recording: \(error.localizedDescription)"
            }
        }
    }

    /// Saves the recording as a `voice` event (or the typed text as a `note`) and closes.
    private func save() {
        if denied {
            let t = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, let h = store.ensureHandle(for: talk) {
                store.addNote(t, openedAt: Date(), to: h)
            }
            dismiss()
            return
        }
        let started = rec.startedAt
        if let d = rec.stop() { pendingDur = d }
        guard let durMs = pendingDur else {
            dismiss()
            return
        }
        if store.saveReflection(talk: talk, temp: rec.tempURL, startedAt: started, durMs: durMs) {
            pendingDur = nil
            Haptics.saved()
            dismiss()
        } else {
            message = "Could not save the reflection. Free up space and try Save again."
        }
    }
}
