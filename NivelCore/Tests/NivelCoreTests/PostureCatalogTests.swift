import XCTest
@testable import NivelCore

final class PostureCatalogTests: XCTestCase {
    private var catalog: PostureCatalog!
    private var calendar: Calendar!

    override func setUpWithError() throws {
        catalog = try PostureCatalog.load()
        calendar = Calendar(identifier: .iso8601)
    }

    /// LE test du lot. Verser les entrées posture dans les catalogues globaux les
    /// afficherait sur les deux téléphones ET ferait passer la rotation de la séance
    /// du jour de 11 à 16 entrées, donc changerait la séance vue chaque jour par tout
    /// le monde. La spec sport interdit de toucher à cette rotation.
    func testLesCataloguesSontCloisonnes() throws {
        let globalActivities = Set(try Catalogs.activities().map(\.id))
        let globalSessions = Set(try Catalogs.sessions().map(\.id))
        let postureActivities = Set(catalog.activities.map(\.id))
        let postureSessions = Set(catalog.sessions.map(\.id))

        XCTAssertTrue(globalActivities.isDisjoint(with: postureActivities))
        XCTAssertTrue(globalSessions.isDisjoint(with: postureSessions))
        XCTAssertEqual(globalSessions.count, 11, "la rotation de la séance du jour a bougé")
        XCTAssertEqual(globalActivities.count, 20)
    }

    func testTailleDesCatalogues() {
        XCTAssertEqual(catalog.activities.count, 9)
        XCTAssertEqual(catalog.sessions.count, 5)
    }

    func testChaqueEtapeReferenceUnExerciceExistant() {
        let ids = Set(catalog.activities.map(\.id))
        for session in catalog.sessions {
            XCTAssertFalse(session.steps.isEmpty, session.id)
            for step in session.steps {
                XCTAssertTrue(ids.contains(step.activityID),
                              "\(session.id) cite un exercice inconnu : \(step.activityID)")
                XCTAssertGreaterThan(step.minutes, 0)
                XCTAssertFalse(step.tempo.isEmpty, "\(session.id)/\(step.activityID) sans tempo")
            }
        }
    }

    func testIntegriteDesExercices() {
        for activity in catalog.activities {
            XCTAssertEqual(activity.durations, activity.durations.sorted(), activity.id)
            XCTAssertEqual(activity.durations.count, 3, activity.id)
            XCTAssertGreaterThan(activity.kcalPerMin, 0, activity.id)
            XCTAssertTrue((3...4).contains(activity.instructions.count),
                          "\(activity.id) : 3 ou 4 consignes attendues")
            XCTAssertEqual(activity.location, .home, activity.id)
        }
    }

    /// Cinq séances : cinq soirs consécutifs en donnent cinq différentes, le sixième
    /// revient à la première. Rotation partagée avec la séance du jour, donc même
    /// référence fixe du 1ᵉʳ janvier 2026.
    func testRotationSurCinqJours() throws {
        let start = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 3))
        )
        let five = (0..<5).compactMap { offset -> String? in
            let day = calendar.date(byAdding: .day, value: offset, to: start)!
            return catalog.session(for: day, calendar: calendar)?.id
        }
        XCTAssertEqual(Set(five).count, 5, "deux soirs de suite donnent la même séance")

        let sixth = calendar.date(byAdding: .day, value: 5, to: start)!
        XCTAssertEqual(catalog.session(for: sixth, calendar: calendar)?.id, five.first)
    }

    /// Une séance douce doit exister : un programme à un seul niveau d'effort se fait
    /// abandonner le premier soir de fatigue (spec §5).
    func testUneSeanceDouceExiste() {
        let gentle = catalog.sessions.first { $0.id == "posture_gentle" }
        XCTAssertNotNil(gentle)
        XCTAssertLessThanOrEqual(gentle?.totalMinutes ?? 99, 6)
    }
}
