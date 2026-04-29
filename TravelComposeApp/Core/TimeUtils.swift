import Foundation

// MARK: - Centralized time parsing.
//
// Closes Engineering hygiene gap #8 from the playbook: parseTime/parseMinutes
// were defined twice (AppStore.swift + CommuteMatchingEngine inside it). Both
// now delegate to TimeUtils so the rules drift in one place.

enum TimeUtils {

    /// Parse "HH:mm" → (hour, minute). Returns nil if malformed or out of range.
    static func parseTime(_ text: String) -> (hour: Int, minute: Int)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return (h, m)
    }

    /// Parse "HH:mm" → minutes-since-midnight. Returns nil if malformed.
    static func parseMinutes(_ text: String) -> Int? {
        guard let (h, m) = parseTime(text) else { return nil }
        return h * 60 + m
    }

    /// Format minutes-since-midnight back to "HH:mm".
    static func formatMinutes(_ minutes: Int) -> String {
        let clamped = max(0, min(23 * 60 + 59, minutes))
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    /// `yyyy-MM-dd` formatter used for backend ISO-day query params.
    static let isoDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
