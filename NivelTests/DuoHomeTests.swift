// NivelTests/DuoHomeTests.swift
// Le duo sur l'accueil (spec 1.15 §3.9) : le bouton d'en-tête, sa pastille, et la bulle
// qui annonce un cœur.
//
// Deux promesses tiennent dans ces tests, et elles sont de nature opposée : sans duo,
// l'accueil est RIGOUREUSEMENT celui de la 1.14 ; avec un duo, le signal du cœur ne prend
// jamais la place d'une récompense en cours.

import XCTest
import NivelCore
@testable import Nivel

final class DuoHomeButtonTests: XCTestCase {

    // Il y avait ici un test de `HomeView.showsDuoButton(hasPartner:)`, retiré avec la
    // fonction. Elle rendait son argument tel quel, elle était doublée dans l'en-tête par le
    // dépliage de l'optionnel qui décidait réellement, et son test ne pouvait donc pas
    // échouer : il restait vert quoi qu'il arrive à la vue.
    //
    // La promesse « sans duo, l'en-tête est rigoureusement celui de la 1.14 » repose
    // maintenant sur la STRUCTURE — un `if let` sur l'instantané du partenaire — et c'est
    // plus solide qu'une cérémonie qui donnait l'illusion d'être gardée.

    /// La pastille n'est pas une information de couleur seule : le bouton le DIT.
    func testLeBoutonAnnonceLesNouveautesAVoiceOver() {
        XCTAssertEqual(DuoAvatarButton.accessibilityLabel(partner: "Marion", hasNews: true),
                       "Profil de Marion, nouveautés")
        XCTAssertEqual(DuoAvatarButton.accessibilityLabel(partner: "Marion", hasNews: false),
                       "Profil de Marion")
    }

    /// Partenaire pas encore nommé (il a rejoint, il n'a pas encore publié) : le libellé
    /// tient debout quand même, sans blanc ni « nil ».
    func testLeLibelleTientDeboutSansPrenom() {
        let texte = DuoAvatarButton.accessibilityLabel(partner: nil, hasNews: true)

        XCTAssertFalse(texte.isEmpty)
        for fuite in ["nil", "Optional", "  "] {
            XCTAssertFalse(texte.contains(fuite), texte)
        }
        XCTAssertTrue(texte.contains("nouveautés"), texte)
    }

    /// L'avatar du bouton et celui de la page sont LE MÊME choix, pas deux tables à faire
    /// diverger : le bouton délègue à la décision déjà éprouvée de la page.
    func testLAvatarDuBoutonEstCeluiDeLaPage() {
        XCTAssertEqual(DuoAvatarButton.assetName(sexRaw: "female"),
                       DuoProfileView.avatarName(sexRaw: "female"))
        XCTAssertEqual(DuoAvatarButton.assetName(sexRaw: "male"),
                       DuoProfileView.avatarName(sexRaw: "male"))
    }
}

final class DuoHomeBubbleTests: XCTestCase {

    /// Un cœur n'interrompt PAS une récompense : Nivelito ne coupe pas un « +20 XP » pour
    /// annoncer un cœur. Même famille de décision que le reste de `bubbleDecision`, étendue
    /// et non doublée — un second mécanisme à côté aurait fini par se contredire.
    func testUnCoeurNInterromptPasUneRecompense() {
        XCTAssertEqual(
            HomeView.bubbleDecision(mealXP: 20, activityXP: nil, unreadDuoLikes: 1,
                                    fallback: .midday, fallbackValue: nil),
            .reward(.afterMealLog, 20))
        XCTAssertEqual(
            HomeView.bubbleDecision(mealXP: nil, activityXP: 30, unreadDuoLikes: 1,
                                    fallback: .midday, fallbackValue: nil),
            .reward(.afterActivity, 30))
    }

    /// Mais il prime sur l'humeur horaire : un cœur reçu vaut mieux qu'un « bonne
    /// après-midi », et c'est le rattrapage promis par le §3.7 quand la notification n'est
    /// pas passée.
    func testUnCoeurPrimeSurLaBulleDHumeur() {
        XCTAssertEqual(
            HomeView.bubbleDecision(mealXP: nil, activityXP: nil, unreadDuoLikes: 1,
                                    fallback: .midday, fallbackValue: nil),
            .duoLike)
    }

    /// Sans cœur non lu, rien ne change : c'est la bulle de la 1.14, au mot près.
    func testSansCoeurNonLuLaBulleEstCelleDAvant() {
        XCTAssertEqual(
            HomeView.bubbleDecision(mealXP: nil, activityXP: nil, unreadDuoLikes: 0,
                                    fallback: .midday, fallbackValue: nil),
            .context(.midday, nil))
    }

    /// **La bulle ne dit JAMAIS ton propre prénom.** Sans repli, le prénom optionnel du
    /// partenaire descend dans `nivelitoSays`, qui retombe sur celui du PROFIL : la bulle
    /// annonçait à Michaël que Michaël avait aimé sa journée. Défaut trouvé en revue.
    ///
    /// Le test pinne aussi que les deux surfaces du §3.7 — la bulle et la notification —
    /// nomment le partenaire de la même façon, puisqu'elles passent par la même fonction.
    func testLaBulleNeDitJamaisTonPropreNom() {
        XCTAssertEqual(HomeView.duoBubbleName(partner: nil), "Ton duo")
        XCTAssertEqual(HomeView.duoBubbleName(partner: ""), "Ton duo")
        XCTAssertEqual(HomeView.duoBubbleName(partner: "   "), "Ton duo")
        XCTAssertEqual(HomeView.duoBubbleName(partner: "Marion"), "Marion")

        XCTAssertTrue(DuoNotifications.title(partner: nil, bank: nil)
            .contains(HomeView.duoBubbleName(partner: nil)),
                      "la notification et la bulle nomment le partenaire pareil")
    }

    /// Reduce Motion coupe le BATTEMENT, jamais le liseré : c'est le liseré qui porte
    /// l'information, l'animation n'est qu'un renfort (convention posée en v1.2).
    func testReduceMotionCoupeLeBattementPasLeLisere() {
        XCTAssertFalse(HomeView.heartBeats(reduceMotion: true))
        XCTAssertTrue(HomeView.heartBeats(reduceMotion: false))
    }

    /// Le nom de l'événement s'affiche SOUS le message, pas dedans : le message est une des
    /// douze phrases de la banque, et y coudre un libellé de repas en ferait une treizième
    /// que personne n'a relue.
    func testLeNomDeLEvenementVitSousLeMessageEtPasDedans() {
        XCTAssertEqual(HomeView.duoBubbleDetail(eventTitle: "Poisson et purée maison"),
                       "Poisson et purée maison")
        XCTAssertNil(HomeView.duoBubbleDetail(eventTitle: ""))
        XCTAssertNil(HomeView.duoBubbleDetail(eventTitle: nil))
    }
}
