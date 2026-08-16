// NivelCore/Sources/NivelCore/DuoLikeID.swift
// Le nom d'enregistrement d'un cœur (spec 1.15 §3.3).

import Foundation

/// Ce qu'il faut savoir d'un cœur pour décider s'il désigne encore quelque chose.
/// Volontairement pas un `CKRecord` : cette décision est pure et s'éprouve sans nuage,
/// et c'est la seule partie du nettoyage qui puisse l'être.
public struct DuoLikeRef: Equatable, Sendable {
    /// L'événement visé, c'est-à-dire le `publicID` d'une entrée locale de QUELQU'UN.
    public let eventID: String
    /// À qui appartient l'événement aimé.
    public let ownerID: String
    /// Qui a envoyé le cœur. Sert à recomposer le nom d'enregistrement à supprimer.
    public let giverID: String

    public init(eventID: String, ownerID: String, giverID: String) {
        self.eventID = eventID
        self.ownerID = ownerID
        self.giverID = giverID
    }
}

public enum DuoLikeID {
    /// `like-<giverID>-<eventID>`, et ce nom est DÉTERMINISTE par décision, pas par
    /// commodité. C'est ce qui donne au cœur ses deux propriétés :
    ///
    /// - aimer deux fois réécrit le même enregistrement au lieu d'en créer un second,
    ///   donc aucun doublon n'est possible, même si l'écriture part deux fois ;
    /// - retirer un cœur est une SUPPRESSION PAR NOM, sans requête préalable pour
    ///   retrouver l'enregistrement — un aller-retour réseau en moins, et un geste qui
    ///   marche même hors connexion à la lecture.
    ///
    /// Remplacer ceci par un `UUID` ferait tomber les deux d'un coup. Ce n'est pas de la
    /// concaténation gratuite.
    ///
    /// **Précondition, mesurée** : l'absence de collision tient à la LONGUEUR FIXE des
    /// identifiants, pas au format de ce nom. `UUID.uuidString` fait toujours 36
    /// caractères, donc la découpe reste sans ambiguïté malgré les quatre tirets
    /// internes de chaque UUID. Mais sur des chaînes quelconques, « like-A-B-C » se lit
    /// aussi bien (« A », « B-C ») que (« A-B », « C ») : le jour où un identifiant de
    /// longueur variable passerait par ici, deux cœurs distincts se confondraient en
    /// silence. Le cas dégénéré existe déjà — un `publicID` vide, non encore attribué
    /// (§3.4) — et c'est à l'appelant de n'aimer que des événements identifiés.
    public static func recordName(giver: String, event: String) -> String {
        "like-\(giver)-\(event)"
    }

    /// Les `eventID` des cœurs qui ne désignent plus rien, à supprimer à la publication
    /// suivante (spec §3.4).
    ///
    /// **La comparaison porte sur les `publicID` DU MAGASIN, jamais sur le fil publié.**
    /// La première rédaction de cette règle disait « les cœurs dont l'`eventID` n'est
    /// plus dans le fil du jour » — or le fil ne couvre que la journée courante. À la
    /// bascule de minuit, TOUS les cœurs reçus la veille seraient devenus orphelins et
    /// auraient été supprimés, y compris ceux qui s'affichent sur les entrées passées des
    /// journaux Repas et Sport (§3.8). On aurait effacé chaque nuit tout ce que le duo
    /// s'est envoyé la veille. Le fil est sous la main et le magasin demande un fetch de
    /// plus : c'est exactement pourquoi quelqu'un « simplifiera » un jour. Ne pas le
    /// faire.
    ///
    /// **Et seulement mes propres événements** (`ownerID == me`). Un cœur que J'AI DONNÉ
    /// porte l'`ownerID` de l'autre, et son entrée n'est pas dans mon magasin : je le
    /// jugerais donc systématiquement orphelin et je supprimerais, à chaque publication,
    /// tous les cœurs que j'ai envoyés. C'est le magasin de l'autre qui en décide, sur
    /// son appareil.
    public static func orphanEventIDs(likes: [DuoLikeRef],
                                      localPublicIDs: Set<String>,
                                      me: String) -> Set<String> {
        Set(likes.lazy
            .filter { $0.ownerID == me && !localPublicIDs.contains($0.eventID) }
            .map(\.eventID))
    }
}
