// NivelCore/Sources/NivelCore/DuoBadge.swift
// La pastille rouge du bouton avatar de l'accueil (spec 1.15 §3.9).

import Foundation

public enum DuoBadge {
    /// La pastille s'allume dès qu'un événement du fil du partenaire est postérieur à
    /// la dernière visite de sa page de profil, et s'éteint à l'ouverture de celle-ci
    /// (c'est l'appelant qui repousse alors `lastSeenAt`).
    ///
    /// Deux cas limites, tranchés ici plutôt que laissés à l'appelant :
    ///
    /// - **jamais visité** (`lastSeenAt == nil`) : tout fil non vide est une nouveauté,
    ///   il n'existe aucune date à quoi le comparer ;
    /// - **jamais visité ET fil vide** : pas de pastille. Autrement elle s'allumerait le
    ///   jour de l'appairage, avant que quiconque ait rien fait, et le tout premier
    ///   signal du duo serait un faux — une pastille qui ment une fois n'est plus
    ///   regardée ensuite.
    ///
    /// La comparaison est STRICTE : un événement horodaté à la seconde exacte de la
    /// visite compte comme vu. Sinon le dernier événement de la page qu'on vient de
    /// fermer rallumerait la pastille aussitôt refermée.
    public static func hasNewActivity(feed: [DuoEvent], lastSeenAt: Date?) -> Bool {
        guard let lastSeenAt else { return !feed.isEmpty }
        return feed.contains { $0.at > lastSeenAt }
    }
}
