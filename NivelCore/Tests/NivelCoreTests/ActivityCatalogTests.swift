import XCTest
@testable import NivelCore

final class ActivityCatalogTests: XCTestCase {
    func testActivitiesLoadAndIdsAreUnique() throws {
        let activities = try Catalogs.activities()
        XCTAssertEqual(activities.count, 20)
        XCTAssertEqual(Set(activities.map(\.id)).count, activities.count)
        XCTAssertTrue(activities.contains { $0.id == "walk" && $0.location == .outdoor })
        XCTAssertTrue(activities.contains { $0.id == "wall_sit" && $0.location == .home })
        XCTAssertTrue(activities.contains { $0.id == "hike" && $0.location == .outdoor })
    }

    func testActivityDurationsAreThreeAscending() throws {
        for activity in try Catalogs.activities() {
            XCTAssertEqual(activity.durations.count, 3, "\(activity.id)")
            XCTAssertEqual(activity.durations, activity.durations.sorted(), "\(activity.id)")
            XCTAssertEqual(Set(activity.durations).count, 3, "\(activity.id) : durées dupliquées")
            XCTAssertGreaterThan(activity.durations.first ?? 0, 0, "\(activity.id)")
        }
    }

    func testSessionsLoadAndStepsResolve() throws {
        let sessions = try Catalogs.sessions()
        let activityIDs = Set(try Catalogs.activities().map(\.id))
        XCTAssertEqual(sessions.count, 11)
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

        // Pin le mode d'arrondi (.rounded() = to-nearest-or-away-from-zero) sur des cas
        // qui ne sont pas des multiples exacts de 10.
        let briskWalk = try XCTUnwrap(activities.first { $0.id == "brisk_walk" }) // 5,5 kcal/min
        XCTAssertEqual(briskWalk.estimatedKcal(minutes: 10), 60)                  // 55 → arrondi au-dessus
        let dance = try XCTUnwrap(activities.first { $0.id == "dance" })          // 5,5 kcal/min
        XCTAssertEqual(dance.estimatedKcal(minutes: 15), 80)                      // 82,5 → arrondi en dessous
        let squats = try XCTUnwrap(activities.first { $0.id == "squats" })        // 5,5 kcal/min
        XCTAssertEqual(squats.estimatedKcal(minutes: 3), 20)                      // 16,5 → arrondi au-dessus

        // wake_up = étirements 4×2,5 + squats 4×5,5 + gainage 3×4,0 = 44 → 40.
        let sessions = try Catalogs.sessions()
        let wakeUp = try XCTUnwrap(sessions.first { $0.id == "wake_up" })
        let byID = Dictionary(uniqueKeysWithValues: activities.map { ($0.id, $0) })
        XCTAssertEqual(wakeUp.totalMinutes, 11)
        XCTAssertEqual(wakeUp.estimatedKcal(activitiesByID: byID), 40)

        // legs_day = squats 3×5,5 + fentes 3×5,5 + chaise murale 2×4,5 + étirements 3×2,5 = 49,5 → 50.
        let legsDay = try XCTUnwrap(sessions.first { $0.id == "legs_day" })
        XCTAssertEqual(legsDay.totalMinutes, 11)
        XCTAssertEqual(legsDay.estimatedKcal(activitiesByID: byID), 50)
    }

    func testEveryActivityHasInstructions() throws {
        for activity in try Catalogs.activities() {
            XCTAssertGreaterThanOrEqual(activity.instructions.count, 3, activity.id)
            XCTAssertLessThanOrEqual(activity.instructions.count, 4, activity.id)
            XCTAssertTrue(activity.instructions.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }, activity.id)
        }
    }

    func testEverySessionStepHasTempo() throws {
        for session in try Catalogs.sessions() {
            for step in session.steps {
                XCTAssertFalse(step.tempo.trimmingCharacters(in: .whitespaces).isEmpty, "\(session.id)/\(step.activityID)")
            }
        }
    }

    func testSegmentsDecodeWhenPresentAndNilOtherwise() throws {
        let sessions = try Catalogs.sessions()
        let wakeUp = try XCTUnwrap(sessions.first { $0.id == "wake_up" })
        XCTAssertEqual(wakeUp.steps.map(\.segments), [2, 3, 3])           // stretching, squats, plank
        let freshAir = try XCTUnwrap(sessions.first { $0.id == "fresh_air" })
        XCTAssertEqual(freshAir.steps.map(\.segments), [nil])             // pas de séries explicites
        // Cohérence : jamais 0 ou 1 (une graduation n'a de sens qu'à partir de 2).
        for session in sessions {
            for step in session.steps {
                if let segments = step.segments { XCTAssertGreaterThanOrEqual(segments, 2, "\(session.id)/\(step.activityID)") }
            }
        }
    }

    func testNoBundleResourceContainsEmDash() throws {
        // Convention v1.2 : aucun tiret cadratin dans les textes utilisateur.
        let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        XCTAssertFalse(urls.isEmpty)
        for url in urls {
            let content = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(content.contains("—"), url.lastPathComponent)
        }
    }
}
