// NivelTests/IconAssetsTests.swift
import XCTest
import UIKit
@testable import Nivel
import NivelCore

final class IconAssetsTests: XCTestCase {
    /// Les 49 glyphes cozy — liste PINNÉE, garde anti-typo de nommage. 15 de la vague 1
    /// (tab bar, timer, réglages) et 34 de la vague 2 (catalogues). Les deux avatars de
    /// l'onboarding n'en font PAS partie : ce sont des illustrations couleur (Avatars/).
    static let iconNames = [
        "tab_home", "tab_home_fill", "tab_meals", "tab_meals_fill",
        "tab_sport", "tab_sport_fill", "tab_progress", "tab_progress_fill",
        "tab_quests", "tab_quests_fill",
        "icon_settings", "icon_check", "icon_play", "icon_pause", "icon_restart",
        "icon_footprint", "icon_footprints", "icon_boot", "icon_runner", "icon_map",
        "icon_flame", "icon_repeat",
        "icon_calendar", "icon_calendar_month", "icon_notebook", "icon_meal_log",
        "icon_book", "icon_books", "icon_ribbon",
        "icon_star", "icon_star_double", "icon_comet", "icon_medal",
        "icon_target", "icon_flag", "icon_clover", "icon_scale",
        "icon_trend_down", "icon_compass",
        "icon_drop", "icon_glass_empty", "icon_sun", "icon_moon",
        "icon_tree", "icon_heart", "icon_bell", "icon_flan", "icon_mint", "icon_wave",
    ]

    func testEveryCozyIconAssetExists() {
        XCTAssertEqual(Set(Self.iconNames).count, 49)
        for name in Self.iconNames {
            let image = UIImage(named: "Icons/\(name)")
            XCTAssertNotNil(image, "asset manquant : Icons/\(name)")
            // Garde du piège n°1 (spec §7) : sans template-rendering-intent, le PDF s'affiche en noir.
            XCTAssertEqual(image?.renderingMode, .alwaysTemplate, "Icons/\(name) : pas template")
            // Taille intrinsèque pinnée : les call sites (CozyIcon) dimensionnent explicitement.
            XCTAssertEqual(image?.size, CGSize(width: 28, height: 28), "Icons/\(name)")
        }
    }

    /// Le contrat de `CatalogIcon` (spec catalogues §4) : le préfixe `icon_`/`tab_` décide
    /// seul si une valeur est un glyphe ou un emoji. Un nom mal orthographié serait donc
    /// pris pour un emoji et s'afficherait en texte brut — ce test est ce qui l'empêche.
    func testEveryCatalogCozyIconResolvesToAnAsset() throws {
        var cozyCount = 0
        for icon in try Catalogs.badges().map(\.icon) + Catalogs.quests().map(\.icon) {
            guard case .cozy(let name) = icon else { continue }
            XCTAssertNotNil(UIImage(named: "Icons/\(name)"), "catalogue : Icons/\(name) introuvable")
            cozyCount += 1
        }
        // 24 badges + 19 quêtes en cozy (16 + les 3 quêtes posture v1.11, icônes
        // réutilisées : icon_wave, icon_repeat, icon_heart) ; 2 quêtes restent en emoji.
        XCTAssertEqual(cozyCount, 43, "les 24 badges + 19 quêtes en cozy (2 quêtes restent en emoji)")

        for palette in ThemePalette.all {
            XCTAssertNotNil(UIImage(named: "Icons/\(palette.icon)"),
                            "thème \(palette.id) : Icons/\(palette.icon) introuvable")
        }

        // Les en-têtes des trois sections de l'onglet Sport (spec v1.14 §4.3). Leurs
        // noms d'icônes vivent dans NivelCore, hors de portée de la liste épinglée
        // ci-dessus : une faute de frappe n'afficherait rien, en silence, et dans les
        // DEUX vues à la fois.
        for section in SportSection.allCases {
            XCTAssertNotNil(UIImage(named: "Icons/\(section.icon)"),
                            "section \(section.rawValue) : Icons/\(section.icon) introuvable")
        }
    }

    /// Les deux Nivelito des cartes de profil : illustrations couleur, donc NI template
    /// ni 28×28 — c'est ce qui les exclut de la liste épinglée ci-dessus.
    func testProfileAvatarAssetsExist() {
        for name in ["boy", "girl"] {
            XCTAssertNotNil(UIImage(named: "Avatars/\(name)"), "asset manquant : Avatars/\(name)")
        }
    }

    /// L'inverse : les SEULES entrées restées en emoji sont les deux quêtes de dessert
    /// léger (spec §2.2). Une troisième, oubliée dans un futur ajout, se verrait ici.
    func testOnlyTheLightDessertQuestsStayEmoji() throws {
        func isEmoji(_ icon: CatalogIcon) -> Bool {
            if case .emoji = icon { true } else { false }
        }
        let ids = try Catalogs.badges().filter { isEmoji($0.icon) }.map(\.id)
            + Catalogs.quests().filter { isEmoji($0.icon) }.map(\.id)
        XCTAssertEqual(Set(ids), ["light_dessert_3", "light_dessert_5"])
    }
}
