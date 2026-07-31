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
        XCTAssertEqual(ids.count, 20)
        for id in ids {
            XCTAssertNotNil(UIImage(named: "Sport/\(id)"), "asset manquant : Sport/\(id)")
        }
    }
}
