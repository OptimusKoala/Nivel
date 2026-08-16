import XCTest
@testable import NivelCore

final class DuoFeedBuilderTests: XCTestCase {

    private func heure(_ h: Int, _ m: Int = 0) -> Date {
        Date(timeIntervalSince1970: TimeInterval(h * 3_600 + m * 60))
    }

    private func repas(_ id: String = "R1", a date: Date, slot: MealSlot = .lunch,
                       titre: String = "Salade de lentilles",
                       kcal: Int = 420, manuel: Bool = false) -> MealFeedInput {
        MealFeedInput(publicID: id, date: date, slot: slot, title: titre,
                      kcal: kcal, isManual: manuel)
    }

    private func activite(_ id: String = "A1", a date: Date,
                          titre: String = "Vélo tranquille",
                          minutes: Int = 20, xp: Int = 30) -> ActivityFeedInput {
        ActivityFeedInput(publicID: id, date: date, title: titre,
                          durationMinutes: minutes, xp: xp)
    }

    // MARK: - L'ordre

    /// Le fil est celui d'une JOURNÉE qu'on relit du matin au soir, pas un fil
    /// d'actualité qui remonterait le plus récent en tête. Repas et activités sont
    /// entremêlés dans le même ordre chronologique.
    func testLeFilEstTrieParHeureCroissante() {
        let fil = DuoFeedBuilder.build(
            meals: [repas("R-midi", a: heure(12, 30)), repas("R-matin", a: heure(8))],
            activities: [activite("A-soir", a: heure(19)), activite("A-matin", a: heure(7))])

        XCTAssertEqual(fil.map(\.id), ["A-matin", "R-matin", "R-midi", "A-soir"])
    }

    /// À heure ÉGALE — un encas validé dans la même minute qu'une séance, ce qui
    /// arrive — l'ordre publié est celui-ci : les repas d'abord, puis les activités,
    /// chacun dans l'ordre reçu. L'enjeu n'est pas esthétique : `DuoSnapshot ==` compare
    /// `events`, donc deux ordres différents pour un contenu identique feraient conclure
    /// « ça a changé » à la publication, qui écrirait dans iCloud à chaque passage,
    /// possiblement en alternant sans fin entre deux ordres.
    ///
    /// CE QUE CE TEST NE PROUVE PAS, et il faut le dire : je l'ai mesuré en retirant le
    /// départage par rang de l'implémentation, et il reste vert. Le tri de la
    /// bibliothèque standard se trouve être stable aujourd'hui sur une entrée de cette
    /// taille, alors que sa documentation ne le garantit PAS. Ce test caractérise donc
    /// le contrat d'ordre, il ne démontre pas que le départage porte quelque chose
    /// aujourd'hui. Le départage reste dans le code parce que c'est la garantie qui
    /// compte, pas le comportement observé d'une version donnée de la stdlib.
    func testAHeureEgaleLOrdreEstCeluiQuOnADocumente() {
        let midi = heure(12)
        let meals = [repas("R1", a: midi), repas("R2", a: midi), repas("R3", a: midi)]
        let activities = [activite("A1", a: midi), activite("A2", a: midi)]

        let attendu = ["R1", "R2", "R3", "A1", "A2"]
        XCTAssertEqual(DuoFeedBuilder.build(meals: meals, activities: activities).map(\.id),
                       attendu)
        // Et le même contenu redonne le même ordre : c'est CETTE propriété que la
        // publication interroge.
        XCTAssertEqual(DuoFeedBuilder.build(meals: meals, activities: activities).map(\.id),
                       attendu)
    }

    func testUnFilVideEstVide() {
        XCTAssertEqual(DuoFeedBuilder.build(meals: [], activities: []), [])
    }

    // MARK: - Les sous-titres

    /// Mot pour mot, parce que c'est ce que le partenaire lit et que rien chez lui ne
    /// recalcule ce texte. L'espace après le tilde vient de `MealFormatting.frKcal`,
    /// réutilisé exprès : le duo ne doit pas inventer une variante du journal Repas.
    func testLeSousTitreDUnRepasNommeLeCreneauEtLesKcal() {
        let fil = DuoFeedBuilder.build(
            meals: [repas(a: heure(12, 30), slot: .lunch, titre: "Salade de lentilles",
                          kcal: 420)],
            activities: [])

        XCTAssertEqual(fil.first?.title, "Salade de lentilles")
        XCTAssertEqual(fil.first?.subtitle, "déjeuner, ~ 420 kcal")
        XCTAssertEqual(fil.first?.kind, .meal)
    }

    /// Le tilde est une promesse d'honnêteté depuis la v1, et il ne doit pas mentir
    /// dans l'autre sens : sur un chiffre saisi à la main, il disparaît. Même règle que
    /// le journal depuis la 1.10, et elle traverse le duo sans exception.
    func testDesKcalSaisiesALaMainPerdentLeTilde() {
        let fil = DuoFeedBuilder.build(
            meals: [repas(a: heure(20), slot: .dinner, titre: "Pizza", kcal: 800,
                          manuel: true)],
            activities: [])

        XCTAssertEqual(fil.first?.subtitle, "dîner, 800 kcal")
    }

    /// Les quatre créneaux nomment bien quatre choses différentes, en minuscule parce
    /// que le libellé arrive en MILIEU de phrase dans le sous-titre.
    func testLesQuatreCreneauxOntChacunLeurLibelle() {
        let libelles = MealSlot.allCases.map(\.frLabel)
        XCTAssertEqual(libelles, ["petit-déjeuner", "déjeuner", "dîner", "encas"])
        XCTAssertEqual(Set(libelles).count, 4)
    }

    func testLeSousTitreDUneActiviteDonneLaDureeEtLXP() {
        let fil = DuoFeedBuilder.build(
            meals: [], activities: [activite(a: heure(18), titre: "Vélo tranquille",
                                             minutes: 20, xp: 30)])

        XCTAssertEqual(fil.first?.title, "Vélo tranquille")
        XCTAssertEqual(fil.first?.subtitle, "20 min, +30 XP")
        XCTAssertEqual(fil.first?.kind, .activity)
    }

    /// Aucun tiret cadratin dans ce qui part chez le partenaire : c'est du texte
    /// affiché, la règle du projet s'y applique, et la virgule fait le travail.
    func testAucunSousTitreNeContientDeTiretCadratin() {
        let fil = DuoFeedBuilder.build(
            meals: MealSlot.allCases.map { repas(a: heure(9), slot: $0) },
            activities: [activite(a: heure(9))])

        for evenement in fil {
            XCTAssertFalse(evenement.subtitle.contains("—"), evenement.subtitle)
        }
    }

    // MARK: - Les identifiants manquants

    /// Le remplissage des entrées d'avant la 1.15, qui sont nées avec un `publicID`
    /// vide (Task 2). Deux entrées vides ne doivent SURTOUT pas recevoir le même
    /// identifiant : ce serait réintroduire ici l'accident que la sentinelle vide
    /// évitait à la migration, et deux repas partageant une identité partageraient
    /// leurs cœurs. Le générateur est injecté et compte ses appels, ce qui prouve
    /// qu'il est appelé UNE FOIS PAR ENTRÉE et non une fois pour toutes.
    func testLesIdentifiantsVidesSontRemplisEtTousDistincts() {
        var compteur = 0
        let attribution = DuoFeedBuilder.assignMissingIDs(
            meals: [repas("", a: heure(8)), repas("", a: heure(12))],
            activities: [activite("", a: heure(18))],
            newID: { compteur += 1; return "ID\(compteur)" })

        // Les rangs sont ceux de CHAQUE tableau, pas d'une numérotation commune :
        // l'appelant applique `meals[i]` à son i-ᵉ repas et `activities[j]` à sa j-ᵉ
        // activité, deux listes qu'il tient séparément.
        XCTAssertEqual(attribution.meals, [0: "ID1", 1: "ID2"])
        XCTAssertEqual(attribution.activities, [0: "ID3"])
        let tous = Array(attribution.meals.values) + Array(attribution.activities.values)
        XCTAssertEqual(Set(tous).count, 3, "Deux entrées ont reçu le même identifiant.")
    }

    /// Le revers, et c'est le plus grave des deux : un identifiant DÉJÀ attribué ne
    /// doit jamais être réattribué. Le réécrire à chaque publication détacherait
    /// silencieusement tous les cœurs déjà reçus sur cette entrée, puisqu'un `DuoLike`
    /// désigne son événement par cet identifiant et rien d'autre.
    func testUnIdentifiantDejaAttribueNEstJamaisReattribue() {
        let attribution = DuoFeedBuilder.assignMissingIDs(
            meals: [repas("R-existant", a: heure(8)), repas("", a: heure(12))],
            activities: [activite("A-existante", a: heure(18))],
            newID: { "NEUF" })

        XCTAssertEqual(attribution.meals, [1: "NEUF"])
        XCTAssertTrue(attribution.activities.isEmpty)
    }

    /// Rien à faire ne fait rien : aucun appel au générateur, donc aucune écriture
    /// demandée à l'appelant. C'est ce qui permet d'appeler la publication à chaque
    /// retour au premier plan sans réveiller SwiftData pour rien.
    func testUnFilDejaIdentifieNeDemandeAucuneEcriture() {
        var appels = 0
        let attribution = DuoFeedBuilder.assignMissingIDs(
            meals: [repas("R1", a: heure(8))], activities: [activite("A1", a: heure(18))],
            newID: { appels += 1; return "NEUF" })

        XCTAssertTrue(attribution.isEmpty)
        XCTAssertEqual(appels, 0)
    }
}
