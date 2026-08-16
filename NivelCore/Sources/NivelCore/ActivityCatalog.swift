import Foundation

/// Activité physique du catalogue sport (spec sport §3.1) — douce, sans matériel.
public struct Activity: Codable, Identifiable, Hashable, Sendable {
    public enum Location: String, Codable, Sendable { case home, outdoor, both }

    /// Rangement de l'onglet Sport : le catalogue doux garde sa place et son rang,
    /// l'intense va dans sa propre section, en dernier. Le champ est posé en spec
    /// v1.14 §4.1, le rangement qu'il commande est décrit en §4.3.
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
/// `Sport/<id>`, et chaque id des catalogues sport en a une (spec icônes catalogues §2.3).
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
    /// Séance du programme muscu maison (spec v1.14 §4.4) — catalogue de séances à part
    /// (`MuscuCatalog`), mais dont les étapes pointent vers le catalogue commun :
    /// surtout des activités « Ça pousse », et aussi des douces comme les squats ou la
    /// chaise au mur. Plafond XP INDÉPENDANT (§5.7) : `XPAction.muscuSessionDone`.
    ///
    /// Comme pour `.posture`, `SportView.doneRow` doit chercher le titre dans
    /// `MuscuCatalog` : passer par le catalogue d'activités retomberait en silence sur
    /// l'identifiant brut, sans qu'aucun test ne s'en plaigne.
    case muscu
}

/// Le découpage de l'onglet Sport (spec v1.14 §4.3), en un seul endroit : deux vues
/// affichent les mêmes sections (`SportView` et `ActivityPickerSheet`) et elles ne
/// doivent pas pouvoir diverger. Pas seulement sur l'appartenance : le libellé,
/// l'icône, l'ordre et la simple PRÉSENCE d'une section viennent d'ici aussi, sans
/// quoi les vues peuvent encore se contredire en silence — une section perdue dans un
/// merge ne casserait aucun test.
public enum SportSection: String, CaseIterable, Sendable {
    case gentleHome, gentleOutdoor, strong

    /// Ordre d'affichage (spec v1.14 §4.3) : le doux d'abord, il reste le chemin par
    /// défaut ; l'intense en dernier, un pas qu'on descend chercher. Explicite et non
    /// déduit de `allCases` : un cas inséré au milieu de l'enum réordonnerait l'écran
    /// sans que personne ne le demande. Un test vérifie qu'aucune section n'y manque.
    public static let displayOrder: [SportSection] = [.gentleHome, .gentleOutdoor, .strong]

    public var frLabel: String {
        switch self {
        case .gentleHome: "À la maison"
        case .gentleOutdoor: "Dehors"
        case .strong: "Ça pousse"
        }
    }

    /// Glyphe cozy de l'en-tête. Un test de la cible app le résout contre les assets
    /// réels : une faute de frappe ici n'afficherait rien du tout, sans un bruit.
    public var icon: String {
        switch self {
        case .gentleHome: "tab_home"
        case .gentleOutdoor: "icon_tree"
        case .strong: "icon_flame"
        }
    }

    /// Les activités de la section. Les trois COUVRENT le catalogue, mais ne le
    /// partitionnent pas : depuis la 1.15 §5.2, une activité `.both` est montrée dans
    /// les DEUX listes douces, et c'est le seul recouvrement qui existe (« Ça pousse »
    /// ignore `location`, donc elle ne croise ni l'une ni l'autre).
    ///
    /// Les deux filtres doux se lisent en négatif, et c'est volontaire : chacun exclut
    /// le lieu qui n'est pas le sien plutôt que d'exiger le sien, de sorte que `.both`
    /// passe des deux côtés. Écrire « Dehors » en `== .outdoor` — ce qu'il était
    /// jusqu'ici — revient à dire que `.both` signifie « chez soi », et cachait les
    /// montées d'escaliers de cette section depuis la v1. La piscine et le ping-pong
    /// auraient hérité du même sort : on y va aussi bien chez soi que chez des amis.
    ///
    /// Un même id peut donc apparaître dans deux sections. Les vues n'en souffrent pas :
    /// `SportView` et `ActivityPickerSheet` font une `ForEach` PAR section, donc les
    /// identités restent uniques à l'intérieur de chaque liste.
    public func activities(in activities: [Activity]) -> [Activity] {
        switch self {
        case .gentleHome: activities.filter { $0.intensity == .gentle && $0.location != .outdoor }
        case .gentleOutdoor: activities.filter { $0.intensity == .gentle && $0.location != .home }
        case .strong: activities.filter { $0.intensity == .strong }
        }
    }
}
