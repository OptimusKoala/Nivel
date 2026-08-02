// Le contenu d'un repas (spec v1.10 §3.2). Un repas est une liste de lignes ; une
// ligne est soit un item seul, soit un plat et sa composition.

import Foundation

/// Un item du catalogue et son poids. TOUJOURS des grammes : l'unité affichée
/// (« 1 œuf », « 1 c. à soupe ») vient du catalogue au moment du rendu, jamais de la
/// base, sinon corriger le poids d'un œuf fausserait les repas déjà loggés.
public struct MealComponent: Codable, Equatable, Hashable, Sendable {
    public let itemID: String
    public let grams: Int
    public init(itemID: String, grams: Int) {
        self.itemID = itemID
        self.grams = grams
    }
}

/// Un enum et non une struct à `components` optionnel : une ligne composée porterait
/// sinon un poids propre qui ne veut rien dire et que le calcul ignorerait en silence.
/// Borne aussi la profondeur à un niveau par construction.
public enum MealLine: Codable, Equatable, Hashable, Sendable {
    case simple(MealComponent)
    case composed(itemID: String, components: [MealComponent])

    /// Ce que la ligne représente au catalogue, quelle que soit sa forme.
    public var itemID: String {
        switch self {
        case .simple(let component): component.itemID
        case .composed(let itemID, _): itemID
        }
    }

    /// Les composants à sommer. Une ligne simple est son propre unique composant.
    public var components: [MealComponent] {
        switch self {
        case .simple(let component): [component]
        case .composed(_, let components): components
        }
    }

    public var isComposed: Bool {
        if case .composed = self { true } else { false }
    }
}

/// Raccourci de saisie, PAS un état persisté (spec §2) : taper une portion réécrit
/// les grammes une bonne fois. Rien ne multiplie donc quoi que ce soit après coup.
public enum MealPortion: String, CaseIterable, Sendable {
    case light, normal, hearty

    public var multiplier: Double {
        switch self {
        case .light: 0.7
        case .normal: 1.0
        case .hearty: 1.3
        }
    }

    public var frLabel: String {
        switch self {
        case .light: "Léger"
        case .normal: "Normal"
        case .hearty: "Copieux"
        }
    }

    /// Plancher à 1 g : une noisette de beurre en léger reste une noisette, pas rien.
    public func applied(to components: [MealComponent]) -> [MealComponent] {
        components.map {
            MealComponent(itemID: $0.itemID,
                          grams: max(1, Int((Double($0.grams) * multiplier).rounded())))
        }
    }

    /// Cran correspondant à des grammes donnés, ou nil si l'utilisateur a ajusté à la
    /// main. La portion n'étant pas persistée, c'est ainsi que le panier retrouve son
    /// libellé. Comparaison sur la composition ENTIÈRE : retirer un ingrédient suffit
    /// à sortir des crans, même si les autres quantités collent encore.
    public static func matching(components: [MealComponent],
                                defaults: [MealComponent]) -> MealPortion? {
        guard !defaults.isEmpty else { return nil }
        return allCases.first { $0.applied(to: defaults) == components }
    }
}
