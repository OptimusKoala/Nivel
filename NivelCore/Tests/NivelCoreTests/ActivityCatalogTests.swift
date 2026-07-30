import XCTest
@testable import NivelCore

final class ActivityCatalogTests: XCTestCase {
    func testActivitiesLoadAndIdsAreUnique() throws {
        let activities = try Catalogs.activities()
        XCTAssertEqual(activities.count, 12)
        XCTAssertEqual(Set(activities.map(\.id)).count, activities.count)
        XCTAssertTrue(activities.contains { $0.id == "walk" && $0.location == .outdoor })
    }

    func testActivityDurationsAreThreeAscending() throws {
        for activity in try Catalogs.activities() {
            XCTAssertEqual(activity.durations.count, 3, "\(activity.id)")
            XCTAssertEqual(activity.durations, activity.durations.sorted(), "\(activity.id)")
            XCTAssertEqual(Set(activity.durations).count, 3, "\(activity.id) : durées dupliquées")
        }
    }

    func testSessionsLoadAndStepsResolve() throws {
        let sessions = try Catalogs.sessions()
        let activityIDs = Set(try Catalogs.activities().map(\.id))
        XCTAssertEqual(sessions.count, 8)
        XCTAssertEqual(Set(sessions.map(\.id)).count, sessions.count)
        for session in sessions {
            XCTAssertFalse(session.steps.isEmpty, "\(session.id)")
            for step in session.steps {
                XCTAssertTrue(activityIDs.contains(step.activityID),
                              "\(session.id) référence '\(step.activityID)' inconnu")
                XCTAssertGreaterThan(step.minutes, 0)
            }
        }
    }

    func testEstimatedKcalRoundsToTens() throws {
        let activities = try Catalogs.activities()
        let walk = try XCTUnwrap(activities.first { $0.id == "walk" })       // 4,0 kcal/min
        XCTAssertEqual(walk.estimatedKcal(minutes: 20), 80)
        let plank = try XCTUnwrap(activities.first { $0.id == "plank" })     // 4,0 kcal/min
        XCTAssertEqual(plank.estimatedKcal(minutes: 5), 20)

        // wake_up = étirements 4×2,5 + squats 4×5,5 + gainage 3×4,0 = 44 → 40.
        let sessions = try Catalogs.sessions()
        let wakeUp = try XCTUnwrap(sessions.first { $0.id == "wake_up" })
        let byID = Dictionary(uniqueKeysWithValues: activities.map { ($0.id, $0) })
        XCTAssertEqual(wakeUp.totalMinutes, 11)
        XCTAssertEqual(wakeUp.estimatedKcal(activitiesByID: byID), 40)
    }
}
