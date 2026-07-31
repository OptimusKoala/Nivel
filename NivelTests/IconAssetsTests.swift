// NivelTests/IconAssetsTests.swift
import XCTest
import UIKit
@testable import Nivel

final class IconAssetsTests: XCTestCase {
    /// Les 15 glyphes cozy (spec icônes §2) — liste PINNÉE, garde anti-typo de nommage.
    static let iconNames = [
        "tab_home", "tab_home_fill", "tab_meals", "tab_meals_fill",
        "tab_sport", "tab_sport_fill", "tab_progress", "tab_progress_fill",
        "tab_quests", "tab_quests_fill",
        "icon_settings", "icon_check", "icon_play", "icon_pause", "icon_restart",
    ]

    func testEveryCozyIconAssetExists() {
        for name in Self.iconNames {
            let image = UIImage(named: "Icons/\(name)")
            XCTAssertNotNil(image, "asset manquant : Icons/\(name)")
            // Garde du piège n°1 (spec §7) : sans template-rendering-intent, le PDF s'affiche en noir.
            XCTAssertEqual(image?.renderingMode, .alwaysTemplate, "Icons/\(name) : pas template")
            // Taille intrinsèque pinnée : les call sites (CozyIcon) dimensionnent explicitement.
            XCTAssertEqual(image?.size, CGSize(width: 28, height: 28), "Icons/\(name)")
        }
    }
}
