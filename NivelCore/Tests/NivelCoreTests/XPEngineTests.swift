import XCTest
@testable import NivelCore

final class XPEngineTests: XCTestCase {
    func testMealXPCappedAtFourPerDay() {
        XCTAssertEqual(XPEngine.award(.mealLogged, todayCount: 0), 20)
        XCTAssertEqual(XPEngine.award(.mealLogged, todayCount: 3), 20)
        XCTAssertEqual(XPEngine.award(.mealLogged, todayCount: 4), 0)
    }

    func testWeighInCappedAtOnePerDay() {
        XCTAssertEqual(XPEngine.award(.weighIn, todayCount: 0), 30)
        XCTAssertEqual(XPEngine.award(.weighIn, todayCount: 1), 0)
    }

    func testUncappedActions() {
        XCTAssertEqual(XPEngine.award(.dayWithinTarget, todayCount: 0), 50)
        XCTAssertEqual(XPEngine.award(.stepGoalReached, todayCount: 0), 40)
        XCTAssertEqual(XPEngine.award(.questCompleted, todayCount: 2), 150)
        XCTAssertEqual(XPEngine.award(.badgeUnlocked, todayCount: 5), 50)
    }

    func testActivityXPCappedAtTwoPerDay() {
        XCTAssertEqual(XPEngine.award(.activityDone, todayCount: 0), 30)
        XCTAssertEqual(XPEngine.award(.activityDone, todayCount: 1), 30)
        XCTAssertEqual(XPEngine.award(.activityDone, todayCount: 2), 0)
    }

    func testDailySessionXPCappedAtOnePerDay() {
        XCTAssertEqual(XPEngine.award(.dailySessionDone, todayCount: 0), 40)
        XCTAssertEqual(XPEngine.award(.dailySessionDone, todayCount: 1), 0)
    }
}
