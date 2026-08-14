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

    func testSportBadgesUnlockOnActivityCounters() throws {
        let badges = try Catalogs.badges()
        var stats = BadgeStats()
        stats.activitiesDone = 10
        stats.dailySessionsDone = 5
        let unlocked = BadgeEngine.newlyUnlocked(badges: badges, stats: stats, alreadyUnlocked: [])
        let ids = Set(unlocked.map(\.id))
        XCTAssertTrue(ids.isSuperset(of: ["sport_first", "sport_10", "sport_sessions_5"]))
        XCTAssertFalse(ids.contains("sport_50"))
    }

    // MARK: - Les trois métriques de la 1.14

    func testLesTroisNouvellesMetriquesDebloquentLeursBadges() throws {
        let badges = try Catalogs.badges()
        var stats = BadgeStats()
        stats.burnTargetDays = 10
        stats.muscuSessionsDone = 1
        stats.recipesLogged = 0
        let ids = Set(BadgeEngine.newlyUnlocked(badges: badges, stats: stats, alreadyUnlocked: []).map(\.id))
        XCTAssertTrue(ids.isSuperset(of: ["burn_first", "burn_10", "muscu_first"]))
        XCTAssertFalse(ids.contains("burn_30"))
        XCTAssertFalse(ids.contains("recipe_first"))
    }

    /// Un badge déjà obtenu ne se reprend JAMAIS, même si la métrique redescend :
    /// `badgeUnlocks` est un journal, pas un état recalculé. Invariant indépendant de
    /// toute histoire de podomètre — c'est `alreadyUnlocked`, et lui seul, qui protège.
    func testUnBadgeDejaObtenuNestJamaisReprisQuandLaMetriqueRedescend() throws {
        let badges = try Catalogs.badges()
        var stats = BadgeStats()
        stats.burnTargetDays = 30
        let ids = Set(BadgeEngine.newlyUnlocked(badges: badges, stats: stats,
                                                alreadyUnlocked: ["burn_first", "burn_10"]).map(\.id))
        XCTAssertFalse(ids.contains("burn_first"))
        XCTAssertFalse(ids.contains("burn_10"))
        XCTAssertTrue(ids.contains("burn_30"))

        // La métrique retombe à zéro (journées non qualifiantes, HealthKit révoqué, peu
        // importe) : le badge acquis n'est pas rendu, donc rien ne peut l'effacer du journal.
        stats.burnTargetDays = 0
        XCTAssertTrue(BadgeEngine.newlyUnlocked(badges: badges, stats: stats,
                                                alreadyUnlocked: ["burn_first"]).isEmpty,
                      "newlyUnlocked ne rend que les NOUVEAUX badges")
    }

    // MARK: - Transcription de la spec §5.6

    /// Garde-fou de transcription : les quatorze lignes du tableau §5.6, relues dans la
    /// SPEC et non dans le JSON. Les autres tests comptent (38) et vérifient l'unicité —
    /// aucun ne regardait le contenu, si bien que `muscu_25` à 20 ou `journal_365` branché
    /// sur `mealsLogged` passait toutes les suites.
    private static let badgesV114: [String: (titre: String, metrique: Badge.Metric, seuil: Int)] = [
        "burn_first":   ("Ça a bougé",             .burnTargetDays,   1),
        "burn_10":      ("Dix jours actifs",       .burnTargetDays,   10),
        "burn_30":      ("Un mois de mouvement",   .burnTargetDays,   30),
        "muscu_first":  ("Première séance muscu",  .muscuSessionsDone, 1),
        "muscu_10":     ("Ça pousse",              .muscuSessionsDone, 10),
        "muscu_25":     ("Costaud",                .muscuSessionsDone, 25),
        "recipe_first": ("Aux fourneaux",          .recipesLogged,    1),
        "recipe_10":    ("Dix recettes",           .recipesLogged,    10),
        "level_30":     ("Niveau 30",              .level,            30),
        "level_50":     ("Niveau 50",              .level,            50),
        "sport_100":    ("Cent activités",         .activitiesDone,   100),
        "meals_500":    ("500 repas notés",        .mealsLogged,      500),
        "journal_365":  ("Une année de journal",   .journalDays,      365),
        "steps_20k":    ("20 000 pas !",           .stepsInOneDay,    20000),
    ]

    func testLesQuatorzeBadgesRetombentSurLaSpec() throws {
        XCTAssertEqual(Self.badgesV114.count, 14, "la table de transcription a perdu une ligne")
        // `uniquingKeysWith` et NON `uniqueKeysWithValues`, contre l'usage du dépôt : un id
        // dupliqué dans le JSON — la faute même que ce garde vise — ferait TRAPPER le
        // processus, et `BadgeEngineTests` passant avant `CatalogsTests` dans l'ordre
        // alphabétique, on perdrait toute la suite et le rapport clair de
        // `testBadgesLoadAndIdsAreUnique`, qui dit déjà mieux la même chose.
        let byID = Dictionary(try Catalogs.badges().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (id, attendu) in Self.badgesV114 {
            let badge = byID[id]
            XCTAssertNotNil(badge, "badge manquant : \(id)")
            // `continue` et non `XCTUnwrap` : sur trois badges absents, on veut les trois
            // dans le rapport, pas le premier puis un arrêt.
            guard let badge else { continue }
            XCTAssertEqual(badge.title, attendu.titre, "\(id) : titre")
            XCTAssertEqual(badge.metric, attendu.metrique, "\(id) : métrique")
            XCTAssertEqual(badge.threshold, attendu.seuil, "\(id) : seuil")
        }
    }
}
