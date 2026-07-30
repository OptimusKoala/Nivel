import XCTest
@testable import NivelCore

final class DailySessionPickerTests: XCTestCase {
    /// Calendrier identique à GameService.calendar (ISO, lundi premier jour).
    private var calendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    func testIndexIsPinnedToReferenceDate() {
        // 01/01/2026 = jour 0 → index 0 ; 8 jours plus tard (count 8) → 0 à nouveau.
        XCTAssertEqual(DailySessionPicker.index(for: date(2026, 1, 1), count: 8, calendar: calendar), 0)
        XCTAssertEqual(DailySessionPicker.index(for: date(2026, 1, 9), count: 8, calendar: calendar), 0)
        // 30/07/2026 = 210 jours après la référence → 210 % 8 = 2.
        XCTAssertEqual(DailySessionPicker.index(for: date(2026, 7, 30), count: 8, calendar: calendar), 2)
    }

    func testConsecutiveDaysRotate() {
        let today = DailySessionPicker.index(for: date(2026, 7, 30), count: 8, calendar: calendar)
        let tomorrow = DailySessionPicker.index(for: date(2026, 7, 31), count: 8, calendar: calendar)
        XCTAssertEqual(tomorrow, (today + 1) % 8)
    }

    func testSameDayDifferentHoursSameIndex() {
        XCTAssertEqual(
            DailySessionPicker.index(for: date(2026, 7, 30, hour: 0), count: 8, calendar: calendar),
            DailySessionPicker.index(for: date(2026, 7, 30, hour: 23), count: 8, calendar: calendar)
        )
    }

    func testDatesBeforeReferenceStayInRange() {
        let index = DailySessionPicker.index(for: date(2025, 12, 31), count: 8, calendar: calendar)
        XCTAssertEqual(index, 7) // jour -1 → modulo positif
    }

    func testSessionForDate() throws {
        let sessions = try Catalogs.sessions()
        let session = DailySessionPicker.session(for: date(2026, 1, 1), sessions: sessions, calendar: calendar)
        XCTAssertEqual(session?.id, sessions[0].id)
        XCTAssertNil(DailySessionPicker.session(for: .now, sessions: [], calendar: calendar))
    }
}
