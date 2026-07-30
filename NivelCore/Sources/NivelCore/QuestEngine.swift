import Foundation

public struct Quest: Codable, Identifiable, Hashable, Sendable {
    public enum Metric: String, Codable, Sendable {
        case mealsLogged, weeklySteps, weighIns,
             daysWithinTarget, daysWithoutAlcohol, lightDessertDays, stepGoalDays,
             activitiesDone, dailySessionsDone
    }
    public let id: String
    public let title: String
    public let emoji: String
    public let metric: Metric
    public let target: Int
    public let requiresSteps: Bool
    public let slot: MealSlot?
}

public enum QuestEngine {
    /// "AAAA-Wnn" — semaine ISO 8601 ; le renouvellement du lundi découle du changement de weekID (spec §7.3, §9).
    public static func weekID(for date: Date, calendar: Calendar) -> String {
        let week = calendar.component(.weekOfYear, from: date)
        let year = calendar.component(.yearForWeekOfYear, from: date)
        return "\(year)-W\(week)"
    }

    /// Tirage déterministe (seedé par weekID) de 3 quêtes du pool, sans HealthKit → sans quêtes de pas.
    /// ⚠️ Repose sur le comportement de `Array.shuffled(using:)`, un détail d'implémentation de la
    /// stdlib non contractuel : s'il change entre versions de Swift, les tirages pour un même weekID
    /// changeraient silencieusement. Voir le test de régression `testWeeklyDrawIsPinnedForKnownWeek`.
    public static func weeklyDraw(pool: [Quest], weekID: String, stepsAvailable: Bool) -> [Quest] {
        let eligible = pool.filter { stepsAvailable || !$0.requiresSteps }
        var generator = SeededGenerator(seed: fnv1a(weekID))
        return Array(eligible.shuffled(using: &generator).prefix(3))
    }

    /// Hash stable inter-lancements (String.hashValue ne l'est PAS).
    static func fnv1a(_ s: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return hash
    }
}

/// PRNG déterministe (SplitMix64) — hashValue de String n'est PAS stable entre lancements,
/// donc seed = FNV-1a du weekID, pas hashValue :
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
