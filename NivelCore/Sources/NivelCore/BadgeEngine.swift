import Foundation

public struct Badge: Codable, Identifiable, Hashable, Sendable {
    public enum Metric: String, Codable, Sendable {
        case weighIns, mealsLogged, journalDays, stepsInOneDay, totalSteps,
             totalKm, level, questsCompleted, weekWithinTarget, trendDownFortnight,
             activitiesDone, dailySessionsDone
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
               activitiesDone = 0, dailySessionsDone = 0
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
        }
    }
}

public enum BadgeEngine {
    public static func newlyUnlocked(badges: [Badge], stats: BadgeStats, alreadyUnlocked: Set<String>) -> [Badge] {
        badges.filter { !alreadyUnlocked.contains($0.id) && stats.value(for: $0.metric) >= $0.threshold }
    }
}
