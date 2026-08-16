// NivelTests/DayCloserTests.swift
import XCTest
import SwiftData
import NivelCore
@testable import Nivel

/// Tests de la clôture des journées passées (DayCloser.swift, spec §9).
/// Les dates sont CONTRÔLÉES : `today` est figé au début du test et passé
/// explicitement à `closeOpenDays(today:)` — la logique ne lit jamais `.now`.
@MainActor
final class DayCloserTests: XCTestCase {
    private var context: ModelContext!
    private var profile: UserProfile!
    private var state: GamificationState!

    /// Jour J figé (les journées à clôturer en sont dérivées).
    private var today: Date!
    private var day1: Date!      // J-3
    private var day2: Date!      // J-2
    private var day3: Date!      // J-1 = hier
    private var yesterday: Date! // = day3

    override func setUp() async throws {
        let schema = Schema([
            UserProfile.self, MealEntry.self, WeightEntry.self,
            DayLog.self, GamificationState.self, ActivityEntry.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)

        today = Date.now
        let todayKey = GameService.dayKey(for: today)
        day1 = try XCTUnwrap(GameService.calendar.date(byAdding: .day, value: -3, to: todayKey))
        day2 = try XCTUnwrap(GameService.calendar.date(byAdding: .day, value: -2, to: todayKey))
        day3 = try XCTUnwrap(GameService.calendar.date(byAdding: .day, value: -1, to: todayKey))
        yesterday = day3

        profile = UserProfile(
            name: "Michaël",
            sex: .male,
            birthDate: Date(timeIntervalSince1970: 0),
            heightCm: 180,
            initialWeightKg: 90,
            activity: .moderate,
            dailyCalorieTarget: 2000,
            dailyStepGoal: 8000,
            createdAt: day1 // 3 journées ouvertes : J-3, J-2, J-1
        )
        context.insert(profile)

        // Semaine courante + aucune quête active : les tests de clôture ne sont
        // pas parasités par le tirage (le rollover a son test dédié).
        state = GamificationState(
            questWeekID: QuestEngine.weekID(for: today, calendar: GameService.calendar)
        )
        context.insert(state)
        try context.save()
    }

    private func makeService(steps: FakeStepsService) -> GameService {
        GameService(modelContext: context, stepsService: steps, widgetDefaults: nil, duoIdentity: nil)
    }

    /// Repas inséré directement (sans XP) à midi du jour donné : la clôture doit
    /// recalculer les kcal depuis les MealEntry, source de vérité.
    private func insertMeal(on day: Date, kcal: Int, slot: MealSlot = .lunch) {
        context.insert(MealEntry(
            date: day.addingTimeInterval(12 * 3600),
            slot: slot,
            lines: [.simple(MealComponent(itemID: "pasta", grams: 500))],
            estimatedKcal: kcal
        ))
    }

    private func fetchDayLogs() throws -> [DayLog] {
        try context.fetch(FetchDescriptor<DayLog>(sortBy: [SortDescriptor(\.day)]))
    }

    /// DayLog d'une journée précise — XCTUnwrap plutôt qu'un index : un test qui
    /// parle de J-3 doit échouer en le disant, pas sur un `logs[0]` décalé.
    private func fetchDayLog(_ day: Date) throws -> DayLog {
        try XCTUnwrap(fetchDayLogs().first { $0.day == day }, "aucun DayLog pour \(day)")
    }

    /// Validation sport insérée directement (sans XP) à 18 h du jour donné : la
    /// clôture doit en tirer la dépense de la journée.
    private func insertActivity(on day: Date, kind: ActivityKind, refID: String, kcal: Int) {
        context.insert(ActivityEntry(
            date: day.addingTimeInterval(18 * 3600),
            kind: kind,
            refID: refID,
            durationMinutes: 30,
            estimatedKcal: kcal
        ))
    }

    // MARK: - Clôture d'un trou de 3 jours

    func testClosesThreeDayGapWithCorrectXPAndSnapshots() async throws {
        // J-3 : 2 repas SOUS l'objectif (1300 ≤ 2000) + 9000 pas ≥ 8000 → +50 +40.
        insertMeal(on: day1, kcal: 650, slot: .lunch)
        insertMeal(on: day1, kcal: 650, slot: .dinner)
        // J-2 : 2 repas AU-DESSUS (2100 > 2000) → +0.
        insertMeal(on: day2, kcal: 1450, slot: .lunch)
        insertMeal(on: day2, kcal: 650, slot: .dinner)
        // J-1 : aucun repas → sans journal, pas de jugement (withinTarget false, pas de +50).
        try context.save()

        let service = makeService(steps: FakeStepsService(
            stepsByDay: [day1: 9000, day2: 2000] // J-1 absent → 0 pas
        ))
        await service.closeOpenDays(today: today)

        let logs = try fetchDayLogs()
        XCTAssertEqual(logs.count, 3)
        XCTAssertTrue(logs.allSatisfy(\.closed))
        XCTAssertEqual(logs.map(\.day), [day1, day2, day3])

        // J-3 : dans l'objectif + objectif de pas atteint.
        XCTAssertEqual(logs[0].kcalEaten, 1300)
        XCTAssertEqual(logs[0].kcalTarget, 2000)
        XCTAssertEqual(logs[0].steps, 9000)
        XCTAssertTrue(logs[0].withinTarget)
        XCTAssertEqual(logs[0].xpEarned, 90) // +50 dayWithinTarget, +40 stepGoalReached

        // J-2 : au-dessus de l'objectif.
        XCTAssertEqual(logs[1].kcalEaten, 2100)
        XCTAssertEqual(logs[1].steps, 2000)
        XCTAssertFalse(logs[1].withinTarget)
        XCTAssertEqual(logs[1].xpEarned, 0)

        // J-1 : aucun log → pas de jugement.
        XCTAssertEqual(logs[2].kcalEaten, 0)
        XCTAssertEqual(logs[2].steps, 0)
        XCTAssertFalse(logs[2].withinTarget)
        XCTAssertEqual(logs[2].xpEarned, 0)

        // XP total = 90 (clôtures) + 50 (badge "Premier repas", 4 repas au journal)
        // + 50 (badge "Ça a bougé" : J-3 et ses 9000 pas passent la cible de dépense).
        XCTAssertEqual(state.totalXP, 190)
        XCTAssertTrue(logs[0].burnTargetReached)
        // L'ENSEMBLE exact, et pas deux XCTAssertNotNil : un futur badge qui tomberait
        // aussi dans ce scénario ferait sinon échouer le total sur un « 190 != 240 » nu,
        // sans nommer le coupable.
        XCTAssertEqual(Set(state.badgeUnlocks.keys), ["first_meal", "burn_first"])
        XCTAssertEqual(state.lastClosedDay, yesterday)
    }

    // MARK: - Renouvellement hebdo

    func testWeekRolloverRedrawsQuestsAndPreservesHistory() async throws {
        let lastWeek = try XCTUnwrap(
            GameService.calendar.date(byAdding: .day, value: -7, to: today)
        )
        state.questWeekID = QuestEngine.weekID(for: lastWeek, calendar: GameService.calendar)
        state.activeQuestIDs = ["weigh_in_1", "log_meals_10", "no_alcohol_2"]
        state.completedThisWeekQuestIDs = ["weigh_in_1"]
        state.questProgress = ["weigh_in_1": 1, "log_meals_10": 4]
        state.completedQuestIDs = ["weigh_in_1"] // historique all-time, déjà alimenté à la complétion
        state.lastClosedDay = yesterday          // rien à clôturer : on isole le rollover
        // Badge "Première quête" déjà débloqué : l'XP total doit rester STRICTEMENT inchangé.
        state.badgeUnlocks = ["quest_first": .now]
        try context.save()

        let service = makeService(steps: FakeStepsService(authorized: false))
        await service.closeOpenDays(today: today)

        let currentWeekID = QuestEngine.weekID(for: today, calendar: GameService.calendar)
        XCTAssertEqual(state.questWeekID, currentWeekID)

        // Nouveau tirage : 3 quêtes valides du catalogue, sans quête de pas (HealthKit
        // refusé). Les drapeaux de programme sont hors sujet ici : ce test tire pour
        // `Date.now`, donc selon la semaine réelle son triplet peut n'en contenir aucun
        // même avec le filtre cassé. Ce sont les deux tests à quinze semaines fixes qui
        // les tiennent (chercher `quetesTireesSurQuinzeSemaines`).
        let catalog = try Catalogs.quests()
        let catalogByID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        XCTAssertEqual(state.activeQuestIDs.count, 3)
        for id in state.activeQuestIDs {
            let quest = try XCTUnwrap(catalogByID[id], "id de quête inconnu : \(id)")
            XCTAssertFalse(quest.requiresSteps, id)
        }

        // Garde hebdo remis à zéro ; l'HISTORIQUE all-time n'est PAS retouché
        // (les complétées y sont déjà — pas de ré-archivage, contrat GameService).
        XCTAssertTrue(state.completedThisWeekQuestIDs.isEmpty)
        XCTAssertEqual(state.completedQuestIDs, ["weigh_in_1"])

        // Progression repartie de zéro : uniquement les nouvelles quêtes, toutes à 0
        // (aucune donnée cette semaine).
        XCTAssertTrue(Set(state.questProgress.keys).isSubset(of: Set(state.activeQuestIDs)))
        XCTAssertTrue(state.questProgress.values.allSatisfy { $0 == 0 })

        XCTAssertEqual(state.totalXP, 0)
    }

    /// Ce que le test précédent ne prouve pas : que `DayCloser` passe bien les DEUX
    /// interrupteurs de programme à `weeklyDraw`. Il tire pour la seule semaine courante,
    /// et écrire `postureAvailable: true` / `muscuAvailable: true` en dur dans le closer
    /// laissait toute la suite verte — mutation faite, le trou était réel, et il
    /// préexistait à la 1.14 pour la posture.
    ///
    /// Ce qui le comble : QUINZE semaines FIXES, balayées par
    /// `quetesTireesSurQuinzeSemaines`. Des dates figées plutôt que `Date.now` — une
    /// garde ne doit pas dépendre du jour où la suite tourne.
    ///
    /// Les deux drapeaux sont INJECTÉS, plus lus sur les singletons : ce test dit ce que
    /// fait le closer quand on lui passe `false`, pas ce que contiennent les
    /// `UserDefaults` du hôte.
    func testLeRenouvellementNeTirePasDeQueteAProgrammeEteint() async throws {
        let tirages = try await quetesTireesSurQuinzeSemaines(postureAvailable: false,
                                                              muscuAvailable: false)
        for (weekID, quetes) in tirages {
            XCTAssertEqual(quetes.count, 3, weekID)
            for quete in quetes {
                XCTAssertFalse(quete.requiresPosture, "\(weekID) : \(quete.id)")
                XCTAssertFalse(quete.requiresMuscu, "\(weekID) : \(quete.id)")
                XCTAssertFalse(quete.requiresSteps, "\(weekID) : \(quete.id)")
            }
        }
    }

    /// La moitié qui décide si le câblage sert à quelque chose : le test ci-dessus
    /// protège Michaël de recevoir des quêtes qu'il ne peut pas faire, celui-ci protège
    /// Marion de ne JAMAIS en recevoir. Un closer qui cesserait de lire les interrupteurs
    /// laisserait les six quêtes à drapeau hors de tout tirage du lundi, en silence — et
    /// aucun test ne le dirait, `muscuAvailable: false` en dur passait au vert.
    ///
    /// Un drapeau à la fois : allumer la posture ne doit pas faire sortir de quête muscu,
    /// et réciproquement. Le pool éligible passe alors de 15 quêtes (25 moins les 4 de pas
    /// moins les 6 à drapeau) à 18, dont 3 portent le drapeau allumé.
    ///
    /// « Au moins un tirage » n'est pas une nécessité mathématique, c'est une propriété
    /// MESURÉE de ces graines-là : six des quinze semaines sortent une quête à drapeau,
    /// pour la posture comme pour la muscu, et la première est la première du balayage
    /// (2026-W12). La marge est confortable mais elle vaut pour ce catalogue et ces quinze
    /// dates — un futur ajout de quêtes la déplacera, et c'est le genre d'échec qui se lit
    /// tout seul.
    func testLeRenouvellementTireLesQuetesAProgrammeQuandIlEstAllume() async throws {
        let avecPosture = try await quetesTireesSurQuinzeSemaines(postureAvailable: true,
                                                                  muscuAvailable: false)
        XCTAssertTrue(avecPosture.contains { $0.quetes.contains(where: \.requiresPosture) },
                      "aucune quête posture sur quinze semaines, programme allumé")
        XCTAssertFalse(avecPosture.contains { $0.quetes.contains(where: \.requiresMuscu) },
                       "la posture allumée a fait sortir une quête muscu")

        let avecMuscu = try await quetesTireesSurQuinzeSemaines(postureAvailable: false,
                                                                muscuAvailable: true)
        XCTAssertTrue(avecMuscu.contains { $0.quetes.contains(where: \.requiresMuscu) },
                      "aucune quête muscu sur quinze semaines, programme allumé")
        XCTAssertFalse(avecMuscu.contains { $0.quetes.contains(where: \.requiresPosture) },
                       "la muscu allumée a fait sortir une quête posture")
    }

    /// Quinze renouvellements hebdo consécutifs, pilotés par les dates : pour chacun, le
    /// weekID est vérifié et les quêtes tirées sont résolues sur le catalogue.
    ///
    /// `questWeekID` périmé force le rollover ; `lastClosedDay` à la veille saute tout le
    /// bloc de clôture, si bien que seul le tirage s'exerce. HealthKit refusé, donc jamais
    /// de quête de pas : c'est ce qui laisse de la place aux quêtes à drapeau.
    private func quetesTireesSurQuinzeSemaines(
        postureAvailable: Bool, muscuAvailable: Bool
    ) async throws -> [(weekID: String, quetes: [Quest])] {
        let catalogByID = Dictionary(uniqueKeysWithValues: try Catalogs.quests().map { ($0.id, $0) })
        let service = makeService(steps: FakeStepsService(authorized: false))
        let base = try XCTUnwrap(GameService.calendar.date(from: DateComponents(year: 2026, month: 3, day: 18)))

        var tirages: [(weekID: String, quetes: [Quest])] = []
        for semaine in 0..<15 {
            let jour = try XCTUnwrap(GameService.calendar.date(byAdding: .weekOfYear, value: -semaine, to: base))
            state.questWeekID = "2000-W1"
            state.lastClosedDay = try XCTUnwrap(GameService.calendar.date(byAdding: .day, value: -1, to: jour))
            try context.save()

            await service.closeOpenDays(today: jour,
                                        postureAvailable: postureAvailable,
                                        muscuAvailable: muscuAvailable)

            let weekID = QuestEngine.weekID(for: jour, calendar: GameService.calendar)
            XCTAssertEqual(state.questWeekID, weekID)
            let quetes = try state.activeQuestIDs.map {
                try XCTUnwrap(catalogByID[$0], "id de quête inconnu : \($0)")
            }
            tirages.append((weekID, quetes))
        }
        return tirages
    }

    // MARK: - Erreur HealthKit

    func testStepsQueryErrorSkipsWholeClosingRun() async throws {
        // Journée qui AURAIT été récompensée si la requête de pas avait réussi.
        insertMeal(on: day1, kcal: 650, slot: .lunch)
        insertMeal(on: day1, kcal: 650, slot: .dinner)
        try context.save()

        // HealthKit "disponible" mais la requête échoue (nil ≠ [:]) : rien ne doit
        // être figé à 0 pas — toute la passe est abandonnée et sera retentée.
        let service = makeService(steps: FakeStepsService(
            stepsByDay: [day1: 9000],
            failing: true
        ))
        await service.closeOpenDays(today: today)

        XCTAssertNil(state.lastClosedDay)
        XCTAssertTrue(try fetchDayLogs().isEmpty)
        XCTAssertEqual(state.totalXP, 0)

        // La requête redevient saine → le rattrapage complet passe.
        (service.stepsService as? FakeStepsService)?.failing = false
        await service.closeOpenDays(today: today)
        XCTAssertEqual(state.lastClosedDay, yesterday)
        XCTAssertEqual(try fetchDayLogs().first?.xpEarned, 90)
    }

    // MARK: - Dépense du jour (spec v1.14 §5.4/§5.5)

    /// 8 000 pas à 90 kg = 411 kcal, au-dessus de l'objectif de 350 (4 × 90 arrondi
    /// au pas de 50) : la dépense est enregistrée ET l'objectif marqué atteint.
    func testLaClotureEnregistreLaDepenseDuJour() async throws {
        let service = makeService(steps: FakeStepsService(stepsByDay: [day1: 8000, day2: 2000]))
        await service.closeOpenDays(today: today)

        let log = try fetchDayLog(day1)
        XCTAssertEqual(log.kcalBurned, 411)
        XCTAssertEqual(log.burnTarget, 350) // cible GELÉE, comme kcalTarget
        XCTAssertTrue(log.burnTargetReached)
    }

    /// 2 000 pas = 103 kcal, sous l'objectif : rien n'est marqué, et surtout rien
    /// n'est reproché.
    func testObjectifDeDepenseNonAtteintResteFaux() async throws {
        let service = makeService(steps: FakeStepsService(stepsByDay: [day1: 8000, day2: 2000]))
        await service.closeOpenDays(today: today)

        let log = try fetchDayLog(day2)
        XCTAssertEqual(log.kcalBurned, 103)
        XCTAssertFalse(log.burnTargetReached)
    }

    /// Les validations sport du jour s'ajoutent aux pas, SAUF celles qui sont déjà
    /// dans le podomètre : 411 (8 000 pas) + 90 (yoga) + 0 (marche, doublon).
    func testLaDepenseAjouteLeSportSansDoublerLaMarche() async throws {
        insertActivity(on: day1, kind: .activity, refID: "yoga", kcal: 90)
        insertActivity(on: day1, kind: .activity, refID: "walk", kcal: 100)
        try context.save()

        let service = makeService(steps: FakeStepsService(stepsByDay: [day1: 8000]))
        await service.closeOpenDays(today: today)

        XCTAssertEqual(try fetchDayLog(day1).kcalBurned, 501)
    }

    /// HealthKit refusé : la dépense ne tombe pas à zéro, elle vaut le sport validé —
    /// marche comprise, puisque aucun podomètre ne peut la compter deux fois.
    func testSansPodometreLaMarcheValideeCompteQuandMeme() async throws {
        insertActivity(on: day1, kind: .activity, refID: "walk", kcal: 100)
        try context.save()

        let service = makeService(steps: FakeStepsService(authorized: false))
        await service.closeOpenDays(today: today)

        let log = try fetchDayLog(day1)
        XCTAssertEqual(log.kcalBurned, 100)
        XCTAssertFalse(log.burnTargetReached)
    }

    /// Tomber PILE sur l'objectif, c'est l'avoir atteint — le cas le plus frustrant
    /// à perdre pour un kcal, et le seul que `>` au lieu de `>=` ferait disparaître.
    func testTomberPileSurLObjectifCompteCommeAtteint() async throws {
        profile.dailyBurnTarget = 411 // exactement la dépense de 8 000 pas à 90 kg
        try context.save()

        let service = makeService(steps: FakeStepsService(stepsByDay: [day1: 8000]))
        await service.closeOpenDays(today: today)

        let log = try fetchDayLog(day1)
        XCTAssertEqual(log.kcalBurned, 411)
        XCTAssertTrue(log.burnTargetReached)
    }

    /// L'objectif réglé dans les Réglages fait FOI : à 600, une journée de 8 000 pas
    /// ne l'atteint pas, alors que le calcul automatique (350 à 90 kg) l'aurait dit
    /// atteint. La clôture doit lire le profil, pas recalculer depuis le poids.
    func testLObjectifRegleDansLesReglagesLEmporteSurLeCalcul() async throws {
        profile.dailyBurnTarget = 600
        try context.save()

        let service = makeService(steps: FakeStepsService(stepsByDay: [day1: 8000]))
        await service.closeOpenDays(today: today)

        let log = try fetchDayLog(day1)
        XCTAssertEqual(log.kcalBurned, 411)
        XCTAssertEqual(log.burnTarget, 600) // la cible gelée est bien celle du profil
        XCTAssertFalse(log.burnTargetReached)
    }

    /// Dépense et objectif suivent le poids COURANT, pas celui de l'onboarding :
    /// après une pesée à 60 kg, 8 000 pas ne valent plus 411 kcal mais 274, et
    /// l'objectif automatique descend de 350 à 250 — donc atteint.
    func testLaDepenseSuitLaDernierePeseeEtNonLePoidsInitial() async throws {
        context.insert(WeightEntry(date: day3, weightKg: 60))
        try context.save()

        let service = makeService(steps: FakeStepsService(stepsByDay: [day1: 8000]))
        await service.closeOpenDays(today: today)

        let log = try fetchDayLog(day1)
        XCTAssertEqual(log.kcalBurned, 274)  // 411 avec le poids initial de 90 kg
        XCTAssertEqual(log.burnTarget, 250)  // 350 avec le poids initial
        XCTAssertTrue(log.burnTargetReached) // 274 ≥ 250, alors que 274 < 350
    }

    /// Une séance de programme n'est pas un total opaque : elle est REDÉCOMPOSÉE par
    /// ses étapes, ce qui n'est possible que si la table des séances contient aussi
    /// les catalogues posture et muscu, et pas seulement `sessions.json`.
    ///
    /// Les 500 kcal de l'entrée sont ARTIFICIELLES — en production, le total stocké est
    /// calculé depuis les mêmes étapes et vaut donc déjà 16. C'est justement pourquoi il
    /// faut les fausser : aucune séance posture ou muscu n'ayant d'étape marchée
    /// aujourd'hui, décomposition et repli sur le total stocké donnent le même chiffre,
    /// et un test « honnête » passerait aussi bien sans la fusion des catalogues. L'écart
    /// est le seul moyen de voir LEQUEL des deux chemins a servi.
    func testUneSeancePostureEstRedecomposeeParSesEtapes() async throws {
        insertActivity(on: day1, kind: .posture, refID: "posture_open", kcal: 500)
        try context.save()

        let service = makeService(steps: FakeStepsService(stepsByDay: [day1: 8000]))
        await service.closeOpenDays(today: today)

        // 411 (8 000 pas) + 16 (2 + 3 + 3 min à 2 kcal/min), et non le total stocké.
        XCTAssertEqual(try fetchDayLog(day1).kcalBurned, 427)
    }

    // MARK: - Idempotence

    func testRunningTwiceDoesNotDoubleAward() async throws {
        insertMeal(on: day1, kcal: 650, slot: .lunch)
        insertMeal(on: day1, kcal: 650, slot: .dinner)
        try context.save()

        let service = makeService(steps: FakeStepsService(stepsByDay: [day1: 9000]))
        await service.closeOpenDays(today: today)

        let xpAfterFirstRun = state.totalXP
        let lastClosedAfterFirstRun = state.lastClosedDay

        await service.closeOpenDays(today: today)

        XCTAssertEqual(state.totalXP, xpAfterFirstRun)
        XCTAssertEqual(state.lastClosedDay, lastClosedAfterFirstRun)

        let logs = try fetchDayLogs()
        XCTAssertEqual(logs.count, 3) // pas de DayLog dupliqué
        XCTAssertEqual(logs[0].xpEarned, 90) // pas de double attribution sur J-3
    }
}
