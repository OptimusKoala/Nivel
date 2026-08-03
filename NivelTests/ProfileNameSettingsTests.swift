// NivelTests/ProfileNameSettingsTests.swift
// Le champ Prénom des Réglages ne doit jamais persister un prénom vide (spec
// v1.12 §6). Même mécanique que l'objectif kcal, testée de la même façon : la
// décision « faut-il persister cette frappe ? » est une fonction pure.

import XCTest
import NivelCore
@testable import Nivel

final class ProfileNameSettingsTests: XCTestCase {

    private func commit(_ typed: String, current: String = "Michaël") -> String? {
        SettingsContent.nameToCommit(typed, current: current)
    }

    /// Le cas nominal : un prénom différent est persisté, nettoyé.
    func testUnNouveauPrenomEstPersisteNettoye() {
        XCTAssertEqual(commit("Marion"), "Marion")
        XCTAssertEqual(commit("  Marion  "), "Marion")
    }

    /// Le vrai risque du champ libre : vider le champ ne doit pas laisser un
    /// profil sans nom, qui rendrait l'Accueil et le widget muets en silence.
    func testUnChampVideNePersisteRien() {
        XCTAssertNil(commit(""))
        XCTAssertNil(commit("   "))
        XCTAssertNil(commit("\n\t"))
    }

    /// Rien à écrire quand la valeur nettoyée est déjà celle persistée : évite un
    /// save() et une synchro widget à chaque frappe qui ne change rien.
    func testIdentiqueNePersisteRien() {
        XCTAssertNil(commit("Michaël"))
        XCTAssertNil(commit("  Michaël  "))
    }
}
