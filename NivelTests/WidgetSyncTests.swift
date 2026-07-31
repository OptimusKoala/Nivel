// NivelTests/WidgetSyncTests.swift
// WidgetBridge (spec widgets §3.2) : le snapshot circule par les UserDefaults
// partagés. Suite dédiée par test, comme ThemeStoreTests.
import XCTest
import NivelCore
@testable import Nivel

final class WidgetBridgeTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "nivel.tests.widget.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSaveThenLoadRoundTrips() {
        let snapshot = WidgetSnapshot(dayKey: Date(timeIntervalSinceReferenceDate: 0),
                                      kcalEaten: 500, kcalTarget: 1800, totalXP: 42,
                                      userName: "Marion", themeID: "ocean",
                                      generatedAt: .now)
        WidgetBridge.save(snapshot, to: defaults)
        XCTAssertEqual(WidgetBridge.load(from: defaults), snapshot)
    }

    func testLoadReturnsNilWhenEmptyOrCorrupted() {
        XCTAssertNil(WidgetBridge.load(from: defaults))
        defaults.set(Data("pas du json".utf8), forKey: WidgetBridge.snapshotKey)
        XCTAssertNil(WidgetBridge.load(from: defaults))
    }
}
