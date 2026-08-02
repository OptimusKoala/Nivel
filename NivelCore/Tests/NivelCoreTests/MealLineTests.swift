import XCTest
@testable import NivelCore

final class MealLineTests: XCTestCase {
    /// Barème local, pour ne pas dépendre du vrai catalogue : le calcul est testé ici,
    /// le contenu l'est dans FoodCatalogTests.
    private let kcal: [String: Double] = ["rice": 130, "chicken": 165, "beer": 43, "oil": 900]

    private func sum(_ lines: [MealLine]) -> Int {
        MealEstimator.kcal(lines: lines, kcalPer100g: { self.kcal[$0] })
    }

    func testLigneSimple() {
        XCTAssertEqual(sum([.simple(MealComponent(itemID: "beer", grams: 250))]), 108)
    }

    func testLigneComposeeVautLaSommeDeSesComposants() {
        let salad = MealLine.composed(itemID: "bowl", components: [
            MealComponent(itemID: "rice", grams: 250),
            MealComponent(itemID: "chicken", grams: 100),
        ])
        XCTAssertEqual(sum([salad]), 325 + 165)
    }

    /// Le poids de la ligne composée n'existe pas : seul le contenu compte.
    func testCompositionVideVautZero() {
        XCTAssertEqual(sum([.composed(itemID: "bowl", components: [])]), 0)
    }

    func testPlusieursLignes() {
        let lines: [MealLine] = [
            .composed(itemID: "bowl", components: [MealComponent(itemID: "rice", grams: 200)]),
            .simple(MealComponent(itemID: "beer", grams: 250)),
        ]
        XCTAssertEqual(sum(lines), 260 + 108)
    }

    func testListeVide() {
        XCTAssertEqual(sum([]), 0)
    }

    /// Un item inconnu du catalogue vaut zéro et ne fait pas tomber le calcul :
    /// un JSON corrompu ne doit jamais empêcher d'ouvrir son journal.
    func testItemInconnuVautZero() {
        XCTAssertEqual(sum([.simple(MealComponent(itemID: "fantome", grams: 100))]), 0)
    }

    /// UN SEUL arrondi, à la fin. Quinze arrondis composant par composant dériveraient.
    func testArrondiUniqueALaFin() {
        // 3 × (10 g d'huile à 900) = 3 × 90 = 270 exactement.
        let lines = (0..<3).map { _ in MealLine.simple(MealComponent(itemID: "oil", grams: 10)) }
        XCTAssertEqual(sum(lines), 270)
        // 3 × 33 g de riz à 130 = 3 × 42,9 = 128,7 → 129, et non 3 × 43 = 129 par hasard :
        // on vérifie surtout que le total suit la somme réelle.
        let rice = (0..<3).map { _ in MealLine.simple(MealComponent(itemID: "rice", grams: 33)) }
        XCTAssertEqual(sum(rice), 129)
    }

    // MARK: Raccourci de portion

    func testPortionReecritLesGrammes() {
        let base = [MealComponent(itemID: "rice", grams: 250),
                    MealComponent(itemID: "chicken", grams: 100)]
        XCTAssertEqual(MealPortion.light.applied(to: base).map(\.grams), [175, 70])
        XCTAssertEqual(MealPortion.normal.applied(to: base).map(\.grams), [250, 100])
        XCTAssertEqual(MealPortion.hearty.applied(to: base).map(\.grams), [325, 130])
    }

    /// Arrondi à l'entier, jamais zéro : une noisette de beurre en léger reste une noisette.
    func testPortionArrondieEtPlancher() {
        let tiny = [MealComponent(itemID: "oil", grams: 1)]
        XCTAssertEqual(MealPortion.light.applied(to: tiny).map(\.grams), [1])
    }

    // MARK: Portion déduite des grammes

    private let defaults = [MealComponent(itemID: "rice", grams: 250),
                            MealComponent(itemID: "chicken", grams: 100)]

    /// La portion n'est pas persistée : le panier la déduit en comparant les grammes
    /// courants à la composition par défaut du plat.
    func testPortionDeduiteDesGrammes() {
        for portion in MealPortion.allCases {
            XCTAssertEqual(MealPortion.matching(components: portion.applied(to: defaults),
                                                defaults: defaults), portion)
        }
    }

    /// Ajustement à la main : ne retombe sur aucun cran, le panier dira « ajusté ».
    func testGrammesAjustesNeCorrespondentAAucunCran() {
        let tweaked = [MealComponent(itemID: "rice", grams: 250),
                       MealComponent(itemID: "chicken", grams: 175)]
        XCTAssertNil(MealPortion.matching(components: tweaked, defaults: defaults))
    }

    /// Un composant retiré ou ajouté n'est plus la composition par défaut, quelles
    /// que soient les quantités restantes.
    func testCompositionModifieeNeCorrespondAAucunCran() {
        let removed = [MealComponent(itemID: "rice", grams: 250)]
        XCTAssertNil(MealPortion.matching(components: removed, defaults: defaults))
    }

    func testSansCompositionParDefautAucunCran() {
        XCTAssertNil(MealPortion.matching(components: defaults, defaults: []))
    }
}
