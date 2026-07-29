import XCTest
@testable import NivelCore

final class BadgeEngineTests: XCTestCase {
    func testUnlocksOnlyNewBadgesAtOrAboveThreshold() throws {
        let badges = try Catalogs.badges()
        var stats = BadgeStats()
        stats.weighIns = 1
        stats.level = 5
        let unlocked = BadgeEngine.newlyUnlocked(badges: badges, stats: stats, alreadyUnlocked: ["level_5"])
        XCTAssertEqual(Set(unlocked.map(\.id)), ["first_weigh"])   // level_5 déjà eu, seuils non atteints ailleurs
    }

    func testNoUnlockBelowThreshold() throws {
        let badges = try Catalogs.badges()
        let unlocked = BadgeEngine.newlyUnlocked(badges: badges, stats: BadgeStats(), alreadyUnlocked: [])
        XCTAssertTrue(unlocked.isEmpty)
    }
}
