// NivelTests/DuoNotificationsTests.swift
// Le réveil silencieux et la notification locale d'un cœur (spec 1.15 §3.7).
//
// L'abonnement de zone et le réveil lui-même ne se prouvent que sur deux vrais iPhones.
// Ce qui suit éprouve tout le reste, c'est-à-dire toutes les décisions : le texte, le
// filtrage, l'interrupteur, et le jeton de changement expiré.

import XCTest
import CloudKit
import NivelCore
@testable import Nivel

final class DuoNotificationTextTests: XCTestCase {

    private func coeur(event: String, titre: String = "Poisson et purée maison") -> DuoLike {
        DuoLike(giverID: "TOI", ownerID: "MOI", eventID: event, eventTitle: titre,
                createdAt: Date(timeIntervalSince1970: 500))
    }

    /// Le titre est une phrase de la banque, contexte `duoLikeReceived`, avec le prénom du
    /// PARTENAIRE en `{name}`. Les mêmes douze phrases serviront à la bulle de l'accueil :
    /// un cœur reçu ne dit jamais deux fois la même chose.
    func testLeTitreEstUnePhraseDeLaBanqueAuNomDuPartenaire() throws {
        let bank = try MessageBank.load()

        let titre = DuoNotifications.title(partner: "Marion", bank: bank)

        XCTAssertTrue(titre.contains("Marion"), titre)
        XCTAssertFalse(titre.contains("{name}"), "la substitution doit être faite")
        XCTAssertFalse(titre.isEmpty)
    }

    /// Banque illisible : on dit quand même quelque chose. Un bundle corrompu ne doit pas
    /// transformer un cœur reçu en notification vide.
    func testSansBanqueLeTitreResteUnePhrase() {
        let titre = DuoNotifications.title(partner: "Marion", bank: nil)

        XCTAssertTrue(titre.contains("Marion"), titre)
        XCTAssertFalse(titre.contains("{name}"))
    }

    /// Partenaire encore inconnu (il a aimé avant d'avoir publié) : pas de blanc, pas de
    /// « nil », une tournure qui tient debout.
    func testUnPartenaireSansNomNeLaissePasDeBlanc() {
        let titre = DuoNotifications.title(partner: nil, bank: nil)

        XCTAssertFalse(titre.isEmpty)
        XCTAssertFalse(titre.hasPrefix(" "), "un nom vide laisserait la phrase commencer par un blanc")
        for fuite in ["nil", "Optional", "{name}", "  "] {
            XCTAssertFalse(titre.contains(fuite), titre)
        }
    }

    /// Le corps est le libellé de l'événement, tel que publié. Il est recopié dans
    /// l'enregistrement du cœur (§3.3) précisément pour que ce texte n'exige aucune
    /// relecture du fil : au réveil, on n'a peut-être rien d'autre sous la main.
    func testLeCorpsEstLeLibelleDeLEvenementAime() {
        XCTAssertEqual(DuoNotifications.body(for: [coeur(event: "E1")]),
                       "Poisson et purée maison")
    }

    /// Deux cœurs arrivés dans le même réveil : une seule notification, qui les compte.
    /// En poster deux ferait vibrer deux fois pour un même geste.
    func testDeuxCoeursArrivesEnsembleNeFontQuUneNotification() {
        let texte = DuoNotifications.body(for: [coeur(event: "E1"),
                                                coeur(event: "E2", titre: "Vélo tranquille")])

        XCTAssertEqual(texte, "2 moments de ta journée")
    }

    /// Un cœur dont le titre n'a pas voyagé reste annonçable : le titre de la notification
    /// porte déjà l'essentiel, et se taire serait pire.
    func testUnCoeurSansLibelleResteAnnoncable() {
        let texte = DuoNotifications.body(for: [coeur(event: "E1", titre: "")])

        XCTAssertFalse(texte.isEmpty)
        XCTAssertFalse(texte.contains("—"))
    }

    // MARK: - Notifier, ou se taire

    /// L'interrupteur « Cœurs reçus » des réglages coupe la notification, et rien d'autre :
    /// l'appairage et la publication continuent (§3.7).
    func testAucuneNotificationSansNouveauteOuInterrupteurCoupe() {
        XCTAssertTrue(DuoNotifications.shouldNotify(newLikes: 1, enabled: true))
        XCTAssertFalse(DuoNotifications.shouldNotify(newLikes: 0, enabled: true))
        XCTAssertFalse(DuoNotifications.shouldNotify(newLikes: 1, enabled: false))
        XCTAssertFalse(DuoNotifications.shouldNotify(newLikes: 0, enabled: false))
    }

    /// Un cœur déjà connu ne se réannonce pas. Le réveil rend les enregistrements CHANGÉS,
    /// et un cœur peut revenir dans un lot pour une raison qui ne nous regarde pas : sans
    /// ce tri, le téléphone sonnerait deux fois pour le même geste.
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
