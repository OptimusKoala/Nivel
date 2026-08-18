// NivelTests/DuoPairingTests.swift
// L'appairage du duo (spec 1.15 §3.6) : ce qu'il en reste d'éprouvable.
//
// Créer une zone, la partager et accepter une invitation demandent deux comptes iCloud,
// que ni le simulateur ni la CI ne savent jouer. Ce qui suit tient donc sur trois choses
// qui, elles, se décident hors ligne : le rendu du QR code, le texte montré quand ça rate,
// et les gardes qui évitent une requête inutile.

import XCTest
import CloudKit
import NivelCore
@testable import Nivel

// MARK: - Le QR code

final class DuoQRCodeTests: XCTestCase {

    /// Une URL de partage typique donne bien une image.
    func testUneURLDePartageDonneUnQRCode() {
        let image = DuoQRCode.image(from: "https://www.icloud.com/share/0aB1cD2eF3gH4iJ5kL6mN7oP8")

        XCTAssertNotNil(image)
    }

    /// Rien à encoder, rien à afficher. La chaîne vide est le cas réel : `shareURL` est nil
    /// tant que le partage n'a pas été créé, et un carré noir vide se ferait scanner sans
    /// jamais rien donner.
    func testRienAEncoderNeDonneAucuneImage() {
        XCTAssertNil(DuoQRCode.image(from: ""))
        XCTAssertNil(DuoQRCode.image(from: "   \n "))
    }

    /// Le QR est agrandi AVANT d'être rendu, et c'est tout l'intérêt de passer par une
    /// image plutôt que par le filtre nu : `CIFilter.qrCodeGenerator` sort un carré d'une
    /// vingtaine de pixels de côté. Étiré par SwiftUI, il devient un flou gris que la
    /// caméra d'en face ne lit pas — et l'appairage échoue sans que rien ne dise pourquoi.
    func testLeQRCodeEstRenduAssezGrandPourEtreScanne() throws {
        let image = try XCTUnwrap(
            DuoQRCode.image(from: "https://www.icloud.com/share/0aB1cD2eF3gH4iJ5kL6mN7oP8"))

        XCTAssertGreaterThanOrEqual(image.size.width, 200)
        XCTAssertEqual(image.size.width, image.size.height, "un QR code est carré")
    }
}

// MARK: - Ce qu'on dit quand ça rate

/// Aucune erreur de duo n'interrompt l'utilisateur par une alerte : elle se raconte dans
/// l'écran d'appairage. Encore faut-il qu'elle soit lisible, et qu'elle dise la suite à
/// donner quand il y en a une (spec §3.10).
final class DuoPairingMessageTests: XCTestCase {

    /// Pas de compte iCloud : le cas est prévu par la spec, et c'est le seul où
    /// l'utilisateur a quelque chose à faire ailleurs. Le message le nomme.
    func testSansCompteICloudLeMessageLeDit() {
        let texte = DuoService.message(for: CKError(.notAuthenticated))

        XCTAssertTrue(texte.contains("iCloud"), texte)
    }

    /// Réseau absent : on invite à réessayer, on ne parle pas d'échec définitif.
    func testSansReseauOnProposeDeReessayer() {
        for code in [CKError.Code.networkUnavailable, .networkFailure] {
            let texte = DuoService.message(for: CKError(code))

            // Les deux morceaux comptent : ce qui manque (la connexion) et ce qu'il y a à
            // faire. Sans le premier, le message générique passerait ce test sans rien dire.
            XCTAssertTrue(texte.lowercased().contains("connexion"), texte)
            XCTAssertTrue(texte.lowercased().contains("réessai"), texte)
        }
    }

    /// Une erreur qu'on n'a pas prévue reste une phrase, jamais un code ni un type Swift.
    /// C'est le cas le plus fréquent en vrai : CloudKit a une quarantaine de codes.
    func testUneErreurImprevueResteUnePhraseLisible() {
        let texte = DuoService.message(for: CKError(.internalError))

        XCTAssertFalse(texte.isEmpty)
        for jargon in ["CKError", "Error", "erreur 1", "nil", "code"] {
            XCTAssertFalse(texte.contains(jargon), texte)
        }
    }

    /// Règle du dépôt : aucun tiret cadratin dans un texte affiché. Et règle fondatrice :
    /// rien qui reproche quoi que ce soit à celui qui lit.
    func testAucunMessageNeReprocheNiNePorteDeTiretCadratin() {
        let codes: [CKError.Code] = [.notAuthenticated, .networkUnavailable, .networkFailure,
                                     .quotaExceeded, .permissionFailure, .internalError,
                                     .serviceUnavailable]
        for code in codes {
            let texte = DuoService.message(for: CKError(code))

            XCTAssertFalse(texte.contains("—"), texte)
            for reproche in ["tu as", "impossible", "invalide", "échec"] {
                XCTAssertFalse(texte.lowercased().contains(reproche), texte)
            }
        }
    }
}

// MARK: - Les gardes de l'invitation

@MainActor
final class DuoInvitationTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "nivel.tests.duopairing.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    /// Rouvrir l'écran d'invitation ne recrée ni zone ni partage : l'URL déjà obtenue est
    /// rendue telle quelle. Sans cette garde, chaque affichage tenterait un second
    /// `CKShare` sur la même zone, ce qui échoue côté serveur — et l'écran montrerait une
    /// erreur alors que le QR affiché juste au-dessus est parfaitement valide.
    ///
    /// Le conteneur est injecté et COMPTÉ : la garde est prouvée par le fait qu'aucun
    /// n'est convoqué, pas par le résultat, qui pourrait être juste par accident.
    func testReouvrirLInvitationNeRecreeRien() async {
        let identite = DuoIdentity(defaults: defaults)
        identite.role = .owner
        identite.zoneName = DuoDatabase.defaultZoneName
        identite.shareURL = URL(string: "https://www.icloud.com/share/0aB1cD2eF3")
        var conteneurs = 0
        let service = DuoService(identity: identite, resolveTarget: { _ in nil },
                                 makeContainer: {
                                     conteneurs += 1
                                     return CKContainer(identifier: DuoDatabase.containerID)
                                 })

        let resultat = await service.startInvitation()

        XCTAssertEqual(conteneurs, 0)
        XCTAssertEqual(resultat, .ready(URL(string: "https://www.icloud.com/share/0aB1cD2eF3")!))
    }

    /// L'identité de cet appareil est créée par l'appairage, et seulement par lui. Le lot A1
    /// a laissé `createMemberID()` sans aucun appelant, exprès : un type qui écrit en
    /// naissant n'a aucun endroit sûr où être lu. Mais l'oublier ici serait pire encore, le
    /// duo s'appairerait sans jamais rien publier, en silence — `publishDuoNow` sort sur
    /// `guard let memberID`.
    func testLInvitationDonneSonIdentiteACetAppareil() async {
        let identite = DuoIdentity(defaults: defaults)
        identite.role = .owner
        identite.shareURL = URL(string: "https://www.icloud.com/share/0aB1cD2eF3")
        let service = DuoService(identity: identite, resolveTarget: { _ in nil },
                                 makeContainer: { CKContainer(identifier: DuoDatabase.containerID) })

        XCTAssertNil(identite.memberID, "rien avant l'appairage")
        _ = await service.startInvitation()

        XCTAssertNotNil(identite.memberID)
        XCTAssertEqual(DuoIdentity(defaults: defaults).memberID, identite.memberID,
                       "et il est persisté, sinon le membre de la zone changerait d'identité")
    }

    // MARK: - Rejoindre

    /// Le scanner lit N'IMPORTE QUEL QR code, et le champ accepte n'importe quel texte : un
    /// contenu qui n'est pas une invitation ne doit jamais partir vers CloudKit. La
    /// validation du §3.6 tranche avant, et c'est son message qui s'affiche, pas une erreur
    /// de nuage sur une URL que le nuage n'avait aucune raison de recevoir.
    func testRejoindreAvecUnTexteQuelconqueNAppellePasLeNuage() async {
        var conteneurs = 0
        let service = DuoService(identity: DuoIdentity(defaults: defaults),
                                 resolveTarget: { _ in nil },
                                 makeContainer: {
                                     conteneurs += 1
                                     return CKContainer(identifier: DuoDatabase.containerID)
                                 })

        let resultat = await service.join(shareURL: "bonjour, c'est moi")

        XCTAssertEqual(conteneurs, 0)
        XCTAssertEqual(resultat, .failed(DuoService.invalidShareMessage))
        XCTAssertFalse(service.isPaired, "rien n'a été appairé au passage")
    }

    /// Champ vide : le message dit quoi faire, et rien ne part non plus. C'est l'état du
    /// champ à l'ouverture de l'écran, donc le cas le plus fréquent de tous.
    func testRejoindreAvecUnChampVideDitQuoiFaire() async {
        var conteneurs = 0
        let service = DuoService(identity: DuoIdentity(defaults: defaults),
                                 resolveTarget: { _ in nil },
                                 makeContainer: {
                                     conteneurs += 1
                                     return CKContainer(identifier: DuoDatabase.containerID)
                                 })

        let resultat = await service.join(shareURL: "   ")

        XCTAssertEqual(conteneurs, 0)
        XCTAssertEqual(resultat, .failed(DuoService.emptyShareMessage))
    }
}

// MARK: - L'abonnement est posé au bout de l'appairage

/// **Le second défaut trouvé sur deux vrais iPhones.** `installSubscriptionIfNeeded`
/// n'était appelé que depuis `refresh()`, et `refresh()` n'est déclenché que par les
/// Réglages, la page de profil, la boucle d'appairage et le retour au premier plan. Qui
/// appairait puis rentrait à l'accueil n'avait donc **aucun abonnement de zone**, donc
/// aucun réveil silencieux, donc aucune notification, jusqu'à rouvrir les Réglages par
/// hasard.
///
/// Chaque maillon avait pourtant son test : la pose de l'abonnement, l'appairage, le
/// désappairage qui l'efface. Aucun ne suivait la CHAÎNE, et c'est par là que le défaut est
/// passé. Ces tests-ci la suivent, des deux côtés, de `startInvitation()` et de `join()`
/// jusqu'à l'abonnement réellement remis au nuage.
///
/// Les deux gestes CloudKit de l'appairage sont injectés — c'est la seule façon de tenir
/// cette chaîne sans deux comptes iCloud, que ni le simulateur ni la CI ne savent jouer.
@MainActor
final class DuoPairingSubscriptionTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "nivel.tests.duosub.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private let lien = URL(string: "https://www.icloud.com/share/0aB1cD2eF3")!

    /// Celui qui INVITE : le partage créé, l'abonnement est posé dans la foulée, sans
    /// qu'aucun `refresh()` n'ait à passer par là.
    func testInviterPoseLAbonnementSansAttendreUnRafraichissement() async {
        var poses: [CKSubscription] = []
        let identite = DuoIdentity(defaults: defaults)
        let service = DuoService(
            identity: identite,
            createShare: { _ in
                (CKRecordZone.ID(zoneName: DuoDatabase.defaultZoneName,
                                 ownerName: CKCurrentUserDefaultName), self.lien)
            },
            saveSubscription: { _, abonnement in poses.append(abonnement); return true })

        let resultat = await service.startInvitation()

        XCTAssertEqual(resultat, .ready(lien))
        XCTAssertEqual(poses.count, 1, "sans abonnement, plus jamais un seul réveil")
        XCTAssertTrue(identite.zoneSubscriptionInstalled)
        XCTAssertEqual((poses.first as? CKRecordZoneSubscription)?.zoneID.zoneName,
                       DuoDatabase.defaultZoneName)
    }

    /// Celui qui REJOINT, et c'est le côté qui comptait le plus : l'invité n'a aucune raison
    /// de rouvrir les Réglages après avoir scanné, il rentre à l'accueil.
    ///
    /// Une zone partagée REFUSE `CKRecordZoneSubscription`. L'invité doit poser le seul
    /// abonnement que CloudKit y accepte : un abonnement de base filtré sur le signal de
    /// like. Cette différence est ce qui rend les alertes bidirectionnelles.
    func testRejoindrePoseUnAbonnementDeBasePartageePourLesCoeurs() async {
        var poses: [CKSubscription] = []
        let identite = DuoIdentity(defaults: defaults)
        let service = DuoService(
            identity: identite,
            acceptShare: { _, _ in
                CKRecordZone.ID(zoneName: DuoDatabase.defaultZoneName, ownerName: "PROPRIO")
            },
            saveSubscription: { _, abonnement in poses.append(abonnement); return true })

        let resultat = await service.join(shareURL: lien.absoluteString)

        XCTAssertEqual(resultat, .joined)
        XCTAssertEqual(poses.count, 1, "sans abonnement, plus jamais un seul réveil")
        XCTAssertTrue(identite.zoneSubscriptionInstalled)
        let abonnement = poses.first as? CKDatabaseSubscription
        XCTAssertNotNil(abonnement)
        XCTAssertEqual(abonnement?.recordType, DuoRecord.likeAlertType)
    }

    /// L'alerte est distante et limitée au signal de like : elle reste visible si l'app a
    /// été tuée, sans annoncer les snapshots ni les retraits de cœurs.
    func testLAbonnementPoseUneAlerteVisiblePourLeSignalDeCoeur() async {
        var poses: [CKSubscription] = []
        let service = DuoService(
            identity: DuoIdentity(defaults: defaults),
            acceptShare: { _, _ in
                CKRecordZone.ID(zoneName: DuoDatabase.defaultZoneName, ownerName: "PROPRIO")
            },
            saveSubscription: { _, abonnement in poses.append(abonnement); return true })

        _ = await service.join(shareURL: lien.absoluteString)

        let info = poses.first?.notificationInfo
        XCTAssertEqual(info?.shouldSendContentAvailable, true)
        XCTAssertEqual(info?.title, DuoService.likeAlertTitle)
        XCTAssertEqual(info?.alertBody, DuoService.likeAlertBody)
        XCTAssertEqual(info?.soundName, "default")
        XCTAssertEqual((poses.first as? CKDatabaseSubscription)?.recordType,
                       DuoRecord.likeAlertType)
        XCTAssertEqual(poses.first?.subscriptionID, DuoService.subscriptionID)
    }

    /// Un appairage qui rate ne pose rien : sans zone, l'abonnement partirait sur une
    /// identité qui n'existe pas, et le marquerait posé pour toujours.
    func testUnAppairageQuiRateNePoseAucunAbonnement() async {
        var poses = 0
        let identite = DuoIdentity(defaults: defaults)
        let service = DuoService(
            identity: identite,
            createShare: { _ in throw CKError(.networkUnavailable) },
            acceptShare: { _, _ in throw CKError(.networkUnavailable) },
            saveSubscription: { _, _ in poses += 1; return true })

        _ = await service.startInvitation()
        _ = await service.join(shareURL: lien.absoluteString)

        XCTAssertEqual(poses, 0)
        XCTAssertFalse(identite.zoneSubscriptionInstalled)
        XCTAssertFalse(service.isPaired)
    }

    /// La garde d'idempotence est ce qui rend l'appel de l'appairage sans coût : le FILET
    /// gardé dans `refresh()` ne repose pas un abonnement déjà en place, et l'appairage ne
    /// le repose pas non plus après une reprise.
    func testUnAbonnementDejaPoseNEstPasRepose() async {
        var poses = 0
        let identite = DuoIdentity(defaults: defaults)
        identite.zoneSubscriptionInstalled = true
        identite.likeNotificationSubscriptionVersion = DuoService.subscriptionVersion
        let service = DuoService(
            identity: identite,
            acceptShare: { _, _ in
                CKRecordZone.ID(zoneName: DuoDatabase.defaultZoneName, ownerName: "PROPRIO")
            },
            saveSubscription: { _, _ in poses += 1; return true })

        _ = await service.join(shareURL: lien.absoluteString)

        XCTAssertEqual(poses, 0)
    }

    /// Une v1 était mémorisée comme « posée », mais elle était silencieuse et, côté invité,
    /// du mauvais type. La version force une remise à niveau lors du prochain appairage ou
    /// rafraîchissement, sans demander une nouvelle action à la personne.
    func testUneAncienneVersionDAbonnementEstRemplacee() async {
        var poses = 0
        let identite = DuoIdentity(defaults: defaults)
        identite.zoneSubscriptionInstalled = true
        identite.likeNotificationSubscriptionVersion = 1
        let service = DuoService(
            identity: identite,
            acceptShare: { _, _ in
                CKRecordZone.ID(zoneName: DuoDatabase.defaultZoneName, ownerName: "PROPRIO")
            },
            saveSubscription: { _, _ in poses += 1; return true })

        _ = await service.join(shareURL: lien.absoluteString)

        XCTAssertEqual(poses, 1)
        XCTAssertEqual(identite.likeNotificationSubscriptionVersion,
                       DuoService.subscriptionVersion)
    }

    /// Le nuage a refusé : on ne marque SURTOUT pas l'abonnement comme posé, sinon plus
    /// rien ne le retentera jamais. C'est le filet de `refresh()` qui reprendra la main.
    func testUnAbonnementRefuseResteARetenter() async {
        let identite = DuoIdentity(defaults: defaults)
        let service = DuoService(
            identity: identite,
            acceptShare: { _, _ in
                CKRecordZone.ID(zoneName: DuoDatabase.defaultZoneName, ownerName: "PROPRIO")
            },
            saveSubscription: { _, _ in false })

        _ = await service.join(shareURL: lien.absoluteString)

        XCTAssertTrue(service.isPaired, "l'appairage, lui, a bien eu lieu")
        XCTAssertFalse(identite.zoneSubscriptionInstalled)
    }

    /// Couper « Cœurs reçus » retire réellement l'abonnement distant. Sans cette étape,
    /// l'interrupteur ne ferait qu'ignorer localement une bannière qu'Apple a déjà affichée.
    func testCouperLesCoeursRetireLAbonnementCloudKit() async {
        let identite = DuoIdentity(defaults: defaults)
        identite.role = .owner
        identite.zoneName = DuoDatabase.defaultZoneName
        identite.zoneSubscriptionInstalled = true
        identite.likeNotificationSubscriptionVersion = DuoService.subscriptionVersion
        let target = DuoDatabase.Target(
            database: CKContainer(identifier: DuoDatabase.containerID).privateCloudDatabase,
            zoneID: CKRecordZone.ID(zoneName: DuoDatabase.defaultZoneName,
                                    ownerName: CKCurrentUserDefaultName),
            scope: .private)
        var suppressions: [CKSubscription.ID] = []
        let service = DuoService(
            identity: identite,
            resolveTarget: { _ in target },
            deleteSubscription: { _, id in suppressions.append(id); return true })

        await service.setLikeNotificationsEnabled(false)

        XCTAssertFalse(service.likeNotificationsEnabled)
        XCTAssertEqual(suppressions, [DuoService.subscriptionID])
        XCTAssertFalse(identite.zoneSubscriptionInstalled)
        XCTAssertEqual(identite.likeNotificationSubscriptionVersion, 0)
    }

    /// Le désappairage fait la même suppression explicite. C'est indispensable côté invité,
    /// où l'abonnement vit dans sa base partagée, distincte de la zone du propriétaire.
    func testLeDesappairageRetireAussiLAbonnementCloudKit() async {
        let identite = DuoIdentity(defaults: defaults)
        identite.role = .guest
        identite.zoneName = DuoDatabase.defaultZoneName
        identite.zoneOwnerName = "PROPRIO"
        let target = DuoDatabase.Target(
            database: CKContainer(identifier: DuoDatabase.containerID).sharedCloudDatabase,
            zoneID: CKRecordZone.ID(zoneName: DuoDatabase.defaultZoneName, ownerName: "PROPRIO"),
            scope: .shared)
        var suppressions: [CKSubscription.ID] = []
        let service = DuoService(
            identity: identite,
            resolveTarget: { _ in target },
            deleteSubscription: { _, id in suppressions.append(id); return true },
            deleteZone: { _ in })

        await service.unpair()

        XCTAssertEqual(suppressions, [DuoService.subscriptionID])
        XCTAssertFalse(service.isPaired)
    }
}

// MARK: - Le signal qui porte l'alerte

final class DuoLikeAlertRecordTests: XCTestCase {

    func testLeSignalEstBorneParDonneurEtPorteLeDernierCoeur() {
        let zone = CKRecordZone.ID(zoneName: DuoDatabase.defaultZoneName, ownerName: "PROPRIO")
        let premier = DuoEvent(id: "E1", kind: .meal, at: .now, title: "Déjeuner", subtitle: "")
        let suivant = DuoEvent(id: "E2", kind: .activity, at: .now, title: "Marche", subtitle: "")

        let signal1 = DuoRecord.likeAlert(giver: "MOI", owner: "TOI", event: premier, in: zone)
        let signal2 = DuoRecord.likeAlert(giver: "MOI", owner: "TOI", event: suivant, in: zone)

        XCTAssertEqual(signal1.recordType, DuoRecord.likeAlertType)
        XCTAssertEqual(signal1.recordID.recordName, "like-alert-MOI")
        XCTAssertEqual(signal2.recordID, signal1.recordID,
                       "un même donneur réécrit son signal au lieu d'en créer un par like")
        XCTAssertEqual(signal2[DuoRecord.Field.eventID] as? String, "E2")
        XCTAssertEqual(signal2[DuoRecord.Field.eventTitle] as? String, "Marche")
    }
}

final class DuoSubscriptionResultTests: XCTestCase {

    func testUnEchecIndividuelNeMarqueJamaisLAbonnementCommePose() {
        let id: CKSubscription.ID = DuoService.subscriptionID
        let abonnement = CKDatabaseSubscription(subscriptionID: id)
        let reussite: [CKSubscription.ID: Result<CKSubscription, any Error>] = [
            id: .success(abonnement)
        ]
        let echec: [CKSubscription.ID: Result<CKSubscription, any Error>] = [
            id: .failure(CKError(.permissionFailure))
        ]

        XCTAssertTrue(DuoService.subscriptionSaveSucceeded(reussite, id: id))
        XCTAssertFalse(DuoService.subscriptionSaveSucceeded(echec, id: id))
        XCTAssertFalse(DuoService.subscriptionSaveSucceeded([:], id: id))
    }
}

// MARK: - Le scanner et son repli

final class DuoScannerAvailabilityTests: XCTestCase {

    /// Caméra refusée, ou appareil qui ne sait pas scanner : on tombe sur le champ
    /// « coller un lien », JAMAIS sur une impasse (spec §3.10). Le champ est d'ailleurs
    /// toujours affiché, même quand la caméra marche : on n'est pas forcément côte à côte.
    func testSansCameraOnTombeSurLeChampEtJamaisSurUneImpasse() {
        XCTAssertTrue(DuoJoinView.showsScanner(isSupported: true, isAvailable: true))
        XCTAssertFalse(DuoJoinView.showsScanner(isSupported: true, isAvailable: false))
        XCTAssertFalse(DuoJoinView.showsScanner(isSupported: false, isAvailable: true))
        XCTAssertFalse(DuoJoinView.showsScanner(isSupported: false, isAvailable: false))
    }
}
