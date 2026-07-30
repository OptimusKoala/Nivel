import XCTest
@testable import NivelCore

final class DailySessionPickerTests: XCTestCase {
    /// Calendrier hermétique (indépendant du réglage Région du host) — le picker
    /// n'utilise que les unités de jour, pas les semaines.
    private var calendar: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
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
        XCTAssertEqual(
            DailySessionPicker.index(for: date(2025, 12, 31, hour: 23), count: 8, calendar: calendar),
            7
        )
    }

    func testRotationStaysContiguousAcrossDSTTransitions() {
        // Passages à l'heure d'été (29/03/2026) et d'hiver (25/10/2026) en Europe/Paris.
        for (y, m, dRange) in [(2026, 3, 28...30), (2026, 10, 24...26)] {
            var previous: Int?
            for d in dRange {
                let index = DailySessionPicker.index(for: date(y, m, d), count: 8, calendar: calendar)
                if let previous { XCTAssertEqual(index, (previous + 1) % 8, "\(d)/\(m)") }
                previous = index
            }
        }
    }

    func testIndexWithNonPositiveCountReturnsZero() {
        XCTAssertEqual(DailySessionPicker.index(for: date(2026, 1, 1), count: 0, calendar: calendar), 0)
    }

    func testSessionForDate() throws {
        let sessions = try Catalogs.sessions()
        let session = DailySessionPicker.session(for: date(2026, 1, 1), sessions: sessions, calendar: calendar)
        XCTAssertEqual(session?.id, sessions[0].id)
        XCTAssertNil(DailySessionPicker.session(for: .now, sessions: [], calendar: calendar))
    }
}
