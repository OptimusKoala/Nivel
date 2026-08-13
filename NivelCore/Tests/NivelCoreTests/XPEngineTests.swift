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

    /// Plafonds INDÉPENDANTS : faire la séance du jour et la séance posture le même
    /// soir doit payer les deux, sinon on punit exactement ce qu'on veut encourager.
    func testPostureEtSeanceDuJourSontIndependantes() {
        XCTAssertEqual(XPEngine.award(.postureSessionDone, todayCount: 0), 40)
        XCTAssertEqual(XPEngine.award(.postureSessionDone, todayCount: 1), 0)
        // Le compteur de l'une n'affecte pas l'autre : les deux sont interrogées à 0.
        XCTAssertEqual(XPEngine.award(.dailySessionDone, todayCount: 0), 40)
    }

    /// Troisième plafond indépendant (spec v1.14 §5.7), au même barème que les deux
    /// autres séances : 40 XP, une fois par jour.
    func testLaSeanceMuscuAUnPlafondQuotidienIndependant() {
        XCTAssertEqual(XPEngine.award(.muscuSessionDone, todayCount: 0), 40)
        XCTAssertEqual(XPEngine.award(.muscuSessionDone, todayCount: 1), 0)
        // Trois séances de nature différente le même soir paient TROIS fois : les
        // plafonds sont indépendants, sinon le lot punit ce qu'il veut installer.
        XCTAssertEqual(XPEngine.award(.dailySessionDone, todayCount: 0)
                       + XPEngine.award(.postureSessionDone, todayCount: 0)
                       + XPEngine.award(.muscuSessionDone, todayCount: 0), 120)
    }
}
