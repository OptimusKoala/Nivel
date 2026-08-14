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
    /// Recette de saison (spec v1.14 §6.1) : un plat comme les autres pour
    /// l'estimation, le panier et le journal, mais masqué des onglets du catalogue.
    /// Sans ce drapeau, l'onglet Plats passerait du simple au double.
    ///
    /// DOIT décoder en optionnel avec un défaut à faux, comme `Quest.requiresPosture` :
    /// les 122 entrées déjà écrites ne portent pas la clé, et un Bool non optionnel
    /// ferait échouer le décodage de TOUT le catalogue — donc disparaître les aliments.
    /// Seules les recettes portent donc `"isRecipe": true` dans `foods.json`, ce qui
    /// les rend en prime repérables d'un `grep`.
    public let isRecipe: Bool

    /// ⚠️ Liste écrite à la main depuis la 1.14 : le compilateur ne réclame plus les
    /// clés manquantes. Une propriété qui porte un défaut sur sa déclaration
    /// (`var seasonal: Bool = false`, la forme courte et spontanée) compile sans
    /// erreur, n'apparaît ni dans `init(from:)` ni dans le memberwise, et se tait :
    /// sa clé JSON est ignorée à la lecture et absente à l'écriture. Tout nouveau
    /// champ s'écrit donc `let` SANS valeur par défaut — alors, et alors seulement,
    /// l'oubli d'une clé ici est une erreur de compilation.
    private enum CodingKeys: String, CodingKey {
        case id, name, emoji, kcalPer100g, unitLabel, unitLabelPlural, unitGrams,
             category, tags, slots, defaultGrams, isRecipe
    }

    public init(id: String, name: String, emoji: String, kcalPer100g: Double,
                unitLabel: String? = nil, unitLabelPlural: String? = nil, unitGrams: Int? = nil,
                category: Category, tags: [String] = [], slots: [MealSlot] = [],
                defaultGrams: Int, isRecipe: Bool = false) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.kcalPer100g = kcalPer100g
        self.unitLabel = unitLabel
        self.unitLabelPlural = unitLabelPlural
        self.unitGrams = unitGrams
        self.category = category
        self.tags = tags
        self.slots = slots
        self.defaultGrams = defaultGrams
        self.isRecipe = isRecipe
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        emoji = try container.decode(String.self, forKey: .emoji)
        kcalPer100g = try container.decode(Double.self, forKey: .kcalPer100g)
        unitLabel = try container.decodeIfPresent(String.self, forKey: .unitLabel)
        unitLabelPlural = try container.decodeIfPresent(String.self, forKey: .unitLabelPlural)
        unitGrams = try container.decodeIfPresent(Int.self, forKey: .unitGrams)
        category = try container.decode(Category.self, forKey: .category)
        tags = try container.decode([String].self, forKey: .tags)
        slots = try container.decode([MealSlot].self, forKey: .slots)
        defaultGrams = try container.decode(Int.self, forKey: .defaultGrams)
        isRecipe = try container.decodeIfPresent(Bool.self, forKey: .isRecipe) ?? false
    }

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
        // DEUX, pas « plus d'un » : en français le pluriel commence à deux, et un
        // nombre décimal en dessous reste au singulier — « 1,5 tranche », jamais
        // « 1,5 tranches ». Le seul cas concerné est le demi-cran entre 1 et 2, mais il
        // se présente sur DIX combinaisons du catalogue — dix couples (plat, ingrédient)
        // dont la quantité tombe sur « 1,5 », le jambon du sandwich et le pain du
        // gaspacho en tête — et sur trois écrans (le panier, le détail d'une ligne, la
        // fiche recette). Défaut de la v1.10, corrigé en 1.14.
        //
        // Dix, pas dix-neuf : dix-neuf est le nombre d'aliments À UNITÉ cités par les
        // compositions, une autre grandeur, et la plupart y tombent sur un compte rond.
        let label = rounded >= 2 ? (unitLabelPlural ?? unitLabel + "s") : unitLabel
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
            // Les recettes auront leur propre porte d'entrée (la bande d'idées,
            // spec v1.14 §6.4) : les laisser ici noierait la grille de taps.
            guard !item.isRecipe else { return false }
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
