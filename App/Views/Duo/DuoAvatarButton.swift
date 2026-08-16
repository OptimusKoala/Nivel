// App/Views/Duo/DuoAvatarButton.swift
// Le bouton du duo dans l'en-tête de l'accueil (spec 1.15 §3.9) : l'avatar du partenaire,
// cerclé de bordeaux comme Nivelito, avec sa pastille de nouveauté.
//
// **Il n'existe que s'il y a un duo.** Sans partenaire, l'appelant ne le construit pas du
// tout : pas de bouton grisé, pas d'état vide à dessiner, et l'en-tête de quelqu'un qui ne
// veut pas de duo reste exactement celui de la 1.14 (§3.11, aucune découverte imposée).

import SwiftUI
import NivelCore

struct DuoAvatarButton: View {
    /// Le sexe publié par le partenaire, brut : c'est lui qui choisit l'illustration.
    let sexRaw: String
    /// Son prénom, pour le libellé lu à voix haute. `nil` tant qu'il n'a pas publié.
    let partnerName: String?
    /// Un événement de son fil est postérieur à ma dernière visite de sa page. La décision
    /// vit dans `DuoBadge.hasNewActivity` (NivelCore, lot A1) et arrive déjà prise.
    let hasNews: Bool
    let action: () -> Void

    /// 34 pt, la taille arrêtée sur maquette. La zone de tap, elle, est portée à 44 pt par
    /// le `frame` ci-dessous : un bouton rond de 34 pt est trop petit pour un pouce, et
    /// c'est le minimum recommandé par Apple.
    static let diameter: CGFloat = 34

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(decorative: Self.assetName(sexRaw: sexRaw))
                    .resizable()
                    .scaledToFit()
                    .frame(width: Self.diameter, height: Self.diameter)
                    .background(Theme.card, in: Circle())
                    // Cerclé de bordeaux comme Nivelito : c'est ce qui dit « une personne »
                    // plutôt qu'« une icône de réglage ».
                    .overlay(Circle().stroke(Theme.accent, lineWidth: 2))

                if hasNews { pastille }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // La pastille n'est jamais une information de COULEUR SEULE : le libellé la dit.
        .accessibilityLabel(Self.accessibilityLabel(partner: partnerName, hasNews: hasNews))
    }

    /// **La seule tache rouge de toute l'app**, et l'exception est raisonnée : c'est la
    /// convention iOS d'un badge, elle ne juge personne et ne commente aucun chiffre de
    /// l'utilisateur. Partout ailleurs la règle fondatrice de la v1 tient, y compris pour le
    /// liseré de la bulle (bordeaux) et pour le cœur des lignes du fil (bordeaux).
    private var pastille: some View {
        Circle()
            .fill(.red)
            .frame(width: 10, height: 10)
            .overlay(Circle().stroke(Theme.background, lineWidth: 2))
            .offset(x: 3, y: -3)
    }

    // MARK: - Décisions

    /// L'illustration du partenaire. Délègue à la page de profil plutôt que de tenir une
    /// seconde table : deux tables finissent toujours par diverger, et un jour l'un des
    /// deux écrans montrerait le mauvais visage.
    static func assetName(sexRaw: String) -> String {
        DuoProfileView.avatarName(sexRaw: sexRaw)
    }

    /// « Profil de Marion, nouveautés ». Sans prénom connu — il a rejoint mais n'a pas
    /// encore publié — la phrase tient quand même debout.
    static func accessibilityLabel(partner: String?, hasNews: Bool) -> String {
        let qui = (partner?.isEmpty == false) ? partner! : "ton duo"
        return hasNews ? "Profil de \(qui), nouveautés" : "Profil de \(qui)"
    }
}
