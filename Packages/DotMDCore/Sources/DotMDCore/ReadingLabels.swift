import Foundation

/// The words the reader uses for when something was read: the chip's "since 1:02 PM" and the dotted line's
/// "You stopped reading here at 1:02 PM". dotPen's copy is English, so the formats are fixed to en_US.
public enum ReadingLabels {
    /// "since 1:02 PM" today, "since yesterday", "since Oct 18" this year, "since Oct 18, 2025" before that.
    public static func since(_ date: Date?, now: Date = .now, calendar: Calendar = .current) -> String {
        guard let date else { return "since you last read it" }
        if calendar.isDate(date, inSameDayAs: now) { return "since " + format(date, "h:mm a", calendar) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "since yesterday"
        }
        return "since " + day(date, now: now, calendar: calendar)
    }

    /// "You stopped reading here at 1:02 PM" today, "yesterday", or "on Oct 18".
    public static func stoppedReading(at date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "You stopped reading here at " + format(date, "h:mm a", calendar) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "You stopped reading here yesterday"
        }
        return "You stopped reading here on " + day(date, now: now, calendar: calendar)
    }

    /// When a comment was written or sent: "now" in its first minute, "2:20 PM" today, "yesterday", or "Oct 18".
    public static func commentTime(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if abs(now.timeIntervalSince(date)) < 60 { return "now" }
        if calendar.isDate(date, inSameDayAs: now) { return format(date, "h:mm a", calendar) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "yesterday"
        }
        return day(date, now: now, calendar: calendar)
    }

    private static func day(_ date: Date, now: Date, calendar: Calendar) -> String {
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return format(date, sameYear ? "MMM d" : "MMM d, yyyy", calendar)
    }

    private static func format(_ date: Date, _ pattern: String, _ calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
