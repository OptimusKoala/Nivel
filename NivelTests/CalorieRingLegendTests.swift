// NivelTests/CalorieRingLegendTests.swift
// Réglages de mise à l'échelle de la carte calories (spec v1.14 §5.5) : la légende de
// dépense s'efface aux tailles d'accessibilité, où elle passait à trois lignes et
// faisait presque doubler la hauteur de la carte ; le contenu central de l'anneau est
// plafonné, faute de quoi il se dessine par-dessus le tracé.
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

    // MARK: - Plafond du contenu central

    /// Le plafond exact, épinglé : l'anneau ne s'agrandit pas avec le texte, son centre
    /// non plus. `.large` a été retenu à l'image, pas déduit.
    func testLePlafondDuCentreEstLarge() {
        XCTAssertEqual(CalorieRingCard.centerTypeSizeCap, .large)
    }

    /// La raison du plafond, dite en termes de comportement : `.xLarge` est la première
    /// taille où le gros chiffre mord le tracé de l'anneau, donc le plafond doit rester
    /// STRICTEMENT en dessous. C'est cette borne-là qui l'a fixé — et non `.xxxLarge`,
    /// où c'est la seconde ligne qui traverse le tracé.
    func testLePlafondDuCentreResteSousLaTailleQuiMordLeTrace() {
        XCTAssertLessThan(CalorieRingCard.centerTypeSizeCap, .xLarge)
    }

    /// Un plafond au-delà des tailles ordinaires ne plafonnerait plus rien : c'est le
    /// sens même du réglage, et ça interdit de le « détendre » sans y penser.
    func testLePlafondDuCentreNEstPasUneTailleAccessibilite() {
        XCTAssertFalse(CalorieRingCard.centerTypeSizeCap.isAccessibilitySize)
    }
}
