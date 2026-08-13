// Programme muscu maison (spec v1.14 §4.4) : catalogue de SÉANCES séparé, avec sa
// propre rotation.
//
// Le cloisonnement du fichier n'est pas un rangement : verser ces cinq séances dans
// sessions.json ferait passer la rotation de la séance du jour de 11 à 16 entrées,
// donc changerait la séance vue chaque jour par tout le monde. La spec sport l'interdit.
//
// Différence avec PostureCatalog : pas de catalogue d'exercices propre. Les étapes
// pointent vers le catalogue commun (surtout des activités « Ça pousse », mais aussi
// des douces comme les squats ou la chaise au mur) — dupliquer des exercices
// identiques serait deux vérités pour un même mouvement.
//
// Pas de méthode `kcal` non plus : `GameService.sessionKcal(_:)` fait déjà le calcul
// pour n'importe quelle séance, avec la table d'activités fusionnée du service.

import Foundation

public struct MuscuCatalog: Sendable {
    public let sessions: [ActivitySession]

    public static func load() throws -> MuscuCatalog {
        MuscuCatalog(sessions: try Catalogs.muscuSessions())
    }

    /// Repli sans crash quand le JSON est corrompu, comme les autres catalogues.
    public static let empty = MuscuCatalog(sessions: [])

    /// Même rotation générique que la séance du jour, appliquée au pool muscu.
    public func session(for date: Date, calendar: Calendar) -> ActivitySession? {
        DailySessionPicker.session(for: date, sessions: sessions, calendar: calendar)
    }
}
