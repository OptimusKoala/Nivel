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

    /// from 9 h : toutes les heures pleines jusqu'à 7 h du lendemain inclus
    /// (spec vivant §3) : 9 h (from), 10 h … 23 h, minuit, 1 h … 7 h = 23 entrées.
    func testEntriesCoverEveryHourUntilNextMorning() {
        let from = date(hour: 9)
        let entries = WidgetTimelinePlanner.entries(snapshot: snapshot(), from: from,
                                                    bank: bank, calendar: calendar)
        var expected: [Date] = [from]
        expected += (10...23).map { date(hour: $0) }
        expected.append(calendar.startOfDay(for: date(hour: 0, day: 32)))
        expected += (1...7).map { date(hour: $0, day: 32) }
        XCTAssertEqual(entries.map(\.date), expected)
        XCTAssertEqual(entries.count, 23)
    }

    /// from 23 h : plus d'heure restante le jour même, la nuit du lendemain suit.
    func testEntriesLateEveningRollIntoNextDay() {
        let from = date(hour: 23)
        let entries = WidgetTimelinePlanner.entries(snapshot: snapshot(), from: from,
                                                    bank: bank, calendar: calendar)
        var expected: [Date] = [from]
        expected.append(calendar.startOfDay(for: date(hour: 0, day: 32)))
        expected += (1...7).map { date(hour: $0, day: 32) }
        XCTAssertEqual(entries.map(\.date), expected)
    }

    /// Pire cas pré-aube (spec §3) : from entre 0 h et 1 h = 32 entrées.
    func testPreDawnWorstCaseIsThirtyTwoEntries() {
        let from = date(hour: 0, minute: 30)
        let entries = WidgetTimelinePlanner.entries(snapshot: snapshot(), from: from,
                                                    bank: bank, calendar: calendar)
        XCTAssertEqual(entries.count, 32)
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

    /// L'index est stable et borné pour la même heure absolue.
    func testMessageIndexDeterministicAndBounded() {
        for hours in [-25, 0, 1, 24, 1_000] {
            let a = WidgetTimelinePlanner.messageIndex(hoursSinceReference: hours, count: 7)
            let b = WidgetTimelinePlanner.messageIndex(hoursSinceReference: hours, count: 7)
            XCTAssertEqual(a, b)
            XCTAssertTrue((0..<7).contains(a))
        }
    }

    /// Le seed avance de 1 par heure : deux heures consécutives ne coïncident
    /// JAMAIS, quel que soit le pool (>= 2) — y compris 23 h vers 0 h, la
    /// collision systématique qu'un seed (jour, créneau) multiplié aurait créée
    /// (spec vivant §3).
    func testConsecutiveHoursNeverCollide() {
        for count in [2, 25, 26] {
            for hours in [0, 23, 47, 500] {
                XCTAssertNotEqual(
                    WidgetTimelinePlanner.messageIndex(hoursSinceReference: hours, count: count),
                    WidgetTimelinePlanner.messageIndex(hoursSinceReference: hours + 1, count: count),
                    "count \(count), heure \(hours)")
            }
        }
    }

    /// La même heure d'un jour à l'autre change aussi (delta 24, non multiple
    /// des tailles de pools actuelles 25/26). Si un futur pool devient multiple
    /// de 24, ce test le signalera : c'est voulu (spec vivant §7).
    func testSameHourNextDayDiffers() {
        for context in [MessageContext.morning, .midday, .evening] {
            let count = bank.messages(for: context).count + bank.messages(for: .fun).count
            XCTAssertNotEqual(24 % count, 0, "pool \(context) de taille \(count)")
        }
    }

    /// Compagnon du canary arithmétique ci-dessus : pinne la variété jour à
    /// jour sur une VRAIE timeline (une mutation qui perdrait la composante
    /// jour du seed passerait tous les autres tests).
    func testSameHourNextDayDiffersOnRealTimeline() {
        let today = WidgetTimelinePlanner.entries(snapshot: snapshot(), from: date(hour: 9),
                                                  bank: bank, calendar: calendar)
        let tomorrow = WidgetTimelinePlanner.entries(
            snapshot: snapshot(dayKey: calendar.startOfDay(for: date(hour: 0, day: 32))),
            from: date(hour: 9, day: 32),
            bank: bank, calendar: calendar
        )
        XCTAssertNotEqual(today.first!.message, tomorrow.first!.message)
    }

    /// Parité avec DailySessionPickerTests : count non positif renvoie 0 (pas de crash).
    func testMessageIndexWithNonPositiveCountReturnsZero() {
        XCTAssertEqual(WidgetTimelinePlanner.messageIndex(hoursSinceReference: 5, count: 0), 0)
        XCTAssertEqual(WidgetTimelinePlanner.messageIndex(hoursSinceReference: 5, count: -1), 0)
    }

    /// Pinne explicitement la non-collision de minuit sur une VRAIE timeline :
    /// l'entrée de 23 h et celle de minuit portent des messages différents.
    func testMidnightEntryDiffersFromElevenPM() {
        let entries = WidgetTimelinePlanner.entries(snapshot: snapshot(), from: date(hour: 21),
                                                    bank: bank, calendar: calendar)
        let elevenPM = entries.first { $0.date == date(hour: 23) }!
        let midnight = entries.first {
            $0.date == calendar.startOfDay(for: date(hour: 0, day: 32))
        }!
        XCTAssertNotEqual(elevenPM.message, midnight.message)
    }

    /// Deux heures consécutives d'une vraie timeline (même pool du matin)
    /// portent des messages différents.
    func testHourlyEntriesRotateWithinASlot() {
        let entries = WidgetTimelinePlanner.entries(snapshot: snapshot(), from: date(hour: 8),
                                                    bank: bank, calendar: calendar)
        let nine = entries.first { $0.date == date(hour: 9) }!
        let ten = entries.first { $0.date == date(hour: 10) }!
        XCTAssertNotEqual(nine.message, ten.message)
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

    func testSameDaySameHourSameMessage() {
        let a = WidgetTimelinePlanner.entries(snapshot: snapshot(), from: date(hour: 9),
                                              bank: bank, calendar: calendar)
        let b = WidgetTimelinePlanner.entries(snapshot: snapshot(), from: date(hour: 10),
                                              bank: bank, calendar: calendar)
        // L'entrée de 12 h est présente dans les deux : même jour, même heure, même message.
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
