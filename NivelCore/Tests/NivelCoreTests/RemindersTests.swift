import XCTest
@testable import NivelCore

final class RemindersTests: XCTestCase {

    /// Valeurs ÉPINGLÉES sur celles de la v1 : une modification ici déplacerait les
    /// rappels des installations existantes sans que personne ne l'ait demandé.
    func testLesQuatreDefautsSontCeuxDeLaV1() {
        let byID = Dictionary(uniqueKeysWithValues: ReminderCatalog.all.map { ($0.id, $0) })
        // 4 + le rappel posture de la v1.11 (épinglé séparément par
        // testLaCinquiemeEntreeEstLeRappelPosture) : seule ligne touchée ici, aucune des
        // valeurs pinnées des quatre rappels historiques ci-dessous n'a changé.
        XCTAssertEqual(ReminderCatalog.all.count, 5)

        XCTAssertEqual(byID["lunch"]?.defaultHour, 12)
        XCTAssertEqual(byID["lunch"]?.defaultMinute, 30)
        XCTAssertNil(byID["lunch"]?.defaultWeekday)
        XCTAssertEqual(byID["lunch"]?.context, .midday)
        XCTAssertEqual(byID["lunch"]?.title, "Déjeuner")

        XCTAssertEqual(byID["dinner"]?.defaultHour, 20)
        XCTAssertEqual(byID["dinner"]?.defaultMinute, 0)
        XCTAssertEqual(byID["dinner"]?.context, .evening)
        XCTAssertEqual(byID["dinner"]?.title, "Dîner")

        XCTAssertEqual(byID["weigh"]?.defaultHour, 9)
        XCTAssertEqual(byID["weigh"]?.defaultWeekday, 7)   // samedi
        XCTAssertEqual(byID["weigh"]?.context, .weighReminder)
        XCTAssertEqual(byID["weigh"]?.title, "Pesée")

        XCTAssertEqual(byID["steps"]?.defaultHour, 18)
        XCTAssertEqual(byID["steps"]?.context, .stepsEncouragement)
        XCTAssertEqual(byID["steps"]?.title, "Pas")
    }

    /// Ces minutes sont la source de vérité pour toute installation qui n'a jamais
    /// touché les réglages (spec §4.2, repli sur le catalogue) : un renversement
    /// heure/minute ici décalerait une vraie notification sans qu'un test échoue.
    func testMinutesDepuisMinuitEtRecherche() {
        XCTAssertEqual(ReminderCatalog.definition(id: "lunch")?.defaultMinutesFromMidnight, 750)
        XCTAssertEqual(ReminderCatalog.definition(id: "dinner")?.defaultMinutesFromMidnight, 1200)
        XCTAssertEqual(ReminderCatalog.definition(id: "weigh")?.defaultMinutesFromMidnight, 540)
        XCTAssertEqual(ReminderCatalog.definition(id: "steps")?.defaultMinutesFromMidnight, 1080)
        XCTAssertNil(ReminderCatalog.definition(id: "inconnu"))
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
        let expectedShort = ["dim.", "lun.", "mar.", "mer.", "jeu.", "ven.", "sam."]
        for (index, name) in expected.enumerated() {
            XCTAssertEqual(ReminderSchedule.frLabel(hour: 7, minute: 0, weekday: index + 1),
                           "le \(name) à 7 h")
            XCTAssertEqual(ReminderSchedule.frShortWeekday(index + 1), expectedShort[index])
        }
    }

    /// Un jour hors plage (bug amont) ne doit jamais planter ni afficher n'importe quoi :
    /// repli silencieux sur « tous les jours » / chaîne vide.
    func testJourHorsPlage() {
        XCTAssertEqual(ReminderSchedule.frLabel(hour: 9, minute: 0, weekday: 0),
                       "tous les jours à 9 h")
        XCTAssertEqual(ReminderSchedule.frLabel(hour: 9, minute: 0, weekday: 8),
                       "tous les jours à 9 h")
        XCTAssertEqual(ReminderSchedule.frShortWeekday(0), "")
        XCTAssertEqual(ReminderSchedule.frShortWeekday(8), "")
    }

    /// Arithmétique pure, sans `Calendar` : les minutes stockées par le lot D doivent
    /// redonner l'heure et la minute à afficher par le lot E, et faire l'aller-retour
    /// avec `defaultMinutesFromMidnight` pour les quatre rappels du catalogue.
    func testHeureMinuteDepuisMinutes() {
        XCTAssertTrue(ReminderSchedule.hourMinute(fromMinutesFromMidnight: 0) == (hour: 0, minute: 0))
        XCTAssertTrue(ReminderSchedule.hourMinute(fromMinutesFromMidnight: 750) == (hour: 12, minute: 30))
        XCTAssertTrue(ReminderSchedule.hourMinute(fromMinutesFromMidnight: 1439) == (hour: 23, minute: 59))

        for definition in ReminderCatalog.all {
            let roundTrip = ReminderSchedule.hourMinute(fromMinutesFromMidnight: definition.defaultMinutesFromMidnight)
            XCTAssertEqual(roundTrip.hour, definition.defaultHour, "heure pour \(definition.id)")
            XCTAssertEqual(roundTrip.minute, definition.defaultMinute, "minute pour \(definition.id)")
        }
    }

    func testFrequence() {
        XCTAssertEqual(ReminderSchedule.frFrequency(weekday: nil), "tous les jours")
        XCTAssertEqual(ReminderSchedule.frFrequency(weekday: 7), "chaque semaine")
    }

    /// Cinquième entrée du catalogue (spec v1.11 §10) : le rappel posture, 21 h,
    /// tous les jours, jour non modifiable. Valeurs ÉPINGLÉES comme les quatre autres.
    func testLaCinquiemeEntreeEstLeRappelPosture() {
        XCTAssertEqual(ReminderCatalog.all.count, 5, "le catalogue gagne le rappel posture")
        let posture = ReminderCatalog.definition(id: "posture")
        XCTAssertEqual(posture?.title, "Posture")
        XCTAssertEqual(posture?.defaultHour, 21)
        XCTAssertEqual(posture?.defaultMinute, 0)
        XCTAssertNil(posture?.defaultWeekday, "tous les jours, pas de jour fixe")
        XCTAssertEqual(posture?.isWeekdayEditable, false, "jour non modifiable (spec §10)")
        XCTAssertEqual(posture?.context, .postureReminder)

        XCTAssertEqual(
            ReminderSchedule.frLabel(hour: posture!.defaultHour, minute: posture!.defaultMinute,
                                     weekday: posture!.defaultWeekday),
            "tous les jours à 21 h"
        )
    }

    /// Aucun tiret cadratin dans les textes destinés à l'écran (règle v1.2).
    func testAucunTiretCadratin() {
        for definition in ReminderCatalog.all {
            XCTAssertFalse(definition.title.contains("—"))
        }
        XCTAssertFalse(ReminderSchedule.frLabel(hour: 9, minute: 0, weekday: 7).contains("—"))
    }

    // MARK: - Résolution surcharge / défaut (source unique, spec §4.3)

    /// Absence de surcharge : on retombe sur le défaut du catalogue.
    func testResolvedMinutesSansSurchargeDonneLeDefaut() {
        let lunch = ReminderCatalog.definition(id: "lunch")!
        XCTAssertEqual(ReminderSchedule.resolvedMinutes(nil, for: lunch), 750)
    }

    /// Surcharge valide : elle l'emporte sur le défaut.
    func testResolvedMinutesSurchargeValideEstAppliquee() {
        let lunch = ReminderCatalog.definition(id: "lunch")!
        XCTAssertEqual(ReminderSchedule.resolvedMinutes(13 * 60 + 15, for: lunch), 13 * 60 + 15)
    }

    /// Surcharge hors bornes : écartée, on retombe sur le défaut du catalogue.
    func testResolvedMinutesSurchargeHorsPlageDonneLeDefaut() {
        let lunch = ReminderCatalog.definition(id: "lunch")!
        for bad in [-1, 1440, 99_999] {
            XCTAssertEqual(ReminderSchedule.resolvedMinutes(bad, for: lunch), 750)
        }
    }

    func testResolvedWeekdaySansSurchargeDonneLeDefaut() {
        let weigh = ReminderCatalog.definition(id: "weigh")!
        XCTAssertEqual(ReminderSchedule.resolvedWeekday(nil, for: weigh), 7)
    }

    func testResolvedWeekdaySurchargeValideEstAppliquee() {
        let weigh = ReminderCatalog.definition(id: "weigh")!
        XCTAssertEqual(ReminderSchedule.resolvedWeekday(1, for: weigh), 1)
    }

    func testResolvedWeekdaySurchargeHorsPlageDonneLeDefaut() {
        let weigh = ReminderCatalog.definition(id: "weigh")!
        for bad in [0, 8, -3] {
            XCTAssertEqual(ReminderSchedule.resolvedWeekday(bad, for: weigh), 7)
        }
    }

    /// Court-circuit : un rappel dont le jour n'est pas modifiable ignore la
    /// surcharge, même valide, et ne consulte jamais la valeur stockée.
    func testResolvedWeekdaySurchargeIgnoreeSurRappelNonModifiable() {
        let lunch = ReminderCatalog.definition(id: "lunch")!
        XCTAssertNil(ReminderSchedule.resolvedWeekday(3, for: lunch))
        XCTAssertNil(ReminderSchedule.resolvedWeekday(nil, for: lunch))
    }

    // MARK: - Planificateur

    private let allOn = ["lunch": true, "dinner": true, "weigh": true, "steps": true]

    private func planned(_ enabled: [String: Bool], times: [String: Int] = [:],
                         weekdays: [String: Int] = [:]) -> [PlannedReminder] {
        ReminderPlanner.planned(enabled: enabled, times: times, weekdays: weekdays)
    }

    func testSansSurchargeOnRetrouveLesDefauts() {
        let result = planned(allOn)
        XCTAssertEqual(result.count, 4)
        let lunch = result.first { $0.id == "lunch" }
        XCTAssertEqual(lunch?.hour, 12)
        XCTAssertEqual(lunch?.minute, 30)
        XCTAssertNil(lunch?.weekday)
        XCTAssertEqual(result.first { $0.id == "weigh" }?.weekday, 7)
    }

    func testRappelEteintAbsentDuResultat() {
        let result = planned(["lunch": true, "dinner": false, "weigh": true])
        XCTAssertEqual(Set(result.map(\.id)), ["lunch", "weigh"])
    }

    func testSurchargeAppliquee() {
        let result = planned(allOn, times: ["lunch": 13 * 60 + 15], weekdays: ["weigh": 1])
        XCTAssertEqual(result.first { $0.id == "lunch" }?.hour, 13)
        XCTAssertEqual(result.first { $0.id == "lunch" }?.minute, 15)
        XCTAssertEqual(result.first { $0.id == "weigh" }?.weekday, 1)
    }

    /// Un réglage corrompu ne doit JAMAIS faire disparaître un rappel actif :
    /// on retombe sur le défaut du catalogue, on ne saute pas l'entrée.
    func testValeursAberrantesRetombentSurLeDefaut() {
        for badMinutes in [-1, 1440, 99_999] {
            let result = planned(allOn, times: ["lunch": badMinutes])
            XCTAssertEqual(result.first { $0.id == "lunch" }?.hour, 12)
            XCTAssertEqual(result.first { $0.id == "lunch" }?.minute, 30)
        }
        for badWeekday in [0, 8, -3] {
            let result = planned(allOn, weekdays: ["weigh": badWeekday])
            XCTAssertEqual(result.first { $0.id == "weigh" }?.weekday, 7)
        }
    }

    /// Poser un jour sur un rappel quotidien ne doit pas le rendre hebdomadaire.
    func testJourIgnoreSurUnRappelNonModifiable() {
        let result = planned(allOn, weekdays: ["lunch": 3])
        XCTAssertNil(result.first { $0.id == "lunch" }?.weekday)
    }

    /// Résidu d'une version antérieure ou d'un lot futur non installé.
    func testIdentifiantInconnuIgnore() {
        let result = planned(allOn.merging(["ghost": true]) { a, _ in a },
                             times: ["ghost": 60])
        XCTAssertEqual(result.count, 4)
        XCTAssertNil(result.first { $0.id == "ghost" })
    }

    func testMinuitEtDerniereMinuteSontValides() {
        XCTAssertEqual(planned(allOn, times: ["lunch": 0]).first { $0.id == "lunch" }?.hour, 0)
        let last = planned(allOn, times: ["lunch": 1439]).first { $0.id == "lunch" }
        XCTAssertEqual(last?.hour, 23)
        XCTAssertEqual(last?.minute, 59)
    }

    /// `hourMinute` doit rester une paire heure/minute valide même hors plage :
    /// on écrête plutôt que de renvoyer une heure 24 ou une minute négative.
    func testHeureMinuteEcreteHorsPlage() {
        XCTAssertTrue(ReminderSchedule.hourMinute(fromMinutesFromMidnight: -30) == (hour: 0, minute: 0))
        XCTAssertTrue(ReminderSchedule.hourMinute(fromMinutesFromMidnight: 1440) == (hour: 23, minute: 59))
        XCTAssertTrue(ReminderSchedule.hourMinute(fromMinutesFromMidnight: 99_999) == (hour: 23, minute: 59))
    }
}
