// Catalogue unique des aliments (spec v1.10 §4.1). Remplace Dish et Extra : plats,
// accompagnements, boissons et encas ne diffèrent plus que par leur catégorie.

import Foundation

public struct FoodItem: Codable, Identifiable, Hashable, Sendable {
    public enum Category: String, Codable, CaseIterable, Sendable {
        case dish, side, drink, snack

        public var frLabel: String {
            switch self {
            case .dish: "Plats"
            case .side: "Accompagnements"
            case .drink: "Boissons"
            case .snack: "Encas"
            }
        }
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

    public static func load() throws -> FoodCatalog {
        let items = try Catalogs.foods()
        return FoodCatalog(
            items: items,
            byID: Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }),
            compositions: try Catalogs.compositions()
        )
    }

    public func kcalPer100g(_ itemID: String) -> Double? { byID[itemID]?.kcalPer100g }

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
