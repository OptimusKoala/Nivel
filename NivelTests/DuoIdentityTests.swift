// NivelTests/DuoIdentityTests.swift
// L'état d'appairage du duo (spec 1.15 §3.6), qui est de l'état d'APPAREIL.
// Suite UserDefaults dédiée par test — jamais les vrais réglages de l'app.

import XCTest
import NivelCore
@testable import Nivel

final class DuoIdentityTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "nivel.tests.duo.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func instantane(kcal: Int = 1_180) -> DuoSnapshot {
        DuoSnapshot(
            memberID: "M-partenaire", name: "Marion", sexRaw: "female",
            level: 11, totalXP: 2_340, xpIntoLevel: 140, xpForNextLevel: 220,
            dayKey: "2026-08-16",
            kcalEaten: kcal, kcalTarget: 1_550, burned: 310, burnTarget: 400, steps: 7_240,
            quest: DuoQuestLine(title: "Bouger 4 fois", done: 3, total: 4),
            events: [], generatedAt: Date(timeIntervalSince1970: 1_000))
    }

    // MARK: - Le domaine vierge

    /// Un téléphone qui n'a jamais appairé : pas de duo, et AUCUNE valeur fantôme.
    /// C'est l'état dans lequel vit l'app tant que personne n'a scanné de QR code, et
    /// la 1.15 promet qu'il se comporte alors exactement comme la 1.14.
    func testUnDomaineViergeNeDonneAucunDuo() {
        let identite = DuoIdentity(defaults: defaults)

        XCTAssertFalse(identite.isPaired)
        XCTAssertNil(identite.role)
        XCTAssertNil(identite.zoneName)
        XCTAssertNil(identite.zoneOwnerName)
        XCTAssertNil(identite.shareURL)
        XCTAssertNil(identite.profileLastSeenAt)
        XCTAssertNil(identite.partnerSnapshot)
        XCTAssertEqual(identite.unreadLikeCount, 0)
    }

    // MARK: - L'identité de cet appareil

    /// `memberID` est créé UNE fois et ne bouge plus. Deux instances lisant le même
    /// domaine voient le même, parce que la première l'a écrit en naissant.
    func testLeMemberIDEstStableEntreDeuxInstancesEtNonVide() {
        let premiere = DuoIdentity(defaults: defaults)
        premiere.createMemberID()
        let seconde = DuoIdentity(defaults: defaults)

        XCTAssertEqual(premiere.memberID?.isEmpty, false)
        XCTAssertEqual(premiere.memberID, seconde.memberID)
    }

    /// LE test de la correction : naître ne crée RIEN. Un `DuoIdentity` construit sur un
    /// domaine vierge ne doit y écrire aucune clé — sans quoi la moindre lecture, sur un
    /// chemin aussi chaud que `saveOrAssert`, sème une identité de duo dans les réglages.
    func testNaitreNEcritRienDansLesReglages() {
        _ = DuoIdentity(defaults: defaults)

        XCTAssertNil(defaults.string(forKey: DuoIdentity.Key.memberID))
        XCTAssertTrue(defaults.dictionaryRepresentation()
            .keys.filter { $0.hasPrefix("nivel.duo") }.isEmpty)
    }

    /// La création est explicite et idempotente : en fabriquer une seconde laisserait la
    /// première en fantôme dans la zone partagée.
    func testLaCreationEstExpliciteEtIdempotente() {
        let identite = DuoIdentity(defaults: defaults)

        let premier = identite.createMemberID()
        let second = identite.createMemberID()

        XCTAssertEqual(premier, second)
        XCTAssertFalse(premier.isEmpty)
        XCTAssertEqual(defaults.string(forKey: DuoIdentity.Key.memberID), premier)
    }

    /// Deux appareils, deux domaines, deux identités : sans quoi les deux membres du
    /// duo porteraient le même `memberID` et chacun verrait l'instantané de l'autre
    /// écraser le sien dans la zone partagée.
    func testDeuxAppareilsDifferentsOntDesIdentitesDifferentes() {
        let autreNom = "nivel.tests.duo.\(UUID().uuidString)"
        let autreDomaine = UserDefaults(suiteName: autreNom)!
        defer { autreDomaine.removePersistentDomain(forName: autreNom) }

        XCTAssertNotEqual(DuoIdentity(defaults: defaults).createMemberID(),
                          DuoIdentity(defaults: autreDomaine).createMemberID())
    }

    // MARK: - Persistance

    func testLEtatDAppairageSurvitAUneNouvelleInstance() throws {
        let ecrivain = DuoIdentity(defaults: defaults)
        ecrivain.role = .guest
        ecrivain.zoneName = "duo"
        ecrivain.zoneOwnerName = "_abc123"
        ecrivain.shareURL = URL(string: "https://www.icloud.com/share/0abc")
        ecrivain.profileLastSeenAt = Date(timeIntervalSince1970: 5_000)
        ecrivain.unreadLikeCount = 3

        let relecteur = DuoIdentity(defaults: defaults)

        XCTAssertTrue(relecteur.isPaired)
        XCTAssertEqual(relecteur.role, .guest)
        XCTAssertEqual(relecteur.zoneName, "duo")
        XCTAssertEqual(relecteur.zoneOwnerName, "_abc123")
        XCTAssertEqual(relecteur.shareURL?.absoluteString, "https://www.icloud.com/share/0abc")
        XCTAssertEqual(relecteur.profileLastSeenAt, Date(timeIntervalSince1970: 5_000))
        XCTAssertEqual(relecteur.unreadLikeCount, 3)
    }

    /// Le cache de l'instantané du partenaire fait l'aller-retour. C'est lui qui permet
    /// d'ouvrir la page du duo HORS LIGNE sur les derniers chiffres connus, au lieu d'un
    /// écran vide le temps qu'iCloud réponde.
    func testLeCacheDInstantaneFaitLAllerRetour() throws {
        let ecrivain = DuoIdentity(defaults: defaults)
        ecrivain.partnerSnapshot = instantane()

        let relu = try XCTUnwrap(DuoIdentity(defaults: defaults).partnerSnapshot)

        XCTAssertEqual(relu, instantane())
        XCTAssertEqual(relu.name, "Marion")
        // `==` ignorant `generatedAt` (spec §3.5), on le vérifie à part : sans ça, un
        // horodatage perdu au cache passerait inaperçu et la ligne « mis à jour il y
        // a… » mentirait.
        XCTAssertEqual(relu.generatedAt, Date(timeIntervalSince1970: 1_000))
    }

    /// Un cache illisible ne doit pas empêcher l'app de démarrer. Le cas arrive pour de
    /// vrai : une version future changera la forme de `DuoSnapshot`, et le cache écrit
    /// par l'ancienne restera sur le disque. On repart sans cache, la page se remplira
    /// à la prochaine réponse d'iCloud.
    func testUnCacheIllisibleEstIgnoreSansCasserLeDemarrage() {
        defaults.set(Data("pas du JSON".utf8), forKey: DuoIdentity.Key.partnerSnapshot)

        let identite = DuoIdentity(defaults: defaults)

        XCTAssertNil(identite.partnerSnapshot)
    }

    // MARK: - Le désappairage

    /// Le désappairage efface le duo, PAS l'appareil. `memberID` survit parce que c'est
    /// l'identité de ce téléphone-ci et non celle du couple : quelqu'un qui défait un
    /// duo puis le refait avec la même personne ne doit pas revenir en inconnu, sous
    /// peine de laisser un membre fantôme dans la zone et de perdre ses cœurs.
    func testLeDesappairageEffaceLeDuoMaisGardeLeMemberID() {
        let identite = DuoIdentity(defaults: defaults)
        let identifiantDAvant = identite.createMemberID()
        identite.role = .owner
        identite.zoneName = "duo"
        identite.zoneOwnerName = "_abc123"
        identite.shareURL = URL(string: "https://www.icloud.com/share/0abc")
        identite.profileLastSeenAt = Date(timeIntervalSince1970: 5_000)
        identite.unreadLikeCount = 4
        identite.partnerSnapshot = instantane()

        identite.unpair()

        XCTAssertEqual(identite.memberID, identifiantDAvant)
        XCTAssertFalse(identite.isPaired)
        XCTAssertNil(identite.role)
        XCTAssertNil(identite.zoneName)
        XCTAssertNil(identite.zoneOwnerName)
        XCTAssertNil(identite.shareURL)
        XCTAssertNil(identite.profileLastSeenAt)
        XCTAssertNil(identite.partnerSnapshot)
        XCTAssertEqual(identite.unreadLikeCount, 0)
    }

    /// Et l'effacement est écrit sur le DISQUE, pas seulement dans l'instance : sinon le
    /// duo réapparaîtrait au prochain lancement, ce qui est le mode de panne le plus
    /// déroutant possible pour quelqu'un qui vient de désappairer.
    func testLeDesappairageEstPersisteEtNonSeulementEnMemoire() {
        let identite = DuoIdentity(defaults: defaults)
        let identifiantDAvant = identite.createMemberID()
        identite.role = .owner
        identite.zoneName = "duo"
        identite.partnerSnapshot = instantane()

        identite.unpair()
        let relecteur = DuoIdentity(defaults: defaults)

        XCTAssertFalse(relecteur.isPaired)
        XCTAssertNil(relecteur.zoneName)
        XCTAssertNil(relecteur.partnerSnapshot)
        XCTAssertEqual(relecteur.memberID, identifiantDAvant)
    }
}
