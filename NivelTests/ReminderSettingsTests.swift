// NivelTests/ReminderSettingsTests.swift
import XCTest
import SwiftData
import NivelCore
@testable import Nivel

@MainActor
final class ReminderSettingsTests: XCTestCase {

    /// Le container est retenu par le cas de test, pas par une variable locale :
    /// SwiftData ne le retient PAS depuis son mainContext, et une locale peut être
    /// libérée dès son dernier usage sous optimisation, ce qui invalide le modèle
    /// et fait tomber tout le processus de test. `_ = container` ne garantit rien.
    private var container: ModelContainer!

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    private func makeProfile() throws -> UserProfile {
        let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                             DayLog.self, GamificationState.self, ActivityEntry.self])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let profile = UserProfile(
            name: "Marion", sex: .female,
            birthDate: Date(timeIntervalSince1970: 0),
            heightCm: 165, initialWeightKg: 70, activity: .light,
            dailyCalorieTarget: 1700,
            remindersEnabled: ["lunch": true, "dinner": true, "weigh": true, "steps": true]
        )
        container.mainContext.insert(profile)
        return profile
    }

    /// Un profil créé sans horaires (donc tout profil déjà installé) doit produire
    /// exactement la planification de la v1.
    func testProfilSansHorairesGardeLesDefauts() throws {
        let profile = try makeProfile()
        XCTAssertTrue(profile.reminderTimes.isEmpty)
        XCTAssertTrue(profile.reminderWeekdays.isEmpty)

        let planned = ReminderPlanner.planned(enabled: profile.remindersEnabled,
                                              times: profile.reminderTimes,
                                              weekdays: profile.reminderWeekdays,
                                              enabledPlans: Set(ReminderPlan.allCases))
        let lunch = planned.first { $0.id == "lunch" }
        XCTAssertEqual(lunch?.hour, 12)
        XCTAssertEqual(lunch?.minute, 30)
        XCTAssertEqual(planned.first { $0.id == "weigh" }?.weekday, 7)
    }

    func testHoraireModifiePersisteEtEstPlanifie() throws {
        let profile = try makeProfile()
        profile.reminderTimes = ["dinner": 19 * 60 + 45]
        profile.reminderWeekdays = ["weigh": 1]
        try container.mainContext.save()

        let reloaded = try XCTUnwrap(
            try container.mainContext.fetch(FetchDescriptor<UserProfile>()).first
        )
        let planned = ReminderPlanner.planned(enabled: reloaded.remindersEnabled,
                                              times: reloaded.reminderTimes,
                                              weekdays: reloaded.reminderWeekdays,
                                              enabledPlans: Set(ReminderPlan.allCases))
        let dinner = planned.first { $0.id == "dinner" }
        XCTAssertEqual(dinner?.hour, 19)
        XCTAssertEqual(dinner?.minute, 45)
        XCTAssertEqual(planned.first { $0.id == "weigh" }?.weekday, 1)
    }

    /// Le sous-titre affiché doit suivre l'horaire réel, pas un texte figé.
    func testSousTitreSuitLHoraire() throws {
        let profile = try makeProfile()
        profile.reminderTimes = ["dinner": 19 * 60 + 45]
        let planned = ReminderPlanner.planned(enabled: profile.remindersEnabled,
                                              times: profile.reminderTimes,
                                              weekdays: profile.reminderWeekdays,
                                              enabledPlans: Set(ReminderPlan.allCases))
        let dinner = try XCTUnwrap(planned.first { $0.id == "dinner" })
        XCTAssertEqual(
            ReminderSchedule.frLabel(hour: dinner.hour, minute: dinner.minute,
                                     weekday: dinner.weekday),
            "tous les jours à 19 h 45"
        )
    }
}
