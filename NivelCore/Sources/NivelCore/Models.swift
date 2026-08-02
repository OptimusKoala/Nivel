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
}
