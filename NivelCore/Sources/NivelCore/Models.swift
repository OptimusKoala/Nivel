import Foundation

public enum Sex: String, Codable, CaseIterable, Sendable {
    case male, female
}

public enum ActivityLevel: String, Codable, CaseIterable, Sendable {
    case sedentary, light, moderate, active

    public var factor: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.375
        case .moderate: 1.55
        case .active: 1.725
        }
    }
}

public enum MealSlot: String, Codable, CaseIterable, Sendable {
    case breakfast, lunch, dinner, snack

    /// Créneau pré-rempli d'après l'heure (spec §4.2) :
    /// avant 11 h = petit-déj, 11-15 h = déjeuner, après 18 h = dîner, sinon encas.
    public static func suggested(forHour hour: Int) -> MealSlot {
        switch hour {
        case ..<11: .breakfast
        case 11..<15: .lunch
        case 18...: .dinner
        default: .snack
        }
    }

    /// Le créneau nommé en forme naturelle MINUSCULE, pour tomber en milieu de phrase :
    /// « déjeuner, ~ 420 kcal » dans le sous-titre d'un événement du duo (spec 1.15
    /// §3.4). C'est la seule forme atteignable depuis NivelCore, et il en faut une ici
    /// parce que ce texte est composé à la PUBLICATION, chez celui qui a le catalogue,
    /// et non à l'affichage chez le partenaire.
    ///
    /// Il existe donc trois formes du même créneau, et ce n'est pas une duplication à
    /// nettoyer : `MealLogSheet` en garde deux, une courte pour les pastilles
    /// (« Petit-déj », qui doit tenir dans peu de place) et une longue capitalisée pour
    /// les titres (« Petit-déjeuner »). Les faire dériver l'une de l'autre changerait du
    /// texte déjà affiché, ce que personne n'a demandé. Elles répondent à trois
    /// contraintes typographiques différentes, pas à un oubli de factorisation.
    public var frLabel: String {
        switch self {
        case .breakfast: "petit-déjeuner"
        case .lunch: "déjeuner"
        case .dinner: "dîner"
        case .snack: "encas"
        }
    }
}
