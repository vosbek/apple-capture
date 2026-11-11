import Foundation
import SwiftUI

/// Date, time and naming helpers. All stored timestamps are UTC; display and folder names
/// use conference-local time (America/Los_Angeles).
enum Fmt {
    static let confTZName = "America/Los_Angeles"
    static let confTZ: TimeZone = TimeZone(identifier: "America/Los_Angeles") ?? TimeZone(secondsFromGMT: -8 * 3600)!

    static let isoMs: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    /// "2026-11-16T17:07:12.380Z"
    static func utc(_ d: Date) -> String { isoMs.string(from: d) }
    /// "2026-11-16T17:00:00Z"
    static func utcPlain(_ d: Date) -> String { isoPlain.string(from: d) }

    static func parse(_ s: String?) -> Date? {
        guard let s = s else { return nil }
        return isoMs.date(from: s) ?? isoPlain.date(from: s)
    }

    private static func formatter(_ format: String, _ tz: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz
        f.dateFormat = format
        return f
    }

    static let dayKeyF = formatter("yyyy-MM-dd", confTZ)
    static let hhmmF = formatter("HHmm", confTZ)
    static let clockF = formatter("h:mm a", confTZ)
    static let slotF = formatter("H:mm", confTZ)
    static let dayShortF = formatter("EEE", confTZ)
    static let captionF = formatter("EEE MMM d · h:mm a", confTZ)
    static let adhocF = formatter("yyyyMMdd-HHmm", confTZ)
    static let utcTimeF = formatter("HHmmss", TimeZone(secondsFromGMT: 0)!)

    static func dayKey(_ d: Date) -> String { dayKeyF.string(from: d) }
    static func clock(_ d: Date) -> String { clockF.string(from: d) }
    static func dayShort(_ d: Date) -> String { dayShortF.string(from: d) }
    static func caption(_ d: Date) -> String { captionF.string(from: d).uppercased() }

    /// Day name for a "yyyy-MM-dd" key, e.g. "Mon".
    static func dayName(_ key: String) -> String {
        guard let d = dayKeyF.date(from: key) else { return key }
        return dayShort(d.addingTimeInterval(12 * 3600))
    }

    /// "+22:58", "-4:10", "+72:05"
    static func offset(ms: Int) -> String {
        let sign = ms < 0 ? "-" : "+"
        let s = abs(ms) / 1000
        return String(format: "%@%ld:%02ld", sign, s / 60, s % 60)
    }

    static func ms(_ interval: TimeInterval) -> Int { Int((interval * 1000).rounded()) }

    static func seq4(_ n: Int) -> String { String(format: "%04ld", n) }

    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    /// Monotonic clock that keeps counting while the device sleeps (Darwin CLOCK_MONOTONIC).
    static func monoNow() -> UInt64 { clock_gettime_nsec_np(CLOCK_MONOTONIC) }

    static func deviceModel() -> String {
        var sys = utsname()
        uname(&sys)
        let machine = withUnsafePointer(to: &sys.machine) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        return machine
    }

    static func appVersion() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    static func speakerLine(_ speakers: [Speaker]) -> String {
        if speakers.isEmpty { return "Speaker to be announced" }
        return speakers.map { s in
            if let c = s.company, !c.isEmpty { return "\(s.name), \(c)" }
            return s.name
        }.joined(separator: "; ")
    }

    static func kindLabel(_ talk: Talk) -> String {
        if let t = talk.track, !t.isEmpty { return t }
        switch talk.kind {
        case .keynote: return "Keynote"
        case .presentation: return "Talk"
        case .unconference: return "Unconference"
        case .sponsored: return "Sponsored"
        case .training: return "Training"
        case .social: return "Social"
        case .adhoc: return "Ad hoc"
        }
    }
}

enum Theme {
    static let tint = Color(red: 0x18 / 255.0, green: 0x57 / 255.0, blue: 0xB8 / 255.0)
    static let tintDim = Color(red: 0x8A / 255.0, green: 0xB4 / 255.0, blue: 0xF8 / 255.0)
}
