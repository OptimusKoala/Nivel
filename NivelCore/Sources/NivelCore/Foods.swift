// Catalogue unique des aliments (spec v1.10 §4.1, cinquième catégorie en v1.14 §3.4).
// Remplace Dish et Extra : plats, ingrédients, boissons, encas et desserts ne
// diffèrent plus que par leur catégorie.

import Foundation

public struct FoodItem: Codable, Identifiable, Hashable, Sendable {
    public enum Category: String, Codable, CaseIterable, Sendable {
        case dish, side, drink, snack, dessert

        public var frLabel: String {
            switch self {
            case .dish: "Plats"
            // « Accompagnements » ne tient pas dans cinq pastilles, et la catégorie
            // contient des ingrédients depuis la 1.10 : le libellé rattrape le contenu.
            case .side: "Ingrédients"
            case .drink: "Boissons"
            case .snack: "Encas"
            case .dessert: "Desserts"
            }
        }

        /// Ordre d'affichage (spec v1.14 §3.4) : les desserts en dernier, après les encas.
        /// Explicite et non déduit de `allCases` : un cas inséré au milieu de l'enum
        /// déplacerait les onglets sans que personne ne le demande. Un test vérifie
        /// qu'aucune catégorie n'y manque.
        public static let tabOrder: [Category] = [.dish, .side, .drink, .snack, .dessert]
    }

    public let id: String
    public let name: String
    public let emoji: String
    public let kcalPer100g: Double
    /// Unité naturelle de saisie (« œuf », « c. à soupe »). nil = au gramme.
    public let unitLabel: String?
    /// Pluriel de l'unité, quand il ne s'obtient pas en ajoutant un s (« morceaux »
    /// s'obtient, « c. à soupe » est invariable). nil = ajouter un s.
    public let unitLabelPlural: String?
    /// Poids d'une unité. Non nil si et seulement si `unitLabel` l'est.
    public let unitGrams: Int?
    public let category: Category
    /// Étiquettes libres consultées par les quêtes (spec v1.10 §7.1) : "alcohol",
    /// "richDessert". Vide si l'item n'a rien à dire à une quête. Les ids d'items
    /// changent (v1 → v1.10, ex. beer → beer_half/beer_pint) ; les quêtes lisent
    /// des tags stables plutôt que des ids en dur, qui se seraient tus en silence.
    public let tags: [String]
    /// Créneaux pertinents pour les plats. Vide = proposé partout.
    public let slots: [MealSlot]
    /// Quantité posée au tap dans le catalogue.
    public let defaultGrams: Int

    public var hasUnit: Bool { unitLabel != nil && unitGrams != nil }

    /// « 2 œufs », « 1 c. à soupe », « 80 g ». Les grammes restent la vérité ; l'unité
    /// n'est qu'une commodité d'affichage.
    public func frQuantity(grams: Int) -> String {
        guard let unitLabel, let unitGrams, unitGrams > 0 else { return "\(grams) g" }
        let count = Double(grams) / Double(unitGrams)
        let rounded = (count * 2).rounded() / 2      // au demi près
        // Sous un demi, l'unité mentirait : « 0 c. à soupe » pour 1 g de vinaigrette
        // annonce zéro là où il y a quelque chose. On retombe sur les grammes.
        guard rounded > 0 else { return "\(grams) g" }
        let number = rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(rounded).replacingOccurrences(of: ".", with: ",")
        let label = rounded > 1 ? (unitLabelPlural ?? unitLabel + "s") : unitLabel
        return "\(number) \(label)"
    }
}

/// Catalogue chargé une fois, indexé. Les vues et le calcul y lisent leur barème.
public struct FoodCatalog: Sendable {
    public let items: [FoodItem]
    public let byID: [String: FoodItem]
    public let compositions: [String: [MealComponent]]

    public init(items: [FoodItem], byID: [String: FoodItem], compositions: [String: [MealComponent]]) {
        self.items = items
        self.byID = byID
        self.compositions = compositions
    }

    /// Repli si le bundle est corrompu (jamais de crash, comme les autres catalogues
    /// de `GameService`). Un catalogue vide ne matche aucun tag : voir la note sur
    /// `hasTag` avant de s'en servir pour une quête.
    public static let empty = FoodCatalog(items: [], byID: [:], compositions: [:])

    public static func load() throws -> FoodCatalog {
        let items = try Catalogs.foods()
        return FoodCatalog(
            items: items,
            byID: Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }),
            compositions: try Catalogs.compositions()
        )
    }

    public func kcalPer100g(_ itemID: String) -> Double? { byID[itemID]?.kcalPer100g }

    /// Un item du catalogue porte-t-il ce tag (spec §7.1) ? Item inconnu = false,
    /// même repli que `kcalPer100g` : un JSON corrompu ne doit pas planter une quête.
    public func hasTag(_ tag: String, itemID: String) -> Bool {
        byID[itemID]?.tags.contains(tag) ?? false
    }

    public func items(category: FoodItem.Category, slot: MealSlot?) -> [FoodItem] {
        items.filter { item in
            guard item.category == category else { return false }
            guard let slot, !item.slots.isEmpty else { return true }
            return item.slots.contains(slot)
        }
    }

    /// La ligne posée au tap : composée si le plat a une composition, simple sinon.
    public func line(for item: FoodItem) -> MealLine {
        if let composition = compositions[item.id], !composition.isEmpty {
            return .composed(itemID: item.id, components: composition)
        }
        return .simple(MealComponent(itemID: item.id, grams: item.defaultGrams))
    }
}
