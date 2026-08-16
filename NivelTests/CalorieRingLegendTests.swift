// NivelTests/CalorieRingLegendTests.swift
// La légende de dépense de la carte calories (spec v1.14 §5.5) : elle s'efface aux
// tailles d'accessibilité, où elle passait à trois lignes et faisait presque doubler la
// hauteur de la carte.
//
// Le contenu central de l'anneau — son plafond de taille compris — vit dans
// CalorieRingCenterTests depuis la 1.15, avec le reste de la géométrie du centre.
//
// Ce que ces tests couvrent, et ce qu'ils NE couvrent PAS. Comme MealLogSheetDismissTests,
// ils épinglent des décisions pures (une frontière, un plafond) extraites de la vue. Ils
// ne vérifient pas que la vue les applique : supprimer le `if showsBurnLegend` ou le
// `.dynamicTypeSize(...)` laisse cette suite verte. C'est la limite inhérente au
// découpage — la pose se vérifie à l'œil, au simulateur, pas ici.

import XCTest
import SwiftUI
@testable import Nivel

final class CalorieRingLegendTests: XCTestCase {
    /// Le cas ordinaire : à la taille par défaut, la légende est là.
    func testTailleParDefautAfficheLaLegende() {
        XCTAssertTrue(CalorieRingCard.showsBurnLegend(at: .large))
    }

    /// La frontière, dans le bon sens : `.xxxLarge` est la plus grande taille NON
    /// d'accessibilité, et la légende y reste affichée. Elle n'y « tient » pas au large
    /// pour autant — vérifié au simulateur, elle y passe déjà sur deux lignes, l'emoji
    /// seul sur la seconde. C'est la marge qu'on accepte, pas une marge confortable.
    func testPlusGrandeTailleOrdinaireGardeLaLegende() {
        XCTAssertTrue(CalorieRingCard.showsBurnLegend(at: .xxxLarge))
    }

    /// La frontière, dans l'autre sens : le premier cran d'accessibilité masque déjà.
    func testPremiereTailleAccessibiliteMasqueLaLegende() {
        XCTAssertFalse(CalorieRingCard.showsBurnLegend(at: .accessibility1))
    }

    /// Le vrai cas du défaut — la capture qui a déclenché la correction.
    func testTailleAccessibiliteXXLMasqueLaLegende() {
        XCTAssertFalse(CalorieRingCard.showsBurnLegend(at: .accessibility4))
    }

    /// Le seuil est unique et il tombe exactement entre `.xxxLarge` et `.accessibility1` :
    /// la liste est écrite en toutes lettres, et NON dérivée de `isAccessibilitySize`,
    /// pour que le test dise autre chose que l'implémentation. Si un jour SwiftUI
    /// reclassait une taille, c'est ici que ça se verrait.
    func testSeulesLesSeptTaillesOrdinairesAffichentLaLegende() {
        let affichent = DynamicTypeSize.allCases.filter { CalorieRingCard.showsBurnLegend(at: $0) }
        XCTAssertEqual(affichent, [.xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge])
    }
}
