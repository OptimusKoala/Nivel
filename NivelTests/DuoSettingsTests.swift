// NivelTests/DuoSettingsTests.swift
// La section Duo des réglages (spec 1.15 §3.9, §3.10) : ses quatre états, et ce que le
// désappairage a le droit d'effacer.
//
// Les libellés sont éprouvés au mot près. Ce n'est pas de la coquetterie : ce sont les
// seules phrases de la feature qui parlent de pannes, et une phrase qui reproche quelque
// chose à quelqu'un qui n'y peut rien casse la règle fondatrice de la v1 aussi sûrement
// qu'un chiffre rouge sur l'accueil.

import XCTest
import CloudKit
import NivelCore
@testable import Nivel

final class DuoSettingsStateTests: XCTestCase {
    private let seizeAout = Date(timeIntervalSince1970: 1_786_881_600)  // 2026-08-16, 12 h UTC

    // MARK: - Les quatre états

    func testChaqueEtatDuDuoADitSonMot() {
        XCTAssertEqual(DuoSettingsState.label(for: .noAccount),
                       "Connecte-toi à iCloud pour créer un duo")
        XCTAssertEqual(DuoSettingsState.label(for: .unpaired), "Aucun duo pour l'instant")
        XCTAssertEqual(DuoSettingsState.label(for: .zoneGone),
                       "Ce duo n'existe plus, tu peux en créer un nouveau")
        XCTAssertEqual(DuoSettingsState.label(for: .paired(name: "Marion", since: seizeAout)),
                       "Appairé avec Marion depuis le 16 août 2026")
    }

    /// Sans compte iCloud, rien d'autre ne compte : ni l'appairage passé ni la zone. Le
    /// message dit où aller le régler, parce que c'est le seul état de cette liste dont la
    /// solution est ailleurs que dans Nivel.
    func testSansCompteICloudRienDAutreNeCompte() {
        let etat = DuoSettingsState.current(hasAccount: false, isPaired: true, zoneIsGone: false,
                                            partnerName: "Marion", pairedAt: seizeAout)

        XCTAssertEqual(etat, .noAccount)
    }

    /// La zone disparue prime sur l'appairage local : l'état d'appareil dit encore
    /// « appairé » alors qu'il n'y a plus rien en face, et c'est exactement le moment où il
    /// faut proposer de recommencer plutôt que d'afficher un duo qui n'existe plus.
    func testUneZoneDisparuePrimeSurLAppairageLocal() {
        let etat = DuoSettingsState.current(hasAccount: true, isPaired: true, zoneIsGone: true,
                                            partnerName: "Marion", pairedAt: seizeAout)

        XCTAssertEqual(etat, .zoneGone)
    }

    func testUnDuoNormalEstAppaireAvecSonNomEtSaDate() {
        let etat = DuoSettingsState.current(hasAccount: true, isPaired: true, zoneIsGone: false,
                                            partnerName: "Marion", pairedAt: seizeAout)

        XCTAssertEqual(etat, .paired(name: "Marion", since: seizeAout))
    }

    func testSansDuoOnLeDitSansRienProposerDAutre() {
        let etat = DuoSettingsState.current(hasAccount: true, isPaired: false, zoneIsGone: false,
                                            partnerName: nil, pairedAt: nil)

        XCTAssertEqual(etat, .unpaired)
    }

    /// Appairé, mais l'autre n'a encore rien écrit : c'est l'instant entre l'acceptation du
    /// partage et sa première publication. On l'annonce comme une attente, pas comme un
    /// duo cassé, et surtout pas en affichant un nom vide.
    func testUnPartenaireQuiNAPasEncorePublieSAnnonceEnAttente() {
        let texte = DuoSettingsState.label(for: .paired(name: nil, since: seizeAout))

        XCTAssertEqual(texte, "Appairé depuis le 16 août 2026, en attente de l'autre iPhone")
        for fuite in ["nil", "Optional", "()"] {
            XCTAssertFalse(texte.contains(fuite), texte)
        }
    }

    /// Une date d'appairage inconnue (un duo noué par une version antérieure) ne doit ni
    /// faire disparaître la ligne ni inventer une date.
    func testUneDateInconnueNeFabriqueAucuneDate() {
        XCTAssertEqual(DuoSettingsState.label(for: .paired(name: "Marion", since: nil)),
                       "Appairé avec Marion")
    }

    func testAucunLibelleNeReprocheNiNePorteDeTiretCadratin() {
        let etats: [DuoSettingsState] = [.noAccount, .unpaired, .zoneGone,
                                         .paired(name: "Marion", since: seizeAout),
                                         .paired(name: nil, since: nil)]
        for etat in etats {
            let texte = DuoSettingsState.label(for: etat)

            XCTAssertFalse(texte.contains("—"), texte)
            for reproche in ["erreur", "échec", "impossible", "tu n'as", "invalide"] {
                XCTAssertFalse(texte.lowercased().contains(reproche), texte)
            }
        }
    }

    // MARK: - Reconnaître une zone disparue

    /// Le partenaire a désinstallé, ou le propriétaire a défait le duo de son côté : la
    /// zone n'est plus là. Deux codes CloudKit le disent, et il faut les distinguer d'une
    /// panne de réseau, qui elle est passagère et ne doit surtout pas faire annoncer la
    /// fin du duo.
    func testUneZoneDisparueSeReconnaitAuCodeEtPasAUnePanneDeReseau() {
        XCTAssertTrue(DuoService.isZoneGone(error: CKError(.zoneNotFound)))
        XCTAssertTrue(DuoService.isZoneGone(error: CKError(.userDeletedZone)))

        XCTAssertFalse(DuoService.isZoneGone(error: CKError(.networkUnavailable)))
        XCTAssertFalse(DuoService.isZoneGone(error: CKError(.networkFailure)))
        XCTAssertFalse(DuoService.isZoneGone(error: CKError(.serviceUnavailable)))
        XCTAssertFalse(DuoService.isZoneGone(error: CKError(.notAuthenticated)))
    }
}

// MARK: - Le désappairage

@MainActor
final class DuoUnpairingTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "nivel.tests.duounpair.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func identiteAppairee() -> DuoIdentity {
        let identite = DuoIdentity(defaults: defaults)
        identite.createMemberID()
        identite.role = .guest
        identite.zoneName = "duo"
        identite.zoneOwnerName = "_proprietaire"
        identite.pairedAt = Date(timeIntervalSince1970: 1_786_881_600)
        identite.unreadLikeCount = 2
        identite.partnerSnapshot = DuoSnapshot(
            memberID: "M-partenaire", name: "Marion", sexRaw: "female",
            level: 11, totalXP: 2_340, xpIntoLevel: 140, xpForNextLevel: 220,
            dayKey: "2026-08-16", kcalEaten: 1_180, kcalTarget: 1_550,
            burned: 310, burnTarget: 400, steps: 7_240,
            quest: nil, events: [], generatedAt: Date(timeIntervalSince1970: 1_000))
        return identite
    }

    /// Le désappairage efface le lien et le cache, et rien d'autre.
    func testLeDesappairageEffaceLeLienEtLeCache() async {
        let identite = identiteAppairee()
        let service = DuoService(identity: identite, resolveTarget: { _ in nil },
                                 makeContainer: { CKContainer(identifier: DuoDatabase.containerID) })

        await service.unpair()

        XCTAssertFalse(service.isPaired)
        XCTAssertNil(identite.role)
        XCTAssertNil(identite.zoneName)
        XCTAssertNil(identite.zoneOwnerName)
        XCTAssertNil(identite.partnerSnapshot)
        XCTAssertNil(identite.pairedAt)
        XCTAssertEqual(identite.unreadLikeCount, 0)
        // Et c'est écrit sur le disque : un duo qui réapparaîtrait au lancement suivant
        // serait le plus déroutant des modes de panne.
        XCTAssertFalse(DuoIdentity(defaults: defaults).isPaired)
    }

    /// `memberID` SURVIT. C'est l'identité de ce téléphone, pas celle du couple :
    /// réappairer avec la même personne doit retrouver le même membre, sinon on laisse un
    /// fantôme dans la zone et on détache tous les cœurs déjà échangés.
    func testLeDesappairageNeTouchePasALIdentiteDeCetAppareil() async {
        let identite = identiteAppairee()
        let avant = identite.memberID
        let service = DuoService(identity: identite, resolveTarget: { _ in nil },
                                 makeContainer: { CKContainer(identifier: DuoDatabase.containerID) })

        await service.unpair()

        XCTAssertEqual(identite.memberID, avant)
        XCTAssertEqual(DuoIdentity(defaults: defaults).memberID, avant)
    }

    /// Les cœurs déjà reçus RESTENT (spec §3.10) : ils font partie de l'histoire, pas de la
    /// connexion, et ils continuent de s'afficher sur les entrées des journaux Repas et
    /// Sport. Les effacer avec le duo reviendrait à retirer de son propre journal ce que
    /// quelqu'un vous a dit de gentil.
    func testLesCoeursDejaRecusSurviventAuDesappairage() async {
        let identite = identiteAppairee()
        identite.receivedLikeEventIDs = ["E1", "E2"]
        let service = DuoService(identity: identite, resolveTarget: { _ in nil },
                                 makeContainer: { CKContainer(identifier: DuoDatabase.containerID) })

        await service.unpair()

        XCTAssertEqual(service.likedEventIDs, ["E1", "E2"])
        XCTAssertEqual(DuoIdentity(defaults: defaults).receivedLikeEventIDs, ["E1", "E2"])
    }

    /// L'annonce des cœurs est allumée par défaut, y compris sur un appareil qui n'a jamais
    /// touché ce réglage. `defaults.bool(forKey:)` rend `false` sur une clé absente : lu
    /// ainsi, l'interrupteur naîtrait ÉTEINT et personne ne recevrait jamais rien, sans
    /// qu'aucun réglage ne paraisse anormal.
    func testLAnnonceDesCoeursEstAllumeeParDefaut() {
        XCTAssertTrue(DuoIdentity(defaults: defaults).likeNotificationsEnabled)
    }

    /// Et l'interrupteur, une fois coupé, le reste au lancement suivant. Il ne défait pas
    /// l'appairage : c'est le sens du réglage, on garde le duo et on cesse d'être prévenu.
    func testLInterrupteurDesCoeursSePersisteSansDefaireLeDuo() {
        let identite = identiteAppairee()
        identite.likeNotificationsEnabled = false

        let relu = DuoIdentity(defaults: defaults)

        XCTAssertFalse(relu.likeNotificationsEnabled)
        XCTAssertTrue(relu.isPaired)
    }
}
