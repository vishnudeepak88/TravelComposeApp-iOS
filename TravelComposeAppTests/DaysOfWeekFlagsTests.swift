import Testing
import Foundation
@testable import TravelComposeApp

// MARK: - DaysOfWeekFlags
//
// Calendar-edge math is the kind of thing that's easy to write once,
// works in your timezone, and quietly breaks in someone else's. Pin
// the day-of-week mapping with a few concrete dates so future refactors
// (e.g. switching to `Calendar.dateComponents` style) can't drift.

@Suite("DaysOfWeekFlags")
struct DaysOfWeekFlagsTests {

    @Test(".weekdays preset matches Mon–Fri")
    func weekdaysPresetMonToFri() {
        let f = DaysOfWeekFlags.weekdays
        #expect(f.monday)
        #expect(f.tuesday)
        #expect(f.wednesday)
        #expect(f.thursday)
        #expect(f.friday)
        #expect(!f.saturday)
        #expect(!f.sunday)
    }

    @Test(".allDays preset enables every day")
    func allDaysPreset() {
        let f = DaysOfWeekFlags.allDays
        #expect(f.monday && f.tuesday && f.wednesday && f.thursday)
        #expect(f.friday && f.saturday && f.sunday)
    }

    @Test("enabled(for:) returns true on weekdays for the .weekdays preset")
    func enabledOnWeekdays() {
        let cal = Calendar(identifier: .gregorian)
        let monday = cal.date(from: DateComponents(year: 2026, month: 5, day: 4))!  // Mon
        let friday = cal.date(from: DateComponents(year: 2026, month: 5, day: 8))!  // Fri
        let f = DaysOfWeekFlags.weekdays
        #expect(f.enabled(for: monday))
        #expect(f.enabled(for: friday))
    }

    @Test("enabled(for:) returns false on weekends for the .weekdays preset")
    func disabledOnWeekends() {
        let cal = Calendar(identifier: .gregorian)
        let saturday = cal.date(from: DateComponents(year: 2026, month: 5, day: 9))!
        let sunday   = cal.date(from: DateComponents(year: 2026, month: 5, day: 10))!
        let f = DaysOfWeekFlags.weekdays
        #expect(!f.enabled(for: saturday))
        #expect(!f.enabled(for: sunday))
    }

    @Test("shortLabel reads naturally for common patterns")
    func shortLabel() {
        #expect(DaysOfWeekFlags.weekdays.shortLabel == "Mon, Tue, Wed, Thu, Fri")
        let weekendOnly = DaysOfWeekFlags(
            monday: false, tuesday: false, wednesday: false, thursday: false,
            friday: false, saturday: true, sunday: true
        )
        #expect(weekendOnly.shortLabel == "Sat, Sun")
        let none = DaysOfWeekFlags(
            monday: false, tuesday: false, wednesday: false, thursday: false,
            friday: false, saturday: false, sunday: false
        )
        #expect(none.shortLabel == "None")
    }
}
