// NivelCore/Tests/NivelCoreTests/FoodSearchTests.swift
// La recherche du frigo (spec v1.14 §6.3). Chaque test tue une mutation précise :
// retirer le rabattage des accents, échanger `contains` contre `hasPrefix`, oublier le
// nettoyage des espaces ou le filtre à requête vide font tomber l'un d'eux.
import XCTest
@testable import NivelCore

final class FoodSearchTests: XCTestCase {
    private func ingredients() throws -> [FoodItem] {
        try FoodCatalog.load().items(category: .side, slot: nil)
    }

    /// Le cas qui a motivé la règle : personne ne tape l'accent grave sur un clavier iOS.
    ///
    /// Deux résultats depuis la 1.15 §6.3, et non plus un : « Épinards à la crème » est
    /// arrivé dans les ingrédients. La liste reste épinglée EXACTE, dans l'ordre du
    /// catalogue — se rabattre sur un `contains` laisserait passer un filtre qui rend
    /// tout. Les deux noms portent leur accent, donc retirer le rabattage des accents
    /// vide toujours la liste : la mutation que ce test tue est intacte.
    func testSansAccentTrouveAvecAccent() throws {
        let found = FoodSearch.filter(try ingredients(), query: "creme")
        XCTAssertEqual(found.map(\.id), ["cream", "spinach_cream"])
    }

    /// … et l'inverse doit marcher aussi : accent tapé, nom sans accent trouvé quand
    /// même. Le rabattage porte sur LES DEUX côtés de la comparaison.
    func testAvecAccentTrouveSansAccent() throws {
        let items = [FoodItem(id: "test", name: "Mais", emoji: "🌽", kcalPer100g: 90,
                              unitLabel: nil, unitLabelPlural: nil, unitGrams: nil,
                              category: .side, tags: [], slots: [], defaultGrams: 100)]
        XCTAssertEqual(FoodSearch.filter(items, query: "maïs").map(\.id), ["test"])
    }

    func testLaCasseNeComptePas() throws {
        let items = try ingredients()
        XCTAssertEqual(FoodSearch.filter(items, query: "TOMATES").map(\.id),
                       FoodSearch.filter(items, query: "tomates").map(\.id))
        XCTAssertFalse(FoodSearch.filter(items, query: "TOMATES").isEmpty)
    }

    /// Le milieu d'un nom compte autant que son début : `hasPrefix` ferait disparaître
    /// tous les ingrédients dont le mot cherché n'ouvre pas le libellé.
    func testChercheAussiAuMilieuDuNom() throws {
        let items = [FoodItem(id: "test", name: "Crème fraîche", emoji: "🥛", kcalPer100g: 200,
                              unitLabel: nil, unitLabelPlural: nil, unitGrams: nil,
                              category: .side, tags: [], slots: [], defaultGrams: 30)]
        XCTAssertEqual(FoodSearch.filter(items, query: "fraiche").map(\.id), ["test"])
    }

    /// Requête vide = pas de filtre. C'est l'état d'ouverture de l'écran : le rater
    /// afficherait un frigo vide à qui n'a rien tapé.
    func testRequeteVideRendTout() throws {
        let items = try ingredients()
        XCTAssertEqual(FoodSearch.filter(items, query: "").count, items.count)
    }

    /// Une requête réduite à des espaces vaut une requête vide — un espace resté après
    /// un mot effacé ne doit pas vider la liste.
    func testRequeteDEspacesRendTout() throws {
        let items = try ingredients()
        XCTAssertEqual(FoodSearch.filter(items, query: "   ").count, items.count)
        XCTAssertEqual(FoodSearch.filter(items, query: " tomates ").map(\.id),
                       FoodSearch.filter(items, query: "tomates").map(\.id))
    }

    /// Rien ne correspond = liste vide, et surtout pas la liste entière.
    func testRequeteSansResultat() throws {
        XCTAssertTrue(FoodSearch.filter(try ingredients(), query: "zzz").isEmpty)
    }

    /// L'ordre du catalogue est conservé : le filtre filtre, il ne trie pas.
    func testOrdreDuCatalogueConserve() throws {
        let items = try ingredients()
        let found = FoodSearch.filter(items, query: "e")
        XCTAssertEqual(found.map(\.id), items.filter { found.contains($0) }.map(\.id))
    }
}
