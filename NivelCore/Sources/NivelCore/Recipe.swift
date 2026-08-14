// Recette de saison (spec v1.14 §6.2). Ne porte QUE ce que le catalogue
// d'aliments ne sait pas dire : les mois où la recette a du sens, et sa
// préparation. Tout le reste se retrouve à partir de l'`itemID`, et n'est jamais
// recopié ici : le nom, l'emoji et les créneaux sur le `FoodItem` de même id ;
// les ingrédients dans `compositions.json`, indexé par ce même id ; les kcal
// enfin par `MealEstimator` sur cette composition — le `kcalPer100g` de l'entrée
// n'étant qu'un repli, et un repli arrondi (338 kcal par la composition de
// `leek_potato_soup` contre 335,4 par son repli — l'écart vient du seul arrondi
// entier de `kcalPer100g`, et c'est le plus grand des trente-cinq).

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
    ///
    /// Ce qu'une étape nomme se range dans TROIS cas, et pas deux — le troisième est
    /// celui dont la moitié des recettes dépendent, et le seul qu'on oublie d'écrire :
    ///
    /// 1. **Ce qui pèse et a son entrée au catalogue** (pain, huile d'olive, crème)
    ///    entre en composition. Toujours. C'est ce que la fiche affiche et ce que le
    ///    frigo fait cocher.
    /// 2. **Le condiment sans entrée au catalogue** — citron, thym, épices, poivre,
    ///    bouillon, herbes fraîches — reste au texte seul. Sans cette permission,
    ///    aucune vraie recette ne s'écrit.
    /// 3. **L'ingrédient précis qui pèse mais n'a pas d'entrée à lui** — concombre,
    ///    poivron, asperges, courge, cabillaud — entre en composition SOUS SA LIGNE
    ///    GÉNÉRIQUE (« Légumes verts », « Légumes de soupe », « Poisson »), et les
    ///    étapes continuent de le nommer précisément. La fiche montre alors le
    ///    générique sous un texte plus précis que lui, et c'est voulu : le catalogue
    ///    est un barème de kcal, pas un dictionnaire de primeur.
    ///
    /// Ce qui est une faute, c'est le sens inverse du cas 1 : une ligne affichée dont
    /// aucune étape ne parle (la laitue de `cod_papillote` avant la Task 3). Le frigo
    /// la fera cocher (§6.4 règles 3-4) et la carte affichera « il manque 1 » pour
    /// quelque chose que la préparation ne demande jamais.
    ///
    /// Le NOM du `FoodItem`, lui, est lu SEUL dans la bande d'idées (§6.4), sans les
    /// étapes pour l'amortir. Il peut nommer précisément ce que la composition porte
    /// génériquement — « Risotto de courge » au-dessus d'une ligne « Légumes de soupe »
    /// est juste, c'est le cas 3. Il ne peut jamais nommer un condiment : « Omelette
    /// aux herbes » promettait la seule chose qui n'était ni pesée, ni affichée, ni
    /// même garantie par ses propres étapes (« les herbes que tu as sous la main »).
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
