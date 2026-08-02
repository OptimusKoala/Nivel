// NivelCore/Sources/NivelCore/MealFormatting.swift
// Mise en forme d'un repas pour l'écran (spec v1.10 §5.5 et §6). Séparé de
// MealEstimator : estimer et mettre en forme sont deux métiers, et un seul endroit
// doit décider de la règle du tilde pour que la feuille de log et le journal ne
// puissent jamais en afficher deux versions différentes.

import Foundation

public enum MealFormatting {
    /// « ~ 635 kcal » quand l'app a estimé, « 635 kcal » sans tilde quand
    /// l'utilisateur a saisi le chiffre lui-même. Le tilde est une promesse
    /// d'honnêteté portée depuis la v1 : il ne doit pas mentir dans l'autre sens en
    /// restant affiché sur une valeur qu'on sait exacte.
    public static func frKcal(_ kcal: Int, isManual: Bool) -> String {
        let number = kcal.formatted(.number.locale(Locale(identifier: "fr_FR")))
        return isManual ? "\(number) kcal" : "~ \(number) kcal"
    }

    /// Nom de la première ligne, puis « +N » pour les autres (« Tartines +2 »).
    /// « Repas » si le repas n'a aucune ligne : c'est l'unique entrée d'avant la
    /// migration v1.10 (spec §3.1), qui garde ses kcal mais perd son détail.
    public static func frSummary(lines: [MealLine], catalog: FoodCatalog) -> String {
        guard let first = lines.first else { return "Repas" }
        // Item disparu du catalogue (JSON corrompu, ou retiré depuis) : un nom
        // générique plutôt que l'id technique brut, jamais présentable à l'écran.
        // Distinct de "Repas" (aucune ligne du tout) pour ne pas confondre les deux
        // cas si jamais on doit un jour déboguer un affichage étrange.
        let name = catalog.byID[first.itemID]?.name ?? "Aliment"
        let others = lines.count - 1
        return others > 0 ? "\(name) +\(others)" : name
    }
}
