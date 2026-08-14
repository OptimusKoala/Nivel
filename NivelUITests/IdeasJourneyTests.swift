// NivelUITests/IdeasJourneyTests.swift
// Le CÂBLAGE de la bande d'idées de saison (spec v1.14 §6.4 et §6.5), de la carte
// jusqu'au journal.
//
// Pourquoi un test d'INTERFACE et non un test unitaire : tout ce que la bande décide
// est déjà tenu par `NivelTests/RecipeStripTests`, en fonctions pures. Ce qui reste,
// c'est ce que la vue leur donne — et là, aucune assertion de logique ne mord. Les
// trois mutations que voici ont été essayées, et les 188 tests unitaires sont restés
// verts pour chacune ; chacun des trois tests ci-dessous en attrape une :
//
// - `slot: framing.slot` remplacé par `slot: .lunch` : le `Mirror` de
//   `RecipeStripTests` prouve que l'init de `MealLogSheet` range ce qu'on lui donne,
//   jamais que le journal lui donne le bon créneau. L'app annoncerait « Idées pour ce
//   soir » et pré-sélectionnerait « Déjeuner » ;
// - `pantry: pantry` remplacé par `pantry: []` : `frPantryState` est éprouvée des deux
//   côtés, mais rien ne dit que la vue passe le frigo du profil au moteur ;
// - `isToday: isToday` remplacé par `isToday: true` : la bande resterait sur les jours
//   passés, qui sont en lecture seule depuis la v1.
//
// Ces trois tests font donc le trajet sur la vraie app, et c'est leur seule raison
// d'être : ils ne rejouent aucune règle déjà écrite ailleurs.
//
// Dans NivelUITests et donc HORS du schéma quotidien, comme BasketSwipeTests et les
// tours vidéo : chaque geste XCUITest coûte ~2,5 s. Lancé à la main :
//
//   xcodebuild -project Nivel.xcodeproj -scheme NivelPreview \
//     -destination 'platform=iOS Simulator,name=iPhone 17' \
//     -only-testing:NivelUITests/IdeasJourneyTests test

import XCTest

final class IdeasJourneyTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// L'app en mode captures, ouverte sur l'onglet Repas. Le profil de démonstration
    /// a un frigo VIDE (`ScreenshotMode.seed`) : c'est l'état de départ des deux tests,
    /// et l'un d'eux le garnit.
    private func launchOnMealsTab() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--nivel-screenshots", "-nivelScreen", "meals", "-nivel.theme", "creme"]
        app.launch()
        return app
    }

    // MARK: Le créneau, du titre de la bande jusqu'à la feuille de saisie

    /// Le trajet entier : la bande annonce un créneau, on tape une carte, la fiche
    /// s'ouvre, « Noter ce repas » ouvre le panier PRÉ-REMPLI SUR CE MÊME CRÉNEAU, et
    /// le repas validé apparaît dans le journal sous le nom de la recette.
    ///
    /// L'attendu est calculé sur l'HEURE COURANTE, avec la règle de la spec §6.4
    /// (bascule à 15 h) recopiée ici : une cible d'interface ne peut pas importer le
    /// code de l'app, et c'est tant mieux — le test croit la spec, pas
    /// `RecipeStrip.targetSlot`, qu'il aurait sinon comparée à elle-même.
    func testLeCreneauDeLaBandeEstCeluiQueLaFeuilleDeSaisiePreSelectionne() {
        let app = launchOnMealsTab()
        let hour = Calendar.current.component(.hour, from: Date())
        let expectedMoment = hour < 15 ? "ce midi" : "ce soir"
        let expectedSlot = hour < 15 ? "Déjeuner" : "Dîner"

        // 1. Le titre de la bande, c'est-à-dire le créneau qu'elle VISE.
        let stripTitle = app.staticTexts.matching(labelContains("Idées pour \(expectedMoment)")).firstMatch
        XCTAssertTrue(stripTitle.waitForExistence(timeout: 30),
                      "la bande n'annonce pas « Idées pour \(expectedMoment) »")

        // 2. La première carte. Reconnue à « , environ » : c'est la forme de
        //    `frCardLabel` et de rien d'autre dans cet écran.
        let card = app.buttons.matching(labelContains(", environ ")).firstMatch
        XCTAssertTrue(card.exists, "aucune carte d'idée dans la bande")
        let recipeName = String(card.label.prefix(while: { $0 != "," }))
        // Le total du jour, relevé AVANT : c'est lui qui dira, à la fin, que le repas
        // a bien été enregistré ET que le journal s'est rechargé.
        let total = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '/' AND label CONTAINS 'kcal'")
        ).firstMatch
        let totalBefore = total.label
        card.tap()

        // 3. La fiche recette, puis le retour au journal qui présente la saisie.
        let logButton = app.buttons["Noter ce repas"]
        XCTAssertTrue(logButton.waitForExistence(timeout: 5), "la fiche recette ne s'est pas ouverte")
        logButton.tap()

        // 4. LE point du test : le créneau pré-sélectionné est celui que la bande
        //    annonçait, et le panier arrive garni de la recette.
        let chip = app.buttons["Créneau \(expectedSlot)"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "la feuille de saisie ne s'est pas ouverte")
        XCTAssertTrue(chip.isSelected,
                      "la bande visait \(expectedSlot) et la feuille a pré-sélectionné autre chose")
        XCTAssertTrue(app.buttons.matching(labelContains(recipeName)).firstMatch.exists,
                      "le panier n'a pas été pré-rempli de « \(recipeName) »")

        // 5. Le bout de la chaîne : validé, le repas compte dans le total du jour —
        //    c'est le `onDismiss: reloadDayMeals` de la feuille de saisie qui le fait,
        //    et lui seul. Le total plutôt que la ligne du journal : la carte de la
        //    bande porte le même nom que la ligne, et une assertion sur ce nom serait
        //    verte sans que rien n'ait été enregistré.
        app.buttons.matching(labelContains("Valider")).firstMatch.tap()
        XCTAssertTrue(waitUntil { total.exists && total.label != totalBefore },
                      "le repas validé n'a pas bougé le total du jour (\(totalBefore))")
    }

    // MARK: Les jours passés

    /// Un jour passé n'a pas de bande : les jours antérieurs sont en lecture seule
    /// depuis la v1 (§4.2), une idée de dîner pour hier serait un mensonge. Le `nil`
    /// de `framing(at:isToday:)` est éprouvé à l'unité ; ce qui ne l'est pas, c'est
    /// que le journal lui passe son VRAI `isToday` — un `if true` glissé là passerait
    /// toute la suite unitaire.
    ///
    /// Le chevron est interrogé par son identifiant (`chevron.left`) et non par son
    /// libellé : celui-ci vient du symbole système (« Retour »), et il changerait de
    /// langue avec le simulateur.
    func testUnJourPasseNAffichePasLaBande() {
        let app = launchOnMealsTab()
        let stripTitle = app.staticTexts.matching(labelContains("Idées pour ")).firstMatch
        XCTAssertTrue(stripTitle.waitForExistence(timeout: 30), "la bande manque à aujourd'hui")

        app.buttons["chevron.left"].tap()

        XCTAssertTrue(app.staticTexts["Hier"].waitForExistence(timeout: 5),
                      "le chevron n'a pas ramené la veille")
        XCTAssertTrue(waitForDisappearance(of: stripTitle),
                      "la bande d'idées est restée sur un jour passé")
    }

    // MARK: Le frigo, vide puis garni puis vidé

    /// Ce que le frigo change à la bande, dans les deux sens. Frigo vide, les cartes
    /// SE TAISENT sur ce qui manque (elles compteraient ce qu'elles ignorent) et la
    /// carte d'invitation 🧺 ferme la bande ; frigo garni, c'est l'inverse, exactement.
    ///
    /// Les deux états sont donc EXCLUSIFS, et le test le vérifie aux trois moments :
    /// une capture prise à la main pendant la revue les montrait ensemble, ce qui ne
    /// pouvait être qu'une image de transition — en voici la preuve, ou son démenti.
    ///
    /// L'assertion du milieu ne porte pas sur un COMPTE de manquants : les cartes
    /// incomplètes passent par une rotation qui dépend du jour de l'année, et un test
    /// qui les nommerait serait vert aujourd'hui et rouge demain. Elle porte sur une
    /// recette COMPLÈTE, que le moteur promet de proposer tous les jours sans jamais
    /// la faire tourner — et « Poisson vapeur et riz » est de toutes les saisons et
    /// des deux créneaux, donc de toutes les heures auxquelles cette suite tournera.
    func testLeFrigoChangeCeQueLaBandeDit() {
        let app = launchOnMealsTab()

        // 1. Frigo vide : la carte d'invitation, et pas un mot sur ce qui manque.
        let invitation = app.buttons.matching(labelContains("Dis-moi ce que tu as")).firstMatch
        XCTAssertTrue(invitation.waitForExistence(timeout: 30), "la carte 🧺 manque à la bande")
        XCTAssertEqual(pantryStateCards(app).count, 0,
                       "une carte parle du frigo alors qu'il est vide")

        // 2. On coche les QUATRE ingrédients de « Poisson vapeur et riz ».
        app.buttons["Mon frigo"].tap()
        for ingredient in ["Riz cuit", "Légumes verts", "Poisson", "Huile d'olive"] {
            check(ingredient, in: app)
        }
        app.buttons["Fermer"].tap()

        // 3. Frigo garni : la recette dont on a tout est là, et elle le DIT.
        let complete = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Poisson vapeur et riz' AND label CONTAINS 'Tu as tout'")
        ).firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: 5),
                      "la bande n'a pas tenu compte des ingrédients cochés")
        XCTAssertTrue(waitForDisappearance(of: invitation),
                      "la carte 🧺 est restée alors que le frigo est garni")

        // 4. Vidé : on revient à l'état de départ, et surtout les deux états ne se
        //    chevauchent pas une fois l'écran posé.
        app.buttons["Mon frigo"].tap()
        app.buttons["Vider le frigo"].tap()
        app.buttons["Vider"].tap()
        app.buttons["Fermer"].tap()

        XCTAssertTrue(app.buttons.matching(labelContains("Dis-moi ce que tu as")).firstMatch
                        .waitForExistence(timeout: 5),
                      "la carte 🧺 n'est pas revenue après un frigo vidé")
        XCTAssertTrue(waitUntil { pantryStateCards(app).count == 0 },
                      "une carte parle encore du frigo après « Vider »")
    }

    // MARK: Outillage

    /// Coche un ingrédient du frigo. Les 58 ingrédients sont dans un `ScrollView` qui
    /// les rend TOUS (ils existent donc tous dans la hiérarchie, y compris hors
    /// écran) : c'est l'atteignabilité qu'il faut obtenir, et elle se gagne au
    /// glissement. Le geste part du bas de l'écran, loin de la poignée de la feuille
    /// — un glissement vers le haut posé trop haut la referme au lieu de dérouler.
    private func check(_ name: String, in app: XCUIApplication) {
        let row = app.buttons[name]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "ingrédient « \(name) » introuvable")
        var scrolls = 0
        while !row.isHittable && scrolls < 5 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
                .press(forDuration: 0.05,
                       thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
            scrolls += 1
        }
        XCTAssertTrue(row.isHittable, "ingrédient « \(name) » hors d'atteinte")
        row.tap()
    }

    /// Les cartes qui disent quelque chose du frigo. Un PRÉDICAT et non un libellé
    /// exact : il doit attraper « Il manque 3 » comme « Tu as tout ✓ », les deux
    /// moitiés de `frPantryState`.
    private func pantryStateCards(_ app: XCUIApplication) -> [XCUIElement] {
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Il manque' OR label CONTAINS 'Tu as tout'"))
            .allElementsBoundByIndex
    }

    private func labelContains(_ text: String) -> NSPredicate {
        NSPredicate(format: "label CONTAINS %@", text)
    }

    /// Attente ACTIVE d'une condition composée : `expectation(for:)` ne sait interroger
    /// qu'un élément, et deux des assertions ci-dessus portent sur un COMPTE.
    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return condition()
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        waitUntil(timeout: timeout) { !element.exists }
    }
}
