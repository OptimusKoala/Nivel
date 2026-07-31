// NivelTests/DeepLinkTests.swift
import XCTest
@testable import Nivel

final class DeepLinkTests: XCTestCase {
    func testParsesLogMeal() {
        XCTAssertEqual(DeepLink.parse(URL(string: "nivel://log-meal")!), .logMeal)
    }

    /// Contrat à deux faces : l'URL émise par le widget (WidgetBridge.logMealURL)
    /// est exactement celle que l'app sait router.
    func testParsesTheWidgetContractURL() {
        XCTAssertEqual(DeepLink.parse(WidgetBridge.logMealURL), .logMeal)
    }

    func testRejectsOtherSchemesAndHosts() {
        XCTAssertNil(DeepLink.parse(URL(string: "https://log-meal")!))
        XCTAssertNil(DeepLink.parse(URL(string: "nivel://autre-chose")!))
        XCTAssertNil(DeepLink.parse(URL(string: "nivel://")!))
    }
}
