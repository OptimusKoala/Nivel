import XCTest
@testable import NivelCore

final class LevelSystemTests: XCTestCase {
    func testSeuils() {
        XCTAssertEqual(LevelSystem.xpRequired(forLevel: 1), 0)
        XCTAssertEqual(LevelSystem.xpRequired(forLevel: 2), 70)      // 70×1^2,2
        XCTAssertEqual(LevelSystem.xpRequired(forLevel: 3), 322)     // 70×2^2,2 = 321,6
        XCTAssertEqual(LevelSystem.xpRequired(forLevel: 4), 785)
        XCTAssertEqual(LevelSystem.xpRequired(forLevel: 5), 1478)
        XCTAssertEqual(LevelSystem.xpRequired(forLevel: 10), 8799)
        XCTAssertEqual(LevelSystem.xpRequired(forLevel: 20), 45536)
        XCTAssertEqual(LevelSystem.xpRequired(forLevel: 30), 115445)
    }

    func testNiveauPourXP() {
        XCTAssertEqual(LevelSystem.level(forXP: 0), 1)
        XCTAssertEqual(LevelSystem.level(forXP: 69), 1)
        XCTAssertEqual(LevelSystem.level(forXP: 70), 2)
        XCTAssertEqual(LevelSystem.level(forXP: 321), 2)
        XCTAssertEqual(LevelSystem.level(forXP: 322), 3)
    }

    /// Les deux premiers niveaux arrivent PLUS vite qu'avant ; le croisement se fait
    /// au niveau 4. C'est voulu : le premier jour récompense davantage, et le
    /// freinage commence là où la gêne commençait.
    func testPremiersNiveauxMoinsCouteuxQuAvant() {
        XCTAssertLessThan(LevelSystem.xpRequired(forLevel: 2), LevelSystem.legacyXPRequired(forLevel: 2))
        XCTAssertLessThan(LevelSystem.xpRequired(forLevel: 3), LevelSystem.legacyXPRequired(forLevel: 3))
        XCTAssertGreaterThan(LevelSystem.xpRequired(forLevel: 4), LevelSystem.legacyXPRequired(forLevel: 4))
    }

    /// L'ancienne formule doit rester EXACTE : la migration s'en sert pour lire le
    /// niveau déjà atteint. La modifier ferait perdre un niveau à quelqu'un.
    func testFormuleAncienneEstPreservee() {
        XCTAssertEqual(LevelSystem.legacyXPRequired(forLevel: 2), 246)
        XCTAssertEqual(LevelSystem.legacyXPRequired(forLevel: 10), 1995)
        XCTAssertEqual(LevelSystem.legacyXPRequired(forLevel: 20), 4913)
    }

    /// Invariant de forme, indépendant des valeurs : un niveau coûte toujours plus
    /// que le précédent, et l'écart ne se resserre jamais.
    func testCourbeStrictementCroissanteEtAcceleree() {
        for level in 2..<60 {
            let previous = LevelSystem.xpRequired(forLevel: level - 1)
            let current = LevelSystem.xpRequired(forLevel: level)
            let next = LevelSystem.xpRequired(forLevel: level + 1)
            XCTAssertGreaterThan(current, previous, "niveau \(level)")
            // `>` et non `>=` : avec un `>=`, une courbe strictement LINÉAIRE passerait
            // (différences secondes toutes nulles) et « accélérée » serait faux. Une
            // coquille d'exposant à 1,0 ne serait pas attrapée. La marge est large — la
            // plus petite différence seconde réelle vaut 182 sur les 200 premiers
            // niveaux.
            XCTAssertGreaterThan(next - current, current - previous, "niveau \(level)")
        }
    }

    func testProgressionDansLeNiveau() {
        // à 322 XP : début du niveau 3 → 0 gagné, il en faut 785 − 322 pour le 4.
        let p = LevelSystem.progress(forXP: 322)
        XCTAssertEqual(p.current, 0)
        XCTAssertEqual(p.needed, 785 - 322)
    }

    func testStepsCalorieEstimate() {
        // 8000 pas à 90 kg : 8000 × 0.04 × 90/70 ≈ 411
        XCTAssertEqual(StepsEstimator.kcal(steps: 8000, weightKg: 90), 411)
    }
}
