// NivelTests/CalorieRingCenterTests.swift
// Le contenu central du double anneau (spec 1.15 §4) : quatre chiffres doivent
// tenir DANS le disque blanc, pas seulement dans le cadre carré de l'anneau.

import XCTest
@testable import Nivel

final class CalorieRingCenterTests: XCTestCase {

    /// Les deux valeurs de la spec 1.15 §4. Épinglées et non bornées : elles ont été
    /// relevées à l'image, et une dérive « juste un point de plus » ramènerait
    /// exactement le défaut qu'on corrige.
    func testLesDeuxConstantesDuCentreSontCellesDeLaSpec() {
        XCTAssertEqual(CalorieRingCard.centerFontSize, 22)
        XCTAssertEqual(CalorieRingCard.centerHorizontalPadding, 24)
    }

    /// Le test qui porte le RAISONNEMENT, et pas seulement les nombres.
    ///
    /// Géométrie, toute en points : l'anneau est plafonné à 130 de large ; le second
    /// anneau est posé avec `.padding(14)`, son cercle fait donc 102 de diamètre et
    /// son trait 8, ce qui laisse un disque blanc de 94. Le bloc de deux lignes
    /// occupe environ 34 de haut, donc son coin le plus éloigné se trouve à 17 du
    /// centre : la demi-corde utile y vaut √(47² − 17²) ≈ 43,8, soit **87 de large**.
    ///
    /// La largeur laissée au texte doit rester sous cette corde. Avec 14 de
    /// rembourrage elle valait 102 : le texte avait le droit d'être plus large que le
    /// cercle censé le contenir, et `minimumScaleFactor` ne le rattrapait qu'après
    /// qu'il ait mordu le tracé.
    func testLaLargeurLaisseeAuTexteResteSousLaCordeDuDisqueInterieur() {
        let largeurDisponible = CalorieRingCard.ringMaxWidth
            - 2 * CalorieRingCard.centerHorizontalPadding
        XCTAssertLessThanOrEqual(largeurDisponible, 87,
                                 "le texte central peut déborder du disque blanc")
    }

    /// Ce que le plafond de Dynamic Type garde, et que ce lot ne touche pas.
    func testLePlafondDeDynamicTypeResteLarge() {
        XCTAssertEqual(CalorieRingCard.centerTypeSizeCap, .large)
    }
}
