// Programme posture (spec v1.11 §4 à §6) : catalogues SÉPARÉS des catalogues sport
// globaux, avec leur propre rotation.
//
// Le cloisonnement n'est pas une préférence de rangement : verser ces entrées dans
// activities.json et sessions.json les afficherait sur les deux téléphones, et surtout
// ferait passer la rotation de la séance du jour de 11 à 16 entrées, donc changerait
// la séance vue chaque jour par tout le monde. La spec sport l'interdit.

import Foundation

public struct PostureCatalog: Sendable {
    public let activities: [Activity]
    public let sessions: [ActivitySession]
    public let byID: [String: Activity]

    public static func load() throws -> PostureCatalog {
        let activities = try Catalogs.postureActivities()
        return PostureCatalog(
            activities: activities,
            sessions: try Catalogs.postureSessions(),
            byID: Dictionary(activities.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        )
    }

    /// Catalogue vide, pour le repli sans crash du service quand un JSON est corrompu.
    public static let empty = PostureCatalog(activities: [], sessions: [], byID: [:])

    /// Séance du soir. Réutilise la rotation générique de la séance du jour, appliquée
    /// au pool posture : même référence fixe, modulo 5.
    public func session(for date: Date, calendar: Calendar) -> ActivitySession? {
        DailySessionPicker.session(for: date, sessions: sessions, calendar: calendar)
    }

    public func kcal(_ session: ActivitySession) -> Int {
        session.estimatedKcal(activitiesByID: byID)
    }
}
