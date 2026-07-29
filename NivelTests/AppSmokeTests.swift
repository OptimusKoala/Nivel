// NivelTests/AppSmokeTests.swift
import XCTest
import SwiftData
@testable import Nivel

final class AppSmokeTests: XCTestCase {
    func testInMemoryContainerInsertsAndFetchesModels() throws {
        let schema = Schema([
            UserProfile.self, MealEntry.self, WeightEntry.self,
            DayLog.self, GamificationState.self
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

        try context.save()

        let fetchedProfiles = try context.fetch(FetchDescriptor<UserProfile>())
        let fetchedMeals = try context.fetch(FetchDescriptor<MealEntry>())

        XCTAssertEqual(fetchedProfiles.count, 1)
        XCTAssertEqual(fetchedProfiles.first?.name, "Michaël")
        XCTAssertEqual(fetchedProfiles.first?.sex, .male)

        XCTAssertEqual(fetchedMeals.count, 1)
        XCTAssertEqual(fetchedMeals.first?.dishID, "poulet_riz")
        XCTAssertEqual(fetchedMeals.first?.slot, .lunch)
    }
}
