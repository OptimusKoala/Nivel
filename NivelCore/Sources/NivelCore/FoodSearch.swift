// NivelCore/Sources/NivelCore/FoodSearch.swift
// Règle unique de recherche dans le catalogue d'aliments (spec v1.14 §6.3, le champ
// du frigo). Descendue ici plutôt que gardée dans la vue pour deux raisons : elle
// s'éprouve alors sans écran — une vue SwiftUI ne prouve rien de sa casse ni de ses
// accents —, et la bande d'idées de la §6.4 cherchera dans le même catalogue.
//
// Même esprit que ProfileName : deux appelants, une seule décision.

import Foundation

public enum FoodSearch {
    /// Forme comparable d'un texte : accents rabattus, casse ignorée, espaces de tête
    /// et de queue jetés. « creme » doit trouver « Crème fraîche » — sans quoi le champ
    /// ne sert qu'à ceux qui prennent la peine de taper les accents, c'est-à-dire
    /// presque personne sur un clavier iOS.
    ///
    /// Locale FIXE (`fr_FR`) et non `.current` : le rabattage des accents dépend de la
    /// locale, et le résultat ne doit pas changer selon la langue du téléphone alors que
    /// le catalogue, lui, est en français quoi qu'il arrive.
    public static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive],
                     locale: Locale(identifier: "fr_FR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Les items dont le NOM contient la requête, une fois les deux normalisés.
    /// `contains` et non `hasPrefix` : on cherche « fraiche » autant que « creme »,
    /// et un préfixe ferait disparaître la moitié des ingrédients composés.
    /// Requête vide (ou faite d'espaces) = aucun filtre, la liste entière.
    public static func filter(_ items: [FoodItem], query: String) -> [FoodItem] {
        let needle = normalized(query)
        guard !needle.isEmpty else { return items }
        return items.filter { normalized($0.name).contains(needle) }
    }
}
