// NivelTests/MealLogSheetDismissTests.swift
// Garde de fermeture de la feuille de repas (spec v1.14 §3.6) : un panier garni
// ne se jette pas d'un glissement. Même approche qu'ActivityLogSheetTests : la
// décision est une fonction pure statique sur la vue, la vue ne fait que
// l'appliquer.

import XCTest
import NivelCore
@testable import Nivel

final class MealLogSheetDismissTests: XCTestCase {
    /// Rien à perdre : la feuille se referme d'un glissement, sans un mot.
    func testPanierVideSeFermeSansRienDemander() {
        XCTAssertFalse(MealLogSheet.guardsDismissal(lines: []))
    }

    /// Le vrai cas du défaut : une ligne au panier suffit à armer le garde.
    func testPanierGarniDemandeAvantDeFermer() {
        let line = MealLine.simple(MealComponent(itemID: "beer_half", grams: 500))
        XCTAssertTrue(MealLogSheet.guardsDismissal(lines: [line]))
    }

    /// Un panier composé garde le garde : la règle porte sur « il y a du contenu »,
    /// pas sur la forme des lignes.
    func testPanierComposeGardeAussiLeGarde() throws {
        let catalog = try FoodCatalog.load()
        let item = try XCTUnwrap(catalog.byID["tacos"])
        let line = catalog.line(for: item)
        XCTAssertTrue(line.isComposed)
        XCTAssertTrue(MealLogSheet.guardsDismissal(lines: [line]))
    }
}
