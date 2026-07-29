// NivelCore/Tests/NivelCoreTests/CalorieCalculatorTests.swift
import XCTest
@testable import NivelCore

final class CalorieCalculatorTests: XCTestCase {
    // Michaël-type : homme, 90 kg, 180 cm, 40 ans
    func testBMRMale() {
        let bmr = CalorieCalculator.bmr(sex: .male, weightKg: 90, heightCm: 180, ageYears: 40)
        let expected: Double = 10.0*90.0 + 6.25*180.0 - 5.0*40.0 + 5.0
        XCTAssertEqual(bmr, expected, accuracy: 0.001) // 1830
    }

    func testBMRFemale() {
        let bmr = CalorieCalculator.bmr(sex: .female, weightKg: 70, heightCm: 165, ageYears: 38)
        let expected: Double = 10.0*70.0 + 6.25*165.0 - 5.0*38.0 - 161.0
        XCTAssertEqual(bmr, expected, accuracy: 0.001) // 1380.25
    }

    func testTDEEAppliesActivityFactor() {
        let tdee = CalorieCalculator.tdee(bmr: 1830, activity: .light)
        XCTAssertEqual(tdee, 1830 * 1.375, accuracy: 0.001)
    }

    func testDailyTargetSubtracts350AndRoundsToTen() {
        // TDEE 2516.25 → 2166.25 → arrondi 2170
        let target = CalorieCalculator.dailyTarget(sex: .male, weightKg: 90, heightCm: 180, ageYears: 40, activity: .light)
        XCTAssertEqual(target, 2170)
    }

    func testDailyTargetFloorFemale() {
        // Profil très petit → sous 1200 → plancher
        let target = CalorieCalculator.dailyTarget(sex: .female, weightKg: 45, heightCm: 150, ageYears: 60, activity: .sedentary)
        XCTAssertEqual(target, 1200)
    }

    func testDailyTargetFloorMale() {
        let target = CalorieCalculator.dailyTarget(sex: .male, weightKg: 50, heightCm: 155, ageYears: 70, activity: .sedentary)
        XCTAssertEqual(target, 1500)
    }
}
