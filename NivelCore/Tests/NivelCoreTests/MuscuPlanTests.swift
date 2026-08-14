// Programme muscu maison (spec v1.14 §4.4) : catalogue de SÉANCES cloisonné,
// exercices pris dans le catalogue commun, rotation propre.
import XCTest
@testable import NivelCore

final class MuscuPlanTests: XCTestCase {
    private func parisCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    func testLesSeancesSeChargentEtLeursEtapesExistentDansLeCatalogueCommun() throws {
        let catalog = try MuscuCatalog.load()
        XCTAssertEqual(catalog.sessions.count, 5)
        XCTAssertEqual(Set(catalog.sessions.map(\.id)).count, 5)
        // Différence assumée avec la posture : PAS de catalogue d'exercices séparé.
        let shared = Set(try Catalogs.activities().map(\.id))
        for session in catalog.sessions {
            XCTAssertFalse(session.steps.isEmpty, session.id)
            for step in session.steps {
                XCTAssertTrue(shared.contains(step.activityID),
                              "\(session.id) référence \(step.activityID), absent du catalogue commun")
                XCTAssertGreaterThan(step.minutes, 0, "\(session.id)/\(step.activityID)")
                // Les deux invariants que les suites sœurs gardent déjà pour
                // sessions.json et posture-sessions.json, et dont les manquements se
                // voient à l'écran : SessionPlayerSheet affiche `tempo` sans condition
                // dans une capsule colorée (un tempo vide = une pastille orange vide),
                // et TimerRingView ne dessine des graduations qu'à partir de deux
                // segments (un `"segments": 1` mentirait donc en silence).
                XCTAssertFalse(step.tempo.trimmingCharacters(in: .whitespaces).isEmpty,
                               "\(session.id)/\(step.activityID) sans tempo")
                if let segments = step.segments {
                    XCTAssertGreaterThanOrEqual(segments, 2, "\(session.id)/\(step.activityID)")
                }
            }
        }
    }

    /// LE test qui protège la spec sport : verser ces séances dans sessions.json
    /// ferait passer la rotation de 11 à 16 entrées et changerait la séance vue
    /// chaque jour par les DEUX téléphones.
    func testLaMuscuNeTouchePasALaRotationCommune() throws {
        let shared = try Catalogs.sessions()
        XCTAssertEqual(shared.count, 11, "la rotation de la séance du jour a bougé")
        let muscuIDs = Set(try MuscuCatalog.load().sessions.map(\.id))
        XCTAssertTrue(Set(shared.map(\.id)).isDisjoint(with: muscuIDs))
        // `Sport/<id>` est un espace de noms PLAT sur les cinq catalogues : une séance
        // muscu qui s'appellerait `plank` volerait l'illustration de l'activité.
        XCTAssertTrue(Set(try Catalogs.activities().map(\.id)).isDisjoint(with: muscuIDs))
    }

    /// La rotation est déterministe : même JOUR, même séance, quelle que soit l'heure
    /// d'ouverture. C'est une propriété, et non une comparaison à `DailySessionPicker`
    /// avec les mêmes entrées — celle-ci ne vérifierait que la délégation, et ne
    /// pourrait échouer que si `session(for:)` cessait de déléguer. Le bug qu'une
    /// rotation datée attrape vraiment est une date non normalisée qui bascule à 23 h.
    func testLaRotationNeDependPasDeLHeureDOuverture() throws {
        let catalog = try MuscuCatalog.load()
        let calendar = parisCalendar()
        let matin = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 13,
                                                                    hour: 0, minute: 5)))
        let soir = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 13,
                                                                   hour: 23, minute: 55)))
        let id = try XCTUnwrap(catalog.session(for: matin, calendar: calendar)?.id)
        XCTAssertEqual(catalog.session(for: soir, calendar: calendar)?.id, id)
    }

    /// Cinq séances, cinq jours consécutifs : la rotation les visite toutes, puis
    /// revient à la première le sixième jour. Le bouclage compte autant que la
    /// visite — cinq ids distincts sur cinq jours ne diraient rien du modulo, et
    /// c'est ce que `PostureCatalogTests` garde déjà pour l'autre programme.
    func testLaRotationVisiteLesCinqSeancesPuisBoucle() throws {
        let catalog = try MuscuCatalog.load()
        let calendar = parisCalendar()
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 13)))
        let seen = try (0..<5).compactMap { offset -> String? in
            let day = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: start))
            return catalog.session(for: day, calendar: calendar)?.id
        }
        XCTAssertEqual(Set(seen).count, 5)

        let sixieme = try XCTUnwrap(calendar.date(byAdding: .day, value: 5, to: start))
        XCTAssertEqual(catalog.session(for: sixieme, calendar: calendar)?.id, seen.first)
    }

    func testUnCatalogueVideNePlantePas() {
        XCTAssertNil(MuscuCatalog.empty.session(for: .now, calendar: .current))
    }
}
