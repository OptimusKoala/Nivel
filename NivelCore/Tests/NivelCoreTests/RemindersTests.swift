import XCTest
@testable import NivelCore

final class RemindersTests: XCTestCase {

    /// Valeurs ÉPINGLÉES sur celles de la v1 : une modification ici déplacerait les
    /// rappels des installations existantes sans que personne ne l'ait demandé.
    func testLesQuatreDefautsSontCeuxDeLaV1() {
        let byID = Dictionary(uniqueKeysWithValues: ReminderCatalog.all.map { ($0.id, $0) })
        XCTAssertEqual(ReminderCatalog.all.count, 4)

        XCTAssertEqual(byID["lunch"]?.defaultHour, 12)
        XCTAssertEqual(byID["lunch"]?.defaultMinute, 30)
        XCTAssertNil(byID["lunch"]?.defaultWeekday)
        XCTAssertEqual(byID["lunch"]?.context, .midday)

        XCTAssertEqual(byID["dinner"]?.defaultHour, 20)
        XCTAssertEqual(byID["dinner"]?.defaultMinute, 0)
        XCTAssertEqual(byID["dinner"]?.context, .evening)

        XCTAssertEqual(byID["weigh"]?.defaultHour, 9)
        XCTAssertEqual(byID["weigh"]?.defaultWeekday, 7)   // samedi
        XCTAssertEqual(byID["weigh"]?.context, .weighReminder)

        XCTAssertEqual(byID["steps"]?.defaultHour, 18)
        XCTAssertEqual(byID["steps"]?.context, .stepsEncouragement)
    }

    /// La pesée est le seul rappel hebdomadaire, donc le seul dont le jour se choisit.
    func testSeuleLaPeseeALeJourModifiable() {
        for definition in ReminderCatalog.all {
            XCTAssertEqual(definition.isWeekdayEditable, definition.id == "weigh",
                           "jour modifiable inattendu sur \(definition.id)")
        }
    }

    func testLibelleFrancais() {
        XCTAssertEqual(ReminderSchedule.frLabel(hour: 12, minute: 30, weekday: nil),
                       "tous les jours à 12 h 30")
        XCTAssertEqual(ReminderSchedule.frLabel(hour: 20, minute: 0, weekday: nil),
                       "tous les jours à 20 h")
        XCTAssertEqual(ReminderSchedule.frLabel(hour: 8, minute: 5, weekday: nil),
                       "tous les jours à 8 h 05")
        XCTAssertEqual(ReminderSchedule.frLabel(hour: 0, minute: 0, weekday: nil),
                       "tous les jours à 0 h")
        XCTAssertEqual(ReminderSchedule.frLabel(hour: 9, minute: 0, weekday: 7),
                       "le samedi à 9 h")
        XCTAssertEqual(ReminderSchedule.frLabel(hour: 9, minute: 0, weekday: 1),
                       "le dimanche à 9 h")
    }

    func testLesSeptJours() {
        let expected = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]
        for (index, name) in expected.enumerated() {
            XCTAssertEqual(ReminderSchedule.frLabel(hour: 7, minute: 0, weekday: index + 1),
                           "le \(name) à 7 h")
            XCTAssertFalse(ReminderSchedule.frShortWeekday(index + 1).isEmpty)
        }
    }

    func testFrequence() {
        XCTAssertEqual(ReminderSchedule.frFrequency(weekday: nil), "tous les jours")
        XCTAssertEqual(ReminderSchedule.frFrequency(weekday: 7), "chaque semaine")
    }

    /// Aucun tiret cadratin dans les textes destinés à l'écran (règle v1.2).
    func testAucunTiretCadratin() {
        for definition in ReminderCatalog.all {
            XCTAssertFalse(definition.title.contains("—"))
        }
        XCTAssertFalse(ReminderSchedule.frLabel(hour: 9, minute: 0, weekday: 7).contains("—"))
    }
}
