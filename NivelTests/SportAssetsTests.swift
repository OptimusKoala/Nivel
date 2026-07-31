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
        let ids = try Catalogs.activities().map(\.id) + Catalogs.sessions().map(\.id)
        XCTAssertFalse(ids.isEmpty)
        for id in ids {
            let image = try XCTUnwrap(UIImage(named: "Sport/\(id)"), "asset manquant : Sport/\(id)")
            // Imagesets single-scale : .size est en pixels — attrape une source 1254px déposée à la main.
            XCTAssertEqual(image.size.width, 750, "Sport/\(id) : source non redimensionnée ?")
        }
    }
}
