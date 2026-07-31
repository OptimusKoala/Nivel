import XCTest
@testable import NivelCore

final class WidgetTimelinePlannerTests: XCTestCase {
    private let calendar = Calendar.current
    private var bank: MessageBank!

    override func setUpWithError() throws {
        bank = try MessageBank.load()
    }

    /// 31 juillet 2026 à `hour` heures, heure locale.
    private func date(hour: Int, minute: Int = 0, day: Int = 31) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: day,
                                           hour: hour, minute: minute))!
    }

    private func snapshot(dayKey: Date? = nil, kcal: Int = 850) -> WidgetSnapshot {
        WidgetSnapshot(dayKey: dayKey ?? calendar.startOfDay(for: date(hour: 0)),
                       kcalEaten: kcal, kcalTarget: 1800, totalXP: 300,
                       userName: "Michaël", themeID: "creme",
                       generatedAt: date(hour: 9))
    }

    // MARK: - Bornes

    func testEntriesFromMorningCoverAllRemainingBoundaries() {
        let from = date(hour: 9)
        let entries = WidgetTimelinePlanner.entries(snapshot: snapshot(), from: from,
                                                    bank: bank, calendar: calendar)
        // from, 12 h, 18 h, 22 h, minuit, 7 h du lendemain.
        XCTAssertEqual(entries.map(\.date),
                       [from, date(hour: 12), date(hour: 18), date(hour: 22),
                        calendar.startOfDay(for: date(hour: 0, day: 32)),
                        date(hour: 7, day: 32)])
    }

    func testEntriesLateEveningSkipPastBoundaries() {
        let from = date(hour: 23)
        let entries = WidgetTimelinePlanner.entries(snapshot: snapshot(), from: from,
                                                    bank: bank, calendar: calendar)
        XCTAssertEqual(entries.map(\.date),
                       [from,
                        calendar.startOfDay(for: date(hour: 0, day: 32)),
                        date(hour: 7, day: 32)])
    }

    func testPreDawnGetsSameDaySevenAMBoundary() {
        let from = date(hour: 2)
        let entries = WidgetTimelinePlanner.entries(snapshot: snapshot(), from: from,
                                                    bank: bank, calendar: calendar)
        XCTAssertTrue(entries.map(\.date).contains(date(hour: 7)),
                      "avant l'aube, une borne 7 h le jour même réveille Nivelito")
    }

    // MARK: - Bascule de minuit

    func testMidnightRolloverResetsKcalKeepsXP() {
        let entries = WidgetTimelinePlanner.entries(snapshot: snapshot(), from: date(hour: 21),
                                                    bank: bank, calendar: calendar)
        let beforeMidnight = entries.first { $0.date == date(hour: 22) }!
        let afterMidnight = entries.first {
            $0.date == calendar.startOfDay(for: date(hour: 0, day: 32))
        }!
        XCTAssertEqual(beforeMidnight.kcalEaten, 850)
        XCTAssertEqual(afterMidnight.kcalEaten, 0)
        XCTAssertEqual(afterMidnight.kcalTarget, 1800)
        XCTAssertEqual(afterMidnight.totalXP, 300)
    }

    func testStaleSnapshotFromYesterdayShowsZeroKcalToday() {
        // Snapshot d'hier (30 juillet), timeline générée aujourd'hui 9 h.
        let stale = snapshot(dayKey: calendar.startOfDay(for: date(hour: 0, day: 30)))
        let entries = WidgetTimelinePlanner.entries(snapshot: stale, from: date(hour: 9),
                                                    bank: bank, calendar: calendar)
        XCTAssertEqual(entries.first!.kcalEaten, 0)
        XCTAssertEqual(entries.first!.totalXP, 300)
    }

    // MARK: - Expression

    func testExpressionBoundaries() {
        XCTAssertEqual(WidgetTimelinePlanner.expression(hour: 21), .happy)
        XCTAssertEqual(WidgetTimelinePlanner.expression(hour: 22), .sleepy)
        XCTAssertEqual(WidgetTimelinePlanner.expression(hour: 0), .sleepy)
        XCTAssertEqual(WidgetTimelinePlanner.expression(hour: 6), .sleepy)
        XCTAssertEqual(WidgetTimelinePlanner.expression(hour: 7), .happy)
    }

    func testEntryAtTenPMIsSleepy() {
        let entries = WidgetTimelinePlanner.entries(snapshot: snapshot(), from: date(hour: 21),
                                                    bank: bank, calendar: calendar)
        XCTAssertEqual(entries.first { $0.date == date(hour: 22) }?.expression, .sleepy)
        XCTAssertEqual(entries.first { $0.date == date(hour: 7, day: 32) }?.expression, .happy)
    }
}
