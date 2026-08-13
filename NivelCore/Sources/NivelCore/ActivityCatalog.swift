import Foundation

/// Activité physique du catalogue sport (spec sport §3.1) — douce, sans matériel.
public struct Activity: Codable, Identifiable, Hashable, Sendable {
    public enum Location: String, Codable, Sendable { case home, outdoor, both }

    /// Rangement de l'onglet Sport (spec v1.14 §4.1) : le catalogue doux garde sa
    /// place et son rang, l'intense va dans sa propre section, en dernier.
    public enum Intensity: String, Codable, Sendable { case gentle, strong }

    public let id: String
    public let name: String
    public let location: Location
    public let kcalPerMin: Double
    /// Les 3 durées proposées (minutes), croissantes — propres à l'activité
    /// (une planche ne se scale pas comme une marche).
    public let durations: [Int]
    /// Consignes « comment faire » : 3-4 puces courtes (position, mouvement,
    /// repère sécurité/respiration), ton bienveillant (spec illustrations §4.1).
    public let instructions: [String]
    public let intensity: Intensity
    /// Vrai si l'activité produit des PAS déjà comptés par HealthKit. Lu par
    /// `BurnCalculator` (spec v1.14 §5.4) : sans ce drapeau, une marche de 40 min
    /// validée serait comptée deux fois dans l'anneau de dépense.
    public let stepsBased: Bool

    /// Estimation "~ kcal" arrondie à la dizaine — indicative, jamais créditée au budget.
    public func estimatedKcal(minutes: Int) -> Int {
        Int((kcalPerMin * Double(minutes) / 10).rounded()) * 10
    }
}

public struct SessionStep: Codable, Hashable, Sendable {
    public let activityID: String
    public let minutes: Int
    /// Rythme suggéré et petits rappels de forme, affiché en badge dans le player (spec §4.2).
    /// Jamais un programme rigide : une suggestion, pas un chrono.
    public let tempo: String
    /// Nombre de séries affiché en graduations sur l'anneau du timer (spec timer §4).
    /// nil = pas de graduations (tempos en fourchette ou sans séries explicites).
    public let segments: Int?
    public init(activityID: String, minutes: Int, tempo: String, segments: Int? = nil) {
        self.activityID = activityID; self.minutes = minutes; self.tempo = tempo; self.segments = segments
    }
}

/// Séance composée toute faite — la « séance du jour » (spec sport §3.2).
/// Pas de champ d'icône : l'identité visuelle d'une séance est son illustration
/// `Sport/<id>`, et les 31 ids du catalogue en ont toutes une (spec icônes catalogues §2.3).
public struct ActivitySession: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
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
    /// Séance ou exercice du programme posture (spec v1.11 §8) — catalogue cloisonné
    /// (`PostureCatalog`), mais même mécanique de validation que `dailySession`.
    case posture
}
