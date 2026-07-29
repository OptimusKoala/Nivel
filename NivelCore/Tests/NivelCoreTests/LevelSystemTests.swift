import XCTest
@testable import NivelCore

final class LevelSystemTests: XCTestCase {
    func testThresholds() {
        XCTAssertEqual(LevelSystem.xpRequired(forLevel: 1), 0)      // niveau de départ
        XCTAssertEqual(LevelSystem.xpRequired(forLevel: 2), 246)    // 100×2^1.3 = 246.2 → 246
        XCTAssertEqual(LevelSystem.xpRequired(forLevel: 5), 810)    // 100×5^1.3 = 810.33 → 810
        XCTAssertEqual(LevelSystem.xpRequired(forLevel: 10), 1995)  // 100×10^1.3
    }

    func testLevelForXP() {
        XCTAssertEqual(LevelSystem.level(forXP: 0), 1)
        XCTAssertEqual(LevelSystem.level(forXP: 245), 1)
        XCTAssertEqual(LevelSystem.level(forXP: 246), 2)
        XCTAssertEqual(LevelSystem.level(forXP: 2000), 10)
    }

    func testProgressWithinLevel() {
        // à 246 XP : début du niveau 2 → progression 0 vers le niveau 3 (100×3^1.3 = 417)
        let p = LevelSystem.progress(forXP: 246)
        XCTAssertEqual(p.current, 0)
        XCTAssertEqual(p.needed, 417 - 246)
    }

    func testStepsCalorieEstimate() {
        // 8000 pas à 90 kg : 8000 × 0.04 × 90/70 ≈ 411
        XCTAssertEqual(StepsEstimator.kcal(steps: 8000, weightKg: 90), 411)
    }
}
