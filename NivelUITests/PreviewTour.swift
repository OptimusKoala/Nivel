// NivelUITests/PreviewTour.swift
//
// Visites guidées de l'app, filmées pour les aperçus App Store (scripts/preview.sh).
// Ce ne sont PAS des tests : rien n'est vérifié, on promène l'app à un rythme lisible
// pendant que `simctl io recordVideo` enregistre l'écran.
//
// DEUX visites, et non une seule, parce qu'un aperçu Apple dure au maximum 30 s : chaque
// geste XCUITest coûte ~2,5 s (interrogation de la hiérarchie d'accessibilité), donc une
// visite complète en dépassait 55. Apple autorise trois aperçus par taille d'écran ;
// deux récits courts valent mieux qu'un seul tronqué.
//
//   testTourRepas  — noter un repas, le geste central
//   testTourSport  — la séance guidée, puis les progrès et les quêtes
//
// Chaque geste est JOURNALISÉ avec son instant (préfixe « TOUR: ») et aucun échec
// n'interrompt le tournage : un libellé qui a bougé se lit dans le journal, au lieu de
// laisser une vidéo inexplicablement figée.
//
// L'app tourne en mode captures : profil de démonstration en mémoire, jamais de vraies
// données (App/Support/ScreenshotSupport.swift).

import XCTest

final class PreviewTour: XCTestCase {
    private var started: TimeInterval = 0

    override func setUp() {
        continueAfterFailure = true
    }

    // MARK: - Aperçu 1 : noter un repas

    func testTourRepas() {
        let app = launch()
        pause(3.0)                                   // l'accueil, posément

        // Correspondance PARTIELLE et non exacte : depuis la v1.13 le bouton est une
        // carte dont le libellé d'accessibilité combine titre et sous-titre
        // (« Noter un repas, ce que tu viens de manger »).
        tap(app.buttons.matching(labelContains("Noter un repas")).firstMatch, "bouton noter un repas")
        pause(0.8)
        // Le créneau est pré-rempli d'après l'heure ; « Déjeuner » a le catalogue de
        // plats le plus parlant.
        //
        // Correspondance PARTIELLE, pour la même raison qu'au bouton précédent : depuis
        // la 1.14 la pastille porte un libellé d'accessibilité préfixé (« Créneau
        // Déjeuner »), parce que « Encas » désigne à la fois un créneau et une catégorie
        // dans cette feuille. Une égalité de libellé décrochait ici en silence.
        tap(app.buttons.matching(labelContains("Déjeuner")).firstMatch, "créneau Déjeuner")
        pause(0.6)
        tap(app.buttons.matching(labelContains("Salade composée")).firstMatch, "plat Salade composée")
        pause(0.8)
        tap(app.buttons.matching(labelContains("Riz / féculents")).firstMatch, "plat Riz")
        pause(1.6)                                   // l'estimation se met à jour
        tap(app.buttons.matching(labelContains("Valider")).firstMatch, "validation du repas")
        // Fin volontairement longue : c'est là que l'anneau se réévalue et que Nivelito
        // félicite. Cette visite doit aussi rester au-dessus des 15 s exigées.
        pause(4.2)

        finish()
    }

    // MARK: - Aperçu 2 : bouger, puis voir ses progrès

    func testTourSport() {
        let app = launch()
        pause(1.4)

        tap(app.buttons.matching(labelContains("SÉANCE DU JOUR")).firstMatch, "carte séance du jour")
        pause(1.6)                                   // grande illustration de Nivelito
        tap(app.buttons["C'est parti !"], "bouton C'est parti")
        pause(1.2)                                   // page d'étape : consignes, tempo
        tap(app.buttons.matching(labelContains("Lancer le timer")).firstMatch, "lancement du minuteur")
        pause(2.4)                                   // l'anneau se remplit
        dismissSheet(app)
        pause(0.8)

        tap(app.tabBars.buttons["Progrès"], "onglet Progrès")
        pause(1.4)                                   // poids, calories, pas
        tap(app.tabBars.buttons["Quêtes"], "onglet Quêtes")
        pause(1.0)
        app.swipeUp()
        pause(1.8)                                   // la grille de badges

        finish()
    }

    // MARK: - Cadre commun

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--nivel-screenshots", "-nivelScreen", "home", "-nivel.theme", "creme"]
        app.launch()

        // Repère de synchronisation : le script de tournage retranche l'attente de
        // lancement (installation, démarrage) en comparant cet instant à celui de la
        // première image filmée. Sans lui, l'aperçu commencerait par l'écran d'accueil iOS.
        _ = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Salut'"))
            .firstMatch.waitForExistence(timeout: 30)
        started = Date().timeIntervalSince1970
        print("TOUR: START \(started)")
        return app
    }

    private func finish() {
        print("TOUR: END \(Date().timeIntervalSince1970)")
    }

    private func labelContains(_ text: String) -> NSPredicate {
        NSPredicate(format: "label CONTAINS %@", text)
    }

    private func tap(_ element: XCUIElement, _ what: String) {
        guard element.waitForExistence(timeout: 4) else { return log("MANQUÉ (absent) \(what)") }
        guard element.isHittable else { return log("MANQUÉ (masqué) \(what)") }
        element.tap()
        log("tap \(what)")
    }

    /// Fermeture d'une feuille par glissement du haut vers le bas. Un `swipeDown()` sur
    /// l'application ferait défiler le contenu de la feuille au lieu de la refermer.
    private func dismissSheet(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06))
            .press(forDuration: 0.05,
                   thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        log("fermeture de la feuille")
    }

    /// `Thread.sleep` et non une attente d'élément : on veut un rythme constant à
    /// l'image, pas la fin la plus rapide possible.
    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// L'instant relatif au départ de la visite : c'est lui qui dit où part le temps
    /// quand une visite dépasse les 30 s permises.
    private func log(_ message: String) {
        print(String(format: "TOUR: %5.1fs %@", Date().timeIntervalSince1970 - started, message))
    }
}
