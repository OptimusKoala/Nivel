// NivelTests/SportAssetsTests.swift
import XCTest
import UIKit
import NivelCore
@testable import Nivel

final class SportAssetsTests: XCTestCase {
    /// Garde anti-typo : chaque entrée de catalogue sport a son illustration embarquée
    /// (spec illustrations §7). Le fallback emoji existe, mais un asset manquant est un
    /// bug de packaging à attraper ici.
    func testEveryCatalogEntryHasAnIllustration() throws {
        // Tous les catalogues qui alimentent un écran sport : le commun, la posture
        // (spec v1.11 §11) et la muscu (spec v1.14 §4.5) — mêmes règles de packaging.
        // Volontairement sans compte en dur : quand un lot ajoute un catalogue, c'est
        // cette liste qu'il faut compléter, et un chiffre en commentaire ne le dirait pas.
        let ids = try Catalogs.activities().map(\.id) + Catalogs.sessions().map(\.id)
            + Catalogs.postureActivities().map(\.id) + Catalogs.postureSessions().map(\.id)
            + Catalogs.muscuSessions().map(\.id)
        XCTAssertFalse(ids.isEmpty)
        for id in ids {
            let image = try XCTUnwrap(UIImage(named: "Sport/\(id)"), "asset manquant : Sport/\(id)")
            // Imagesets single-scale : .size est en pixels — attrape une source 1254px déposée à la main.
            XCTAssertEqual(image.size.width, 750, "Sport/\(id) : source non redimensionnée ?")
        }
    }
}
