import XCTest
import NivelCore

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

    /// Les clés JSON sont un contrat de stockage (App Group, lu par l'extension) :
    /// ce test décode un littéral pour figer les noms de champs.
    func testDecodesFromStoredJSONKeys() throws {
        let json = Data(#"{"dayKey":800000000,"kcalEaten":850,"kcalTarget":1800,"totalXP":1234,"userName":"Marion","themeID":"menthe","generatedAt":800040000}"#.utf8)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: json)
        XCTAssertEqual(decoded.kcalEaten, 850)
        XCTAssertEqual(decoded.kcalTarget, 1800)
        XCTAssertEqual(decoded.totalXP, 1234)
        XCTAssertEqual(decoded.userName, "Marion")
        XCTAssertEqual(decoded.themeID, "menthe")
        XCTAssertEqual(decoded.dayKey, Date(timeIntervalSinceReferenceDate: 800_000_000))
        XCTAssertEqual(decoded.generatedAt, Date(timeIntervalSinceReferenceDate: 800_040_000))
    }
}
