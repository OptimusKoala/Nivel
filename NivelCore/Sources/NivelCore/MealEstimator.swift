import Foundation

public enum MealEstimator {
    /// kcal = plat × portion (arrondi) + somme des extras × quantité (spec §6).
    public static func estimate(dish: Dish, portion: Portion, extras: [(Extra, Int)]) -> Int {
        let dishKcal = Int((Double(dish.kcal) * portion.multiplier).rounded())
        let extrasKcal = extras.reduce(0) { $0 + $1.0.kcal * $1.1 }
        return dishKcal + extrasKcal
    }
}
