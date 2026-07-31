import Foundation

/// Résumé minimal écrit par l'app dans l'App Group et lu par l'extension widget
/// (spec widgets §4.1). La base SwiftData ne quitte jamais le conteneur de l'app :
/// ce snapshot est la SEULE donnée qui circule.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// Minuit local du jour auquel appartiennent les kcal.
    public let dayKey: Date
    public let kcalEaten: Int
    public let kcalTarget: Int
    public let totalXP: Int
    /// Prénom du profil : substitue `{name}` dans les messages de Nivelito.
    public let userName: String
    /// Id de palette (`ThemePalette.id`) ; id inconnu → Crème côté widget.
    public let themeID: String
    public let generatedAt: Date

    public init(dayKey: Date, kcalEaten: Int, kcalTarget: Int, totalXP: Int,
                userName: String, themeID: String, generatedAt: Date) {
        self.dayKey = dayKey
        self.kcalEaten = kcalEaten
        self.kcalTarget = kcalTarget
        self.totalXP = totalXP
        self.userName = userName
        self.themeID = themeID
        self.generatedAt = generatedAt
    }
}
