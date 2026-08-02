// NivelTests/ReminderSettingsTests.swift
import XCTest
import SwiftData
import NivelCore
@testable import Nivel

@MainActor
final class ReminderSettingsTests: XCTestCase {

    private func makeProfile() throws -> (ModelContainer, UserProfile) {
        let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                             DayLog.self, GamificationState.self, ActivityEntry.self])
        let container = try ModelContainer(
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
        return (container, profile)
    }

    /// Un profil créé sans horaires (donc tout profil déjà installé) doit produire
    /// exactement la planification de la v1.
    func testProfilSansHorairesGardeLesDefauts() throws {
        // Le container doit rester en vie tant que `profile` est lu : SwiftData ne
        // le retient pas via mainContext, un `_` ici invaliderait le modèle (crash).
        let (container, profile) = try makeProfile()
        _ = container
        XCTAssertTrue(profile.reminderTimes.isEmpty)
        XCTAssertTrue(profile.reminderWeekdays.isEmpty)

        let planned = ReminderPlanner.planned(enabled: profile.remindersEnabled,
                                              times: profile.reminderTimes,
                                              weekdays: profile.reminderWeekdays)
        let lunch = planned.first { $0.id == "lunch" }
        XCTAssertEqual(lunch?.hour, 12)
        XCTAssertEqual(lunch?.minute, 30)
        XCTAssertEqual(planned.first { $0.id == "weigh" }?.weekday, 7)
    }

    func testHoraireModifiePersisteEtEstPlanifie() throws {
        let (container, profile) = try makeProfile()
        profile.reminderTimes = ["dinner": 19 * 60 + 45]
        profile.reminderWeekdays = ["weigh": 1]
        try container.mainContext.save()

        let reloaded = try XCTUnwrap(
            try container.mainContext.fetch(FetchDescriptor<UserProfile>()).first
        )
        let planned = ReminderPlanner.planned(enabled: reloaded.remindersEnabled,
                                              times: reloaded.reminderTimes,
                                              weekdays: reloaded.reminderWeekdays)
        let dinner = planned.first { $0.id == "dinner" }
        XCTAssertEqual(dinner?.hour, 19)
        XCTAssertEqual(dinner?.minute, 45)
        XCTAssertEqual(planned.first { $0.id == "weigh" }?.weekday, 1)
    }

    /// Le sous-titre affiché doit suivre l'horaire réel, pas un texte figé.
    func testSousTitreSuitLHoraire() throws {
        // Idem : conserver le container vivant pour la durée du test (cf. commentaire
        // ci-dessus dans testProfilSansHorairesGardeLesDefauts).
        let (container, profile) = try makeProfile()
        _ = container
        profile.reminderTimes = ["dinner": 19 * 60 + 45]
        let planned = ReminderPlanner.planned(enabled: profile.remindersEnabled,
                                              times: profile.reminderTimes,
                                              weekdays: profile.reminderWeekdays)
        let dinner = try XCTUnwrap(planned.first { $0.id == "dinner" })
        XCTAssertEqual(
            ReminderSchedule.frLabel(hour: dinner.hour, minute: dinner.minute,
                                     weekday: dinner.weekday),
            "tous les jours à 19 h 45"
        )
    }
}
