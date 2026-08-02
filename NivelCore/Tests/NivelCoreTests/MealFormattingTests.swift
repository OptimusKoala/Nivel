// NivelCore/Tests/NivelCoreTests/MealFormattingTests.swift
// Règle du tilde (spec v1.10 §5.5) et résumé de repas (spec §6), pures et testées
// ici pour que la feuille de log et le journal ne puissent jamais diverger.
import XCTest
@testable import NivelCore

final class MealFormattingTests: XCTestCase {
    // MARK: frKcal

    /// « ~ 635 kcal » quand l'app a estimé, « 635 kcal » sans tilde quand
    /// l'utilisateur a saisi lui-même le chiffre : le tilde ne doit jamais rester
    /// affiché sur une valeur qu'on sait exacte.
    func testRegleDuTilde() {
        XCTAssertEqual(MealFormatting.frKcal(635, isManual: false), "~ 635 kcal")
        XCTAssertEqual(MealFormatting.frKcal(635, isManual: true), "635 kcal")
        // Séparateur de milliers français (espace fine insécable), identique à
        // Int.frFormatted côté app : la même règle ne doit pas diverger visuellement.
        XCTAssertEqual(MealFormatting.frKcal(1250, isManual: false), "~ 1\u{202F}250 kcal")
    }

    // MARK: frSummary

    private var catalog: FoodCatalog!

    override func setUpWithError() throws {
        catalog = try FoodCatalog.load()
    }

    func testRepasSansLigneAfficheRepas() {
        XCTAssertEqual(MealFormatting.frSummary(lines: [], catalog: catalog), "Repas")
    }

    func testUneLigneAfficheSonNomSeul() {
        let lines = [catalog.line(for: catalog.byID["toast"]!)]
        XCTAssertEqual(MealFormatting.frSummary(lines: lines, catalog: catalog), "Tartines")
    }

    func testDeuxLignesAjouteLeCompteurDesAutres() {
        let lines: [MealLine] = [
            catalog.line(for: catalog.byID["toast"]!),
            .simple(MealComponent(itemID: "beer_half", grams: 250)),
        ]
        XCTAssertEqual(MealFormatting.frSummary(lines: lines, catalog: catalog), "Tartines +1")
    }

    func testQuatreLignesComptentTroisAutres() {
        let lines: [MealLine] = [
            catalog.line(for: catalog.byID["toast"]!),
            .simple(MealComponent(itemID: "beer_half", grams: 250)),
            .simple(MealComponent(itemID: "coffee_milk", grams: 200)),
            .simple(MealComponent(itemID: "yogurt", grams: 125)),
        ]
        XCTAssertEqual(MealFormatting.frSummary(lines: lines, catalog: catalog), "Tartines +3")
    }

    /// Un item qui n'existe plus au catalogue (JSON corrompu, ou retiré depuis) ne
    /// doit ni planter, ni afficher son id technique brut à l'écran.
    func testItemInconnuAfficheUnNomGeneriqueSansCrash() {
        let lines: [MealLine] = [.simple(MealComponent(itemID: "fantome", grams: 100))]
        let summary = MealFormatting.frSummary(lines: lines, catalog: catalog)
        XCTAssertFalse(summary.contains("fantome"))
        XCTAssertFalse(summary.isEmpty)
    }
}
