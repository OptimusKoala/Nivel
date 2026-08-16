// App/Views/Duo/DuoLikeMark.swift
// Le petit cœur reçu, en bout d'une de MES lignes (spec 1.15 §3.8).
//
// Il apparaît dans le journal Repas et dans l'écran Sport, sur les entrées qui ont plu au
// partenaire. C'est là qu'on les relit une fois la bulle de l'accueil passée, et c'est ce
// qui donne son sens à la promesse du §3.10 : un cœur reçu fait partie de l'histoire, pas
// de la connexion — il reste après le désappairage.
//
// Un composant partagé plutôt que deux fois le même `Image` : les deux écrans doivent dire
// la même chose de la même façon, et le libellé lu à voix haute ne doit exister qu'une fois.

import SwiftUI

struct DuoLikeMark: View {

    /// Ce que VoiceOver annonce. Le cœur est décoratif à l'œil — l'information tient dans sa
    /// seule présence — mais sans libellé il n'existerait PAS pour qui ne voit pas l'écran,
    /// et c'est justement une marque d'affection qu'on lui cacherait.
    ///
    /// Aucun compteur, ici comme sur la page du partenaire : à deux, « aimé » suffit (§3.8).
    /// C'est une décision de conception, pas une limite technique, et un test la garde.
    static let label = "Aimé par ton duo"

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 13, weight: .semibold))
            // Bordeaux, jamais rouge : la règle fondatrice de la v1. Seule la pastille de
            // nouveauté du bouton d'accueil y a droit, parce qu'elle suit la convention iOS
            // d'un badge et ne commente aucun chiffre.
            .foregroundStyle(Theme.accent)
            .accessibilityLabel(Self.label)
    }

    /// Cette entrée a-t-elle reçu un cœur ?
    ///
    /// **Un `publicID` vide ne matche rien**, et cette garde n'est pas défensive : les
    /// entrées d'avant la 1.15 naissent sans identifiant, qui n'est rempli qu'à la première
    /// publication (§3.4). Sans elle, un seul identifiant vide qui traînerait dans la liste
    /// allumerait un cœur sur TOUTES les entrées pas encore identifiées d'un coup — sur des
    /// repas que le partenaire n'a jamais vus. C'est le même faux-ami que le `like-G1-` du
    /// lot A1, vu de l'autre bout.
    static func isLiked(publicID: String, likedEventIDs: Set<String>) -> Bool {
        !publicID.isEmpty && likedEventIDs.contains(publicID)
    }
}
