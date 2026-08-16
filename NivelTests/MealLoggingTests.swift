// NivelTests/MealLoggingTests.swift
// Persistance des lignes de repas (spec v1.10 §3.1, Task 4) : `MealEntry` troque
// dishID/portionRaw/extras contre lines/manualKcal, migration légère SwiftData.
import XCTest
import SwiftData
import NivelCore
@testable import Nivel

@MainActor
final class MealLoggingTests: XCTestCase {
    /// Container retenu par le cas de test : SwiftData ne le retient pas depuis son
    /// mainContext, et une locale peut être libérée dès son dernier usage (leçon v1.9).
    private var container: ModelContainer!

    override func setUpWithError() throws {
        let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                             DayLog.self, GamificationState.self, ActivityEntry.self])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
        )
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    private let lines: [MealLine] = [
        .composed(itemID: "salad", components: [
            MealComponent(itemID: "lettuce", grams: 80),
            MealComponent(itemID: "tuna", grams: 80),
        ]),
        .simple(MealComponent(itemID: "beer_half", grams: 250)),
    ]

    func testLesLignesSurviventAUnAllerRetourEnBase() throws {
        let entry = MealEntry(slot: .lunch, lines: lines, estimatedKcal: 230)
        container.mainContext.insert(entry)
        try container.mainContext.save()

        let reloaded = try XCTUnwrap(
            try container.mainContext.fetch(FetchDescriptor<MealEntry>()).first
        )
        XCTAssertEqual(reloaded.lines, lines)
        XCTAssertEqual(reloaded.lines.first?.components.count, 2)
        XCTAssertNil(reloaded.manualKcal)
    }

    func testKcalManuellesCourtCircuitentLeCalcul() throws {
        let catalog = try FoodCatalog.load()
        let computed = MealEstimator.kcal(lines: lines, kcalPer100g: catalog.kcalPer100g)
        let entry = MealEntry(slot: .lunch, lines: lines,
                              manualKcal: 450, estimatedKcal: 450)
        XCTAssertNotEqual(computed, 450)
        XCTAssertEqual(entry.estimatedKcal, 450)
        XCTAssertEqual(entry.manualKcal, 450)
    }

    /// Le repas d'avant la migration : aucune ligne, mais ses kcal et son XP intacts.
    func testRepasSansLigneNeCassePas() throws {
        let entry = MealEntry(slot: .dinner, lines: [], estimatedKcal: 620, xpAwarded: 20)
        container.mainContext.insert(entry)
        try container.mainContext.save()
        XCTAssertTrue(entry.lines.isEmpty)
        XCTAssertEqual(entry.estimatedKcal, 620)
    }
}
