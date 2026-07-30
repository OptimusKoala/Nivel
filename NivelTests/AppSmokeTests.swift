// NivelTests/AppSmokeTests.swift
import XCTest
import SwiftData
import NivelCore
@testable import Nivel

final class AppSmokeTests: XCTestCase {
    func testInMemoryContainerInsertsAndFetchesModels() throws {
        let schema = Schema([
            UserProfile.self, MealEntry.self, WeightEntry.self,
            DayLog.self, GamificationState.self, ActivityEntry.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let profile = UserProfile(
            name: "Michaël",
            sex: .male,
            birthDate: Date(timeIntervalSince1970: 0),
            heightCm: 180,
            initialWeightKg: 90,
            activity: .moderate,
            dailyCalorieTarget: 2000
        )
        context.insert(profile)

        let meal = MealEntry(
            slot: .lunch,
            dishID: "poulet_riz",
            portion: .normal,
            estimatedKcal: 650
        )
        context.insert(meal)

        let activity = ActivityEntry(kind: .activity, refID: "walk",
                                     durationMinutes: 20, estimatedKcal: 80, xpAwarded: 30)
        context.insert(activity)

        try context.save()

        let fetchedProfiles = try context.fetch(FetchDescriptor<UserProfile>())
        let fetchedMeals = try context.fetch(FetchDescriptor<MealEntry>())

        XCTAssertEqual(fetchedProfiles.count, 1)
        XCTAssertEqual(fetchedProfiles.first?.name, "Michaël")
        XCTAssertEqual(fetchedProfiles.first?.sex, .male)

        XCTAssertEqual(fetchedMeals.count, 1)
        XCTAssertEqual(fetchedMeals.first?.dishID, "poulet_riz")
        XCTAssertEqual(fetchedMeals.first?.slot, .lunch)

        let fetchedActivities = try context.fetch(FetchDescriptor<ActivityEntry>())
        XCTAssertEqual(fetchedActivities.count, 1)
        XCTAssertEqual(fetchedActivities.first?.kind, .activity)
        XCTAssertEqual(fetchedActivities.first?.refID, "walk")
        XCTAssertEqual(fetchedActivities.first?.durationMinutes, 20)
        XCTAssertEqual(fetchedActivities.first?.estimatedKcal, 80)
        XCTAssertEqual(fetchedActivities.first?.xpAwarded, 30)
    }
}
