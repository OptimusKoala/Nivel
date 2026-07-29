import Foundation

public enum StepsEstimator {
    /// Estimation indicative, jamais ajoutée au budget (spec §6) : pas × 0.04 × poids/70.
    public static func kcal(steps: Int, weightKg: Double) -> Int {
        Int((Double(steps) * 0.04 * weightKg / 70).rounded())
    }
}
