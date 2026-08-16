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
    /// Géométrie, toute en points. Le piège d'abord, parce qu'il a déjà fait tomber
    /// deux versions : le plafond de 130 est la largeur du CADRE, pas celle du
    /// `ZStack`. Le `.padding(ringOuterPadding)` est posé AVANT le `.frame`, donc il
    /// retranche au lieu d'ajouter, et le `ZStack` ne reçoit que **118**. Tout ce qui
    /// suit part de 118 ; en partant de 130 on se trompe de 12 sur chaque longueur.
    ///
    /// Ensuite : le second anneau est posé avec `.padding(14)`, son cercle fait donc
    /// 90 de diamètre et son trait 8, ce qui laisse un disque blanc de 82, soit un
    /// rayon de 41. Le bloc de deux lignes occupe environ 34 de haut, donc son coin le
    /// plus éloigné se trouve à 17 du centre : la demi-corde utile y vaut
    /// √(41² − 17²) ≈ 37,3, soit **74,6 de large**.
    ///
    /// La largeur laissée au texte doit rester sous cette corde. Elle vaut aujourd'hui
    /// 118 − 2×24 = 70, et il reste donc 4,6 de marge. Avec 14 de rembourrage elle
    /// valait 90 : le texte avait le droit d'être plus large que le cercle censé le
    /// contenir, et `minimumScaleFactor` ne le rattrapait qu'après qu'il ait mordu le
    /// tracé.
    ///
    /// La largeur se CALCULE à partir des constantes, `ringOuterPadding` compris : un
    /// jour où l'on touchera à l'une d'elles, c'est ce calcul qui doit bouger, pas la
    /// confiance qu'on place dans un nombre recopié.
    func testLaLargeurLaisseeAuTexteResteSousLaCordeDuDisqueInterieur() {
        let largeurDisponible = CalorieRingCard.ringMaxWidth
            - 2 * CalorieRingCard.ringOuterPadding
            - 2 * CalorieRingCard.centerHorizontalPadding
        XCTAssertLessThanOrEqual(largeurDisponible, 74,
                                 "le texte central peut déborder du disque blanc")
    }

    /// Ce que le plafond de Dynamic Type garde, et que ce lot ne touche pas.
    func testLePlafondDeDynamicTypeResteLarge() {
        XCTAssertEqual(CalorieRingCard.centerTypeSizeCap, .large)
    }
}
