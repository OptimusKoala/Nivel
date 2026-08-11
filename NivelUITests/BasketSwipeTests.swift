// NivelUITests/BasketSwipeTests.swift
// Non-régression du swipe de suppression du panier « Ton repas » (spec v1.13 §7).
//
// Pourquoi un test d'INTERFACE et non un test unitaire : le défaut corrigé était une
// affaire de PRIORITÉ DE GESTES entre un parent et son `Button` enfant. Aucun test de
// logique pure ne pouvait l'attraper — le code était juste, il ne recevait rien. Seul
// un vrai geste sur un vrai rendu le prouve.
//
// Les deux moitiés du contrat sont testées ensemble, parce qu'elles s'opposent :
// `highPriorityGesture` doit gagner sur le drag, et perdre sur le tap.
//
// Dans NivelUITests et donc HORS du schéma quotidien, comme les tours vidéo : chaque
// geste XCUITest coûte ~2,5 s. Lancé à la main (voir README) :
//
//   xcodebuild -project Nivel.xcodeproj -scheme NivelPreview \
//     -destination 'platform=iOS Simulator,name=iPhone 17' \
//     -only-testing:NivelUITests/BasketSwipeTests test

import XCTest

final class BasketSwipeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// L'app en mode captures s'ouvre directement sur la feuille de repas, panier
    /// pré-rempli de deux lignes (`ScreenshotMode.demoMealLines`).
    private func launchOnMealSheet() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--nivel-screenshots", "-nivelScreen", "meallog", "-nivel.theme", "creme"]
        app.launch()
        return app
    }

    /// La ligne « Salade composée » DU PANIER. Le catalogue plus bas contient une carte
    /// du même nom : seule la ligne du panier porte « ingrédients » dans son libellé.
    private func basketRow(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'ingrédients'")).firstMatch
    }

    /// La corbeille de la PREMIÈRE ligne. Deux précautions, apprises en écrivant ce
    /// test :
    ///
    /// - `boundBy: 0` et non `["Retirer"]` : il y a une corbeille par ligne du panier,
    ///   et une requête ambiguë échoue au `tap()`.
    /// - c'est `isHittable`, jamais `exists`, qui dit si elle est révélée : la corbeille
    ///   est TOUJOURS dans la hiérarchie, posée derrière la ligne dans un `ZStack`.
    ///   `exists` est donc vrai même au repos.
    private func removeButton(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(identifier: "Retirer").element(boundBy: 0)
    }

    /// Glissement LENT vers la gauche : un `swipeLeft()` sec peut franchir le seuil sans
    /// que le geste soit suivi comme un drag continu, ce qui ne prouverait rien.
    private func swipeRowLeft(_ row: XCUIElement) {
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
            .press(forDuration: 0.1,
                   thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)),
                   withVelocity: .slow,
                   thenHoldForDuration: 0.3)
    }

    // MARK: Le geste réparé

    /// Le cœur de la régression, énoncé par ses DEUX faces : la ligne doit glisser, et
    /// surtout la page de détail ne doit PAS s'ouvrir — c'était très exactement le bug
    /// de la v1.10 à la v1.12, où le `Button` de la ligne captait le glissement.
    ///
    /// L'assertion porte sur la POSITION de la ligne et non sur l'atteignabilité de la
    /// corbeille : celle-ci est posée derrière la ligne dans un `ZStack`, et XCUITest la
    /// considère atteignable même au repos. Le déplacement, lui, ne trompe pas.
    func testSwipingLeftSlidesTheRowInsteadOfOpeningIt() {
        let app = launchOnMealSheet()
        let row = basketRow(app)
        XCTAssertTrue(row.waitForExistence(timeout: 30), "ligne du panier absente")
        let originBefore = row.frame.minX

        swipeRowLeft(row)

        // 84 pt de découvert au repos : on exige au moins la moitié du chemin.
        XCTAssertLessThan(basketRow(app).frame.minX, originBefore - 42,
                          "la ligne n'a pas glissé vers la gauche")
        // La régression elle-même : « Copieux » est une puce de portion, donc la preuve
        // que le détail de la ligne s'est ouvert.
        XCTAssertFalse(app.buttons["Copieux"].exists,
                       "le glissement a ouvert le détail au lieu de faire glisser la ligne")
    }

    func testTappingTheRemoveButtonDeletesTheLine() {
        let app = launchOnMealSheet()
        let row = basketRow(app)
        XCTAssertTrue(row.waitForExistence(timeout: 30), "ligne du panier absente")

        swipeRowLeft(row)
        let remove = removeButton(app)
        XCTAssertTrue(waitUntilHittable(remove), "la corbeille n'a pas été révélée")
        remove.tap()

        // La ligne composée disparaît ; la seconde ligne du panier reste. On la cherche
        // par « 1 fruit », son sous-titre de quantité : le catalogue plus bas contient
        // aussi une carte « Fruit », mais elle n'affiche jamais de quantité.
        XCTAssertTrue(waitForDisappearance(of: row), "la ligne n'a pas été retirée")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS '1 fruit'"))
                        .firstMatch.exists, "la seconde ligne ne devait pas partir")
    }

    // MARK: L'autre moitié du contrat

    /// `minimumDistance: 12` est ce qui rend l'inversion de priorité sans danger : un
    /// tap SANS mouvement doit continuer d'atteindre le bouton de la ligne et d'ouvrir
    /// son détail. Sans ce test, « réparer » le swipe pourrait casser l'édition.
    func testTappingARowStillOpensItsDetail() {
        let app = launchOnMealSheet()
        let row = basketRow(app)
        XCTAssertTrue(row.waitForExistence(timeout: 30), "ligne du panier absente")

        row.tap()

        // La page de détail d'une salade composée : ses puces de portion.
        XCTAssertTrue(app.buttons["Copieux"].waitForExistence(timeout: 3),
                      "le tap n'a pas ouvert le détail de la ligne")
    }

    // MARK: Outillage

    /// `waitForExistence` ne convient pas : la corbeille existe déjà (voir `removeButton`).
    /// C'est son ATTEIGNABILITÉ qu'il faut attendre, et elle n'a pas de prédicat tout fait.
    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.isHittable { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return element.isHittable
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return !element.exists
    }
}
