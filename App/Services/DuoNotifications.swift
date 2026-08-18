// App/Services/DuoNotifications.swift
// Les petites décisions locales du duo : le nom du partenaire dans la bulle, l'état de
// l'autorisation système et le tri des cœurs déjà vus. L'alerte elle-même est désormais
// composée par la souscription CloudKit dans `DuoService`, pour rester visible même si
// l'app n'est pas en mémoire.

import Foundation
import UserNotifications

@MainActor
enum DuoNotifications {

    /// Comment on NOMME le partenaire quand on ne connaît pas encore son prénom : il a aimé
    /// avant que son instantané n'arrive, ce qui est le cas normal des premières secondes
    /// d'un duo. Ne jamais laisser la bulle retomber sur le prénom du profil local.
    nonisolated static func partnerDisplayName(_ partner: String?) -> String {
        guard let partner, !partner.trimmingCharacters(in: .whitespaces).isEmpty
        else { return "Ton duo" }
        return partner
    }

    /// L'autorisation système laisse-t-elle passer une alerte CloudKit ? La section Duo des
    /// Réglages consulte cette règle avant d'afficher l'interrupteur, afin de ne pas promettre
    /// des alertes que le système retiendrait.
    ///
    /// `.provisional` compte : une notification provisoire est livrée discrètement, sans son
    /// ni bandeau, mais elle est livrée. `.ephemeral` ne concerne que les App Clips.
    nonisolated static func systemAllows(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional
    }

    /// L'autorisation système, telle qu'elle est en ce moment. Elle se lit de façon
    /// asynchrone, d'où cet accès unique consulté à l'apparition de la section Duo et au
    /// retour des réglages système.
    static func systemStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Les cœurs qu'on n'a pas encore rangés comme lus. Un push peut être réémis ou arriver
    /// avec d'autres changements ; ce tri garantit que le compteur ne double jamais.
    nonisolated static func unseen(_ likes: [DuoLike], knownEventIDs: Set<String>) -> [DuoLike] {
        likes.filter { !knownEventIDs.contains($0.eventID) }
    }
}
