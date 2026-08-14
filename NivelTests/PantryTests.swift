// NivelTests/PantryTests.swift
// Le frigo (spec v1.14 §6.3) : une liste d'ids d'ingrédients sur le profil, cochée
// à la main, qui servira de clé de classement aux idées de repas.
import XCTest
import SwiftData
import NivelCore
@testable import Nivel

@MainActor
final class PantryTests: XCTestCase {
    /// Le container est retenu par le cas de test, pas par une locale (même raison
    /// que ReminderSettingsTests : SwiftData ne le retient pas depuis son mainContext).
    private var container: ModelContainer!

    private static let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                                        DayLog.self, GamificationState.self, ActivityEntry.self])

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Self.schema,
            configurations: [ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: true)]
        )
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    /// Profil INSÉRÉ dans un contexte en mémoire, comme le fait le reste de la suite
    /// (cf. WidgetSyncTests) : muter un modèle SwiftData détaché ne prouve rien de ce
    /// qui se passe à l'usage.
    private func makeProfile() -> UserProfile {
        let profile = UserProfile(name: "Marion", sex: .female,
                                  birthDate: Date(timeIntervalSince1970: 0),
                                  heightCm: 165, initialWeightKg: 70,
                                  activity: .light, dailyCalorieTarget: 1700)
        container.mainContext.insert(profile)
        return profile
    }

    /// CE QUE CE TEST NE COUVRE PAS : la règle de mutation elle-même. `Pantry` réassigne
    /// le tableau entier à chaque coche plutôt que de le muter en place, et aucune
    /// assertion écrite ici ne peut faire la différence — les deux chemins laissent le
    /// MÊME tableau derrière eux. La piste de la « sauvegarde effective » a été essayée
    /// et jetée : un test temporaire faisant `profile.pantryItemIDs.append(...)` puis
    /// `save()` et une relecture depuis un autre `ModelContext` passe exactement comme
    /// la version qui réassigne — l'accesseur généré par `@Model` intercepte les deux.
    /// Le nom dit donc ce que le corps éprouve — coche, décoche, pas de doublon — et la
    /// règle de réassignation reste tenue par la relecture du code, pas par cette suite.
    /// (Le plan appelait ce test `testTogglingAnIngredientReassignsTheWholeArray` :
    /// renommé, ce nom promettait un mécanisme qu'aucune de ses assertions n'éprouve.)
    func testCocherPuisDecocherUnIngredient() throws {
        let profile = makeProfile()
        XCTAssertTrue(profile.pantryItemIDs.isEmpty)

        Pantry.toggle("tomato", on: profile)
        XCTAssertEqual(profile.pantryItemIDs, ["tomato"])

        Pantry.toggle("egg", on: profile)
        XCTAssertEqual(Set(profile.pantryItemIDs), ["tomato", "egg"])

        Pantry.toggle("tomato", on: profile)
        XCTAssertEqual(profile.pantryItemIDs, ["egg"])
    }

    /// Pas de doublon possible, même sur une longue série de coches — `toggle` est le
    /// seul chemin d'écriture, c'est donc lui, et lui seul, qui doit tenir l'invariant.
    func testPasDeDoublon() throws {
        let profile = makeProfile()
        for id in ["tomato", "egg", "tomato", "cream", "egg", "tomato"] {
            Pantry.toggle(id, on: profile)
        }
        XCTAssertEqual(profile.pantryItemIDs.count, Set(profile.pantryItemIDs).count)
        // tomato coché, décoché, recoché ; egg coché puis décoché ; cream coché.
        XCTAssertEqual(Set(profile.pantryItemIDs), ["tomato", "cream"])
    }

    /// « Vider » vide, et ne laisse pas une liste à moitié pleine.
    func testViderLeFrigo() throws {
        let profile = makeProfile()
        Pantry.toggle("tomato", on: profile)
        Pantry.toggle("egg", on: profile)
        Pantry.clear(on: profile)
        XCTAssertTrue(profile.pantryItemIDs.isEmpty)
    }

    /// Le frigo est une donnée persistée, pas un état d'écran : il doit se retrouver
    /// après sauvegarde, relu depuis un AUTRE contexte du même container — donc depuis
    /// le store, et non depuis l'objet qu'on vient de muter.
    func testLeFrigoSurvitALaSauvegarde() throws {
        let profile = makeProfile()
        Pantry.toggle("tomato", on: profile)
        Pantry.toggle("egg", on: profile)
        try container.mainContext.save()

        let autreContexte = ModelContext(container)
        let relu = try XCTUnwrap(try autreContexte.fetch(FetchDescriptor<UserProfile>()).first)
        XCTAssertEqual(Set(relu.pantryItemIDs), ["tomato", "egg"])
    }

    /// Un profil d'avant la 1.14 n'a pas de frigo : le défaut vit sur la DÉCLARATION
    /// (migration légère SwiftData), et l'`init` ne prend pas ce paramètre. Un profil
    /// tout neuf part donc du même endroit qu'un profil migré : la liste vide.
    func testFrigoVideParDefaut() throws {
        let profile = makeProfile()
        XCTAssertEqual(profile.pantryItemIDs, [])
    }

    // MARK: L'écran

    /// LA MOITIÉ MANQUANTE d'un contrat déjà à demi tenu : `RecipeCatalogTests`
    /// (NivelCore) exige que chaque ingrédient de recette soit un `.side` parce que le
    /// frigo ne liste que ceux-là, et cite `PantryView` nommément. Rien, jusqu'ici, ne
    /// vérifiait l'autre bout. Un `.dish` ou un `.drink` glissé dans cette liste rendrait
    /// la couverture complète inatteignable pour la bande d'idées, sans un test rouge.
    func testLeFrigoNeListeQueDesIngredients() throws {
        let catalog = try FoodCatalog.load()
        let ingredients = PantryContent.ingredients(in: catalog)
        XCTAssertEqual(ingredients.count, 58)
        XCTAssertTrue(ingredients.allSatisfy { $0.category == .side })
        // Les recettes de la 1.14 ne sont pas des ingrédients : elles ont leur bande.
        XCTAssertTrue(ingredients.allSatisfy { !$0.isRecipe })
    }

    /// Le compteur ne compte QUE des ids que le catalogue connaît encore : un aliment
    /// retiré de `foods.json` laisserait sinon « 1 ingrédient coché » sans la moindre
    /// coche à l'écran, et un « Vider » actif qui ne vide rien de visible.
    func testLesIdsInconnusNeSontPasComptes() throws {
        let ingredients = PantryContent.ingredients(in: try FoodCatalog.load())
        XCTAssertEqual(PantryContent.knownIDs(["tomato", "fantome", "egg"], in: ingredients),
                       ["tomato", "egg"])
    }

    /// Catalogue illisible (repli `.empty`) : on ne déclare pas tout le frigo fantôme.
    /// C'est le même garde qui empêche le nettoyage à l'ouverture de vider un frigo
    /// réel parce qu'un JSON n'a pas pu être lu.
    func testCatalogueIllisibleNeVidePasLeFrigo() throws {
        XCTAssertEqual(PantryContent.knownIDs(["tomato", "egg"], in: []), ["tomato", "egg"])
    }

    /// Les trois branches du compteur, singulier compris.
    func testLibelleDuCompteur() throws {
        XCTAssertEqual(PantryContent.countLabel(0), "Rien de coché pour l'instant.")
        XCTAssertEqual(PantryContent.countLabel(1), "1 ingrédient coché.")
        XCTAssertEqual(PantryContent.countLabel(7), "7 ingrédients cochés.")
    }
}
