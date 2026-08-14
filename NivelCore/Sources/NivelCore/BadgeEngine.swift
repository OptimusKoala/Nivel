import Foundation

public struct Badge: Codable, Identifiable, Hashable, Sendable {
    public enum Metric: String, Codable, Sendable {
        case weighIns, mealsLogged, journalDays, stepsInOneDay, totalSteps,
             totalKm, level, questsCompleted, weekWithinTarget, trendDownFortnight,
             activitiesDone, dailySessionsDone,
             /// Journées clôturées où `DayLog.burnTargetReached` est vrai (spec v1.14 §5.6).
             burnTargetDays,
             /// `ActivityEntry` de `kind == .muscu` — des ENTRÉES, pas des jours distincts,
             /// contrairement à `dailySessionsDone` : deux séances muscu le même jour, ça compte double.
             muscuSessionsDone,
             /// Repas dont au moins une ligne porte un item marqué recette (spec §6.1).
             recipesLogged
    }
    public let id: String
    public let title: String
    public let icon: CatalogIcon
    public let hint: String
    public let metric: Metric
    public let threshold: Int
}

/// Snapshot des compteurs de l'utilisateur — rempli par GameService côté app.
public struct BadgeStats: Sendable {
    public var weighIns = 0, mealsLogged = 0, journalDays = 0, stepsInOneDay = 0,
               totalSteps = 0, totalKm = 0, level = 1, questsCompleted = 0,
               weekWithinTarget = 0, trendDownFortnight = 0,
               activitiesDone = 0, dailySessionsDone = 0,
               burnTargetDays = 0, muscuSessionsDone = 0, recipesLogged = 0
    public init() {}

    func value(for metric: Badge.Metric) -> Int {
        switch metric {
        case .weighIns: weighIns
        case .mealsLogged: mealsLogged
        case .journalDays: journalDays
        case .stepsInOneDay: stepsInOneDay
        case .totalSteps: totalSteps
        case .totalKm: totalKm
        case .level: level
        case .questsCompleted: questsCompleted
        case .weekWithinTarget: weekWithinTarget
        case .trendDownFortnight: trendDownFortnight
        case .activitiesDone: activitiesDone
        case .dailySessionsDone: dailySessionsDone
        case .burnTargetDays: burnTargetDays
        case .muscuSessionsDone: muscuSessionsDone
        case .recipesLogged: recipesLogged
        }
    }
}

public enum BadgeEngine {
    /// Badges franchis à cet instant. Aucun filtre sur la disponibilité de HealthKit, et
    /// surtout PAS sur les trois badges de dépense : sans podomètre, `BurnCalculator`
    /// compte TOUTES les activités validées, marche comprise, aucun doublon n'étant alors
    /// possible (`BurnCalculatorTests.testSansPasToutCompte`). Une course à pied de 45 min
    /// suffit à franchir la cible d'une journée. Les retirer refuserait donc un trophée
    /// mérité, quand l'accueil vient d'afficher l'anneau plein — l'inverse de « pas de
    /// données ≠ échec ». Ne pas re-dériver ce raisonnement à l'envers : la conclusion
    /// contraire a déjà été tirée une fois, en n'ayant compté que les séances guidées.
    ///
    /// ⚠️ `newlyUnlocked` ne rend que des badges absents d'`alreadyUnlocked` : rien ici
    /// ne peut RIEN reprendre. `badgeUnlocks` est un journal, pas un état recalculé
    /// (`testUnBadgeDejaObtenuNestJamaisReprisQuandLaMetriqueRedescend`).
    public static func newlyUnlocked(badges: [Badge], stats: BadgeStats, alreadyUnlocked: Set<String>) -> [Badge] {
        badges.filter { !alreadyUnlocked.contains($0.id) && stats.value(for: $0.metric) >= $0.threshold }
    }
}
