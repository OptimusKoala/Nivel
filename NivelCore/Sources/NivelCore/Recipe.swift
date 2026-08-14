// Recette de saison (spec v1.14 §6.2). Ne porte QUE ce que le catalogue
// d'aliments ne sait pas dire : les mois où la recette a du sens, et sa
// préparation. Tout le reste se retrouve à partir de l'`itemID`, et n'est jamais
// recopié ici : le nom, l'emoji et les créneaux sur le `FoodItem` de même id ;
// les ingrédients dans `compositions.json`, indexé par ce même id ; les kcal
// enfin par `MealEstimator` sur cette composition — le `kcalPer100g` de l'entrée
// n'étant qu'un repli, et un repli arrondi (388 kcal par la composition de
// `cod_papillote` contre 408 par son repli).

import Foundation

public struct Recipe: Codable, Identifiable, Hashable, Sendable {
    /// Id du `FoodItem` marqué `isRecipe` qui porte le reste.
    public let itemID: String
    /// Mois (1-12) où la recette est de saison.
    public let months: [Int]
    /// Trois à quatre lignes de préparation, au ton de Nivelito. Les étapes sont à
    /// l'impératif — une étape de recette ne peut pas ne pas l'être. Ce qui fait le
    /// ton, c'est donc : tutoiement, jamais de « vous devez », et une dernière ligne
    /// qui souffle plutôt qu'elle n'ordonne (« profites-en pour mettre la table »).
    public let steps: [String]

    public var id: String { itemID }

    public func isInSeason(month: Int) -> Bool { months.contains(month) }
}

/// Catalogue chargé une fois. Repli vide si le JSON est corrompu : la bande
/// d'idées disparaît, l'app continue — même règle que les trois autres catalogues
/// qui portent un `.empty` : `FoodCatalog`, `PostureCatalog`, `MuscuCatalog`.
public struct RecipeCatalog: Sendable {
    public let recipes: [Recipe]
    /// Aucun lecteur dans le lot D : `RecipeSuggester` itère `recipes` et résout ses
    /// ids par `FoodCatalog.byID`. Gardé parce qu'un catalogue d'`Identifiable` sans
    /// accès par id se contourne en `first(where:)` à la première demande, et surtout
    /// pour la propriété ci-dessous, qui est ce que ce type apporte de plus que `[Recipe]`.
    public let byItemID: [String: Recipe]

    /// L'index se construit ICI et non dans `load()` : c'est le seul chemin qui existe
    /// pour obtenir un `RecipeCatalog`, donc `byItemID` ne PEUT pas diverger de
    /// `recipes`. `FoodCatalog` laisse les deux passer en paramètres, et son catalogue
    /// de laboratoire (`FoodCatalogTests.testLeFiltreEcarteUneRecetteDeSaCategorie`)
    /// pourrait s'en construire un incohérent sans qu'on l'apprenne.
    ///
    /// Un `itemID` en double est avalé en silence, comme partout ailleurs : mieux
    /// vaut une recette perdue qu'une app qui ne démarre pas. Laquelle des deux
    /// survit n'est en revanche tenu par rien — `{ a, _ in a }` se muterait en
    /// `{ _, b in b }` sans qu'un test bronche, et c'est correct : sans doublon la
    /// différence n'est pas observable. Ce qui est tenu, et par le seul
    /// `RecipeCatalogTests.testPasDeDoublonDItemID`, c'est qu'il n'y ait pas de doublon.
    public init(recipes: [Recipe]) {
        self.recipes = recipes
        self.byItemID = Dictionary(recipes.map { ($0.itemID, $0) }, uniquingKeysWith: { a, _ in a })
    }

    public static let empty = RecipeCatalog(recipes: [])

    public static func load() throws -> RecipeCatalog {
        RecipeCatalog(recipes: try Catalogs.recipes())
    }
}
