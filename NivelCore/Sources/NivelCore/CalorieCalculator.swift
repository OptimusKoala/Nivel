// NivelCore/Sources/NivelCore/CalorieCalculator.swift
import Foundation

public enum CalorieCalculator {
    public static func bmr(sex: Sex, weightKg: Double, heightCm: Double, ageYears: Int) -> Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(ageYears)
        return sex == .male ? base + 5 : base - 161
    }

    public static func tdee(bmr: Double, activity: ActivityLevel) -> Double {
        bmr * activity.factor
    }

    /// Objectif quotidien : TDEE − 350, arrondi à la dizaine, avec plancher de sécurité (spec §6).
    public static func dailyTarget(sex: Sex, weightKg: Double, heightCm: Double, ageYears: Int, activity: ActivityLevel) -> Int {
        let tdee = tdee(bmr: bmr(sex: sex, weightKg: weightKg, heightCm: heightCm, ageYears: ageYears), activity: activity)
        let raw = tdee - 350
        let rounded = Int((raw / 10).rounded()) * 10
        let floor = sex == .female ? 1200 : 1500
        return max(rounded, floor)
    }
}
