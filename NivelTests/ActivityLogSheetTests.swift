// NivelTests/ActivityLogSheetTests.swift
// Contrat de la puce « Autre » (spec v1.9 §5.1, exigence de test §8). Même approche que
// SessionPlayerTests : la décision est une fonction pure statique sur la vue, testable
// sans piloter SwiftUI.

import XCTest
import NivelCore
@testable import Nivel

final class ActivityLogSheetTests: XCTestCase {
    private let durations = [10, 20, 40]

    private func wheelValue(current: DurationSelection?, wheelValue: Int = 20) -> Int {
        ActivityLogSheet.wheelValueOnCustomTap(current: current, wheelValue: wheelValue,
                                               durations: durations)
    }

    /// Rien de choisi : la roue s'ouvre sur la médiane du catalogue de l'activité.
    func testSansSelectionOuvreSurLaMediane() {
        XCTAssertEqual(wheelValue(current: nil), 20)
    }

    /// Le vrai cas de la régression : taper une puce puis « Autre » doit ouvrir la roue
    /// SUR cette puce, pas sur la valeur figée au chargement de la feuille.
    func testDepuisUnePuceOuvreSurCettePuce() {
        XCTAssertEqual(wheelValue(current: .preset(40), wheelValue: 20), 40)
        XCTAssertEqual(wheelValue(current: .preset(10), wheelValue: 20), 10)
    }

    /// Re-taper « Autre » déjà sélectionné ne doit pas effacer la valeur ajustée.
    func testRetaperAutreGardeLaValeurAjustee() {
        XCTAssertEqual(wheelValue(current: .custom(97), wheelValue: 97), 97)
    }

    /// Une puce hors des bornes de la roue retombe sur la médiane plutôt que d'ouvrir
    /// sur une valeur que la roue ne peut pas afficher.
    func testPuceHorsBornesRetombeSurLaMediane() {
        XCTAssertEqual(wheelValue(current: .preset(999)), 20)
    }
}
