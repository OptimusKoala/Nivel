// NivelTests/OnboardingIdentityTests.swift
// Garde du bouton Continuer de la page Identité (spec v1.12 §3 et §7). Même
// approche qu'ActivityLogSheetTests : la décision est une fonction pure statique
// sur la vue, testable sans piloter SwiftUI.

import XCTest
import NivelCore
@testable import Nivel

final class OnboardingIdentityTests: XCTestCase {

    private func canLeave(_ name: String, _ sex: Sex?) -> Bool {
        OnboardingFlow.canLeaveIdentity(name: name, sex: sex)
    }

    /// Le cas nominal.
    func testPrenomEtSexeRenseignesLaissentPasser() {
        XCTAssertTrue(canLeave("Michaël", .male))
        XCTAssertTrue(canLeave("Marion", .female))
    }

    /// La raison d'être de l'optionnel : sans choix explicite, l'objectif kcal
    /// serait calculé sur un sexe que personne n'a confirmé.
    func testSexeNonChoisiBloque() {
        XCTAssertFalse(canLeave("Michaël", nil))
    }

    func testPrenomVideBloque() {
        XCTAssertFalse(canLeave("", .male))
    }

    /// Une barre d'espaces n'est pas un prénom — sinon le repli supprimé
    /// reviendrait par la porte de derrière, sous forme d'un profil nommé « ».
    func testPrenomDEspacesBloque() {
        XCTAssertFalse(canLeave("   ", .male))
        XCTAssertFalse(canLeave("\n\t", .female))
    }

    /// Un prénom entouré d'espaces est valide : c'est la frappe normale au clavier.
    func testPrenomEntoureDEspacesLaissePasser() {
        XCTAssertTrue(canLeave("  Michaël  ", .male))
    }
}
