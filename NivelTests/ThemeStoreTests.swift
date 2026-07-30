// NivelTests/ThemeStoreTests.swift
// ThemeStore (v1.1) : persistance de l'id de palette dans UserDefaults.
// Suite UserDefaults dédiée par test — jamais les vrais réglages de l'app.

import XCTest
@testable import Nivel

final class ThemeStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "nivel.tests.theme.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsToCremeWhenNothingStored() {
        let store = ThemeStore(defaults: defaults)
        XCTAssertEqual(store.palette.id, ThemePalette.creme.id)
        XCTAssertFalse(store.palette.isDark)
    }

    func testPersistsAndRestoresPalette() {
        let store = ThemeStore(defaults: defaults)
        store.palette = .nuitDouce

        XCTAssertEqual(defaults.string(forKey: ThemeStore.defaultsKey),
                       ThemePalette.nuitDouce.id)

        // Un nouveau store sur la même suite (≈ relance de l'app) relit le choix.
        let restored = ThemeStore(defaults: defaults)
        XCTAssertEqual(restored.palette.id, ThemePalette.nuitDouce.id)
        XCTAssertTrue(restored.palette.isDark)
    }

    func testUnknownStoredIDFallsBackToCreme() {
        defaults.set("disco", forKey: ThemeStore.defaultsKey)
        let store = ThemeStore(defaults: defaults)
        XCTAssertEqual(store.palette.id, ThemePalette.creme.id)
    }
}
