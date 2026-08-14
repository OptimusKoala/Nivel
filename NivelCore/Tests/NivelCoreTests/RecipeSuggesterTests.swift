// Classement des suggestions (spec §6.4) : saison, créneau, couverture du frigo,
// kcal, puis rotation par le jour sur la liste courte. Aucun aléatoire — donc
// entièrement testable, et identique à chaque ouverture d'un même jour.
import XCTest
@testable import NivelCore

final class RecipeSuggesterTests: XCTestCase {
    private var catalog: FoodCatalog!
    private var recipes: RecipeCatalog!
    private var calendar: Calendar!

    override func setUpWithError() throws {
        catalog = try FoodCatalog.load()
        recipes = try RecipeCatalog.load()
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar = gregorian
    }

    /// Le mois est un PARAMÈTRE et non plus un « août » en dur : deux des défauts
    /// trouvés en revue ne se voyaient que hors d'août (les ex æquo de kcal
    /// n'existent qu'en automne et en hiver, et le décalage par le jour du mois se
    /// confond avec celui par le jour de l'année tant qu'on ne compare qu'un mois).
    private func jour(_ day: Int, mois: Int = 8) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: mois, day: day))!
    }

    private func picks(day: Int = 13, mois: Int = 8, slot: MealSlot = .dinner,
                       pantry: Set<String> = []) -> [RecipeSuggestion] {
        RecipeSuggester.suggestions(date: jour(day, mois: mois), slot: slot, pantry: pantry,
                                    recipes: recipes, foods: catalog,
                                    calendar: calendar, limit: 3)
    }

    /// Les candidates que la fonction est censée voir, recalculées à part : plusieurs
    /// tests n'ont de valeur que si ce qu'elles contiennent est ce qu'on croit.
    private func candidates(mois: Int, slot: MealSlot = .dinner) -> [Recipe] {
        recipes.recipes.filter {
            $0.isInSeason(month: mois) && catalog.byID[$0.itemID]!.slots.contains(slot)
        }
    }

    private func kcal(_ recipe: Recipe) -> Int {
        MealEstimator.kcal(lines: [catalog.line(for: catalog.byID[recipe.itemID]!)],
                           kcalPer100g: catalog.kcalPer100g)
    }

    /// Le frigo qui couvre exactement ces recettes-là.
    private func ingredients(of recipes: [Recipe]) -> Set<String> {
        Set(recipes.flatMap { catalog.line(for: catalog.byID[$0.itemID]!).components.map(\.itemID) })
    }

    /// L'oracle du classement à couverture égale, écrit à part du comparateur de la
    /// source — qu'il a pour rôle de contraindre, pas de recopier.
    private func parKcalPuisId(_ recipes: [Recipe]) -> [Recipe] {
        recipes.sorted { kcal($0) != kcal($1) ? kcal($0) < kcal($1) : $0.itemID < $1.itemID }
    }

    /// Catalogues de laboratoire : des aliments écrits sur mesure, une recette par
    /// aliment, toutes du même mois. Deux tests découplent ainsi leur sujet — le
    /// créneau, la clé de départage — du contenu éditorial de `recipes.json`.
    private func laboratoire(_ items: [FoodItem],
                             mois: [Int] = [8]) -> (foods: FoodCatalog, recipes: RecipeCatalog) {
        (FoodCatalog(items: items,
                     byID: Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }),
                     compositions: [:]),
         RecipeCatalog(recipes: items.map { Recipe(itemID: $0.id, months: mois, steps: ["a", "b", "c"]) }))
    }

    func testSeulementDeSaisonEtDansLeCreneau() {
        let result = picks()
        XCTAssertEqual(result.count, 3, "la bande montre trois cartes")
        for pick in result {
            XCTAssertTrue(pick.recipe.isInSeason(month: 8), pick.recipe.itemID)
            XCTAssertTrue(catalog.byID[pick.recipe.itemID]!.slots.contains(.dinner))
        }
    }

    /// Frigo vide : tous les taux de couverture valent 0, donc le classement se
    /// fait aux kcal seules (spec §6.4 règle 6). Ce test tombe si l'on classe sur
    /// le NOMBRE d'ingrédients manquants au lieu du taux.
    func testFrigoVideClasseAuxKcalSeules() {
        let result = picks()
        // Le compte D'ABORD : les trois assertions qui suivent sont toutes vraies
        // sur une liste vide (`[] == []`, `allSatisfy` sur rien), et ce test serait
        // muet le jour où le classement ne rend plus rien du tout.
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.map(\.kcal), result.map(\.kcal).sorted())
        XCTAssertTrue(result.allSatisfy { $0.coverage == 0 })
        XCTAssertTrue(result.allSatisfy { $0.missingCount == $0.ingredientCount })
    }

    /// Règle 5 : l'affichage est TOUJOURS trié. Le tri final n'avait aucun témoin —
    /// on pouvait supprimer le `sorted` de la dernière ligne sans qu'un seul des dix
    /// tests ne rougisse. La cause : `testFrigoVideClasseAuxKcalSeules` était le seul
    /// à regarder l'ordre, et il tourne au 13 août, jour 225 de l'année, où
    /// `225 % 9 == 0` — la rotation y est l'IDENTITÉ. Deux jours sur neuf (les 2, 3,
    /// 11, 12, 20 et 21 août) la liste avant tri est `[462, 465, 342]`, la plus légère
    /// en dernier. D'où le balayage des vingt-huit jours, et de deux mois : novembre
    /// n'a pas les mêmes candidates qu'août.
    func testLAffichageResteTrieQuelQueSoitLeDecalage() {
        for mois in [8, 11] {
            for day in 1...28 {
                let result = picks(day: day, mois: mois)
                XCTAssertEqual(result.count, 3, "mois \(mois), jour \(day)")
                XCTAssertEqual(result.map(\.kcal), result.map(\.kcal).sorted(),
                               "mois \(mois), jour \(day)")
            }
        }
    }

    /// Une recette dont on a TOUT passe devant, même plus calorique — c'est ce qu'on
    /// peut cuisiner ce soir sans ressortir —, et la rotation ne l'emporte jamais :
    /// elle reste proposée tous les jours.
    ///
    /// Deux tests n'en font plus qu'un : ils portaient la même fixture recopiée au
    /// caractère près, mouraient sur exactement les mêmes mutations, et la boucle de
    /// l'un couvrait déjà le jour par défaut de l'autre. C'est ici, une fois fusionnés,
    /// que le compte des cartes trouve sa place : une seule recette couverte, c'est le
    /// chemin MIXTE — une complète, deux tournantes —, et `rotated.prefix(remaining)`
    /// s'y mutait en `prefix(limit)` sans un mot, pour une bande à quatre cartes.
    func testLaCouvertureCompletePasseDevantEtNestPasEmporteeParLaRotation() {
        let target = candidates(mois: 8).first!
        XCTAssertTrue(candidates(mois: 8).contains { kcal($0) < kcal(target) },
                      "sans candidate plus légère, « passe devant les kcal » ne prouverait rien")
        let frigo = ingredients(of: [target])
        for day in 1...28 {
            let result = picks(day: day, pantry: frigo)
            XCTAssertEqual(result.count, 3, "jour \(day)")
            XCTAssertEqual(result.first?.recipe.itemID, target.itemID, "jour \(day)")
            XCTAssertEqual(result.first?.missingCount, 0, "jour \(day)")
            XCTAssertTrue(result.first?.hasEverything ?? false, "jour \(day)")
        }
    }

    /// Frigo plein : COMBIEN de cartes, et surtout LESQUELLES.
    ///
    /// Le plafond de trois vaut aussi dans la branche « couverture complète »
    /// (`prefix(limit)` s'y mutait en `prefix(limit + 1)`), et le tri de cette branche
    /// n'avait lui non plus aucun témoin : le supprimer laissait tout vert, parce que
    /// le tri d'AFFICHAGE remet ensuite le résultat en ordre — ce qui est faux alors,
    /// c'est la sélection, pas l'ordre. Les trois affichées seraient celles de l'ordre
    /// de `recipes.json` au lieu des trois moins caloriques.
    func testLeFrigoPleinDonneLesTroisPlusLegeres() {
        let toutes = candidates(mois: 8)
        XCTAssertGreaterThan(toutes.count, 3, "sans plus de trois candidates, le plafond ne plafonne rien")
        let result = picks(pantry: ingredients(of: toutes))
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.allSatisfy(\.hasEverything))
        XCTAssertEqual(result.map(\.recipe.itemID),
                       parKcalPuisId(toutes).prefix(3).map(\.itemID))
    }

    /// La frontière du « tu as tout ✓ », épinglée directement sur le type : elle
    /// n'était nulle part, et `missingCount == 0` se mutait en `<= 1` sans qu'un test
    /// ne bronche — une carte annoncerait « tu as tout » avec un ingrédient en moins,
    /// et passerait devant celles dont on a vraiment tout.
    func testLaFrontiereDuTuAsTout() {
        let recette = Recipe(itemID: "labo", months: [8], steps: ["a", "b", "c"])
        func suggestion(missing: Int) -> RecipeSuggestion {
            RecipeSuggestion(recipe: recette, kcal: 300, ingredientCount: 3, missingCount: missing)
        }
        XCTAssertTrue(suggestion(missing: 0).hasEverything)
        XCTAssertFalse(suggestion(missing: 1).hasEverything)
        XCTAssertEqual(suggestion(missing: 0).coverage, 1)
        XCTAssertEqual(suggestion(missing: 3).coverage, 0)
    }

    /// Le même jour donne le même classement : la bande ne bouge pas entre deux
    /// allers-retours sur l'onglet.
    func testStableDansLaJournee() {
        // Sans ce compte, deux listes vides se ressemblent parfaitement et le test
        // se tait — même défaut que dans `testFrigoVideClasseAuxKcalSeules`.
        XCTAssertEqual(picks().count, 3)
        XCTAssertEqual(picks().map(\.recipe.itemID), picks().map(\.recipe.itemID))
    }

    /// Ce que ce test tient : la rotation sert à quelque chose, et la liste courte
    /// compte bien neuf entrées. Une rotation écrasée par le tri — ou neutralisée —
    /// ramène l'union du mois à trois recettes. (Il fut « LE » test de la rotation ;
    /// il ne l'est plus : les deux voisins ci-dessous rougissent aussi sur un
    /// `offset = 0`, et c'est tant mieux.)
    func testLaRotationVarieDunJourALautre() {
        let month = (1...28).map { picks(day: $0).map(\.recipe.itemID) }
        XCTAssertGreaterThan(Set(month.flatMap { $0 }).count, 3,
                             "un mois entier ne doit pas tourner sur trois recettes")
        // Et elle ne dégénère pas : chaque jour montre bien trois cartes distinctes.
        for day in month { XCTAssertEqual(Set(day).count, 3) }
        // La liste courte est bornée des DEUX côtés : neuf, pas moins. L'assertion
        // ci-dessus ne tient que le plancher (« plus de trois »), et `prefix(limit * 3)`
        // se mutait en `prefix(4)` ou `prefix(limit * 2)` sans un mot — la rotation
        // tournerait alors sur quatre recettes au lieu de neuf. Vingt-huit jours
        // balaient les neuf décalages, donc l'union vaut exactement la liste courte.
        XCTAssertEqual(Set(month.flatMap { $0 }).count, 9,
                       "la liste courte de la spec §6.4 règle 4 en compte neuf")
    }

    /// « Deux jours voisins n'affichent pas la même chose » (spec §6.4) — la seule
    /// règle de la section que rien ne tenait. Un décalage par la SEMAINE
    /// (`dayOfYear / 7`) la viole sept jours sur sept sans faire rougir quoi que ce
    /// soit d'autre : la bande resterait figée du lundi au dimanche.
    func testDeuxJoursVoisinsNaffichentPasLaMemeChose() {
        for day in 1...27 {
            XCTAssertNotEqual(picks(day: day).map(\.recipe.itemID),
                              picks(day: day + 1).map(\.recipe.itemID),
                              "jours \(day) et \(day + 1)")
        }
    }

    /// Et le décalage suit le jour de l'ANNÉE, non celui du mois : `.day, in: .month`
    /// se substituait à `.day, in: .year` sans une rougeur, alors que le 13 de chaque
    /// mois afficherait la même bande. Juillet et août portent exactement les mêmes
    /// douze candidates du soir — à jour du mois égal, seul le rang dans l'année peut
    /// donc les distinguer.
    func testLeDecalageSuitLeJourDeLanneeEtNonCeluiDuMois() {
        XCTAssertEqual(Set(candidates(mois: 7).map(\.itemID)),
                       Set(candidates(mois: 8).map(\.itemID)),
                       "juillet et août doivent porter les mêmes candidates, sinon ce test ne prouve rien")
        XCTAssertNotEqual(picks(day: 13, mois: 7).map(\.recipe.itemID),
                          picks(day: 13, mois: 8).map(\.recipe.itemID))
    }

    /// Ce que ce test tient SEUL, depuis que le test de rotation compte l'union du
    /// mois : que les neuf de la liste courte sont les neuf plus LÉGÈRES des douze
    /// candidates d'août — pas seulement qu'elles sont neuf. Sans lui, la liste courte
    /// pourrait être prise par le bout haut et la bande proposerait un soir sur quatre
    /// les trois plats les plus caloriques de la saison.
    func testLaRotationNePiocheQueDansLesNeufPlusLegeres() {
        let douze = candidates(mois: 8)
        // Sans strictement plus de neuf candidates, la borne ne borne rien et le
        // test ne prouverait plus rien.
        XCTAssertGreaterThan(douze.count, 9)
        let plusLegeres = Set(douze
            .sorted { kcal($0) != kcal($1) ? kcal($0) < kcal($1) : $0.itemID < $1.itemID }
            .prefix(9).map(\.itemID))
        for day in 1...28 {
            let result = picks(day: day)
            // Le compte dans la BOUCLE : sans lui, une bande vide ne fait rien
            // assener au corps de la boucle, et la seule assertion inconditionnelle
            // de ce test porte sur le catalogue, pas sur le classement. C'est le
            // défaut que ce fichier a déjà réparé trois fois ailleurs.
            XCTAssertEqual(result.count, 3, "jour \(day)")
            for pick in result {
                XCTAssertTrue(plusLegeres.contains(pick.recipe.itemID),
                              "jour \(day) : \(pick.recipe.itemID)")
            }
        }
    }

    /// La dernière clé du comparateur — l'id — n'était tenue par rien : la remplacer
    /// par `return false` laissait les dix tests verts, parce qu'aucun ne quittait le
    /// mois d'août. Les ex æquo de kcal existent pourtant vraiment, tous hors saison
    /// chaude : `veg_wok`/`fish_mash` à 465 (soir, novembre à mars),
    /// `tuna_potato_salad`/`pumpkin_soup` à 342 (soir, octobre à décembre),
    /// `squash_risotto`/`autumn_lentils` à 464 (octobre-novembre).
    ///
    /// Catalogue de laboratoire quand même, et les deux recettes déclarées dans
    /// l'ordre INVERSE de leurs ids : le tri de Swift n'est pas garanti stable, un
    /// comparateur sans clé finale rendrait donc un ordre non spécifié — ici, l'ordre
    /// du fichier, qu'on prend soin de faire différer de la réponse attendue.
    func testLesExAequoSordonnentParId() {
        func item(_ id: String) -> FoodItem {
            FoodItem(id: id, name: id, emoji: "🍲", kcalPer100g: 100, category: .dish,
                     slots: [.dinner], defaultGrams: 200, isRecipe: true)
        }
        let labo = laboratoire([item("labo_zoulou"), item("labo_alpha")])
        let result = RecipeSuggester.suggestions(
            date: jour(13), slot: .dinner, pantry: ["labo_zoulou", "labo_alpha"],
            recipes: labo.recipes, foods: labo.foods, calendar: calendar, limit: 2)
        XCTAssertEqual(result.map(\.kcal), [200, 200],
                       "les deux doivent être ex æquo, sinon les kcal trancheraient avant l'id")
        XCTAssertEqual(result.map(\.recipe.itemID), ["labo_alpha", "labo_zoulou"])
    }

    /// Repli : on relâche le MOIS avant le créneau — mieux vaut une idée hors
    /// saison qu'une bande vide au 1ᵉʳ février. Le créneau, lui, ne se relâche
    /// jamais : proposer un déjeuner le soir n'aiderait personne.
    func testLeRepliRelacheLeMois() {
        // Une recette de DÉJEUNER choisie explicitement — se fier à l'ordre du
        // fichier ferait échouer le test pour une raison sans rapport.
        let lunchRecipe = recipes.recipes.first {
            catalog.byID[$0.itemID]!.slots.contains(.lunch)
        }!   // et NON `candidates(mois:)` : c'est une recette hors saison qu'il faut ici
        let januaryOnly = RecipeCatalog(recipes: [
            Recipe(itemID: lunchRecipe.itemID, months: [1], steps: ["a", "b", "c"])
        ])
        let result = RecipeSuggester.suggestions(
            date: jour(13), slot: .lunch, pantry: [], recipes: januaryOnly,
            foods: catalog, calendar: calendar, limit: 3)
        XCTAssertEqual(result.count, 1, "une bande vide serait la fonctionnalité en panne")
        XCTAssertEqual(result.first?.recipe.itemID, lunchRecipe.itemID)
    }

    /// Le créneau ne se relâche jamais, lui.
    ///
    /// Recette et aliment de LABORATOIRE, sans rien tirer de `recipes.json` : le
    /// sujet du test est le relâchement du créneau, pas le contenu éditorial du
    /// catalogue. Écrit avec un `first { slots == [.dinner] }` suivi d'un
    /// `guard … else { return }`, ce test passait au vert sans rien prouver le jour
    /// où plus aucune recette n'est soir-seul — et forçait en retour la Task 3 à en
    /// garder une, couplage invisible entre une donnée et un test de logique.
    func testLeCreneauNeSeRelacheJamais() {
        let item = FoodItem(id: "labo_soir", name: "Soupe du labo", emoji: "🥣",
                            kcalPer100g: 60, category: .dish, slots: [.dinner],
                            defaultGrams: 300, isRecipe: true)
        let labo = laboratoire([item])
        func suggestions(slot: MealSlot) -> [RecipeSuggestion] {
            RecipeSuggester.suggestions(date: jour(13), slot: slot, pantry: [],
                                        recipes: labo.recipes, foods: labo.foods,
                                        calendar: calendar, limit: 3)
        }
        // Le contrôle d'abord : sans lui, un vide dû à une fixture cassée — un id
        // absent du catalogue, par exemple — passerait pour la preuve recherchée.
        XCTAssertEqual(suggestions(slot: .dinner).map(\.recipe.itemID), [item.id])
        XCTAssertTrue(suggestions(slot: .lunch).isEmpty)
    }

    /// Une recette dont l'`itemID` ne tombe dans aucun aliment est écartée là, et
    /// nulle part ailleurs : depuis que `score` reçoit un `FoodItem` non optionnel,
    /// le `guard let` du filtre est la seule défense qui reste — les deux `?? []`
    /// qu'il rendait inatteignables ont été retirés. Une défense sans témoin n'en est
    /// pas une : sans ce test, elle se muterait en `!`, et un `recipes.json` en avance
    /// sur `foods.json` ferait planter l'onglet Repas au lieu de sauter la recette.
    func testUneRecetteSansAlimentEstEcarteeSansPlanter() {
        let orpheline = RecipeCatalog(recipes: [
            Recipe(itemID: "aliment_inexistant", months: [8], steps: ["a", "b", "c"])
        ])
        let result = RecipeSuggester.suggestions(
            date: jour(13), slot: .dinner, pantry: [], recipes: orpheline,
            foods: catalog, calendar: calendar, limit: 3)
        XCTAssertTrue(result.isEmpty)
    }

    func testLeCatalogueVideNeDonneRien() {
        let result = RecipeSuggester.suggestions(
            date: jour(13), slot: .dinner, pantry: [], recipes: .empty,
            foods: catalog, calendar: calendar, limit: 3)
        XCTAssertTrue(result.isEmpty)
    }
}
