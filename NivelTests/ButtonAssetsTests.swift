// NivelTests/ButtonAssetsTests.swift
// Les deux illustrations des boutons d'action (spec v1.13 §6.2). `ActionCardButton`
// a un repli sur glyphe cozy, mais un asset manquant reste un bug de packaging :
// c'est ici qu'il doit se voir, pas sur l'accueil de l'App Store.

import XCTest
import UIKit
@testable import Nivel

final class ButtonAssetsTests: XCTestCase {
    /// Liste PINNÉE, sur le modèle d'IconAssetsTests : garde anti-typo de nommage.
    static let illustrationNames = ["button_icon_eating", "button_icon_sport"]

    func testEveryButtonIllustrationExists() throws {
        for name in Self.illustrationNames {
            let image = try XCTUnwrap(UIImage(named: "Buttons/\(name)"),
                                     "asset manquant : Buttons/\(name)")
            // Imageset single-scale : `.size` est en pixels. 384 px est ce que produit
            // scripts/import-button-icons.sh — attrape une source 1254 px déposée à la
            // main, qui embarquerait 900 Ko par bouton dans le binaire.
            XCTAssertEqual(image.size, CGSize(width: 384, height: 384),
                           "Buttons/\(name) : source non redimensionnée ?")
        }
    }

    /// Ce sont des illustrations en COULEURS, pas des glyphes template : un
    /// `template-rendering-intent` hérité par copier-coller les afficherait en aplat
    /// monochrome, teintes du bouton comprises.
    func testButtonIllustrationsAreNotTemplates() throws {
        for name in Self.illustrationNames {
            let image = try XCTUnwrap(UIImage(named: "Buttons/\(name)"))
            XCTAssertNotEqual(image.renderingMode, .alwaysTemplate, "Buttons/\(name)")
        }
    }
}
