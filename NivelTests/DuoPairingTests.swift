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

}
