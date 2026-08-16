// NivelCore/Sources/NivelCore/DuoLikeID.swift
// Le nom d'enregistrement d'un cœur (spec 1.15 §3.3).

import Foundation

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
}
