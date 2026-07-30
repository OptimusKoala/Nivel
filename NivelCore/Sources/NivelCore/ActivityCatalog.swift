import Foundation

/// Activité physique du catalogue sport (spec sport §3.1) — douce, sans matériel.
public struct Activity: Codable, Identifiable, Hashable, Sendable {
    public enum Location: String, Codable, Sendable { case home, outdoor, both }

    public let id: String
    public let name: String
    public let emoji: String
    public let location: Location
    public let kcalPerMin: Double
    /// Les 3 durées proposées (minutes), croissantes — propres à l'activité
    /// (une planche ne se scale pas comme une marche).
    public let durations: [Int]

    /// Estimation "~ kcal" arrondie à la dizaine — indicative, jamais créditée au budget.
    public func estimatedKcal(minutes: Int) -> Int {
        Int((kcalPerMin * Double(minutes) / 10).rounded()) * 10
    }
}

public struct SessionStep: Codable, Hashable, Sendable {
    public let activityID: String
    public let minutes: Int
    public init(activityID: String, minutes: Int) {
        self.activityID = activityID; self.minutes = minutes
    }
}

/// Séance composée toute faite — la « séance du jour » (spec sport §3.2).
public struct ActivitySession: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let emoji: String
    public let steps: [SessionStep]

    public var totalMinutes: Int { steps.reduce(0) { $0 + $1.minutes } }

    /// Somme des kcal des étapes, arrondie à la dizaine.
    public func estimatedKcal(activitiesByID: [String: Activity]) -> Int {
        let raw = steps.reduce(0.0) {
            $0 + (activitiesByID[$1.activityID]?.kcalPerMin ?? 0) * Double($1.minutes)
        }
        return Int((raw / 10).rounded()) * 10
    }
}

/// Nature d'une validation sport — persistée côté app dans `ActivityEntry.kindRaw`.
public enum ActivityKind: String, Codable, Sendable {
    case activity, dailySession
}
