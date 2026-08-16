import XCTest
@testable import NivelCore

final class DuoSnapshotTests: XCTestCase {

    private func instantane(generatedAt: Date = Date(timeIntervalSince1970: 1_000)) -> DuoSnapshot {
        DuoSnapshot(
            memberID: "M1", name: "Marion", sexRaw: "female",
            level: 11, totalXP: 2_340, xpIntoLevel: 140, xpForNextLevel: 220,
            dayKey: "2026-08-16",
            kcalEaten: 1_180, kcalTarget: 1_550, burned: 310, burnTarget: 400, steps: 7_240,
            quest: DuoQuestLine(title: "Bouger 4 fois", done: 3, total: 4),
            events: [], generatedAt: generatedAt
        )
    }

    /// LE test qui évite les écritures inutiles (spec §3.5) : deux instantanés qui ne
    /// diffèrent QUE par leur horodatage sont le même instantané. Sans cette règle,
    /// chaque appel de la publication écrirait dans iCloud alors que rien n'a bougé.
    func testLEgaliteIgnoreLHorodatage() {
        XCTAssertEqual(instantane(), instantane(generatedAt: Date(timeIntervalSince1970: 9_999)))
    }

    /// La contrepartie : tout le reste compte.
    func testUnChiffreQuiChangeRendLesInstantanesDifferents() {
        var autre = instantane()
        autre.kcalEaten += 1
        XCTAssertNotEqual(instantane(), autre)
    }

    /// La contrepartie, en entier. `==` est écrit à la main (c'est le prix de
    /// l'exclusion de `generatedAt`), et une ligne oubliée y est SILENCIEUSE : deux
    /// instantanés différents passeraient pour égaux, la publication conclurait « rien
    /// n'a bougé » et le partenaire resterait figé sur des chiffres périmés. Le test
    /// précédent ne couvre qu'un champ sur seize.
    ///
    /// La table ci-dessous porte une mutation par champ, et son jeu de clés est
    /// confronté aux champs que `Mirror` lit réellement sur le type. Les deux moitiés
    /// comptent : la confrontation empêche qu'un champ ajouté demain reste non testé,
    /// la boucle vérifie que `==` le regarde vraiment. `generatedAt` est le seul
    /// absent de la table, et il l'est explicitement — c'est le test au-dessus qui le
    /// couvre, en sens inverse.
    func testChaqueChampCompteDansLEgaliteSaufLHorodatage() {
        let mutations: [String: (inout DuoSnapshot) -> Void] = [
            "memberID": { $0.memberID = "M2" },
            "name": { $0.name = "Michaël" },
            "sexRaw": { $0.sexRaw = "male" },
            "level": { $0.level += 1 },
            "totalXP": { $0.totalXP += 1 },
            "xpIntoLevel": { $0.xpIntoLevel += 1 },
            "xpForNextLevel": { $0.xpForNextLevel += 1 },
            "dayKey": { $0.dayKey = "2026-08-17" },
            "kcalEaten": { $0.kcalEaten += 1 },
            "kcalTarget": { $0.kcalTarget += 1 },
            "burned": { $0.burned += 1 },
            "burnTarget": { $0.burnTarget += 1 },
            "steps": { $0.steps = DuoSnapshot.stepsUnavailable },
            // Une progression qui avance, pas un passage à nil : on veut prouver que la
            // quête est comparée par sa VALEUR, pas seulement par sa présence.
            "quest": { $0.quest = DuoQuestLine(title: "Bouger 4 fois", done: 4, total: 4) },
            "events": {
                $0.events.append(DuoEvent(id: "E1", kind: .meal,
                                          at: Date(timeIntervalSince1970: 5_000),
                                          title: "Salade de lentilles",
                                          subtitle: "déjeuner, ~420 kcal"))
            },
        ]

        let champs = Mirror(reflecting: instantane()).children.compactMap(\.label).sorted()
        XCTAssertEqual(
            champs, (Array(mutations.keys) + ["generatedAt"]).sorted(),
            "Un champ de DuoSnapshot n'est couvert par aucune mutation de cette table : "
                + "ajoute-la, et vérifie au passage que `==` le compare.")

        for (nom, muter) in mutations {
            var autre = instantane()
            muter(&autre)
            XCTAssertNotEqual(instantane(), autre,
                              "Le champ `\(nom)` a changé et `==` ne l'a pas vu : "
                                  + "la publication n'écrirait jamais cette différence.")
        }
    }

    /// Les pas sont absents tant que HealthKit n'a pas répondu, et absents pour
    /// toujours s'il est refusé. `-1` porte les deux cas, comme `DailySteps.unavailable`
    /// côté app : un `0` ferait afficher « 0 pas » à quelqu'un qui a marché.
    func testLesPasIndisponiblesSeCodentEnMoinsUn() throws {
        let json = try JSONEncoder().encode(instantane())
        let relu = try JSONDecoder().decode(DuoSnapshot.self, from: json)
        XCTAssertEqual(relu.steps, 7_240)
        XCTAssertEqual(DuoSnapshot.stepsUnavailable, -1)
    }

    /// Compatibilité ascendante (spec §3.4) : un instantané venu d'une version plus
    /// récente, avec une clé de plus, doit se décoder sans erreur chez qui ne la
    /// connaît pas. `JSONDecoder` ignore les clés inconnues, ce test le pinne.
    func testUneCleInconnueNeCassePasLeDecodage() throws {
        var objet = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(instantane()))
                as? [String: Any])
        objet["champDUneVersionFuture"] = "peu importe"
        let donnees = try JSONSerialization.data(withJSONObject: objet)
        XCTAssertNoThrow(try JSONDecoder().decode(DuoSnapshot.self, from: donnees))
    }

    /// Un instantané complet fait l'aller-retour sans rien perdre : le JSON est le
    /// format de `feedJSON` et du cache local du partenaire, pas un détail interne.
    /// `==` ignorant `generatedAt`, l'horodatage est vérifié à part — sinon un champ
    /// perdu au codage passerait inaperçu, justement parce que `==` ne le regarde pas.
    func testUnInstantaneFaitLAllerRetour() throws {
        let origine = instantane()
        let relu = try JSONDecoder().decode(
            DuoSnapshot.self, from: try JSONEncoder().encode(origine))
        XCTAssertEqual(relu, origine)
        XCTAssertEqual(relu.generatedAt, origine.generatedAt)
    }

    /// Un événement se code et se relit à l'identique.
    func testUnEvenementFaitLAllerRetour() throws {
        let evenement = DuoEvent(id: "E1", kind: .meal, at: Date(timeIntervalSince1970: 5_000),
                                 title: "Salade de lentilles", subtitle: "déjeuner, ~420 kcal")
        let relu = try JSONDecoder().decode(
            DuoEvent.self, from: try JSONEncoder().encode(evenement))
        XCTAssertEqual(relu, evenement)
    }

    /// LE test du second volet de la compatibilité ascendante (spec §3.4). Ce qui compte
    /// n'est pas le repli lui-même, c'est qu'un intrus n'emporte pas ses voisins :
    /// mesuré avant correctif, un seul `kind` inconnu levait un `dataCorrupted` sur
    /// `[1].kind` et faisait échouer le décodage du TABLEAU ENTIER — un partenaire resté
    /// en 1.15 n'aurait plus vu AUCUN événement de la journée de l'autre, sans le
    /// moindre message. L'intrus est donc encadré de deux événements valides, et les
    /// trois doivent arriver.
    func testUnGenreInconnuNEmportePasLesEvenementsQuiLEntourent() throws {
        let json = Data("""
            [{"id":"E1","kind":"meal","at":5000,"title":"Salade","subtitle":"déjeuner"},
             {"id":"E2","kind":"weight","at":6000,"title":"Pesée","subtitle":"68,4 kg"},
             {"id":"E3","kind":"activity","at":7000,"title":"Vélo","subtitle":"20 min"}]
            """.utf8)

        let fil = try JSONDecoder().decode([DuoEvent].self, from: json)

        XCTAssertEqual(fil.map(\.id), ["E1", "E2", "E3"])
        XCTAssertEqual(fil.map(\.kind), [.meal, .unknown, .activity])
        // Et l'intrus lui-même reste affichable : `title` et `subtitle` étant calculés
        // à la publication, il ne lui manque que son icône.
        XCTAssertEqual(fil[1].title, "Pesée")
        XCTAssertEqual(fil[1].subtitle, "68,4 kg")
    }

    /// Le repli ne doit pas devenir un trou noir : les deux genres connus continuent de
    /// se décoder pour ce qu'ils sont. Un `init(from:)` trop indulgent (un `try?` mal
    /// placé, un `rawValue` mal orthographié) rendrait le fil entier `unknown` sans que
    /// le test ci-dessus s'en aperçoive.
    func testLesGenresConnusNeRetombentPasSurUnknown() throws {
        let json = Data("""
            [{"id":"E1","kind":"meal","at":5000,"title":"T","subtitle":"S"},
             {"id":"E2","kind":"activity","at":6000,"title":"T","subtitle":"S"}]
            """.utf8)
        XCTAssertEqual(try JSONDecoder().decode([DuoEvent].self, from: json).map(\.kind),
                       [.meal, .activity])
    }

    /// Le genre d'un événement voyage en CHAÎNE, pas en indice : `meal` et `activity`
    /// écrits en clair restent lisibles si un futur cas s'insère entre les deux dans la
    /// déclaration. Un enum sans `String` brut se coderait en 0 / 1 et une insertion
    /// transformerait tous les repas déjà publiés en activités chez le partenaire.
    func testLeGenreDUnEvenementSeCodeEnClair() throws {
        let json = try XCTUnwrap(
            String(data: try JSONEncoder().encode(
                DuoEvent(id: "E1", kind: .activity, at: Date(timeIntervalSince1970: 5_000),
                         title: "Vélo tranquille", subtitle: "20 min, +30 XP")),
                   encoding: .utf8))
        XCTAssertTrue(json.contains("\"activity\""), json)
    }
}
