// NivelTests/DuoLikeMarkTests.swift
// Les cœurs reçus sur ses PROPRES entrées (spec 1.15 §3.8, §3.10), dans le journal Repas et
// dans l'écran Sport.
//
// C'est là qu'on relit un cœur une fois la bulle passée, et c'est ce qui donne son sens à
// la promesse du §3.10 : ils font partie de l'histoire, pas de la connexion.

import XCTest
import CloudKit
import NivelCore
@testable import Nivel

final class DuoLikeMarkTests: XCTestCase {

    /// Le cas courant, dans les deux sens.
    func testUneEntreeAimeePorteSonCoeurEtUneAutreNon() {
        XCTAssertTrue(DuoLikeMark.isLiked(publicID: "E1", likedEventIDs: ["E1", "E2"]))
        XCTAssertFalse(DuoLikeMark.isLiked(publicID: "E3", likedEventIDs: ["E1", "E2"]))
        XCTAssertFalse(DuoLikeMark.isLiked(publicID: "E1", likedEventIDs: []))
    }

    /// **Un `publicID` vide ne matche RIEN**, même si la liste en contient un.
    ///
    /// C'est le même faux-ami qu'au lot A1, celui qui produisait `like-G1-` : les entrées
    /// d'avant la 1.15 naissent sans identifiant, et il est rempli après coup. Sans cette
    /// garde, un seul cœur mal formé allumerait un cœur sur TOUTES les entrées pas encore
    /// identifiées à la fois — sur des repas que personne n'a jamais vus.
    func testUnIdentifiantVideNeMatcheRienDuTout() {
        XCTAssertFalse(DuoLikeMark.isLiked(publicID: "", likedEventIDs: ["E1"]))
        XCTAssertFalse(DuoLikeMark.isLiked(publicID: "", likedEventIDs: [""]))
        XCTAssertFalse(DuoLikeMark.isLiked(publicID: "", likedEventIDs: []))
    }

    /// Le cœur est décoratif à l'œil, mais ANNONCÉ : sans libellé, il n'existe pas pour qui
    /// ne voit pas l'écran, et c'est précisément une marque d'affection qu'on lui cacherait.
    ///
    /// Aucun compteur, ni ici ni ailleurs : à deux, « aimé » suffit. Un test le pinne parce
    /// que c'est une décision de conception (§3.8), pas une limite technique.
    func testLeCoeurEstAnnonceSansCompteurNiReproche() {
        let texte = DuoLikeMark.label

        XCTAssertFalse(texte.isEmpty)
        XCTAssertFalse(texte.contains("—"))
        XCTAssertNil(texte.rangeOfCharacter(from: .decimalDigits), "aucun compteur : \(texte)")
    }
}

// MARK: - La promesse du §3.10, vue de l'affichage

@MainActor
final class DuoLikeMarkAfterUnpairTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "nivel.tests.duomark.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    /// **Une entrée aimée dont le duo a été défait garde son cœur.** C'est le bout de chaîne
    /// complet : `unpair` ne touche pas aux identifiants reçus, `likedEventIDs` les rend
    /// encore, et la ligne les affiche donc toujours.
    ///
    /// Ce test regarde la chaîne entière exprès. Chacun de ses maillons a déjà le sien, mais
    /// la promesse du §3.10 ne vaut que s'ils tiennent ENSEMBLE, et c'est cette promesse-là
    /// que la première rédaction de la spec annonçait sans que rien ne la porte.
    func testUneEntreeAimeeGardeSonCoeurApresLeDesappairage() async {
        let identite = DuoIdentity(defaults: defaults)
        identite.createMemberID()
        identite.role = .guest
        identite.receivedLikeEventIDs = ["E1"]
        let service = DuoService(identity: identite, resolveTarget: { _ in nil })

        await service.unpair()

        XCTAssertFalse(service.isPaired, "le duo est bien défait")
        XCTAssertTrue(DuoLikeMark.isLiked(publicID: "E1", likedEventIDs: service.likedEventIDs))
        // Et au relancement suivant, sur un service reconstruit depuis le disque.
        let apresRelancement = DuoService(identity: DuoIdentity(defaults: defaults),
                                          resolveTarget: { _ in nil })
        XCTAssertTrue(DuoLikeMark.isLiked(publicID: "E1",
                                          likedEventIDs: apresRelancement.likedEventIDs))
    }
}
