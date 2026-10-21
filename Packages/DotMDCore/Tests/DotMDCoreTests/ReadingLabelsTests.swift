import Foundation
import Testing
@testable import DotMDCore

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar
}()

private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
}

private let now = at(2026, 10, 20, 16, 0)

@Test func sinceUsesTheTimeTodayAndTheDayBefore() {
    #expect(ReadingLabels.since(at(2026, 10, 20, 13, 2), now: now, calendar: calendar) == "since 1:02 PM")
    #expect(ReadingLabels.since(at(2026, 10, 19, 9, 0), now: now, calendar: calendar) == "since yesterday")
    #expect(ReadingLabels.since(at(2026, 10, 18, 9, 0), now: now, calendar: calendar) == "since Oct 18")
    #expect(ReadingLabels.since(at(2025, 12, 24, 9, 0), now: now, calendar: calendar) == "since Dec 24, 2025")
    #expect(ReadingLabels.since(nil, now: now, calendar: calendar) == "since you last read it")
}

@Test func theStoppedReadingLineSaysWhen() {
    #expect(ReadingLabels.stoppedReading(at: at(2026, 10, 20, 13, 2), now: now, calendar: calendar) == "You stopped reading here at 1:02 PM")
    #expect(ReadingLabels.stoppedReading(at: at(2026, 10, 19, 13, 2), now: now, calendar: calendar) == "You stopped reading here yesterday")
    #expect(ReadingLabels.stoppedReading(at: at(2026, 10, 2, 13, 2), now: now, calendar: calendar) == "You stopped reading here on Oct 2")
}

@Test func commentTimesStartAtNow() {
    #expect(ReadingLabels.commentTime(at(2026, 10, 20, 15, 59, 30), now: now, calendar: calendar) == "now")
    #expect(ReadingLabels.commentTime(at(2026, 10, 20, 14, 20), now: now, calendar: calendar) == "2:20 PM")
    #expect(ReadingLabels.commentTime(at(2026, 10, 19, 14, 20), now: now, calendar: calendar) == "yesterday")
    #expect(ReadingLabels.commentTime(at(2026, 10, 2, 14, 20), now: now, calendar: calendar) == "Oct 2")
}
