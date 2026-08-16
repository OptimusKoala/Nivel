// NivelTests/CalorieRingCenterTests.swift
// Le contenu central du double anneau (spec 1.15 §4) : quatre chiffres doivent
// tenir DANS le disque blanc, pas seulement dans le cadre carré de l'anneau.
//
// Ce que cette suite couvre, et ce qu'elle ne couvre PAS. Elle épingle des décisions
// extraites de la vue (des constantes, un plafond) et vérifie qu'elles sont
// COHÉRENTES ENTRE ELLES par le calcul. Elle ne vérifie pas que la vue les pose :
// supprimer le `.padding(.horizontal:)` ou le `.minimumScaleFactor()` laisse cette
// suite verte. La pose se vérifie à l'œil, au simulateur, ou sur la prévisualisation
// « Pire cas, 4 chiffres ».

import XCTest
import SwiftUI
import UIKit
@testable import Nivel

final class CalorieRingCenterTests: XCTestCase {

    // MARK: - Les constantes de la spec

    /// Les deux valeurs de la spec 1.15 §4. Épinglées et non bornées : elles ont été
    /// relevées à l'image, et une dérive « juste un point de plus » ramènerait
    /// exactement le défaut qu'on corrige.
    func testLesDeuxConstantesDuCentreSontCellesDeLaSpec() {
        XCTAssertEqual(CalorieRingCard.centerFontSize, 22)
        XCTAssertEqual(CalorieRingCard.centerHorizontalPadding, 24)
    }

    // MARK: - Géométrie du disque blanc

    /// Écart vertical, depuis le centre du disque, du coin d'encre le plus éloigné.
    ///
    /// MESURÉ (CoreText, SF Rounded), pas déduit — d'où la constante plutôt qu'un
    /// calcul. Métriques relevées : gros chiffre à 22 pt heavy rounded, ascendante
    /// 21,27, hauteur de capitale 15,50, hauteur de ligne 25,91 ; caption2, ascendante
    /// 10,63, hauteur de ligne 12,96 ; espacement du `VStack` 2.
    ///
    /// Dérivation. Hauteur de mise en page = 25,91 + 2 + 12,96 = 40,87, donc un
    /// demi-bloc de 20,435. Mais ce qui mord le tracé, c'est l'ENCRE, pas la boîte de
    /// ligne — et les deux ne coïncident pas :
    /// - en haut, les chiffres SF sont des capitales, il reste donc 21,27 − 15,50 =
    ///   5,77 de réserve d'ascendante VIDE au-dessus d'eux. Sommet de l'encre à 5,77
    ///   du haut, soit 14,67 du centre ;
    /// - en bas, aucun glyphe de « / 9 999 kcal » ne descend sous la ligne de base :
    ///   la place des descendantes est réservée mais inoccupée. L'encre s'arrête donc
    ///   à la ligne de base, à 25,91 + 2 + 10,63 = 38,54 du haut, soit 18,10 du centre.
    ///
    /// Le pire coin est donc le bas, à 18,10 — et non les 20,435 de la boîte. Prendre
    /// la boîte serait pessimiste ; prendre une demi-hauteur ronde « ≈ 17 », comme
    /// deux relectures successives l'ont fait, était optimiste ET faux.
    private static let ecartEncreMax: CGFloat = 18.10

    /// Rayon du disque blanc, CALCULÉ depuis les constantes de la vue et non recopié.
    ///
    /// C'est le point de la chose : le `.padding` et l'épaisseur de trait de l'anneau
    /// intérieur pilotent ce rayon. Tant qu'ils étaient en dur dans `ring`, on pouvait
    /// rétrécir le disque — et ramener le défaut — en laissant cette suite verte.
    private static var rayonDuDisqueBlanc: CGFloat {
        (CalorieRingCard.ringMaxWidth
         - 2 * CalorieRingCard.ringOuterPadding
         - 2 * CalorieRingCard.innerRingPadding
         - CalorieRingCard.innerRingLineWidth) / 2
    }

    /// Largeur réellement offerte au texte : le `ZStack` (le cadre MOINS la marge
    /// extérieure, qui retranche au lieu d'ajouter) moins le rembourrage du bloc.
    private static var largeurOfferteAuTexte: CGFloat {
        CalorieRingCard.ringMaxWidth
            - 2 * CalorieRingCard.ringOuterPadding
            - 2 * CalorieRingCard.centerHorizontalPadding
    }

    /// Le repère intermédiaire, épinglé pour que l'erreur se lise ICI plutôt que dans
    /// un écart de quelques dixièmes sur la corde : 130 − 12 − 28 − 8, sur deux, = 41.
    func testLeDisqueBlancFaitQuaranteEtUnDeRayon() {
        XCTAssertEqual(Self.rayonDuDisqueBlanc, 41, accuracy: 0.01)
    }

    /// Le test qui porte le RAISONNEMENT, et pas seulement les nombres.
    ///
    /// Le piège d'abord, parce qu'il a déjà fait tomber deux versions : le plafond de
    /// 130 est la largeur du CADRE, pas celle du `ZStack`. Le
    /// `.padding(ringOuterPadding)` est posé AVANT le `.frame`, donc il retranche au
    /// lieu d'ajouter, et le `ZStack` ne reçoit que 118. En partant de 130 on se
    /// trompe de 12 sur chaque longueur.
    ///
    /// Ensuite, dans un disque, la place disponible dépend de la HAUTEUR à laquelle on
    /// se place : ce n'est pas le diamètre qui compte mais la corde à l'écart d'encre
    /// le plus défavorable (voir `ecartEncreMax`). Avec un rayon de 41 et un écart de
    /// 18,10 : corde = 2·√(41² − 18,10²) ≈ 73,6, pour 70 offerts au texte. Il reste
    /// 3,6 de marge, et c'est mince — d'où l'assertion, qui la surveille.
    func testLaLargeurOfferteAuTexteResteSousLaCordeDuDisqueBlanc() {
        let rayon = Self.rayonDuDisqueBlanc
        let corde = 2 * sqrt(rayon * rayon - Self.ecartEncreMax * Self.ecartEncreMax)

        XCTAssertLessThanOrEqual(
            Self.largeurOfferteAuTexte, corde,
            "le texte central peut déborder du disque blanc : \(Self.largeurOfferteAuTexte) offerts pour une corde de \(corde)"
        )
    }

    // MARK: - Réserve avant le plancher de réduction

    /// La chaîne du pire cas, construite comme la vue la construit (`frFormatted`,
    /// donc l'espace fine insécable du français) plutôt que recopiée à la main.
    private static let pireChaine = "~\(9_999.frFormatted)"

    /// Largeur rendue de la chaîne à une taille donnée, dans la police du gros chiffre.
    ///
    /// La valeur exacte (~79,9 pt à 22 pt) n'est épinglée NULLE PART : c'est une
    /// métrique système, elle peut bouger d'une version d'iOS à l'autre. Ce qu'on
    /// teste, c'est le FACTEUR qui s'en déduit, qui est la grandeur de décision.
    private static func largeurRendue(taille: CGFloat) -> CGFloat {
        let base = UIFont.systemFont(ofSize: taille, weight: .heavy)
        let police = base.fontDescriptor.withDesign(.rounded)
            .map { UIFont(descriptor: $0, size: taille) } ?? base
        return NSAttributedString(string: pireChaine, attributes: [.font: police]).size().width
    }

    /// Facteur de réduction dont `minimumScaleFactor` a besoin pour faire tenir le pire
    /// cas dans la largeur offerte. En dessous de 1, le texte est réduit.
    private static func facteurRequis(taille: CGFloat) -> CGFloat {
        largeurOfferteAuTexte / largeurRendue(taille: taille)
    }

    /// L'invariant dur : le facteur requis doit rester AU-DESSUS du plancher, sans quoi
    /// `minimumScaleFactor` ne peut plus réduire assez et le texte déborde pour de bon.
    func testLeGrosChiffreNExigeJamaisPlusDeReductionQueLePlancherNEnAutorise() {
        XCTAssertGreaterThan(Self.facteurRequis(taille: CalorieRingCard.centerFontSize),
                             CalorieRingCard.centerMinimumScaleFactor)
    }

    /// L'assertion qui défend le choix de 22, et la seule qui ait des dents sur ce
    /// point : à 26 pt le texte TENAIT DÉJÀ (facteur 0,74, au-dessus du plancher de
    /// 0,70), donc le test ci-dessus passait aussi. Ce que 22 achète n'est pas de faire
    /// tenir le texte, c'est de la RÉSERVE avant le plancher : 0,88 au lieu de 0,74.
    ///
    /// Le seuil de 0,80 encode cette réserve. Il échoue à 26 pt — vérifié — donc
    /// remonter la taille sans y penser se voit ici.
    func testLeGrosChiffreGardeDeLaReserveAvantLePlancherDeReduction() {
        XCTAssertGreaterThan(Self.facteurRequis(taille: CalorieRingCard.centerFontSize), 0.80)
    }

    /// Le plancher lui-même, épinglé. À quatre chiffres il n'est pas décoratif : le
    /// gros chiffre est effectivement rendu autour de 19 pt et non 22.
    func testLePlancherDeReductionResteA0_7() {
        XCTAssertEqual(CalorieRingCard.centerMinimumScaleFactor, 0.7)
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
