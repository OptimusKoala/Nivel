import Foundation

public struct Quest: Codable, Identifiable, Hashable, Sendable {
    public enum Metric: String, Codable, Sendable {
        case mealsLogged, weeklySteps, weighIns,
             daysWithinTarget, daysWithoutAlcohol, lightDessertDays, stepGoalDays,
             activitiesDone, dailySessionsDone, postureSessionsDone,
             muscuSessionsDone, burnTargetDays
    }
    public let id: String
    public let title: String
    public let icon: CatalogIcon
    public let metric: Metric
    public let target: Int
    public let requiresSteps: Bool
    public let slot: MealSlot?
    /// Programme posture (spec v1.11 §7.2). DOIT décoder en optionnel avec un défaut à
    /// faux : les entrées existantes de `quests.json` ne portent pas ce champ, et un Bool
    /// non optionnel ferait échouer le décodage de TOUT le catalogue, donc disparaître
    /// les quêtes chez Michaël ET chez Marion. `decodeIfPresent` dans un `init(from:)`
    /// explicite, comme `SessionStep.segments` en v1.5.
    public let requiresPosture: Bool
    /// Programme muscu maison (spec v1.14 §5.7) : miroir exact de `requiresPosture`,
    /// même décodage optionnel par défaut à faux, et pour la même raison — les 21
    /// entrées d'avant la 1.14 ne portent pas ce champ.
    public let requiresMuscu: Bool

    private enum CodingKeys: String, CodingKey {
        case id, title, icon, metric, target, requiresSteps, slot, requiresPosture, requiresMuscu
    }

    public init(id: String, title: String, icon: CatalogIcon, metric: Metric, target: Int,
                requiresSteps: Bool, slot: MealSlot? = nil, requiresPosture: Bool = false,
                requiresMuscu: Bool = false) {
        self.id = id
        self.title = title
        self.icon = icon
        self.metric = metric
        self.target = target
        self.requiresSteps = requiresSteps
        self.slot = slot
        self.requiresPosture = requiresPosture
        self.requiresMuscu = requiresMuscu
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        icon = try container.decode(CatalogIcon.self, forKey: .icon)
        metric = try container.decode(Metric.self, forKey: .metric)
        target = try container.decode(Int.self, forKey: .target)
        requiresSteps = try container.decode(Bool.self, forKey: .requiresSteps)
        slot = try container.decodeIfPresent(MealSlot.self, forKey: .slot)
        requiresPosture = try container.decodeIfPresent(Bool.self, forKey: .requiresPosture) ?? false
        requiresMuscu = try container.decodeIfPresent(Bool.self, forKey: .requiresMuscu) ?? false
    }
}

public enum QuestEngine {
    /// "AAAA-Wnn" — semaine ISO 8601 ; le renouvellement du lundi découle du changement de weekID (spec §7.3, §9).
    public static func weekID(for date: Date, calendar: Calendar) -> String {
        let week = calendar.component(.weekOfYear, from: date)
        let year = calendar.component(.yearForWeekOfYear, from: date)
        return "\(year)-W\(week)"
    }

    /// Tirage déterministe (seedé par weekID) de 3 quêtes du pool, sans HealthKit → sans quêtes de pas,
    /// programme posture éteint → sans quêtes posture, programme muscu éteint → sans quêtes muscu.
    /// ⚠️ Repose sur le comportement de `Array.shuffled(using:)`, un détail d'implémentation de la
    /// stdlib non contractuel : s'il change entre versions de Swift, les tirages pour un même weekID
    /// changeraient silencieusement. Voir le test de régression `testWeeklyDrawIsPinnedForKnownWeek`.
    ///
    /// Deux conséquences du filtre sur le pool ÉLIGIBLE, à ne pas découvrir plus tard (spec v1.11 §7.2) :
    /// - Programme éteint (`postureAvailable: false`) : le pool éligible est identique à celui d'avant
    ///   ce lot, donc **le tirage de Michaël ne change pas d'une quête**. C'est la promesse « rien ne
    ///   bouge chez toi », vérifiée par `testWeeklyDrawIsPinnedForKnownWeek` et
    ///   `testQuetePostureNestTireeQueSiLeProgrammeEstActif`.
    /// - Programme allumé (`postureAvailable: true`) : le pool grandit de trois entrées, donc
    ///   **le tirage de Marion change** pour une semaine donnée par rapport à ce qu'il aurait été sans
    ///   le lot. Ce n'est pas un bug : le tirage n'a jamais été une promesse stable dans le temps, il
    ///   l'est seulement à pool constant.
    ///
    /// `muscuAvailable` est le miroir exact de `postureAvailable`, et les deux drapeaux sont
    /// INDÉPENDANTS : allumer la muscu ne rend pas les quêtes posture tirables (d'où le `&&`, jamais
    /// un `||`). Attention à la portée de la promesse ci-dessus : elle ne vaut que pour les quêtes
    /// À DRAPEAU. La 1.14 ajoute aussi `burn_target_3`, qui n'en porte aucun, donc le pool éligible
    /// de tout le monde passe de 18 à 19 entrées et **les tirages changent, y compris chez Michaël**.
    /// C'est l'effet recherché — une quête pour tout le monde n'a d'intérêt que si elle peut sortir.
    ///
    /// Cas de l'extinction en cours de semaine : si un programme est éteint après le tirage du lundi,
    /// une quête `requiresPosture` ou `requiresMuscu` déjà active peut devenir inatteignable. On ne
    /// fait RIEN de spécial ici : elle reste à sa progression, ne se complète pas, et le lundi suivant
    /// en tire une autre. C'est exactement le comportement d'une quête non finie dans cette app
    /// (spec §7.3) ; la retirer de force serait la seule fois où l'app reprendrait quelque chose.
    /// `weeklyDraw` ne purge donc jamais `activeQuestIDs` a posteriori, il ne fait que décider le
    /// tirage SUIVANT.
    public static func weeklyDraw(pool: [Quest], weekID: String, stepsAvailable: Bool,
                                  postureAvailable: Bool, muscuAvailable: Bool) -> [Quest] {
        let eligible = pool.filter {
            (stepsAvailable || !$0.requiresSteps)
                && (postureAvailable || !$0.requiresPosture)
                && (muscuAvailable || !$0.requiresMuscu)
        }
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
