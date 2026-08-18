// NivelTests/DeepLinkTests.swift
import Foundation
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

    func testRoutesProgramRemindersToTheirOwnSessions() {
        XCTAssertEqual(NotificationNavigation.route(forReminderID: "posture"), .posture)
        XCTAssertEqual(NotificationNavigation.route(forReminderID: "muscu"), .muscu)
        XCTAssertNil(NotificationNavigation.route(forReminderID: "dinner"))
    }

    func testNotificationContentRouteWinsOverTheLegacyIdentifierFallback() {
        XCTAssertEqual(
            NotificationNavigation.route(
                userInfo: [NotificationNavigation.routeUserInfoKey: SportSessionRoute.muscu.rawValue],
                reminderID: "posture"
            ),
            .muscu
        )
    }

    @MainActor
    func testTappedReminderRouteSurvivesColdLaunchThenIsConsumedOnce() {
        let suiteName = "nivel.tests.notification-route.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        NotificationNavigation.receive(.posture, defaults: defaults)
        XCTAssertEqual(NotificationNavigation.consumePendingRoute(defaults: defaults), .posture)
        XCTAssertNil(NotificationNavigation.consumePendingRoute(defaults: defaults))
    }
}
