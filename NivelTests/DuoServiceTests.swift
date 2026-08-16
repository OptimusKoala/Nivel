// NivelTests/DuoServiceTests.swift
// Les décisions de `DuoService` (spec 1.15 §3.6, §3.7, §3.8).
//
// Le service lit et écrit dans une zone iCloud partagée : ni le simulateur ni la CI ne
// savent jouer deux comptes iCloud, donc RIEN de son transport n'est observable ici.
// Ce qui suit éprouve ce qui reste, et qui est l'essentiel : les décisions, extraites en
// statiques pures, exactement comme `HomeView.bubbleDecision` l'a été en v1.
//
// Aucune de ces suites ne touche les vrais `UserDefaults` : la seule qui construise un
// `DuoService` lui passe un domaine à elle, jeté au `tearDown`.

import XCTest
import CloudKit
import NivelCore
@testable import Nivel

// MARK: - Qui est mon partenaire

/// Le premier `DuoMember` écrit gagne (spec §3.6). Deux personnes peuvent accepter le
/// partage avant qu'il ne se referme, et il faut alors trancher SANS hasard : les deux
/// téléphones doivent désigner le même partenaire, sans quoi chacun regarderait quelqu'un
/// d'autre.
final class DuoPartnerChoiceTests: XCTestCase {

    private func membre(_ identifiant: String, _ secondes: TimeInterval) -> DuoMemberRef {
        DuoMemberRef(memberID: identifiant, createdAt: Date(timeIntervalSince1970: secondes))
    }

    func testLePremierMembreEcritGagne() {
        let ancien = membre("A", 100)
        let recent = membre("B", 200)

        // Passés dans le désordre exprès : c'est la date qui décide, pas le rang de
        // lecture, et CloudKit ne promet aucun ordre de réponse.
        XCTAssertEqual(DuoService.partner(among: [recent, ancien], excluding: "MOI")?.memberID,
                       "A")
    }

    func testMonPropreInstantaneNEstJamaisLePartenaire() {
        let moi = membre("MOI", 50)
        let autre = membre("A", 100)

        XCTAssertEqual(DuoService.partner(among: [moi, autre], excluding: "MOI")?.memberID, "A")
    }

    /// Zone rejointe mais personne d'autre encore : ce n'est pas une erreur, c'est
    /// l'instant entre l'acceptation du partage et la première écriture de l'autre. Un
    /// écran qui prendrait ce nil pour une panne afficherait un message d'échec pendant
    /// les quelques secondes de l'appairage, juste au moment où tout va bien.
    func testSeulDansLaZoneNEstPasUneErreur() {
        XCTAssertNil(DuoService.partner(among: [membre("MOI", 50)], excluding: "MOI"))
        XCTAssertNil(DuoService.partner(among: [], excluding: "MOI"))
    }

    /// Un identifiant vide n'est pas quelqu'un. `DuoIdentity` traite déjà la chaîne vide
    /// comme une absence, pour la raison qu'un identifiant vide serait accepté partout
    /// ailleurs sans en être un — et il gagnerait ici s'il était le plus ancien.
    func testUnMembreSansIdentifiantNEstJamaisLePartenaire() {
        let fantome = membre("", 10)
        let vrai = membre("A", 100)

        XCTAssertEqual(DuoService.partner(among: [fantome, vrai], excluding: "MOI")?.memberID,
                       "A")
    }

    /// Deux membres créés dans la même seconde : le départage se fait sur l'identifiant,
    /// donc IDENTIQUEMENT sur les deux téléphones. Sans ce second critère, l'ordre
    /// dépendrait de celui de la réponse CloudKit et les deux appareils pourraient
    /// désigner chacun un partenaire différent — un désaccord silencieux et permanent.
    func testDeuxMembresNesEnMemeTempsSeDepartagentDeLaMemeFacon() {
        let a = membre("AAA", 100)
        let b = membre("BBB", 100)

        XCTAssertEqual(DuoService.partner(among: [a, b], excluding: "MOI")?.memberID, "AAA")
        XCTAssertEqual(DuoService.partner(among: [b, a], excluding: "MOI")?.memberID, "AAA")
    }

    // MARK: - La place est-elle encore libre

    /// Zéro ou un membre, la place attend quelqu'un ; deux, elle est prise (spec §3.6).
    /// C'est ce qui décide de montrer le QR ou non, et de distinguer « personne n'a encore
    /// rejoint » de « quelqu'un est là et rien n'arrive » dans les réglages.
    func testLaPlaceEstPriseDesQuUnSecondMembreApparait() {
        XCTAssertTrue(DuoService.seatIsFree(memberCount: 0))
        XCTAssertTrue(DuoService.seatIsFree(memberCount: 1))
        XCTAssertFalse(DuoService.seatIsFree(memberCount: 2))
        XCTAssertFalse(DuoService.seatIsFree(memberCount: 3))
    }
}

// MARK: - Ce que la place prise déclenche, et ce qu'elle ne déclenche PLUS

/// **Le défaut trouvé sur deux vrais iPhones, et le plus coûteux de la 1.15.**
///
/// La place prise repassait le `CKShare` en `publicPermission = .none`. Or l'invité a
/// rejoint PAR LE LIEN : dans CloudKit il est un participant *public*, et couper la
/// permission publique lui retire son accès. Ses lectures partaient alors en zone
/// introuvable, `handleZoneLoss()` effaçait son appairage, il cessait de publier — le duo
/// disparaissait de son côté, ses repas n'arrivaient jamais chez le propriétaire, et plus
/// aucun réveil ne lui parvenait. Les trois symptômes rapportés, d'une seule cause.
///
/// Ce qui reste est purement LOCAL : on oublie l'URL, donc on cesse de pouvoir l'afficher.
/// Ces tests épinglent les deux moitiés — l'oubli a bien lieu, et **plus rien ne part vers
/// le nuage**. La seconde est celle qui compte : c'est elle qui rougit si quelqu'un remet
/// la révocation en croyant boucher un trou.
@MainActor
final class DuoSeatTakenTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "nivel.tests.duoseat.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func proprietaireAvecSonLien() -> DuoIdentity {
        let identite = DuoIdentity(defaults: defaults)
        _ = identite.createMemberID()
        identite.role = .owner
        identite.zoneName = DuoDatabase.defaultZoneName
        identite.shareURL = URL(string: "https://www.icloud.com/share/0aB1cD2eF3")
        return identite
    }

    /// La place prise fait disparaître le QR, et ne parle à personne pour cela. Les deux
    /// compteurs à zéro sont la PROMESSE de ce test : aucune résolution de zone, aucun
    /// conteneur, donc aucune permission touchée, donc l'invité garde l'accès qu'il a obtenu
    /// par le lien. C'est cette ligne qui rougira si la révocation revient.
    func testLaPlacePriseOublieLeLienSansToucherAuNuage() {
        let identite = proprietaireAvecSonLien()
        var resolutions = 0
        var conteneurs = 0
        let service = DuoService(identity: identite,
                                 resolveTarget: { _ in resolutions += 1; return nil },
                                 makeContainer: {
                                     conteneurs += 1
                                     return CKContainer(identifier: DuoDatabase.containerID)
                                 })

        service.forgetInvitationLinkIfSeatTaken(memberCount: 2)

        XCTAssertNil(identite.shareURL, "le QR ne doit plus pouvoir être affiché")
        XCTAssertEqual(resolutions, 0,
                       "révoquer la permission publique retirait son accès à l'invité")
        XCTAssertEqual(conteneurs, 0)
    }

    /// Tant que la place est libre, le lien reste : c'est lui que le QR affiche, et l'effacer
    /// pendant que l'écran d'invitation tourne ferait disparaître le code sous les yeux de
    /// celui qui le montre.
    func testTantQueLaPlaceEstLibreLeLienReste() {
        let identite = proprietaireAvecSonLien()
        let service = DuoService(identity: identite, resolveTarget: { _ in nil })

        service.forgetInvitationLinkIfSeatTaken(memberCount: 1)

        XCTAssertNotNil(identite.shareURL)
    }

    /// Compte de membres inconnu — aucune lecture n'a encore abouti — n'est PAS « la zone est
    /// vide ». On ne touche à rien tant qu'on ne sait pas.
    func testUnCompteInconnuNeDecideDeRien() {
        let identite = proprietaireAvecSonLien()
        let service = DuoService(identity: identite, resolveTarget: { _ in nil })

        service.forgetInvitationLinkIfSeatTaken(memberCount: nil)

        XCTAssertNotNil(identite.shareURL)
    }

    /// L'invité n'a pas de lien à oublier, et n'est pas propriétaire du partage. On ne va
    /// surtout pas effacer chez lui une URL qui, chez le propriétaire, sert encore.
    func testChezLInviteIlNYARien() {
        let identite = DuoIdentity(defaults: defaults)
        _ = identite.createMemberID()
        identite.role = .guest
        identite.zoneName = DuoDatabase.defaultZoneName
        identite.zoneOwnerName = "AUTRE"
        identite.shareURL = URL(string: "https://www.icloud.com/share/0aB1cD2eF3")
        let service = DuoService(identity: identite, resolveTarget: { _ in nil })

        service.forgetInvitationLinkIfSeatTaken(memberCount: 2)

        XCTAssertNotNil(identite.shareURL)
    }
}

// MARK: - Les cœurs qui me visent

final class DuoIncomingLikesTests: XCTestCase {

    private func coeur(donneur: String, proprietaire: String, evenement: String,
                       a secondes: TimeInterval = 0) -> DuoLike {
        DuoLike(giverID: donneur, ownerID: proprietaire, eventID: evenement,
                eventTitle: "Dîner", createdAt: Date(timeIntervalSince1970: secondes))
    }

    /// Le filtrage est CÔTÉ CLIENT (spec §3.7) : on ne s'en remet pas au fait que
    /// CloudKit épargnerait l'appareil d'origine. Deux conditions, et les deux comptent —
    /// un cœur que j'ai donné sur ma propre entrée ne me revient pas en notification, et
    /// un cœur que j'ai donné à l'autre n'est pas un cœur reçu.
    func testSeulsLesCoeursDesAutresQuiMeVisentComptent() {
        let mienSurMoi = coeur(donneur: "MOI", proprietaire: "MOI", evenement: "E1")
        let sienSurMoi = coeur(donneur: "TOI", proprietaire: "MOI", evenement: "E2")
        let mienSurLui = coeur(donneur: "MOI", proprietaire: "TOI", evenement: "E3")
        let sienSurLui = coeur(donneur: "TOI", proprietaire: "TOI", evenement: "E4")

        XCTAssertEqual(
            DuoService.incomingLikes(from: [mienSurMoi, sienSurMoi, mienSurLui, sienSurLui],
                                     me: "MOI").map(\.eventID),
            ["E2"])
    }

    /// `createdAt` est publié « pour l'ordre d'affichage » (spec §3.3), et c'est ici
    /// qu'il sert. L'ordre de la réponse CloudKit n'est promis par rien.
    func testLesCoeursSontRendusDuPlusAncienAuPlusRecent() {
        let tard = coeur(donneur: "TOI", proprietaire: "MOI", evenement: "TARD", a: 900)
        let tot = coeur(donneur: "TOI", proprietaire: "MOI", evenement: "TOT", a: 100)

        XCTAssertEqual(DuoService.incomingLikes(from: [tard, tot], me: "MOI").map(\.eventID),
                       ["TOT", "TARD"])
    }

    /// Un cœur dont le donneur est inconnu reste un cœur reçu. La zone n'a que deux
    /// membres : un cœur posé sur MON entrée ne peut venir que de l'autre. Le faire
    /// disparaître sur l'absence d'un champ répéterait la faute corrigée au lot A1, où
    /// un `giverID` manquant écartait un cœur du nettoyage pour toujours.
    func testUnCoeurSansDonneurConnuResteVisible() {
        let anonyme = coeur(donneur: "", proprietaire: "MOI", evenement: "E9")

        XCTAssertEqual(DuoService.incomingLikes(from: [anonyme], me: "MOI").map(\.eventID),
                       ["E9"])
    }
}

// MARK: - L'URL d'un partage

/// Le scanner lit n'importe quel QR code, et le champ de repli accepte n'importe quel
/// texte collé (spec §3.6). Ce qui n'est pas une invitation doit être refusé avec une
/// phrase lisible, jamais laissé filer jusqu'à une erreur CloudKit incompréhensible.
final class DuoShareURLTests: XCTestCase {

    private func message(_ brut: String) -> String? {
        if case .invalid(let texte) = DuoService.shareURL(from: brut) { return texte }
        return nil
    }

    func testUneInvitationICloudEstAcceptee() {
        let lien = "https://www.icloud.com/share/0aB1cD2eF3gH4iJ5kL6mN7oP8#duo"

        XCTAssertEqual(DuoService.shareURL(from: lien), .valid(URL(string: lien)!))
    }

    /// Le scanner rend une chaîne brute, souvent avec un retour à la ligne, et un lien
    /// collé depuis Messages traîne presque toujours une espace. Les rejeter pour cela
    /// serait un refus incompréhensible devant un QR parfaitement valide.
    func testLesEspacesEtRetoursALaLigneAutourDuLienSontTolerees() {
        let lien = "https://www.icloud.com/share/0aB1cD2eF3gH4iJ5kL6mN7oP8"

        XCTAssertEqual(DuoService.shareURL(from: "  \(lien)\n"), .valid(URL(string: lien)!))
    }

    func testUnLienDUnAutreDomaineEstRejeteAvecUnMessage() {
        let texte = message("https://example.com/share/0aB1cD2eF3")

        XCTAssertNotNil(texte)
        XCTAssertFalse(texte?.isEmpty ?? true)
        // Le message parle à quelqu'un qui vient de scanner un QR code, pas à un
        // développeur : aucune mention d'URL, de schéma ni de domaine.
        XCTAssertFalse(texte?.lowercased().contains("url") ?? true)
    }

    /// Le piège classique : `icloud.com.autre-chose.tld` contient bien « icloud.com ».
    /// Une vérification par `contains` l'accepterait, et le scan d'un QR malveillant
    /// enverrait l'appareil accepter un partage qui n'est pas celui du duo.
    func testUnSousDomaineTrompeurEstRejete() {
        XCTAssertNotNil(message("https://icloud.com.pas-apple.tld/share/0aB1cD2eF3"))
    }

    /// Bon domaine, mais pas une invitation : un lien de photos partagées, par exemple.
    func testLeBonDomaineSansPartageEstRejete() {
        XCTAssertNotNil(message("https://www.icloud.com/photos/0aB1cD2eF3"))
        XCTAssertNotNil(message("https://www.icloud.com/share/"))
    }

    /// En clair plutôt qu'en `https` : refusé. Une invitation de partage iCloud est
    /// toujours en `https`, et accepter l'autre reviendrait à suivre un lien que
    /// n'importe qui a pu réécrire en route.
    func testUnLienNonSecuriseEstRejete() {
        XCTAssertNotNil(message("http://www.icloud.com/share/0aB1cD2eF3"))
    }

    func testUnTexteQuiNEstPasUnLienEstRejete() {
        XCTAssertNotNil(message("bonjour, c'est moi"))
    }

    /// Champ vide : le message dit QUOI FAIRE, au lieu de constater un échec. Ce n'est
    /// pas la même phrase que pour un lien invalide, parce que ce n'est pas la même
    /// situation : ici l'utilisateur n'a encore rien tenté.
    func testUnChampVideDitQuoiFaire() {
        let vide = message("")
        let espaces = message("   \n ")

        XCTAssertNotNil(vide)
        XCTAssertEqual(vide, espaces)
        XCTAssertNotEqual(vide, message("bonjour, c'est moi"))
    }

    /// Règle du dépôt : aucun tiret cadratin dans un texte affiché.
    func testAucunMessageNePorteDeTiretCadratin() {
        for brut in ["", "bonjour", "https://example.com/share/1", "http://www.icloud.com/share/1"] {
            XCTAssertFalse(message(brut)?.contains("—") ?? false, brut)
        }
    }
}

// MARK: - La lecture des enregistrements de la zone

/// L'aller-retour du câble (spec §3.3). `CKRecord` se construit et se lit sans compte,
/// sans réseau et sans entitlement : c'est la seule partie du transport qui s'éprouve, et
/// c'est aussi celle où une faute est le plus silencieuse.
final class DuoRecordReadingTests: XCTestCase {
    private let zone = CKRecordZone.ID(zoneName: "duo", ownerName: CKCurrentUserDefaultName)

    private func instantane(quest: DuoQuestLine? = DuoQuestLine(title: "Bouger 4 fois",
                                                                done: 3, total: 4),
                            steps: Int = 7_240,
                            events: [DuoEvent] = []) -> DuoSnapshot {
        DuoSnapshot(
            memberID: "M1", name: "Marion", sexRaw: "female",
            level: 11, totalXP: 2_340, xpIntoLevel: 140, xpForNextLevel: 220,
            dayKey: "2026-08-16",
            kcalEaten: 1_180, kcalTarget: 1_550, burned: 310, burnTarget: 400, steps: steps,
            quest: quest, events: events, generatedAt: Date(timeIntervalSince1970: 1_000))
    }

    /// Ce que j'écris, l'autre le relit à l'identique. Ce test est le garde-fou du
    /// contrat de câble : les deux côtés passent par `DuoRecord.Field`, donc une faute de
    /// frappe est la même des deux côtés ou ne compile pas — mais un champ ÉCRIT et
    /// jamais RELU passerait sans lui.
    func testUnInstantaneFaitLAllerRetourParSonEnregistrement() throws {
        let evenements = [
            DuoEvent(id: "E1", kind: .meal, at: Date(timeIntervalSince1970: 5_000),
                     title: "Salade de lentilles", subtitle: "déjeuner, ~ 420 kcal"),
            DuoEvent(id: "E2", kind: .activity, at: Date(timeIntervalSince1970: 9_000),
                     title: "Vélo tranquille", subtitle: "20 min, +30 XP"),
        ]
        let depart = instantane(events: evenements)

        let relu = try XCTUnwrap(DuoRecord.snapshot(from: DuoRecord.member(from: depart,
                                                                          in: zone)))

        // `==` ignore `generatedAt` par décision (il pilote la garde de publication),
        // donc l'horodatage se vérifie à part — c'est lui qui porte la ligne de fraîcheur.
        XCTAssertEqual(relu, depart)
        XCTAssertEqual(relu.generatedAt, depart.generatedAt)
        XCTAssertEqual(relu.events, evenements)
    }

    /// La sentinelle des pas traverse le câble telle quelle. Un `-1` relu en `0`
    /// afficherait « 0 pas » à quelqu'un qui a marché toute la journée.
    func testLaSentinelleDesPasSurvitALAllerRetour() throws {
        let relu = try XCTUnwrap(
            DuoRecord.snapshot(from: DuoRecord.member(
                from: instantane(steps: DuoSnapshot.stepsUnavailable), in: zone)))

        XCTAssertEqual(relu.steps, DuoSnapshot.stepsUnavailable)
    }

    func testSansQueteLaLectureNeFabriquePasDeQuete() throws {
        let relu = try XCTUnwrap(
            DuoRecord.snapshot(from: DuoRecord.member(from: instantane(quest: nil), in: zone)))

        XCTAssertNil(relu.quest)
    }

    /// Une quête amputée d'un de ses trois champs n'est PAS une quête à 0/0 : elle n'est
    /// pas. Le côté écriture prend déjà cette précaution ; la lecture doit la reprendre,
    /// sans quoi une écriture partielle afficherait « Bouger 4 fois, 0/0 » chez l'autre.
    func testUneQueteIncompleteNeDevientJamaisZeroSurZero() throws {
        let record = DuoRecord.member(from: instantane(), in: zone)
        record[DuoRecord.Field.questTotal] = nil

        XCTAssertNil(try XCTUnwrap(DuoRecord.snapshot(from: record)).quest)
    }

    /// Un enregistrement amputé d'un champ obligatoire n'est pas affiché du tout : le
    /// cache et sa ligne de fraîcheur disent alors la vérité sur l'âge des chiffres,
    /// alors qu'un champ remplacé par 0 mentirait sans le dire.
    func testUnEnregistrementAmputeNEstPasAffiche() {
        for champ in [DuoRecord.Field.name, DuoRecord.Field.kcalEaten,
                      DuoRecord.Field.dayKey, DuoRecord.Field.generatedAt] {
            let record = DuoRecord.member(from: instantane(), in: zone)
            record[champ] = nil

            XCTAssertNil(DuoRecord.snapshot(from: record), champ)
        }
    }

    // MARK: Le membre et sa date de création

    func testUnMembreSeLitAvecSonIdentifiant() throws {
        let reference = try XCTUnwrap(
            DuoRecord.memberRef(from: DuoRecord.member(from: instantane(), in: zone)))

        XCTAssertEqual(reference.memberID, "M1")
    }

    /// `creationDate` est posé par le serveur : il est nil sur un enregistrement qui n'a
    /// jamais été écrit. Un tel membre ne doit pas rafler la place du premier arrivé, donc
    /// il est daté du futur le plus lointain, jamais du passé.
    func testUnMembreSansDateDeCreationNePrendPasLaPlaceDuPremierArrive() throws {
        let inconnu = try XCTUnwrap(
            DuoRecord.memberRef(from: DuoRecord.member(from: instantane(), in: zone)))
        let vrai = DuoMemberRef(memberID: "A", createdAt: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(inconnu.createdAt, .distantFuture)
        XCTAssertEqual(DuoService.partner(among: [inconnu, vrai], excluding: "MOI")?.memberID,
                       "A")
    }

    // MARK: Les cœurs

    func testUnCoeurSeLitAvecSonDonneurEtSonTitre() throws {
        let record = CKRecord(recordType: DuoRecord.likeType,
                              recordID: CKRecord.ID(recordName: "like-G1-E1", zoneID: zone))
        record[DuoRecord.Field.giverID] = "G1" as CKRecordValue
        record[DuoRecord.Field.ownerID] = "MOI" as CKRecordValue
        record[DuoRecord.Field.eventID] = "E1" as CKRecordValue
        record[DuoRecord.Field.eventTitle] = "Poisson et purée maison" as CKRecordValue
        record[DuoRecord.Field.createdAt] = Date(timeIntervalSince1970: 700) as CKRecordValue

        let coeur = try XCTUnwrap(DuoRecord.like(from: record))

        XCTAssertEqual(coeur.giverID, "G1")
        XCTAssertEqual(coeur.ownerID, "MOI")
        XCTAssertEqual(coeur.eventID, "E1")
        XCTAssertEqual(coeur.eventTitle, "Poisson et purée maison")
        XCTAssertEqual(coeur.createdAt, Date(timeIntervalSince1970: 700))
        // Le nom d'enregistrement se recompose depuis les deux seuls champs qui le
        // fabriquent, et sert d'identité stable en liste.
        XCTAssertEqual(coeur.id, DuoLikeID.recordName(giver: "G1", event: "E1"))
    }

    /// Seuls les deux champs dont dépendent les décisions sont exigés, comme pour
    /// `likeRef` : un cœur privé de son titre reste un cœur, et le faire disparaître pour
    /// si peu répéterait la faute du lot A1.
    func testUnCoeurSansTitreNiDonneurResteExploitable() throws {
        let record = CKRecord(recordType: DuoRecord.likeType,
                              recordID: CKRecord.ID(recordName: "like-G1-E1", zoneID: zone))
        record[DuoRecord.Field.ownerID] = "MOI" as CKRecordValue
        record[DuoRecord.Field.eventID] = "E1" as CKRecordValue

        let coeur = try XCTUnwrap(DuoRecord.like(from: record))

        XCTAssertEqual(coeur.eventID, "E1")
        XCTAssertEqual(coeur.eventTitle, "")
        XCTAssertEqual(coeur.giverID, "")
    }

    func testUnCoeurSansEvenementNEstPasExploitable() {
        let record = CKRecord(recordType: DuoRecord.likeType,
                              recordID: CKRecord.ID(recordName: "like-G1-", zoneID: zone))
        record[DuoRecord.Field.ownerID] = "MOI" as CKRecordValue

        XCTAssertNil(DuoRecord.like(from: record))
    }
}

// MARK: - Regarder ce qu'on a écrit

/// **En mode non atomique, `modifyRecords` ne lève pas sur un échec par enregistrement** :
/// il le range dans les résultats et rend la main normalement. Trois appels du duo jetaient
/// ce tuple, et prenaient donc un échec pour un succès — instantané mémorisé sans avoir été
/// publié, cœur sorti de la file de rejeu sans être parti.
final class DuoWriteResultTests: XCTestCase {
    private let zone = CKRecordZone.ID(zoneName: "duo", ownerName: CKCurrentUserDefaultName)

    private func identifiant(_ nom: String) -> CKRecord.ID {
        CKRecord.ID(recordName: nom, zoneID: zone)
    }

    func testUnLotEntierementReussiEstReussi() {
        let resultats: [CKRecord.ID: Result<CKRecord, any Error>] = [
            identifiant("A"): .success(CKRecord(recordType: DuoRecord.likeType,
                                                recordID: identifiant("A"))),
        ]

        XCTAssertTrue(DuoRecord.allSucceeded(resultats))
    }

    /// UN seul enregistrement en échec suffit à faire échouer le lot : c'est tout l'intérêt,
    /// puisque l'appel, lui, n'a rien levé.
    func testUnSeulEchecSuffitAFaireEchouerLeLot() {
        let resultats: [CKRecord.ID: Result<CKRecord, any Error>] = [
            identifiant("A"): .success(CKRecord(recordType: DuoRecord.likeType,
                                                recordID: identifiant("A"))),
            identifiant("B"): .failure(CKError(.networkFailure)),
        ]

        XCTAssertFalse(DuoRecord.allSucceeded(resultats))
    }

    /// Un lot vide est réussi : c'est le cas d'une publication sans aucun cœur orphelin à
    /// supprimer, et il ne doit surtout pas passer pour un échec.
    func testUnLotVideEstReussi() {
        let vide: [CKRecord.ID: Result<Void, any Error>] = [:]

        XCTAssertTrue(DuoRecord.allSucceeded(vide))
    }
}

// MARK: - L'état observable

/// La seule suite qui construise un `DuoService`. Domaine de réglages dédié, jeté au
/// `tearDown` : le lot A1 a corrigé un défaut critique où des suites qui n'avaient jamais
/// entendu parler du duo laissaient une identité dans les vrais réglages de l'hôte de test.
@MainActor
final class DuoServiceStateTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "nivel.tests.duoservice.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func instantane(events: [DuoEvent]) -> DuoSnapshot {
        DuoSnapshot(
            memberID: "M-partenaire", name: "Marion", sexRaw: "female",
            level: 11, totalXP: 2_340, xpIntoLevel: 140, xpForNextLevel: 220,
            dayKey: "2026-08-16",
            kcalEaten: 1_180, kcalTarget: 1_550, burned: 310, burnTarget: 400, steps: 7_240,
            quest: nil, events: events, generatedAt: Date(timeIntervalSince1970: 1_000))
    }

    private func evenement(a secondes: TimeInterval) -> DuoEvent {
        DuoEvent(id: "E-\(secondes)", kind: .meal, at: Date(timeIntervalSince1970: secondes),
                 title: "Dîner", subtitle: "dîner, ~ 620 kcal")
    }

    /// LA promesse du §3.1 : sans duo appairé, aucune requête réseau n'est émise et l'app
    /// se comporte exactement comme la 1.14. La zone n'est même pas RÉSOLUE — le compteur
    /// ci-dessous rougit à la première tentative.
    func testSansDuoAppairreAucuneZoneNEstMemeResolue() async {
        var resolutions = 0
        let service = DuoService(identity: DuoIdentity(defaults: defaults),
                                 resolveTarget: { _ in resolutions += 1; return nil })

        await service.refresh()

        XCTAssertEqual(resolutions, 0)
        XCTAssertFalse(service.isPaired)
        XCTAssertNil(service.partnerSnapshot)
        XCTAssertTrue(service.receivedLikes.isEmpty)
    }

    /// La pastille de l'accueil est portée par `DuoBadge.hasNewActivity` (lot A1) ; le
    /// service ne fait que lui donner le fil du partenaire et la date de dernière visite,
    /// qui vivent tous deux dans `DuoIdentity`.
    func testLaPastilleSuitLeFilDuPartenaireEtLaDerniereVisite() {
        let identite = DuoIdentity(defaults: defaults)
        identite.partnerSnapshot = instantane(events: [evenement(a: 5_000)])
        let service = DuoService(identity: identite, resolveTarget: { _ in nil })

        identite.profileLastSeenAt = nil
        XCTAssertTrue(service.hasNewActivity, "jamais visité, et un fil non vide")

        identite.profileLastSeenAt = Date(timeIntervalSince1970: 9_000)
        XCTAssertFalse(service.hasNewActivity, "tout le fil est antérieur à la visite")
    }

    /// Ouvrir la page éteint le signal (spec §3.9) : la pastille et le compteur de cœurs
    /// non lus retombent, et la date de visite est PERSISTÉE — sinon la pastille
    /// reviendrait au lancement suivant, sur des événements déjà vus.
    func testOuvrirLaPageEteintLaPastilleEtLesNonLus() {
        let identite = DuoIdentity(defaults: defaults)
        identite.partnerSnapshot = instantane(events: [evenement(a: 5_000)])
        identite.unreadLikeCount = 3
        let service = DuoService(identity: identite, resolveTarget: { _ in nil })

        service.markProfileSeen(at: Date(timeIntervalSince1970: 6_000))

        XCTAssertFalse(service.hasNewActivity)
        XCTAssertEqual(identite.unreadLikeCount, 0)
        XCTAssertEqual(DuoIdentity(defaults: defaults).profileLastSeenAt,
                       Date(timeIntervalSince1970: 6_000))
    }
}
