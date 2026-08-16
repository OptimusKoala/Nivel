// NivelTests/DuoPublisherTests.swift
// L'identité publique d'une entrée (spec 1.15 §3.4) : `MealEntry` et `ActivityEntry`
// gagnent un `publicID`, seule cible possible d'un cœur du duo.
import XCTest
import SwiftData
import NivelCore
@testable import Nivel

final class DuoPublisherTests: XCTestCase {

    /// Une entrée neuve naît SANS identifiant, comme toutes celles d'avant la 1.15.
    /// C'est le point de la tâche, et il est contre-intuitif : on attendrait un
    /// `UUID().uuidString` dès la naissance. Mais le défaut est porté par la
    /// DÉCLARATION, pour garder la migration légère, et un défaut de déclaration
    /// SwiftData n'offre aucune garantie d'être évalué une fois par ligne à la
    /// migration — une centaine d'entrées existantes pourraient hériter du MÊME
    /// identifiant, ce qui est inacceptable pour une valeur qui sert de cible à un
    /// cœur. La chaîne vide est une sentinelle sans ambiguïté, et le remplissage se
    /// fait plus tard, à la volée, sur un seul chemin.
    func testUnRepasNeufNaitSansIdentifiantPublic() {
        let repas = MealEntry(slot: .lunch, estimatedKcal: 420)
        XCTAssertEqual(repas.publicID, "")
    }

    /// Même règle et même unique chemin pour une activité : rien dans l'`init` ne
    /// permet d'en fabriquer une qui naîtrait déjà identifiée.
    func testUneActiviteNeuveNaitSansIdentifiantPublic() {
        let activite = ActivityEntry(kind: .activity, refID: "bike",
                                     durationMinutes: 20, estimatedKcal: 120)
        XCTAssertEqual(activite.publicID, "")
    }
}

/// La moitié PROUVABLE de la publication (spec §3.5) : `makeDuoSnapshot` est synchrone,
/// n'émet aucune requête et ne touche à rien. Ce qui parle à CloudKit viendra à part et
/// n'aura pas cette chance.
@MainActor
final class DuoSnapshotBuildingTests: XCTestCase {
    private var context: ModelContext!
    private var service: GameService!
    private let midi = Date(timeIntervalSince1970: 1_755_338_400)  // 2025-08-16 12:00 UTC

    override func setUp() async throws {
        let schema = Schema([
            UserProfile.self, MealEntry.self, WeightEntry.self,
            DayLog.self, GamificationState.self, ActivityEntry.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true,
                                               cloudKitDatabase: .none)
        context = ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
        service = GameService(modelContext: context,
                              stepsService: FakeStepsService(authorized: false),
                              widgetDefaults: nil)
    }

    private func creerProfil(cible: Int = 1_800) {
        context.insert(UserProfile(
            name: "Marion", sex: .female, birthDate: Date(timeIntervalSince1970: 0),
            heightCm: 165, initialWeightKg: 70, activity: .moderate, dailyCalorieTarget: cible))
        context.insert(GamificationState())
        try? context.save()
    }

    private func construire(steps: Int? = 7_240) -> DuoSnapshot? {
        service.makeDuoSnapshot(memberID: "M1", steps: steps, now: midi)
    }

    /// Rien à publier tant qu'il n'y a pas de profil, exactement comme
    /// `makeWidgetSnapshot` : sans onboarding il n'y a ni prénom ni cible, et publier
    /// une coquille ferait apparaître un partenaire sans nom chez l'autre.
    func testAucunInstantaneTantQueLOnboardingNEstPasFini() {
        XCTAssertNil(construire())
    }

    func testLesChiffresDuJourSontRepris() async throws {
        creerProfil(cible: 1_800)
        _ = await service.logMeal(slot: .lunch, lines: [], manualKcal: 420, date: midi)

        let instantane = try XCTUnwrap(construire())

        XCTAssertEqual(instantane.memberID, "M1")
        XCTAssertEqual(instantane.name, "Marion")
        XCTAssertEqual(instantane.sexRaw, Sex.female.rawValue)
        XCTAssertEqual(instantane.kcalEaten, 420)
        XCTAssertEqual(instantane.kcalTarget, 1_800)
        XCTAssertEqual(instantane.burnTarget, service.burnTarget())
        XCTAssertEqual(instantane.steps, 7_240)
        XCTAssertEqual(instantane.dayKey, GameService.duoDayKey(for: midi))
        XCTAssertEqual(instantane.generatedAt, midi)
    }

    /// Les pas indisponibles se publient en sentinelle, jamais en zéro : un `0` ferait
    /// afficher « 0 pas » au partenaire de quelqu'un qui a marché toute la journée.
    func testLesPasNonLusSePublientEnSentinelle() throws {
        creerProfil()

        let instantane = try XCTUnwrap(construire(steps: nil))

        XCTAssertEqual(instantane.steps, DuoSnapshot.stepsUnavailable)
        XCTAssertEqual(instantane.steps, -1)
    }

    /// Le niveau part DÉJÀ CALCULÉ (spec §3.4). Le test le confronte à `LevelSystem`
    /// plutôt qu'à des nombres écrits à la main : c'est la COHÉRENCE avec la courbe
    /// locale qui est la propriété, et elle doit survivre à un changement de barème.
    func testLeNiveauEstPublieDejaCalculeEtCoherentAvecLaCourbe() throws {
        creerProfil()
        let etat = service.fetchOrCreateState()
        etat.totalXP = 2_340
        try context.save()

        let instantane = try XCTUnwrap(construire())
        let attendu = LevelSystem.progress(forXP: 2_340)

        XCTAssertEqual(instantane.totalXP, 2_340)
        XCTAssertEqual(instantane.level, LevelSystem.level(forXP: 2_340))
        XCTAssertEqual(instantane.xpIntoLevel, attendu.current)
        XCTAssertEqual(instantane.xpForNextLevel, attendu.needed)
    }

    /// La quête publiée est la plus AVANCÉE non terminée, via `HomeView.featuredQuest` —
    /// la fonction même de la carte de l'accueil. Le partenaire voit donc exactement la
    /// quête que l'autre a sous les yeux, ce qu'une seconde règle écrite dans le
    /// publieur ne garantirait plus le jour où l'une des deux changerait.
    ///
    /// Les quêtes sont posées à la main plutôt que tirées par le rollover hebdomadaire :
    /// un tirage rendrait le test dépendant de la date, et la version précédente de ce
    /// test se contentait d'un `XCTSkipIf` quand la liste était vide, c'est-à-dire
    /// qu'elle ne vérifiait rien du tout.
    func testLaQuetePublieeEstLaPlusAvanceeNonTerminee() throws {
        creerProfil()
        let catalogue = service.questCatalog
        let peuAvancee = try XCTUnwrap(catalogue.first)
        let bienAvancee = try XCTUnwrap(catalogue.dropFirst().first)
        let etat = service.fetchOrCreateState()
        etat.activeQuestIDs = [peuAvancee.id, bienAvancee.id]
        etat.questProgress = [peuAvancee.id: 0, bienAvancee.id: max(1, bienAvancee.target - 1)]
        try context.save()

        let quete = try XCTUnwrap(try XCTUnwrap(construire()).quest)

        XCTAssertEqual(quete.title, bienAvancee.title)
        XCTAssertEqual(quete.done, max(1, bienAvancee.target - 1))
        XCTAssertEqual(quete.total, bienAvancee.target)
    }

    /// Une quête TERMINÉE ne se publie pas, même si c'est la plus avancée : c'est la
    /// moitié « non terminée » de la règle, et elle tomberait en silence si `featuredQuest`
    /// était un jour remplacé par un simple `max(fraction)`.
    func testUneQueteTermineeNEstPasCellePubliee() throws {
        creerProfil()
        let catalogue = service.questCatalog
        let terminee = try XCTUnwrap(catalogue.first)
        let enCours = try XCTUnwrap(catalogue.dropFirst().first)
        let etat = service.fetchOrCreateState()
        etat.activeQuestIDs = [terminee.id, enCours.id]
        etat.questProgress = [terminee.id: terminee.target, enCours.id: 1]
        etat.completedThisWeekQuestIDs = [terminee.id]
        try context.save()

        let quete = try XCTUnwrap(try XCTUnwrap(construire()).quest)

        XCTAssertEqual(quete.title, enCours.title)
    }

    /// Et rien plutôt qu'une ligne vide quand il n'y a aucune quête à montrer.
    func testAucuneQueteDonneUnChampVide() throws {
        creerProfil()
        let etat = service.fetchOrCreateState()
        etat.activeQuestIDs = []
        try context.save()

        XCTAssertNil(try XCTUnwrap(construire()).quest)
    }

    /// Le fil est trié, et il ne contient QUE des événements identifiés : une entrée
    /// d'avant la 1.15 dont le `publicID` est resté vide manque au fil plutôt que d'y
    /// figurer, parce que deux entrées non identifiées partageraient leur cœur.
    func testLeFilEstTrieEtSansEvenementNonIdentifie() async throws {
        creerProfil()
        let soir = midi.addingTimeInterval(6 * 3_600)
        let matin = midi.addingTimeInterval(-3 * 3_600)

        let tardif = await service.logMeal(slot: .dinner, lines: [], manualKcal: 700, date: soir)
        tardif.publicID = "R-soir"
        let matinal = await service.logMeal(slot: .breakfast, lines: [], manualKcal: 300, date: matin)
        matinal.publicID = "R-matin"
        // Celui-ci reste sans identifiant, comme toute entrée d'avant la 1.15.
        _ = await service.logMeal(slot: .snack, lines: [], manualKcal: 100, date: midi)
        try context.save()

        let fil = try XCTUnwrap(construire()).events

        XCTAssertEqual(fil.map(\.id), ["R-matin", "R-soir"])
        XCTAssertEqual(fil.first?.subtitle, "petit-déjeuner, 300 kcal")
    }
}

/// La seule partie de `publishDuoNow` qui s'éprouve sans nuage : la garde d'appairage.
/// Tout ce qui suit parle à CloudKit et ne se vérifie que sur deux appareils.
@MainActor
final class DuoPublishGuardTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var context: ModelContext!
    private var service: GameService!

    override func setUp() async throws {
        suiteName = "nivel.tests.duo.publish.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        let schema = Schema([
            UserProfile.self, MealEntry.self, WeightEntry.self,
            DayLog.self, GamificationState.self, ActivityEntry.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true,
                                               cloudKitDatabase: .none)
        context = ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
        context.insert(UserProfile(
            name: "Marion", sex: .female, birthDate: Date(timeIntervalSince1970: 0),
            heightCm: 165, initialWeightKg: 70, activity: .moderate, dailyCalorieTarget: 1_800))
        context.insert(GamificationState())
        try context.save()
        service = GameService(modelContext: context,
                              stepsService: FakeStepsService(authorized: false),
                              widgetDefaults: nil)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    /// Sans duo appairé, la publication ne fait RIEN. La spec §3.1 le promet
    /// explicitement : aucune requête réseau, aucun enregistrement, l'app se comporte
    /// exactement comme la 1.14.
    ///
    /// La preuve ne porte pas sur le réseau, qu'aucun test ne peut observer ici, mais sur
    /// sa CONSÉQUENCE OBSERVABLE : la publication commence par attribuer et persister les
    /// identifiants publics manquants. Si elle est allée jusque-là, le repas porterait un
    /// `publicID`. Il reste vide, donc elle s'est arrêtée à la garde — avant la
    /// résolution de la zone, donc avant tout contact avec CloudKit.
    func testSansDuoAppairreLaPublicationNeFaitRien() async throws {
        let identite = DuoIdentity(defaults: defaults)
        XCTAssertFalse(identite.isPaired)
        let repas = await service.logMeal(slot: .lunch, lines: [], manualKcal: 420)

        let aPublie = await service.publishDuoNow(identity: identite)

        XCTAssertFalse(aPublie)
        XCTAssertEqual(repas.publicID, "", "la publication a attribué un identifiant, "
                       + "donc elle a dépassé la garde d'appairage")
        XCTAssertNil(identite.lastPublishedSnapshot)
    }

    /// Et un rôle sans identité de zone ne suffit pas : un invité privé de `zoneOwnerName`
    /// écrirait dans une zone à LUI, que personne ne lit. `DuoDatabase.target` rend alors
    /// nil, et la publication s'arrête là.
    func testUnInviteSansProprietaireDeZoneNePubliePasDansLeVide() async throws {
        let identite = DuoIdentity(defaults: defaults)
        identite.role = .guest
        identite.zoneName = "duo"
        // zoneOwnerName volontairement absent.
        let repas = await service.logMeal(slot: .lunch, lines: [], manualKcal: 420)

        let aPublie = await service.publishDuoNow(identity: identite)

        XCTAssertFalse(aPublie)
        XCTAssertEqual(repas.publicID, "")
        XCTAssertNil(identite.lastPublishedSnapshot)
    }



    /// L'ORDRE de la publication, et c'est le seul test qui le garde. Attribuer et
    /// persister les identifiants doit précéder la construction du fil : `build` écarte
    /// tout événement dont le `publicID` est vide, si bien qu'inverser les deux
    /// publierait une journée amputée de TOUTES ses entrées d'avant la 1.15, à chaque
    /// fois, sans que rien ne s'allume.
    ///
    /// La preuve tient à ce que la fonction rend l'instantané : les entrées naissent
    /// sans identifiant, et pourtant les trois sont dans le fil. Si la construction
    /// passait la première, le fil serait vide alors même que les `publicID` seraient
    /// remplis à la fin de l'appel — c'est pourquoi vérifier les seuls `publicID` ne
    /// suffirait pas.
    func testLaPreparationAttribueLesIdentifiantsAvantDeConstruireLeFil() async throws {
        let matin = await service.logMeal(slot: .breakfast, lines: [], manualKcal: 300)
        let midi = await service.logMeal(slot: .lunch, lines: [], manualKcal: 420)
        let sport = await service.logActivity(
            activity: try XCTUnwrap(service.activityCatalog.first), durationMinutes: 20)
        for entree in [matin.publicID, midi.publicID] { XCTAssertEqual(entree, "") }
        XCTAssertEqual(sport.publicID, "")

        let instantane = try XCTUnwrap(
            service.prepareDuoSnapshot(memberID: "M1", steps: nil))

        XCTAssertFalse(matin.publicID.isEmpty)
        XCTAssertFalse(midi.publicID.isEmpty)
        XCTAssertFalse(sport.publicID.isEmpty)
        XCTAssertEqual(Set(instantane.events.map(\.id)),
                       Set([matin.publicID, midi.publicID, sport.publicID]),
                       "le fil ne contient pas toutes les entrées du jour : la "
                           + "construction a-t-elle précédé l'attribution ?")
        XCTAssertEqual(instantane.events.count, 3)
    }

    /// Le pendant côté appelant du test « un cœur de la veille survit ». `orphanEventIDs`
    /// juge contre l'ensemble qu'on lui donne : c'est donc CETTE fonction qui décide si
    /// les cœurs de la veille vivent ou meurent, et elle doit couvrir TOUTES les
    /// journées. La restreindre au jour courant effacerait chaque nuit tout ce que le duo
    /// s'est envoyé la veille.
    func testLesIdentifiantsLocauxCouvrentToutesLesJournees() async throws {
        let hier = Date().addingTimeInterval(-36 * 3_600)
        let ancien = await service.logMeal(slot: .dinner, lines: [], manualKcal: 500, date: hier)
        ancien.publicID = "E-hier"
        let recent = await service.logMeal(slot: .lunch, lines: [], manualKcal: 420)
        recent.publicID = "E-aujourdhui"
        // Une entrée jamais identifiée n'est désignée par aucun cœur légitime.
        _ = await service.logMeal(slot: .snack, lines: [], manualKcal: 100)
        try context.save()

        let identifiants = service.allLocalPublicIDs()

        XCTAssertTrue(identifiants.contains("E-hier"),
                      "les entrées d'hier sont absentes : leurs cœurs seraient effacés")
        XCTAssertTrue(identifiants.contains("E-aujourdhui"))
        XCTAssertFalse(identifiants.contains(""))
    }

    /// Le désappairage oublie aussi ce qui a été publié. Sans ça, réappairer avec la même
    /// personne ne republierait rien tant qu'un chiffre n'aurait pas bougé, et le
    /// partenaire resterait sur un écran vide.
    func testLeDesappairageOublieLeDernierInstantanePublie() throws {
        let identite = DuoIdentity(defaults: defaults)
        identite.role = .owner
        identite.lastPublishedSnapshot = DuoSnapshot(
            memberID: "M1", name: "Marion", sexRaw: "female",
            level: 1, totalXP: 0, xpIntoLevel: 0, xpForNextLevel: 100,
            dayKey: "2026-08-16", kcalEaten: 0, kcalTarget: 1_800, burned: 0, burnTarget: 0,
            steps: DuoSnapshot.stepsUnavailable, quest: nil, events: [],
            generatedAt: Date(timeIntervalSince1970: 1_000))

        identite.unpair()

        XCTAssertNil(identite.lastPublishedSnapshot)
        XCTAssertNil(DuoIdentity(defaults: defaults).lastPublishedSnapshot)
    }
}
