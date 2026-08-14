// Classement des suggestions de repas (spec v1.14 §6.4). Pur et SANS aléatoire :
// la bande doit être identique à chaque ouverture d'un même jour, et testable.

import Foundation

/// Une suggestion prête à afficher : la recette, ses kcal calculées et l'état du
/// frigo la concernant.
public struct RecipeSuggestion: Sendable, Equatable, Identifiable {
    public let recipe: Recipe
    public let kcal: Int
    public let ingredientCount: Int
    public let missingCount: Int

    /// `Identifiable` comme tout ce que ce dépôt affiche en liste : la bande d'idées
    /// est un `ForEach`, et l'id de la recette est déjà l'id de son aliment.
    public var id: String { recipe.itemID }

    public var hasEverything: Bool { missingCount == 0 }

    /// TAUX de couverture (0…1), et c'est lui qui classe — jamais `missingCount`.
    /// Frigo vide, le nombre d'ingrédients manquants vaut le nombre d'ingrédients,
    /// qui varie d'une recette à l'autre : classer là-dessus ferait passer une
    /// recette de 3 ingrédients à 500 kcal devant une de 4 à 300 kcal. Le taux,
    /// lui, vaut 0 partout, et le tri retombe proprement sur les kcal.
    ///
    /// Ce `Double` se compare ensuite par `!=` et `>`, et c'est sûr : la division
    /// IEEE-754 est correctement arrondie, donc deux taux égaux le sont bit à bit
    /// quels que soient leurs dénominateurs (2/4, 3/6 et 1/2 donnent le même
    /// `Double`), et deux taux distincts restent séparés bien au-delà de l'ulp pour
    /// tout nombre d'ingrédients concevable. Rien ici ne dépend du contenu de
    /// `compositions.json` : une recette à sept ingrédients ne rouvre pas le dossier.
    /// Ce n'est en revanche PAS la clé d'id du comparateur qui sauverait ce cas :
    /// elle vient après la couverture, donc un écart d'un ulp entre deux taux censés
    /// être égaux trancherait avant qu'elle n'ait la parole.
    public var coverage: Double {
        // Le seul repli VIVANT du fichier, et il ne protège pas d'un affichage bancal
        // mais du tri : `0/0` vaut NaN, et un NaN dans `byCoverageThenKcal` fait perdre
        // à la comparaison l'ordre faible strict que `sorted` exige.
        guard ingredientCount > 0 else { return 0 }
        return Double(ingredientCount - missingCount) / Double(ingredientCount)
    }
}

public enum RecipeSuggester {
    public static func suggestions(
        date: Date,
        slot: MealSlot,
        pantry: Set<String>,
        recipes: RecipeCatalog,
        // `foods:` et non `catalog:` : au point d'appel, `recipes:` dit déjà quel
        // catalogue, et `catalog:` juste à côté ne dit plus lequel.
        foods: FoodCatalog,
        calendar: Calendar,
        limit: Int = 3
    ) -> [RecipeSuggestion] {
        guard limit > 0 else { return [] }
        let month = calendar.component(.month, from: date)

        // Le créneau ne se relâche JAMAIS : proposer un déjeuner le soir n'aide
        // personne. Le mois, si — mieux vaut une idée hors saison qu'une bande
        // vide au 1ᵉʳ février.
        //
        // L'aliment est résolu UNE fois, ici, et le couple qui en sort n'est plus
        // optionnel : `score` refaisait ce `byID`, et portait deux replis (`?? []`)
        // que cette ligne rendait inatteignables. Une recette dont l'id ne tombe pas
        // dans le catalogue est écartée à cet endroit, et à aucun autre.
        let inSlot: [(recipe: Recipe, item: FoodItem)] = recipes.recipes.compactMap {
            guard let item = foods.byID[$0.itemID], item.slots.contains(slot) else { return nil }
            return ($0, item)
        }
        let inSeason = inSlot.filter { $0.recipe.isInSeason(month: month) }
        // Pas de `guard !candidates.isEmpty` : il serait MORT. Sur une liste vide, le
        // chemin normal rend déjà `[]` — `complete` est vide, `shortlist` aussi, et
        // rien ne divise par sa taille. Une garde qu'aucune mutation ne fait rougir
        // laisse croire qu'elle protège quelque chose.
        let candidates = inSeason.isEmpty ? inSlot : inSeason

        let scored = candidates.map { score($0.recipe, item: $0.item, pantry: pantry, foods: foods) }

        // 1. Ce dont on a TOUT passe devant, trié aux kcal, et n'est jamais soumis
        //    à la rotation : ce qu'on peut cuisiner sans ressortir doit rester
        //    proposé tous les jours.
        let complete = scored.filter(\.hasEverything).sorted(by: byCoverageThenKcal)
        var chosen = Array(complete.prefix(limit))

        // 2. Le reste passe par une liste COURTE que le jour fait tourner. C'est
        //    la seule façon que la rotation change quelque chose : appliquée à
        //    l'ordre final, elle serait écrasée par le tri sur les kcal, et la
        //    bande afficherait les mêmes plats tout le mois.
        let remaining = limit - chosen.count
        if remaining > 0 {
            let rest = scored.filter { !$0.hasEverything }.sorted(by: byCoverageThenKcal)
            // La spec §6.4 règle 4 écrit NEUF, pour la bande de trois cartes — et
            // n'écrit rien d'autre. Le `* 3` est donc une supposition sur ce que
            // vaudrait la liste courte à un autre `limit`, pas une lecture : aucun
            // appel ne passe autre chose que 3. Bornée des deux côtés par les tests :
            // la rotation ne pioche que dans les neuf plus légères, et un mois les
            // montre toutes.
            let shortlist = Array(rest.prefix(limit * 3))
            if !shortlist.isEmpty {
                let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 0
                let offset = dayOfYear % shortlist.count
                let rotated = Array(shortlist[offset...] + shortlist[..<offset])
                chosen += rotated.prefix(remaining)
            }
        }

        // 3. L'affichage, lui, est toujours ordonné : couverture puis kcal.
        return chosen.sorted(by: byCoverageThenKcal)
    }

    private static func score(_ recipe: Recipe, item: FoodItem, pantry: Set<String>,
                              foods: FoodCatalog) -> RecipeSuggestion {
        let line = foods.line(for: item)
        let ids = line.components.map(\.itemID)
        return RecipeSuggestion(
            recipe: recipe,
            kcal: MealEstimator.kcal(lines: [line], kcalPer100g: foods.kcalPer100g),
            ingredientCount: ids.count,
            // Le frigo est stocké en `[String]` côté profil (ordre d'insertion,
            // dédoublonné) et arrive ici en `Set` : c'est le type d'un test
            // d'appartenance, pas une optimisation — la fonction n'examine que les
            // candidates du jour, une douzaine, et le coût ne serait de toute façon
            // pas le sujet.
            missingCount: ids.filter { !pantry.contains($0) }.count
        )
    }

    /// Tri total et déterministe : couverture décroissante, kcal croissantes, puis
    /// l'id en dernier recours — sans cette dernière clé, deux recettes également
    /// couvertes et de mêmes kcal s'ordonneraient au gré du fichier.
    private static func byCoverageThenKcal(_ left: RecipeSuggestion,
                                           _ right: RecipeSuggestion) -> Bool {
        if left.coverage != right.coverage { return left.coverage > right.coverage }
        if left.kcal != right.kcal { return left.kcal < right.kcal }
        return left.recipe.itemID < right.recipe.itemID
    }
}
