// NivelTests/DuoNotificationsTests.swift
// Les cœurs reçus et leur rattrapage local (spec 1.15 §3.7).
//
// L'alerte distante CloudKit elle-même se vérifie sur deux iPhone réels. Ici restent les
// décisions pures : nom de repli, dédoublonnage et conservation de l'historique.

import XCTest
import CloudKit
import NivelCore
@testable import Nivel

final class DuoNotificationStateTests: XCTestCase {

    private func coeur(event: String, titre: String = "Poisson et purée maison") -> DuoLike {
        DuoLike(giverID: "TOI", ownerID: "MOI", eventID: event, eventTitle: titre,
                createdAt: Date(timeIntervalSince1970: 500))
    }

    /// Le nom de repli ne peut pas dévoiler le prénom du profil local, ni être vide.
    func testLeNomDeRepliNePeutJamaisEtreVideOuLocal() {
        XCTAssertEqual(DuoNotifications.partnerDisplayName(nil), "Ton duo")
        XCTAssertEqual(DuoNotifications.partnerDisplayName(""), "Ton duo")
        XCTAssertEqual(DuoNotifications.partnerDisplayName("   "), "Ton duo")
        XCTAssertEqual(DuoNotifications.partnerDisplayName("Marion"), "Marion")
    }

    /// Un cœur déjà connu ne se recompte pas. Un push peut être réémis ou contenir d'autres
    /// changements ; sans ce tri, la bulle annoncerait plusieurs fois le même geste.
    func testUnCoeurDejaConnuNeSeReannoncePas() {
        let deja = coeur(event: "E1")
        let neuf = coeur(event: "E2")

        let inedits = DuoNotifications.unseen([deja, neuf], knownEventIDs: ["E1"])

        XCTAssertEqual(inedits.map(\.eventID), ["E2"])
    }

    func testSansRienDeConnuToutEstNouveau() {
        XCTAssertEqual(DuoNotifications.unseen([coeur(event: "E1")], knownEventIDs: []).count, 1)
    }

}

// MARK: - Fusionner un delta avec ce qu'on a déjà

/// Un réveil ne rend que ce qui a CHANGÉ depuis le jeton. Tout le reste, qui n'a pas bougé,
/// n'est pas dans le lot — et doit rester à l'écran.
final class DuoLikeMergeTests: XCTestCase {

    private func coeur(_ event: String, a secondes: TimeInterval) -> DuoLike {
        DuoLike(giverID: "TOI", ownerID: "MOI", eventID: event, eventTitle: "Dîner",
                createdAt: Date(timeIntervalSince1970: secondes))
    }

    /// LE piège du delta : écraser la liste par le lot reçu ferait disparaître des journaux
    /// tous les cœurs plus anciens que le dernier jeton, à chaque réveil.
    func testUnDeltaNEffacePasLesCoeursQuIlNeMentionnePas() {
        let ancien = coeur("E1", a: 100)
        let arrivant = coeur("E2", a: 900)

        let fusion = DuoService.merge([ancien], with: [arrivant])

        XCTAssertEqual(fusion.map(\.eventID), ["E1", "E2"])
    }

    /// Un cœur qui revient dans un lot ne se dédouble pas : c'est le même enregistrement,
    /// donc la même identité.
    func testUnCoeurQuiRevientNeSeDedoublePas() {
        let coeur1 = coeur("E1", a: 100)

        XCTAssertEqual(DuoService.merge([coeur1], with: [coeur1]).count, 1)
    }
}

// MARK: - Les cœurs retirés pendant qu'on dormait

/// Un réveil rend aussi des SUPPRESSIONS, et elles étaient ignorées : un cœur repris par son
/// auteur restait affiché sur l'entrée jusqu'à la prochaine lecture complète.
final class DuoExtinguishedLikesTests: XCTestCase {

    func testUnCoeurRetireParLePartenaireSeReconnait() {
        let nom = DuoLikeID.recordName(giver: "TOI", event: "E1")

        XCTAssertEqual(DuoService.extinguishedEventIDs([nom], me: "MOI", partner: "TOI"), ["E1"])
    }

    /// Et un cœur que J'AI retiré depuis l'autre appareil du même duo compte aussi : les
    /// deux donneurs possibles sont connus, on essaie l'un puis l'autre.
    func testUnCoeurQueJAiRetireCompteAussi() {
        let nom = DuoLikeID.recordName(giver: "MOI", event: "E9")

        XCTAssertEqual(DuoService.extinguishedEventIDs([nom], me: "MOI", partner: "TOI"), ["E9"])
    }

    /// Un nom qui ne vient d'aucun des deux est IGNORÉ, jamais interprété : mieux vaut
    /// laisser un cœur de trop à l'écran que d'en éteindre un au hasard.
    func testUnNomEtrangerEstIgnoreEtNonDevine() {
        let nom = DuoLikeID.recordName(giver: "QUELQUUN", event: "E1")

        XCTAssertTrue(DuoService.extinguishedEventIDs([nom], me: "MOI", partner: "TOI").isEmpty)
    }

    /// Partenaire encore inconnu : on sait au moins reconnaître les siens.
    func testSansPartenaireConnuOnReconnaitAuMoinsLesSiens() {
        let mien = DuoLikeID.recordName(giver: "MOI", event: "E1")
        let autre = DuoLikeID.recordName(giver: "TOI", event: "E2")

        XCTAssertEqual(DuoService.extinguishedEventIDs([mien, autre], me: "MOI", partner: nil),
                       ["E1"])
    }
}

// MARK: - L'histoire des cœurs survit à un réveil en arrière-plan

/// **Le défaut critique du lot, et il tient en une phrase** : un réveil silencieux peut
/// relancer l'app DEPUIS RIEN. iOS a repris sa mémoire, le processus redémarre en arrière-
/// plan — cas courant, et tout différent de « tuée depuis le sélecteur », que le §3.7 exclut
/// à juste titre. La liste en mémoire naît alors vide pendant que le disque porte toute
/// l'histoire, et l'écrire par-dessus effaçait tous les cœurs sauf celui qui venait
/// d'arriver.
///
/// Ce test part donc d'un disque GARNI et d'une mémoire VIDE, comme au réveil.
final class DuoLikeHistoryTests: XCTestCase {

    private func coeur(_ event: String) -> DuoLike {
        DuoLike(giverID: "TOI", ownerID: "MOI", eventID: event, eventTitle: "Dîner",
                createdAt: Date(timeIntervalSince1970: 500))
    }

    func testUnReveilNEffacePasLHistoireDesCoeurs() {
        let histoire: Set<String> = ["E1", "E2", "E3", "E4", "E5"]

        let apres = DuoService.mergedEventIDs(known: histoire, incoming: [coeur("E6")],
                                              extinguished: [])

        XCTAssertEqual(Set(apres), ["E1", "E2", "E3", "E4", "E5", "E6"])
    }

    /// Et un cœur retiré par son auteur s'en va, lui : c'est la seule façon de sortir de
    /// cette liste, et elle est explicite.
    func testUnCoeurEteintEstLeSeulQuiSorte() {
        let apres = DuoService.mergedEventIDs(known: ["E1", "E2"], incoming: [],
                                              extinguished: ["E1"])

        XCTAssertEqual(apres, ["E2"])
    }

    /// Un cœur qui arrive et repart dans le même lot ne reste pas : l'extinction est
    /// appliquée en dernier, elle a le dernier mot.
    func testLExtinctionALeDernierMot() {
        let apres = DuoService.mergedEventIDs(known: [], incoming: [coeur("E1")],
                                              extinguished: ["E1"])

        XCTAssertTrue(apres.isEmpty)
    }

    /// Rien de neuf, rien d'éteint : l'histoire ne bouge pas d'un iota.
    func testUnDeltaVideNeChangeRien() {
        XCTAssertEqual(DuoService.mergedEventIDs(known: ["E1", "E2"], incoming: [],
                                                 extinguished: []),
                       ["E1", "E2"])
    }
}

// MARK: - La comptabilité des cœurs non lus

/// Le compteur qui allume la bulle de l'accueil. Il a un défaut de conception derrière lui,
/// trouvé en revue : la lecture complète rangeait les cœurs reçus SANS les compter, si bien
/// qu'un cœur découvert en ouvrant les Réglages devenait « déjà vu » pour le réveil suivant.
/// Ni bulle, ni notification, jamais. Les deux chemins comptent maintenant de la même façon,
/// et cette fonction est le seul endroit où ça se décide.
final class DuoUnreadCountTests: XCTestCase {

    private func coeur(_ event: String) -> DuoLike {
        DuoLike(giverID: "TOI", ownerID: "MOI", eventID: event, eventTitle: "Dîner",
                createdAt: Date(timeIntervalSince1970: 500))
    }

    func testUnCoeurInéditIncrementeLeCompteur() {
        XCTAssertEqual(DuoService.unreadCount(current: 0, known: [], incoming: [coeur("E1")]), 1)
        XCTAssertEqual(DuoService.unreadCount(current: 2, known: ["E1"],
                                              incoming: [coeur("E1"), coeur("E2")]), 3)
    }

    /// Revoir les mêmes cœurs ne compte pas deux fois. C'est ce qui permet aux deux chemins
    /// — lecture complète et réveil — de tourner l'un après l'autre sans doubler le signal.
    func testRevoirLesMemesCoeursNeCompteRien() {
        XCTAssertEqual(DuoService.unreadCount(current: 1, known: ["E1"],
                                              incoming: [coeur("E1")]), 1)
        XCTAssertEqual(DuoService.unreadCount(current: 0, known: ["E1", "E2"],
                                              incoming: [coeur("E1"), coeur("E2")]), 0)
    }

    /// Aucun cœur reçu : le compteur ne bouge pas non plus. Un rafraîchissement à vide ne
    /// doit jamais allumer la bulle.
    func testUnRafraichissementAVideNAllumeRien() {
        XCTAssertEqual(DuoService.unreadCount(current: 0, known: [], incoming: []), 0)
        XCTAssertEqual(DuoService.unreadCount(current: 3, known: [], incoming: []), 3)
    }
}

// MARK: - La lecture paginée et sa troncature

/// La lecture d'une zone est PAGINÉE, et la boucle a deux façons de s'arrêter qui se
/// ressemblaient : le serveur n'a plus rien à dire, ou le plafond de pages est atteint alors
/// qu'il en reste. La première rend une zone complète, la seconde une zone à moitié lue — et
/// l'appelant REMPLACE les listes de cœurs avec ce qu'on lui donne.
///
/// La boucle elle-même demande une base CloudKit qui pagine, et n'est donc éprouvée par
/// rien. Ce qu'elle rend en s'arrêtant, en revanche, est une décision pure.
@MainActor
final class DuoZonePaginationTests: XCTestCase {

    private func deltaGarni() -> DuoService.ZoneDelta {
        var delta = DuoService.ZoneDelta()
        delta.likes = [DuoLike(giverID: "TOI", ownerID: "MOI", eventID: "E1",
                               eventTitle: "Dîner", createdAt: Date(timeIntervalSince1970: 500))]
        delta.deletedLikeRecordNames = ["like-TOI-E0"]
        return delta
    }

    /// Fin normale : le serveur n'a plus rien, le delta part tel quel.
    func testUneLectureAlleeAuBoutRendCeQuElleALu() {
        let rendu = DuoService.stoppedDelta(deltaGarni(), moreComing: false)

        XCTAssertFalse(rendu.failed)
        XCTAssertEqual(rendu.likes.map(\.eventID), ["E1"])
        XCTAssertEqual(rendu.deletedLikeRecordNames, ["like-TOI-E0"])
    }

    /// **Troncature : la lecture est marquée en ÉCHEC, et son contenu jeté.** Sans quoi
    /// l'appelant écrirait un début de zone en le faisant passer pour son tout — c'est-à-dire
    /// exactement le défaut que la pagination vient de fermer, déplacé d'une page à vingt.
    ///
    /// Et il ne suffit pas de compter sur « le tour suivant reprendra au jeton » : une
    /// lecture complète part d'un jeton nil et écrase AVANT que le tour suivant n'existe.
    func testUneLectureTronqueeEchoueEtNEcritRien() {
        let rendu = DuoService.stoppedDelta(deltaGarni(), moreComing: true)

        XCTAssertTrue(rendu.failed, "un delta partiel doit être refusé, pas affiché")
        XCTAssertTrue(rendu.likes.isEmpty, "et son contenu ne doit pas fuir jusqu'à l'appelant")
        XCTAssertTrue(rendu.deletedLikeRecordNames.isEmpty)
    }
}

// MARK: - Le jeton de changement

final class DuoChangeTokenTests: XCTestCase {

    /// Un jeton périmé n'est pas une panne : c'est CloudKit qui demande de repartir d'une
    /// lecture complète. Le confondre avec une erreur ordinaire laisserait l'appareil
    /// coincé sur un jeton mort, à ne plus jamais rien recevoir — en silence, et pour
    /// toujours.
    func testUnJetonExpireFaitRepartirDeZeroEtRienDAutre() {
        XCTAssertTrue(DuoService.shouldRestartFromScratch(error: CKError(.changeTokenExpired)))

        XCTAssertFalse(DuoService.shouldRestartFromScratch(error: CKError(.networkFailure)))
        XCTAssertFalse(DuoService.shouldRestartFromScratch(error: CKError(.zoneNotFound)))
        XCTAssertFalse(DuoService.shouldRestartFromScratch(error: CKError(.notAuthenticated)))
    }
}

// MARK: - Un seul travail de zone à la fois

/// La seule pièce de concurrence du duo, jouée directement.
///
/// Le défaut qu'elle ferme est un entrelacement entre les DEUX chemins : un réveil
/// silencieux qui atterrit pendant une lecture complète voyait celle-ci écraser le cœur
/// qu'il venait d'enregistrer et faire régresser le jeton — donc le cœur revenait au réveil
/// suivant, inconnu, et se faisait notifier une seconde fois.
@MainActor
final class DuoZoneSerializationTests: XCTestCase {

    /// Boîte partagée par les deux travaux : c'est son contenu final qui dit s'ils se sont
    /// coupés la parole.
    @MainActor private final class Journal { var lignes: [String] = [] }

    func testDeuxTravauxDeZoneNeSeCoupentJamaisLaParole() async {
        let domaine = "nivel.tests.duoserial.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domaine)!
        defer { defaults.removePersistentDomain(forName: domaine) }
        let service = DuoService(identity: DuoIdentity(defaults: defaults),
                                 resolveTarget: { _ in nil })
        let journal = Journal()

        // `Task.yield()` au milieu : c'est le point de suspension où deux travaux non
        // sérialisés s'entrelaceraient. Avec le sérialiseur, le second n'a même pas commencé.
        async let premier: Void = service.serialized {
            journal.lignes.append("A début")
            await Task.yield()
            journal.lignes.append("A fin")
        }
        async let second: Void = service.serialized {
            journal.lignes.append("B début")
            await Task.yield()
            journal.lignes.append("B fin")
        }
        _ = await (premier, second)

        // L'ordre entre A et B n'est pas garanti et n'a aucune importance : ce qui compte
        // est qu'un travail ne soit jamais COUPÉ par l'autre. On l'éprouve donc sur
        // l'adjacence, pas sur l'ordre — un test qui exigerait « A puis B » serait un test
        // qui clignote.
        XCTAssertEqual(journal.lignes.count, 4)
        XCTAssertEqual(journal.lignes[0].prefix(1), journal.lignes[1].prefix(1),
                       "le premier travail a été coupé : \(journal.lignes)")
        XCTAssertEqual(journal.lignes[2].prefix(1), journal.lignes[3].prefix(1),
                       "le second travail a été coupé : \(journal.lignes)")
    }
}

// MARK: - Ce que le désappairage emporte

@MainActor
final class DuoWakeStateTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "nivel.tests.duowake.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    /// Le jeton et l'abonnement appartiennent à la ZONE, pas à l'appareil : défaire le duo
    /// doit les emporter. Un jeton survivant ferait repartir un futur duo au milieu de
    /// l'histoire d'un autre, et un abonnement cru posé n'en poserait jamais de nouveau —
    /// donc plus aucun réveil, sans le moindre signe.
    func testLeDesappairageEmporteLeJetonEtLAbonnement() async {
        let identite = DuoIdentity(defaults: defaults)
        identite.createMemberID()
        identite.role = .owner
        identite.zoneChangeToken = Data("un jeton".utf8)
        identite.zoneSubscriptionInstalled = true
        let service = DuoService(identity: identite, resolveTarget: { _ in nil },
                                 makeContainer: { CKContainer(identifier: DuoDatabase.containerID) })

        await service.unpair()

        XCTAssertNil(identite.zoneChangeToken)
        XCTAssertFalse(identite.zoneSubscriptionInstalled)
        XCTAssertNil(DuoIdentity(defaults: defaults).zoneChangeToken)
    }

    /// Sans duo appairé, un réveil ne fait RIEN : ni requête, ni notification. Le §3.1 vaut
    /// aussi pour un réveil qui arriverait après un désappairage, l'abonnement pouvant
    /// survivre quelques minutes côté serveur.
    func testUnReveilSansDuoNeFaitRien() async {
        var resolutions = 0
        let service = DuoService(identity: DuoIdentity(defaults: defaults),
                                 resolveTarget: { _ in resolutions += 1; return nil },
                                 makeContainer: { CKContainer(identifier: DuoDatabase.containerID) })

        let recus = await service.handleRemoteWake()

        XCTAssertEqual(resolutions, 0)
        XCTAssertTrue(recus.isEmpty)
    }
}
