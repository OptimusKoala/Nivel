import XCTest
@testable import NivelCore

final class WidgetTimelinePlannerTests: XCTestCase {
    /// Calendrier PINNÉ (iso8601 + Europe/Paris) — indépendant du réglage
    /// Région du host, comme DailySessionPickerTests.
    private var calendar: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }
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

    // MARK: - Hermétisme (fuseau, DST, cohérence des bornes)

    /// Les bornes restent strictement croissantes et uniques les jours de changement
    /// d'heure (29/03 et 25/10/2026, Europe/Paris) — WidgetKit exige des dates ordonnées.
    func testTimelineStaysOrderedAcrossDSTTransitions() {
        for (m, d) in [(3, 28), (3, 29), (10, 25)] {
            for hour in [1, 9, 23] {
                let from = calendar.date(from: DateComponents(year: 2026, month: m, day: d,
                                                              hour: hour, minute: 30))!
                let dates = WidgetTimelinePlanner.entries(
                    snapshot: snapshot(dayKey: calendar.startOfDay(for: from)),
                    from: from, bank: bank, calendar: calendar
                ).map(\.date)
                XCTAssertEqual(dates, dates.sorted(), "\(d)/\(m) \(hour)h")
                XCTAssertEqual(Set(dates).count, dates.count, "\(d)/\(m) \(hour)h")
                XCTAssertTrue(dates.allSatisfy { $0 >= from })
            }
        }
    }

    /// Le réglage Région > Calendrier du device ne déplace ni les bornes ni la
    /// rotation (même leçon que DailySessionPicker).
    func testEntriesAreIndependentOfDeviceCalendarIdentifier() {
        let from = date(hour: 9)
        let reference = WidgetTimelinePlanner.entries(snapshot: snapshot(), from: from,
                                                      bank: bank, calendar: calendar)
        for id in [Calendar.Identifier.buddhist, .japanese, .hebrew] {
            var device = Calendar(identifier: id)
            device.timeZone = calendar.timeZone
            XCTAssertEqual(WidgetTimelinePlanner.entries(snapshot: snapshot(), from: from,
                                                         bank: bank, calendar: device),
                           reference, "\(id)")
        }
    }

    /// Toute heure où le créneau OU l'expression change doit être une borne, et
    /// réciproquement — sinon un changement d'apparence passe inaperçu (pas d'entrée).
    func testBoundaryHoursMatchEveryChangeOfSlotOrExpression() {
        for hour in 1..<24 {
            let changes = WidgetTimelinePlanner.slot(hour: hour) != WidgetTimelinePlanner.slot(hour: hour - 1)
                || WidgetTimelinePlanner.expression(hour: hour) != WidgetTimelinePlanner.expression(hour: hour - 1)
            XCTAssertEqual(changes, WidgetTimelinePlanner.boundaryHours.contains(hour), "\(hour) h")
        }
    }

    /// Parité avec DailySessionPickerTests : count non positif → 0 (pas de crash).
    func testMessageIndexWithNonPositiveCountReturnsZero() {
        XCTAssertEqual(WidgetTimelinePlanner.messageIndex(dayIndex: 5, slot: 1, count: 0), 0)
        XCTAssertEqual(WidgetTimelinePlanner.messageIndex(dayIndex: 5, slot: 1, count: -1), 0)
    }

    // MARK: - Messages

    /// Créneau d'une entrée : nuit (< 7 h) et soirée partagent le pool du soir —
    /// pas de « bonjour » à minuit (spec widgets §4.2).
    func testSlotBoundaries() {
        XCTAssertEqual(WidgetTimelinePlanner.slot(hour: 0), .evening)
        XCTAssertEqual(WidgetTimelinePlanner.slot(hour: 6), .evening)
        XCTAssertEqual(WidgetTimelinePlanner.slot(hour: 7), .morning)
        XCTAssertEqual(WidgetTimelinePlanner.slot(hour: 11), .morning)
        XCTAssertEqual(WidgetTimelinePlanner.slot(hour: 12), .midday)
        XCTAssertEqual(WidgetTimelinePlanner.slot(hour: 17), .midday)
        XCTAssertEqual(WidgetTimelinePlanner.slot(hour: 18), .evening)
        XCTAssertEqual(WidgetTimelinePlanner.slot(hour: 23), .evening)
    }

    /// L'index est stable pour (jour, créneau) et borné par count.
    func testMessageIndexDeterministicAndBounded() {
        for day in [-3, 0, 1, 42] {
            for slot in 0...2 {
                let a = WidgetTimelinePlanner.messageIndex(dayIndex: day, slot: slot, count: 7)
                let b = WidgetTimelinePlanner.messageIndex(dayIndex: day, slot: slot, count: 7)
                XCTAssertEqual(a, b)
                XCTAssertTrue((0..<7).contains(a))
            }
        }
    }

    /// Des jours consécutifs parcourent le pool (rotation, pas un message figé).
    func testMessageIndexRotatesAcrossDays() {
        let indices = (0..<5).map {
            WidgetTimelinePlanner.messageIndex(dayIndex: $0, slot: 0, count: 7)
        }
        XCTAssertTrue(Set(indices).count > 1)
    }

    func testEntriesSubstituteNameAndNeverLeavePlaceholders() {
        let entries = WidgetTimelinePlanner.entries(snapshot: snapshot(), from: date(hour: 9),
                                                    bank: bank, calendar: calendar)
        for entry in entries {
            XCTAssertFalse(entry.message.isEmpty)
            XCTAssertFalse(entry.message.contains("{name}"), entry.message)
            XCTAssertFalse(entry.message.contains("{value}"), entry.message)
        }
        // La substitution insère bien le prénom (pas juste "aucun placeholder").
        XCTAssertTrue(entries.contains { $0.message.contains("Michaël") })
    }

    func testSameDaySameSlotSameMessage() {
        let a = WidgetTimelinePlanner.entries(snapshot: snapshot(), from: date(hour: 9),
                                              bank: bank, calendar: calendar)
        let b = WidgetTimelinePlanner.entries(snapshot: snapshot(), from: date(hour: 10),
                                              bank: bank, calendar: calendar)
        // L'entrée de 12 h est présente dans les deux : même jour, même créneau, même message.
        XCTAssertEqual(a.first { $0.date == date(hour: 12) }?.message,
                       b.first { $0.date == date(hour: 12) }?.message)
    }

    /// Garde à la source (leçon v1.3) : les pools consommés par le widget ne
    /// contiennent JAMAIS `{value}` — le planner n'a pas de valeur à substituer.
    func testWidgetPoolsContainNoValuePlaceholder() {
        for context in [MessageContext.morning, .midday, .evening, .fun] {
            for message in bank.messages(for: context) {
                XCTAssertFalse(message.text.contains("{value}"),
                               "\(context) / \(message.id) contient {value}")
            }
        }
    }
}
