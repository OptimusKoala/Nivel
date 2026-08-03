// NivelCore/Tests/NivelCoreTests/ProfileNameTests.swift
// Règle de nettoyage du prénom (spec v1.12 §7). Partagée par l'onboarding et les
// Réglages : les deux écrans doivent accepter et refuser exactement la même chose.

import XCTest
@testable import NivelCore

final class ProfileNameTests: XCTestCase {

    // MARK: - sanitized

    func testRetireLesEspacesDeTeteEtDeQueue() {
        XCTAssertEqual(ProfileName.sanitized("  Michaël  "), "Michaël")
        XCTAssertEqual(ProfileName.sanitized("\nMarion\n"), "Marion")
    }

    /// Le vrai piège d'un trim naïf : un prénom composé ou en deux mots contient
    /// des espaces et des tirets légitimes, qui doivent survivre intacts.
    func testPreserveLesPrenomsComposes() {
        XCTAssertEqual(ProfileName.sanitized("Jean-Marc"), "Jean-Marc")
        XCTAssertEqual(ProfileName.sanitized("  Marie Claire  "), "Marie Claire")
    }

    func testUneChaineDEspacesDevientVide() {
        XCTAssertEqual(ProfileName.sanitized("   "), "")
        XCTAssertEqual(ProfileName.sanitized("\t\n "), "")
    }

    func testLaCasseNEstPasTouchee() {
        // Le nettoyage ne corrige pas la casse : c'est le clavier qui capitalise
        // (textInputAutocapitalization), et « de Broglie » doit rester possible.
        XCTAssertEqual(ProfileName.sanitized("michaël"), "michaël")
    }

    // MARK: - isAcceptable

    func testAcceptableQuandIlResteQuelqueChose() {
        XCTAssertTrue(ProfileName.isAcceptable("Michaël"))
        XCTAssertTrue(ProfileName.isAcceptable("  Marion  "))
        XCTAssertTrue(ProfileName.isAcceptable("X"))
    }

    func testRefuseLeVideEtLesEspacesSeuls() {
        XCTAssertFalse(ProfileName.isAcceptable(""))
        XCTAssertFalse(ProfileName.isAcceptable("   "))
        XCTAssertFalse(ProfileName.isAcceptable("\n\t"))
    }
}
