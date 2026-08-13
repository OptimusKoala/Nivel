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

    /// Objectif de dépense quotidienne (spec v1.14 §5.3) : poids × 4, arrondi à la
    /// cinquantaine, borné [200, 600].
    ///
    /// Proportionnel au poids, parce qu'un même mouvement ne coûte pas la même chose à
    /// 60 et à 110 kg. Bornes assumées : sous 200 l'objectif ne veut rien dire, au-delà
    /// de 600 il demande une heure de sport par jour et devient un reproche quotidien.
    public static func dailyBurnTarget(weightKg: Double) -> Int {
        let raw = weightKg * 4
        let rounded = Int((raw / 50).rounded()) * 50
        return min(600, max(200, rounded))
    }
}
