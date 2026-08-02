// Calcul des kcal d'un repas (spec v1.10 §3.3). Pur : le barème est INJECTÉ, ce qui
// permet de tester le calcul sans dépendre du contenu du catalogue.

import Foundation

public enum MealEstimator {
    /// kcal = plat × portion (arrondi) + somme des extras × quantité (spec §6).
    /// Conservée pour la durée des Tasks 1 à 3 (v1.10) : encore appelée par GameService
    /// et MealLogSheet côté app, retirée seulement à la Task 4 qui bascule l'app d'un bloc.
    public static func estimate(dish: Dish, portion: Portion, extras: [(Extra, Int)]) -> Int {
        let dishKcal = Int((Double(dish.kcal) * portion.multiplier).rounded())
        let extrasKcal = extras.reduce(0) { $0 + $1.0.kcal * $1.1 }
        return dishKcal + extrasKcal
    }

    /// Un seul arrondi, à la fin : arrondir composant par composant ferait dériver
    /// une composition à six ingrédients de plusieurs kcal pour rien.
    public static func kcal(lines: [MealLine],
                            kcalPer100g: (String) -> Double?) -> Int {
        let total = lines
            .flatMap(\.components)
            .reduce(0.0) { sum, component in
                // Item inconnu = 0 : un JSON corrompu ne doit pas empêcher
                // d'ouvrir son journal.
                sum + (kcalPer100g(component.itemID) ?? 0) * Double(component.grams) / 100
            }
        return Int(total.rounded())
    }
}
