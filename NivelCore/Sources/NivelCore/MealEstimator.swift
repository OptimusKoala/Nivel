// Calcul des kcal d'un repas (spec v1.10 §3.3). Pur : le barème est INJECTÉ, ce qui
// permet de tester le calcul sans dépendre du contenu du catalogue.

import Foundation

public enum MealEstimator {
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
