# Repas précis (v1.10) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rendre le compte de calories juste quand on veut bien le préciser : un repas devient une liste de lignes, chaque plat arrive composé par défaut, tout se règle en grammes, et un chiffre saisi à la main prend le dessus.

**Architecture:** Le modèle et le calcul partent en entier dans NivelCore (`MealLine` en enum, `FoodItem`, `FoodCatalog`, `MealEstimator`), avec les contenus en JSON embarqué comme les autres catalogues. L'app garde SwiftData et SwiftUI : `MealEntry` troque `dishID`/`portion`/`extras` contre `lines` et `manualKcal`, et la feuille de log devient un panier surmontant un catalogue à onglets, avec un écran de détail poussé en navigation.

**Tech Stack:** Swift 5.9, SwiftUI, SwiftData, XcodeGen, XCTest.

**Spec:** `docs/superpowers/specs/2026-08-02-repas-precis-design.md` — **c'est la source unique des contenus**. Les tables §4.2, §4.3, §4.4 et §4.5 ne sont PAS recopiées ici : les transcrire deux fois, c'est garantir qu'elles divergeront.

---

## Commandes de référence

```sh
cd NivelCore && swift test
cd NivelCore && swift test --filter MealEstimatorTests
xcodegen generate
xcodebuild -project Nivel.xcodeproj -scheme Nivel \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Point de départ attendu : **117 tests NivelCore + 68 tests app** au vert sur `main`, version 1.9 (build 10).

## Structure des fichiers

**Créés dans NivelCore**

| Fichier | Responsabilité |
|---|---|
| `Sources/NivelCore/MealLine.swift` | `MealComponent`, `MealLine` (enum), et le raccourci de portion |
| `Sources/NivelCore/Foods.swift` | `FoodItem`, `FoodCategory`, `FoodCatalog` |
| `Sources/NivelCore/Resources/foods.json` | Le catalogue, transcrit des tables de la spec |
| `Sources/NivelCore/Resources/compositions.json` | Les 15 compositions par défaut |
| `Tests/NivelCoreTests/MealLineTests.swift` | |
| `Tests/NivelCoreTests/FoodCatalogTests.swift` | Intégrité, conversions, garde-fou des compositions |
| `Sources/NivelCore/MealFormatting.swift` | Règle du tilde et résumé de repas (Tasks 7 et 8) |

**Créés dans l'app**

| Fichier | Responsabilité |
|---|---|
| `App/Views/Meals/MealBasketView.swift` | Le panier « Ton repas » |
| `App/Views/Meals/FoodCatalogView.swift` | Les quatre onglets et leur grille |
| `App/Views/Meals/MealLineDetailView.swift` | L'écran poussé : portion, composants, grammes |
| `NivelTests/MealLoggingTests.swift` | Persistance des lignes, règle du tilde, résumés |

**Modifiés**

| Fichier | Changement |
|---|---|
| `NivelCore/Sources/NivelCore/MealEstimator.swift` | Réécrit sur les lignes |
| `NivelCore/Sources/NivelCore/Catalogs.swift` | +`foods()`, +`compositions()` |
| `App/Models/PersistentModels.swift` | `MealEntry` : −3 propriétés, +2 |
| `App/Services/GameService.swift` | `logMeal` / `updateMeal` sur des lignes |
| `App/Views/Meals/MealLogSheet.swift` | Réécrite autour du panier |
| `App/Views/Meals/MealsJournalView.swift` | Résumé de ligne, règle du tilde |
| `project.yml`, `README.md` | Version 1.10 (build 11) |

**Supprimés** : `Dish` et `Extra` dans `Catalogs.swift`, `dishes.json`, `extras.json`. Leurs contenus sont absorbés par `foods.json`. Ne PAS les supprimer avant la Task 6, qui est la dernière à les référencer.

---

### Task 1 : `MealLine` et le calcul

**Files:**
- Create: `NivelCore/Sources/NivelCore/MealLine.swift`
- Modify: `NivelCore/Sources/NivelCore/MealEstimator.swift`
- Test: `NivelCore/Tests/NivelCoreTests/MealLineTests.swift`

- [ ] **Step 1: Écrire les tests qui échouent**

```swift
// NivelCore/Tests/NivelCoreTests/MealLineTests.swift
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
```

- [ ] **Step 2: Lancer, vérifier l'échec**

Run: `cd NivelCore && swift test --filter MealLineTests`
Expected: « cannot find 'MealLine' in scope ».

- [ ] **Step 3: Écrire l'implémentation**

```swift
// NivelCore/Sources/NivelCore/MealLine.swift
// Le contenu d'un repas (spec v1.10 §3.2). Un repas est une liste de lignes ; une
// ligne est soit un item seul, soit un plat et sa composition.

import Foundation

/// Un item du catalogue et son poids. TOUJOURS des grammes : l'unité affichée
/// (« 1 œuf », « 1 c. à soupe ») vient du catalogue au moment du rendu, jamais de la
/// base, sinon corriger le poids d'un œuf fausserait les repas déjà loggés.
public struct MealComponent: Codable, Equatable, Hashable, Sendable {
    public let itemID: String
    public let grams: Int
    public init(itemID: String, grams: Int) {
        self.itemID = itemID
        self.grams = grams
    }
}

/// Un enum et non une struct à `components` optionnel : une ligne composée porterait
/// sinon un poids propre qui ne veut rien dire et que le calcul ignorerait en silence.
/// Borne aussi la profondeur à un niveau par construction.
public enum MealLine: Codable, Equatable, Hashable, Sendable {
    case simple(MealComponent)
    case composed(itemID: String, components: [MealComponent])

    /// Ce que la ligne représente au catalogue, quelle que soit sa forme.
    public var itemID: String {
        switch self {
        case .simple(let component): component.itemID
        case .composed(let itemID, _): itemID
        }
    }

    /// Les composants à sommer. Une ligne simple est son propre unique composant.
    public var components: [MealComponent] {
        switch self {
        case .simple(let component): [component]
        case .composed(_, let components): components
        }
    }

    public var isComposed: Bool {
        if case .composed = self { true } else { false }
    }
}

/// Raccourci de saisie, PAS un état persisté (spec §2) : taper une portion réécrit
/// les grammes une bonne fois. Rien ne multiplie donc quoi que ce soit après coup.
public enum MealPortion: String, CaseIterable, Sendable {
    case light, normal, hearty

    public var multiplier: Double {
        switch self {
        case .light: 0.7
        case .normal: 1.0
        case .hearty: 1.3
        }
    }

    public var frLabel: String {
        switch self {
        case .light: "Léger"
        case .normal: "Normal"
        case .hearty: "Copieux"
        }
    }

    /// Plancher à 1 g : une noisette de beurre en léger reste une noisette, pas rien.
    public func applied(to components: [MealComponent]) -> [MealComponent] {
        components.map {
            MealComponent(itemID: $0.itemID,
                          grams: max(1, Int((Double($0.grams) * multiplier).rounded())))
        }
    }

    /// Cran correspondant à des grammes donnés, ou nil si l'utilisateur a ajusté à la
    /// main. La portion n'étant pas persistée, c'est ainsi que le panier retrouve son
    /// libellé. Comparaison sur la composition ENTIÈRE : retirer un ingrédient suffit
    /// à sortir des crans, même si les autres quantités collent encore.
    public static func matching(components: [MealComponent],
                                defaults: [MealComponent]) -> MealPortion? {
        guard !defaults.isEmpty else { return nil }
        return allCases.first { $0.applied(to: defaults) == components }
    }
}
```

```swift
// NivelCore/Sources/NivelCore/MealEstimator.swift
// Calcul des kcal d'un repas (spec v1.10 §3.3). Pur : le barème est INJECTÉ, ce qui
// permet de tester le calcul sans dépendre du contenu du catalogue.

import Foundation

public enum MealEstimator {
    /// Un seul arrondi, à la fin : arrondir composant par composant ferait dériver
    /// une composition à six ingrédients de plusieurs kcal pour rien.
    public static func kcal(lines: [MealLine],
                            kcalPer100g: (String) -> Double?) -> Int {
        let total = lines
            .flatMap(\.components)
            .reduce(0.0) { sum, component in
                // Item inconnu = 0 : un JSON corrompu ne doit pas empêcher
                // d'ouvrir son journal.
                sum + (kcalPer100g(component.itemID) ?? 0) * Double(component.grams) / 100
            }
        return Int(total.rounded())
    }
}
```

- [ ] **Step 4: Lancer, vérifier le succès**

Run: `cd NivelCore && swift test`
Expected: 117 pré-existants + les nouveaux, tous verts.

- [ ] **Step 5: Commit**

```bash
git add NivelCore/Sources/NivelCore/MealLine.swift NivelCore/Sources/NivelCore/MealEstimator.swift NivelCore/Tests/NivelCoreTests/MealLineTests.swift
git commit -m "feat(core): un repas devient une liste de lignes, calcul pur à barème injecté"
```

**Ne PAS supprimer l'ancien `MealEstimator.estimate(dish:portion:extras:)` ici.** Il est encore appelé par `GameService` et `MealLogSheet`, et le retirer casserait la compilation de l'app pendant trois tasks, donc supprimerait tout signal de régression sur cette durée. Les deux fonctions cohabitent jusqu'à la Task 4, qui bascule l'app d'un bloc et emporte l'ancienne. C'est quelques lignes mortes pendant deux commits contre un arbre qui reste vert : le change est bon.

---

### Task 2 : Le catalogue d'aliments

**Files:**
- Create: `NivelCore/Sources/NivelCore/Foods.swift`
- Create: `NivelCore/Sources/NivelCore/Resources/foods.json`
- Modify: `NivelCore/Sources/NivelCore/Catalogs.swift`
- Test: `NivelCore/Tests/NivelCoreTests/FoodCatalogTests.swift`

- [ ] **Step 1: Écrire le type**

```swift
// NivelCore/Sources/NivelCore/Foods.swift
// Catalogue unique des aliments (spec v1.10 §4.1). Remplace Dish et Extra : plats,
// accompagnements, boissons et encas ne diffèrent plus que par leur catégorie.

import Foundation

public struct FoodItem: Codable, Identifiable, Hashable, Sendable {
    public enum Category: String, Codable, CaseIterable, Sendable {
        case dish, side, drink, snack

        public var frLabel: String {
            switch self {
            case .dish: "Plats"
            case .side: "Accompagnements"
            case .drink: "Boissons"
            case .snack: "Encas"
            }
        }
    }

    public let id: String
    public let name: String
    public let emoji: String
    public let kcalPer100g: Double
    /// Unité naturelle de saisie (« œuf », « c. à soupe »). nil = au gramme.
    public let unitLabel: String?
    /// Pluriel de l'unité, quand il ne s'obtient pas en ajoutant un s (« morceaux »
    /// s'obtient, « c. à soupe » est invariable). nil = ajouter un s.
    public let unitLabelPlural: String?
    /// Poids d'une unité. Non nil si et seulement si `unitLabel` l'est.
    public let unitGrams: Int?
    public let category: Category
    /// Créneaux pertinents pour les plats. Vide = proposé partout.
    public let slots: [MealSlot]
    /// Quantité posée au tap dans le catalogue.
    public let defaultGrams: Int

    public var hasUnit: Bool { unitLabel != nil && unitGrams != nil }

    /// « 2 œufs », « 1 c. à soupe », « 80 g ». Les grammes restent la vérité ; l'unité
    /// n'est qu'une commodité d'affichage.
    public func frQuantity(grams: Int) -> String {
        guard let unitLabel, let unitGrams, unitGrams > 0 else { return "\(grams) g" }
        let count = Double(grams) / Double(unitGrams)
        let rounded = (count * 2).rounded() / 2      // au demi près
        let number = rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(rounded).replacingOccurrences(of: ".", with: ",")
        let label = rounded > 1 ? (unitLabelPlural ?? unitLabel + "s") : unitLabel
        return "\(number) \(label)"
    }
}
```

Dans `Catalogs.swift`, ajouter :

```swift
    public static func foods() throws -> [FoodItem] { try load("foods") }
    public static func compositions() throws -> [String: [MealComponent]] { try load("compositions") }
```

Et un accès indexé, parce que tous les appelants en auront besoin :

```swift
/// Catalogue chargé une fois, indexé. Les vues et le calcul y lisent leur barème.
public struct FoodCatalog: Sendable {
    public let items: [FoodItem]
    public let byID: [String: FoodItem]
    public let compositions: [String: [MealComponent]]

    public static func load() throws -> FoodCatalog {
        let items = try Catalogs.foods()
        return FoodCatalog(
            items: items,
            byID: Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }),
            compositions: try Catalogs.compositions()
        )
    }

    public func kcalPer100g(_ itemID: String) -> Double? { byID[itemID]?.kcalPer100g }

    public func items(category: FoodItem.Category, slot: MealSlot?) -> [FoodItem] {
        items.filter { item in
            guard item.category == category else { return false }
            guard let slot, !item.slots.isEmpty else { return true }
            return item.slots.contains(slot)
        }
    }

    /// La ligne posée au tap : composée si le plat a une composition, simple sinon.
    public func line(for item: FoodItem) -> MealLine {
        if let composition = compositions[item.id], !composition.isEmpty {
            return .composed(itemID: item.id, components: composition)
        }
        return .simple(MealComponent(itemID: item.id, grams: item.defaultGrams))
    }
}
```

- [ ] **Step 2: Transcrire `foods.json` depuis la spec**

**La spec est la source, ce plan ne recopie pas les tables.** Ouvrir `docs/superpowers/specs/2026-08-02-repas-precis-design.md` et transcrire :

- §4.2, les 15 boissons, `category: "drink"`, `slots: []`, `defaultGrams` = le poids d'une unité ;
- §4.3, les 12 encas, `category: "snack"`, `slots: []`, `defaultGrams` = le poids d'une unité ;
- §4.4, les 43 ingrédients, `category: "side"`, `slots: []`, `defaultGrams` au jugé (une portion d'appoint plausible : 100 g pour un féculent, 30 g pour du fromage, le poids d'une unité quand il y en a une) ;
- les 16 plats de l'actuel `dishes.json`, `category: "dish"`, en conservant **id, nom, emoji et slots à l'identique**, `kcalPer100g` et `defaultGrams` choisis pour que `defaultGrams × kcalPer100g / 100` retombe sur le forfait v1 (pour un plat composé ces deux valeurs ne servent qu'au repli, la composition primant).

Format :

```json
[
  {
    "id": "beer_half", "name": "Bière, demi", "emoji": "🍺",
    "kcalPer100g": 43, "unitLabel": "demi", "unitGrams": 250,
    "category": "drink", "slots": [], "defaultGrams": 250
  }
]
```

**Attention aux ids qui existent déjà** dans l'ancien `extras.json` : `water`, `beer`, `wine`, `soda`, `dessert_light`, `dessert_rich`. Le nouveau catalogue remplace `beer` par `beer_half` et `beer_pint`, et les deux desserts par les entrées d'encas. Aucun ancien id ne doit survivre par inadvertance.

- [ ] **Step 3: Écrire les tests d'intégrité**

```swift
// NivelCore/Tests/NivelCoreTests/FoodCatalogTests.swift
import XCTest
@testable import NivelCore

final class FoodCatalogTests: XCTestCase {
    private var catalog: FoodCatalog!

    override func setUpWithError() throws {
        catalog = try FoodCatalog.load()
    }

    func testLeCatalogueSeChargeEtEstComplet() throws {
        XCTAssertEqual(catalog.items(category: .drink, slot: nil).count, 15)
        XCTAssertEqual(catalog.items(category: .snack, slot: nil).count, 12)
        XCTAssertEqual(catalog.items(category: .dish, slot: nil).count, 16)
        XCTAssertGreaterThanOrEqual(catalog.items(category: .side, slot: nil).count, 40)
    }

    func testPasDeDoublonDId() {
        XCTAssertEqual(Set(catalog.items.map(\.id)).count, catalog.items.count)
    }

    func testUniteEtPoidsVontEnsemble() {
        for item in catalog.items {
            XCTAssertEqual(item.unitLabel != nil, item.unitGrams != nil,
                           "\(item.id) : unité et poids doivent aller par paire")
            if let grams = item.unitGrams { XCTAssertGreaterThan(grams, 0, item.id) }
            XCTAssertGreaterThan(item.defaultGrams, 0, item.id)
            XCTAssertGreaterThanOrEqual(item.kcalPer100g, 0, item.id)
        }
    }

    /// Garde-fou de transcription : les kcal par unité des tables de la spec doivent
    /// se retrouver à partir de kcalPer100g et du poids d'une unité.
    func testKcalParUniteRetombentSurLaSpec() {
        let expected: [String: Int] = [
            "beer_half": 108, "beer_pint": 215, "wine": 106, "soda": 139,
            "coffee_milk": 90, "chips": 153, "candy": 105, "nuts": 180,
            "choco_bar": 230, "yogurt": 75, "fruit": 80,
        ]
        for (id, kcal) in expected {
            let item = catalog.byID[id]
            XCTAssertNotNil(item, "item manquant : \(id)")
            guard let item, let grams = item.unitGrams else { continue }
            let computed = Int((item.kcalPer100g * Double(grams) / 100).rounded())
            XCTAssertEqual(computed, kcal, accuracy: 1, "\(id) : conversion incohérente")
        }
    }

    func testLibelleDeQuantite() {
        let egg = catalog.byID["egg"]
        XCTAssertEqual(egg?.frQuantity(grams: 60), "1 œuf")
        XCTAssertEqual(egg?.frQuantity(grams: 120), "2 œufs")
        XCTAssertEqual(egg?.frQuantity(grams: 30), "0,5 œuf")
        XCTAssertEqual(catalog.byID["chicken"]?.frQuantity(grams: 150), "150 g")
    }

    /// Les unités invariables doivent porter leur pluriel explicite, sinon on lit
    /// « 2 c. à soupes ».
    func testUnitesInvariables() {
        for item in catalog.items where item.unitLabel?.contains("c. à") == true {
            XCTAssertEqual(item.unitLabelPlural, item.unitLabel,
                           "\(item.id) : pluriel explicite attendu")
        }
    }
}
```

**Le pluriel se règle par les données, pas par une règle.** `unitLabelPlural` est nil quand ajouter un s suffit (« œufs », « verres », « boules »), et explicite sinon : « c. à soupe » et « c. à café » sont invariables, « morceau » donne « morceaux ». À remplir en transcrivant, le test ci-dessus attrape les cuillères oubliées.

- [ ] **Step 4: Vérifier**

Run: `cd NivelCore && swift test`

- [ ] **Step 5: Commit**

```bash
git add NivelCore/
git commit -m "feat(core): catalogue unique d'aliments, 15 boissons et 12 encas"
```

---

### Task 3 : Les compositions par défaut

**Files:**
- Create: `NivelCore/Sources/NivelCore/Resources/compositions.json`
- Modify: `NivelCore/Tests/NivelCoreTests/FoodCatalogTests.swift`

- [ ] **Step 1: Transcrire la table §4.5 de la spec**

Quinze entrées, `dishID → [{itemID, grams}]`. « Autre » n'en a pas : c'est délibéré (§4.5).

```json
{
  "pasta": [
    { "itemID": "pasta_cooked", "grams": 250 },
    { "itemID": "tomato_sauce", "grams": 120 },
    { "itemID": "grated_cheese", "grams": 25 },
    { "itemID": "olive_oil", "grams": 12 }
  ]
}
```

- [ ] **Step 2: Écrire le garde-fou**

Ajouter à `FoodCatalogTests` :

```swift
    /// LE test de contenu de ce lot. Si la composition par défaut d'un plat s'éloigne
    /// de plus de 10 % du forfait qu'il avait en v1, c'est qu'un ingrédient est mal
    /// dosé. Mieux vaut l'apprendre ici qu'au dîner.
    func testChaqueCompositionRetombeSurLeForfaitV1() {
        let forfaits: [String: Int] = [
            "pasta": 650, "rice": 550, "salad": 350, "veggies": 450,
            "red_meat": 700, "fish": 500, "pizza": 900, "soup": 300,
            "sandwich": 550, "stew": 600, "fast_food": 950, "toast": 350,
            "cereal": 400, "pastry": 300, "yogurt_fruit": 200,
        ]
        for (dishID, forfait) in forfaits {
            let composition = catalog.compositions[dishID]
            XCTAssertNotNil(composition, "composition manquante : \(dishID)")
            guard let composition else { continue }
            let sum = MealEstimator.kcal(
                lines: [.composed(itemID: dishID, components: composition)],
                kcalPer100g: catalog.kcalPer100g
            )
            let tolerance = Double(forfait) * 0.10
            XCTAssertEqual(Double(sum), Double(forfait), accuracy: tolerance,
                           "\(dishID) : composition à \(sum) kcal pour un forfait de \(forfait)")
        }
    }

    func testAutreNAPasDeComposition() {
        XCTAssertNil(catalog.compositions["other"])
    }

    func testToutIngredientCiteExiste() {
        for (dishID, composition) in catalog.compositions {
            for component in composition {
                XCTAssertNotNil(catalog.byID[component.itemID],
                                "\(dishID) cite un item inconnu : \(component.itemID)")
                XCTAssertGreaterThan(component.grams, 0, "\(dishID)/\(component.itemID)")
            }
        }
    }
```

- [ ] **Step 3: Lancer et corriger les dosages**

Run: `cd NivelCore && swift test --filter FoodCatalogTests`

Si un plat sort de la tolérance, **corriger les grammes de sa composition**, pas la tolérance ni le forfait. La spec donne des sommes déjà calculées ; un écart signale une erreur de transcription.

- [ ] **Step 4: Commit**

```bash
git add NivelCore/
git commit -m "feat(core): compositions par défaut des 15 plats, avec garde-fou à 10 %"
```

---

### Task 4 : Le modèle persisté et le service

> **Les Tasks 4 et 5 forment un seul changement, à committer une seule fois, à la fin de la Task 5.** Changer la signature de `logMeal` casse `MealLogSheet`, et il n'existe pas de découpage plus fin qui laisse l'arbre compilable : une couche d'adaptateurs temporaires produirait des kcal fausses pendant deux commits, ce qui est pire qu'un arbre rouge. La 4 est donc décrite à part pour rester lisible, mais son seul point de validation est celui de la 5. Ne pas committer entre les deux.

**Files:**
- Modify: `App/Models/PersistentModels.swift`
- Modify: `App/Services/GameService.swift`
- Test: `NivelTests/MealLoggingTests.swift`

- [ ] **Step 1: Écrire le test qui échoue**

```swift
// NivelTests/MealLoggingTests.swift
import XCTest
import SwiftData
import NivelCore
@testable import Nivel

@MainActor
final class MealLoggingTests: XCTestCase {
    /// Container retenu par le cas de test : SwiftData ne le retient pas depuis son
    /// mainContext, et une locale peut être libérée dès son dernier usage (leçon v1.9).
    private var container: ModelContainer!

    override func setUpWithError() throws {
        let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                             DayLog.self, GamificationState.self, ActivityEntry.self])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    private let lines: [MealLine] = [
        .composed(itemID: "salad", components: [
            MealComponent(itemID: "lettuce", grams: 80),
            MealComponent(itemID: "tuna", grams: 80),
        ]),
        .simple(MealComponent(itemID: "beer_half", grams: 250)),
    ]

    func testLesLignesSurviventAUnAllerRetourEnBase() throws {
        let entry = MealEntry(slot: .lunch, lines: lines, estimatedKcal: 230)
        container.mainContext.insert(entry)
        try container.mainContext.save()

        let reloaded = try XCTUnwrap(
            try container.mainContext.fetch(FetchDescriptor<MealEntry>()).first
        )
        XCTAssertEqual(reloaded.lines, lines)
        XCTAssertEqual(reloaded.lines.first?.components.count, 2)
        XCTAssertNil(reloaded.manualKcal)
    }

    func testKcalManuellesCourtCircuitentLeCalcul() throws {
        let catalog = try FoodCatalog.load()
        let computed = MealEstimator.kcal(lines: lines, kcalPer100g: catalog.kcalPer100g)
        let entry = MealEntry(slot: .lunch, lines: lines,
                              estimatedKcal: 450, manualKcal: 450)
        XCTAssertNotEqual(computed, 450)
        XCTAssertEqual(entry.estimatedKcal, 450)
        XCTAssertEqual(entry.manualKcal, 450)
    }

    /// Le repas d'avant la migration : aucune ligne, mais ses kcal et son XP intacts.
    func testRepasSansLigneNeCassePas() throws {
        let entry = MealEntry(slot: .dinner, lines: [], estimatedKcal: 620, xpAwarded: 20)
        container.mainContext.insert(entry)
        try container.mainContext.save()
        XCTAssertTrue(entry.lines.isEmpty)
        XCTAssertEqual(entry.estimatedKcal, 620)
    }
}
```

- [ ] **Step 2: Lancer, vérifier l'échec**

Run: `xcodegen generate` puis la suite app filtrée sur `MealLoggingTests`.
Expected: échec de compilation sur l'init de `MealEntry`.

- [ ] **Step 3: Changer le modèle**

Dans `PersistentModels.swift`, `MealEntry` :

```swift
@Model
final class MealEntry {
    var date: Date
    var slotRaw: String
    // Défauts sur la DÉCLARATION : migration légère SwiftData (leçon v1, reconfirmée
    // en v1.9). La suppression de dishID, portionRaw et extras est elle aussi légère ;
    // l'unique repas déjà loggé perd son détail et garde ses kcal (spec §3.1).
    var lines: [MealLine] = []
    var manualKcal: Int?
    var estimatedKcal: Int
    var xpAwarded: Int

    init(date: Date = .now, slot: MealSlot, lines: [MealLine] = [],
         manualKcal: Int? = nil, estimatedKcal: Int, xpAwarded: Int = 0) { ... }

    var slot: MealSlot { get { ... } set { ... } }
}
```

Supprimer `dishID`, `portionRaw`, `extras` et l'accesseur `portion`.

- [ ] **Step 4: Adapter `GameService`**

`logMeal` et `updateMeal` prennent désormais `lines: [MealLine]` et `manualKcal: Int?` au lieu de `dish/portion/extras`, et calculent :

```swift
let kcal = manualKcal ?? MealEstimator.kcal(lines: lines, kcalPer100g: foodCatalog.kcalPer100g)
```

`GameService` gagne un `foodCatalog: FoodCatalog` chargé une fois au constructeur, comme `activityCatalog`, avec le même repli sur un catalogue vide si le JSON est corrompu (jamais de crash). Tout le reste, plafonds d'XP, `DayLog`, quêtes, badges, niveau, est inchangé.

- [ ] **Step 5: Enchaîner directement sur la Task 5**

Ne rien lancer et ne rien committer ici : l'arbre est rouge par construction, `MealLogSheet` appelle encore l'ancienne signature. Le prochain point d'arrêt est le Step 4 de la Task 5.

---

### Task 5 : La feuille de log, panier et catalogue

**Files:**
- Rewrite: `App/Views/Meals/MealLogSheet.swift`
- Create: `App/Views/Meals/MealBasketView.swift`
- Create: `App/Views/Meals/FoodCatalogView.swift`

- [ ] **Step 1: La structure**

`MealLogSheet` devient :

```swift
NavigationStack {
    ScrollView {
        VStack(alignment: .leading, spacing: 22) {
            slotPicker                    // inchangé
            MealBasketView(lines: $lines, catalog: catalog,
                           onOpen: { index in path.append(index) })
            FoodCatalogView(catalog: catalog, slot: slot,
                            onPick: { item in lines.append(catalog.line(for: item)) })
        }
        .padding(20)
    }
    .safeAreaInset(edge: .bottom) { bottomBar }
    .navigationDestination(for: Int.self) { index in
        MealLineDetailView(line: $lines[index], catalog: catalog)
    }
}
.presentationDetents([.large])
.presentationCornerRadius(28)
.presentationDragIndicator(.visible)
```

Le détent `.large` d'office, comme `ActivityLogSheet` : au medium le catalogue passerait sous le pli.

- [ ] **Step 2: Le panier**

`MealBasketView` : titre « Ton repas », puis soit l'état vide (« Tape un plat, une boisson, ce que tu veux », `Theme.subtext`), soit une ligne par entrée. Chaque ligne : emoji, nom, sous-titre de quantité, kcal, chevron, et un swipe de suppression.

Le sous-titre vient du catalogue :
- ligne composée : `"\(portionLabel) · \(components.count) ingrédients"` s'il en reste, sinon simplement le nombre ;
- ligne simple : `item.frQuantity(grams:)`.

**La portion affichée d'une ligne composée n'est pas persistée** : on la déduit en comparant les grammes courants à la composition par défaut. Extraire ce calcul en fonction pure et testée dans NivelCore plutôt que de le laisser dans la vue :

```swift
/// Portion correspondant à des grammes donnés, ou nil si l'utilisateur a ajusté
/// à la main et que ça ne retombe sur aucun des trois crans.
public static func matching(components: [MealComponent],
                            defaults: [MealComponent]) -> MealPortion?
```

Sous-titre : « normal · 6 ingrédients », ou « ajusté · 6 ingrédients » quand la fonction rend nil.

- [ ] **Step 3: Le catalogue à onglets**

`FoodCatalogView` : un `Picker` segmenté sur `FoodItem.Category.allCases` (Plats · Accompagnements · Boissons · Encas), puis la grille à deux colonnes existante (`dishCard` de l'actuelle feuille, à reprendre tel quel : emoji, nom, kcal). L'onglet Plats est filtré par `catalog.items(category:slot:)` sur le créneau courant ; les trois autres ignorent le créneau.

Un tap appelle `onPick`. Pas de sélection persistante : la puce ne reste pas allumée, c'est le panier qui matérialise le choix.

- [ ] **Step 4: Vérifier**

Run: `xcodegen generate` puis la suite app.
Expected: le projet compile à nouveau, `MealLoggingTests` de la Task 4 passe, 68 tests pré-existants toujours verts. **C'est le point de validation des Tasks 4 et 5 réunies** : si l'arbre est encore rouge ici, ne pas committer, corriger.

Ouvrir la preview et vérifier : panier vide au départ, un tap sur Pâtes ajoute une ligne, le total de la barre basse suit.

- [ ] **Step 5: Commit unique pour les Tasks 4 et 5**

```bash
git add App/Models/PersistentModels.swift App/Services/GameService.swift \
        App/Views/Meals/ NivelTests/MealLoggingTests.swift Nivel.xcodeproj/project.pbxproj
git commit -m "feat(repas): basculer le modèle, le service et la feuille sur des lignes"
```

---

### Task 6 : L'écran de détail d'une ligne

**Files:**
- Create: `App/Views/Meals/MealLineDetailView.swift`
- Delete: `NivelCore/Sources/NivelCore/Resources/dishes.json`, `extras.json`
- Modify: `NivelCore/Sources/NivelCore/Catalogs.swift` (retirer `Dish`, `Extra`, `dishes()`, `extras()`)

- [ ] **Step 1: L'écran**

Poussé par le chevron du panier. De haut en bas :

1. Le nom de l'item et son emoji.
2. **Pour une ligne composée uniquement** : les trois puces Léger / Normal / Copieux, qui appliquent `MealPortion.applied(to:)` à la composition **par défaut** du plat, pas aux grammes courants. C'est le point délicat : partir des grammes courants ferait dériver les valeurs à chaque tap (copieux sur copieux donnerait ×1,69).
3. La liste des composants. Chacun : emoji, nom, et son réglage à droite. Stepper dans l'unité naturelle si l'item en a une, champ numérique en grammes sinon. Un champ grammes reste accessible dans les deux cas.
4. Un bouton « Ajouter un ingrédient » qui ouvre le catalogue filtré sur `side`, et un swipe pour retirer un composant.
5. Pour une ligne **simple**, le même écran sans les sections 2 et 4 : juste la quantité.

- [ ] **Step 2: Supprimer l'ancien catalogue**

C'est la dernière task à référencer `Dish` et `Extra`. Vérifier :

Run: `grep -rn "Dish\b\|Extra\b\|dishes()\|extras()" App NivelCore/Sources NivelTests`
Expected: aucun résultat hors commentaires historiques. Alors seulement supprimer les deux JSON et les deux types.

- [ ] **Step 3: Vérifier**

Run: `cd NivelCore && swift test` puis la suite app.

Dans le simulateur : ajouter une salade, ouvrir son détail, taper Copieux, vérifier que les six quantités montent et que le total du panier suit ; retirer les croûtons ; repasser en Normal et vérifier qu'on retombe exactement sur la composition par défaut moins les croûtons.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat(repas): écran de détail d'une ligne, suppression de Dish et Extra"
```

---

### Task 7 : Les kcal manuelles et la règle du tilde

**Files:**
- Modify: `App/Views/Meals/MealLogSheet.swift` (barre basse)
- Modify: `NivelTests/MealLoggingTests.swift`

- [ ] **Step 1: La barre basse**

À gauche, « Estimation » et le montant. Le montant est **tappable** et ouvre un champ numérique. Ajouter une affordance visible plutôt qu'un texte nu : un petit crayon à côté du montant, sinon personne ne devinera que c'est éditable.

Règle d'affichage, la même partout dans l'app :

```swift
/// « ~ 635 kcal » quand l'app a estimé, « 635 kcal » quand l'utilisateur a saisi.
/// Le tilde est une promesse d'honnêteté depuis la v1 : il ne doit pas mentir dans
/// l'autre sens non plus en restant là sur un chiffre certain.
MealFormatting.frKcal(_ kcal: Int, isManual: Bool) -> String
```

Dans un nouveau `NivelCore/Sources/NivelCore/MealFormatting.swift`, pas dans `MealEstimator` : estimer et mettre en forme sont deux métiers, et `frSummary` de la Task 8 viendra le rejoindre. Utilisé par la feuille ET par le journal, pour que la règle ne puisse pas diverger entre les deux écrans.

Quand la saisie manuelle est active : un bouton « revenir à l'estimation » qui remet `manualKcal` à nil.

- [ ] **Step 2: Tests**

```swift
    func testRegleDuTilde() {
        XCTAssertEqual(MealFormatting.frKcal(635, isManual: false), "~ 635 kcal")
        XCTAssertEqual(MealFormatting.frKcal(635, isManual: true), "635 kcal")
        XCTAssertEqual(MealFormatting.frKcal(1250, isManual: false), "~ 1 250 kcal")
    }
```

Le séparateur de milliers vient de `frFormatted`, déjà utilisé partout.

- [ ] **Step 3: Vérifier et committer**

```bash
git add -A
git commit -m "feat(repas): kcal saisies à la main, le tilde disparaît"
```

---

### Task 8 : Le journal

**Files:**
- Modify: `App/Views/Meals/MealsJournalView.swift`

- [ ] **Step 1: Le résumé de ligne**

`subtitle(for:)` ne parle plus de portion ni d'extras. Nouvelle règle, en fonction pure et testée :

```swift
/// « Salade composée », « Salade composée +2 », « Repas » si aucune ligne.
MealFormatting.frSummary(lines: [MealLine], catalog: FoodCatalog) -> String
```

L'emoji de la ligne principale remplace celui du plat. Les kcal suivent `frKcal(_:isManual:)`.

- [ ] **Step 2: Tests**

Un, deux et quatre lignes ; zéro ligne (le repas d'avant la migration) ; une ligne dont l'item n'existe plus au catalogue.

- [ ] **Step 3: Vérifier et committer**

```bash
git add -A
git commit -m "feat(repas): résumé des lignes dans le journal"
```

---

### Task 9 : Version, documentation, vérifications

**Files:**
- Modify: `project.yml`, `README.md`

- [ ] **Step 1: Version 1.10, build 11**, sur les **deux** cibles, sinon XcodeGen retombe sur 1.0/1 pour l'extension (leçon v1.6). La version atterrit dans `App/Info.plist` et `Widgets/Info.plist`, pas dans le `pbxproj`.

- [ ] **Step 2: README** : badges de version et de tests aux comptes réels.

- [ ] **Step 3: Vérifications transverses**

```sh
grep -rn "dishID\|portionRaw\|MealEstimator.estimate\|Dish\b\|Extra\b" App NivelCore/Sources Widgets NivelTests
grep -rn '"[^"]*—[^"]*"' App/Views NivelCore/Sources
```
Expected : rien dans les deux cas.

- [ ] **Step 4: Les deux suites en entier**, comptes reportés dans le README.

- [ ] **Step 5: Commit**

```bash
git add project.yml README.md App/Info.plist Widgets/Info.plist
git commit -m "chore: version 1.10 (build 11)"
```

---

## Vérification sur les téléphones (par Michaël, après merge)

Reprise du §10 de la spec.

- [ ] Le store s'ouvre : poids, pas, XP, badges et quêtes intacts. Seul le repas d'avant perd son détail.
- [ ] Logger une bière seule, sans plat.
- [ ] Logger un paquet de chips à 16 h.
- [ ] Détailler une salade : retirer les croûtons, passer le thon en poulet, le total suit.
- [ ] Saisir des kcal à la main : le tilde disparaît dans la feuille ET dans le journal.
- [ ] Le rendu du panier et de l'écran de détail sur le plus petit des deux iPhones.
