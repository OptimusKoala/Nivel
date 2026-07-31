import XCTest
@testable import NivelCore

final class WidgetSnapshotTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let snapshot = WidgetSnapshot(
            dayKey: Date(timeIntervalSinceReferenceDate: 800_000_000),
            kcalEaten: 850,
            kcalTarget: 1800,
            totalXP: 1234,
            userName: "Marion",
            themeID: "menthe",
            generatedAt: Date(timeIntervalSinceReferenceDate: 800_040_000)
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }
}
