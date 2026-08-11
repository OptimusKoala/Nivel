// NivelTests/TintedWidgetTests.swift
// Le contrat du mode teinté (spec v1.13 §3).
//
// Ce qu'un test PEUT prouver ici, et c'est tout : que l'information du rendu teinté
// est bien portée par l'ALPHA, et dans le bon ordre. C'est la seule propriété qui
// survit au remplacement des couleurs par WidgetKit.
//
// Ce qu'aucun test ne peut prouver : le rendu final. `\.widgetRenderingMode` est en
// lecture seule, et le remplacement des couleurs a lieu dans WidgetKit, pas dans
// SwiftUI. La vérification visuelle est donc manuelle et documentée (spec §3.4) :
// widget posé sur l'écran d'accueil du simulateur, basculé en mode teinté.

import XCTest
import SwiftUI
import UIKit
@testable import Nivel

final class TintedWidgetTests: XCTestCase {
    /// L'opacité effective d'une couleur SwiftUI.
    private func alpha(_ color: Color) -> CGFloat {
        UIColor(color).cgColor.alpha
    }

    // MARK: La palette teintée

    /// Le fond est transparent : c'est le système qui fournit la tuile translucide.
    /// Un fond opaque ici referait exactement le bug de la 1.12.
    func testAccentedBackgroundIsFullyTransparent() {
        XCTAssertEqual(alpha(ThemePalette.accented.background), 0, accuracy: 0.001)
    }

    /// L'ordre de lisibilité, du plus discret au plus appuyé. C'est LUI qui remplace
    /// la teinte : deux rôles au même alpha seraient indiscernables après remplacement.
    func testAccentedRolesAreOrderedByAlpha() {
        let p = ThemePalette.accented
        // La piste de l'anneau passe sous la carte, qui passe sous le texte secondaire.
        XCTAssertLessThan(alpha(p.track), alpha(p.card))
        XCTAssertLessThan(alpha(p.card), alpha(p.subtext))
        // Le texte secondaire reste nettement en dessous de l'encre pleine.
        XCTAssertLessThan(alpha(p.subtext), alpha(p.accent))
        // La progression est juste sous l'encre pleine.
        XCTAssertLessThan(alpha(p.accent), alpha(p.text))
        // L'encre pleine : texte, couleur principale et contour de la mascotte.
        for (name, color) in [("text", p.text), ("primary", p.primary), ("outline", p.outline)] {
            XCTAssertEqual(alpha(color), 1, accuracy: 0.001, name)
        }
    }

    /// L'anneau distingue sa piste de sa progression par un écart d'alpha franc —
    /// sans quoi il n'afficherait plus qu'un cercle plein.
    func testAccentedRingSeparatesTrackFromProgress() {
        let p = ThemePalette.accented
        XCTAssertGreaterThan(alpha(p.success) - alpha(p.track), 0.5)
        XCTAssertGreaterThan(alpha(p.accent) - alpha(p.track), 0.5)
    }

    /// La palette teintée est IMPOSÉE par le système, jamais choisie : elle doit rester
    /// hors des Réglages, et `byID` ne doit jamais la retourner — pas même pour son
    /// propre id, qu'un snapshot corrompu pourrait porter.
    func testAccentedPaletteIsNotSelectable() {
        XCTAssertEqual(ThemePalette.all.count, 4)
        XCTAssertFalse(ThemePalette.all.contains { $0.id == ThemePalette.accented.id })
        XCTAssertEqual(ThemePalette.byID("accented").id, ThemePalette.creme.id)
        XCTAssertEqual(ThemePalette.byID(nil).id, ThemePalette.creme.id)
    }

    // MARK: Les encres de la mascotte

    /// `.full` ne fait que relayer les couleurs d'identité : aucune dérive possible.
    func testFullInkKeepsTheMascotIdentityColours() {
        let ink = NivelitoInk.full
        XCTAssertEqual(UIColor(ink.fur), UIColor(NivelitoColors.fur))
        XCTAssertEqual(UIColor(ink.cream), UIColor(NivelitoColors.cream))
        XCTAssertEqual(UIColor(ink.earBrown), UIColor(NivelitoColors.earBrown))
        XCTAssertEqual(UIColor(ink.cheekBrown), UIColor(NivelitoColors.cheekBrown))
        XCTAssertEqual(UIColor(ink.blushPink), UIColor(NivelitoColors.blushPink))
    }

    /// Le dessin teinté est reconnaissable parce que l'ORDRE de clarté du dessin
    /// d'origine est conservé : les creux d'oreille et les joues sont plus sombres que
    /// la fourrure, qui est plus sombre que le museau crème. C'est cet ordre, et non
    /// les couleurs, qui fait la mascotte.
    func testTintedInkPreservesTheDrawingsLightnessOrder() {
        let ink = NivelitoInk.tinted
        XCTAssertLessThan(alpha(ink.cheekBrown), alpha(ink.fur))
        XCTAssertLessThan(alpha(ink.earBrown), alpha(ink.fur))
        XCTAssertLessThan(alpha(ink.fur), alpha(ink.cream))
        XCTAssertLessThan(alpha(ink.cream), 1)
    }

    /// La fourrure doit rester un FOND : au-delà, la tête devient un aplat sur lequel
    /// museau et oreilles ne se détachent plus. Borne haute pinnée à dessein.
    func testTintedFurStaysABackground() {
        XCTAssertLessThanOrEqual(alpha(NivelitoInk.tinted.fur), 0.35)
    }

    /// Toutes les encres teintées sont du blanc : la teinte est de toute façon
    /// remplacée, et une couleur résiduelle ici ne serait qu'un mensonge sur l'intention.
    func testTintedInkIsWhiteOnly() {
        let ink = NivelitoInk.tinted
        for color in [ink.fur, ink.cream, ink.earBrown, ink.cheekBrown, ink.blushPink, ink.eyeHighlight] {
            var white: CGFloat = 0
            var alpha: CGFloat = 0
            XCTAssertTrue(UIColor(color).getWhite(&white, alpha: &alpha))
            XCTAssertEqual(white, 1, accuracy: 0.001)
        }
    }
}
