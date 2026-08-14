// NivelTests/GameServiceTests.swift
import XCTest
import SwiftData
import NivelCore
@testable import Nivel

@MainActor
final class GameServiceTests: XCTestCase {
    private var context: ModelContext!
    private var service: GameService!
    private var catalog: FoodCatalog!

    /// Pâtes à la composition par défaut du catalogue (spec v1.10 §4.1/§4.5) : le
    /// remplaçant du `Dish` v1. Somme à 651 kcal (garde-fou `FoodCatalogTests`),
    /// PAS 650 : les tests qui en dépendent calculent l'attendu via
    /// `MealEstimator.kcal` sur les lignes réelles, jamais un nombre recopié à la
    /// main — le forfait rond de la v1 a disparu avec `Dish`.
    private var pastaLines: [MealLine] {
        [catalog.line(for: catalog.byID["pasta"]!)]
    }

    /// Pâtes copieux + 2 bières + 1 barre chocolatée : équivalent lignes du fixture
    /// v1 "pâtes copieux + 2 bières + dessert gourmand" (`dessert_rich` n'existe
    /// plus ; `choco_bar`, tagué "richDessert", en est le remplaçant le plus proche).
    private func heartyPastaPlusExtras() -> [MealLine] {
        let hearty = MealPortion.hearty.applied(to: catalog.compositions["pasta"]!)
        return [
            .composed(itemID: "pasta", components: hearty),
            .simple(MealComponent(itemID: "beer_half", grams: 250)),
            .simple(MealComponent(itemID: "beer_half", grams: 250)),
            .simple(MealComponent(itemID: "choco_bar", grams: 45)),
        ]
    }

    private func expectedKcal(_ lines: [MealLine]) -> Int {
        MealEstimator.kcal(lines: lines, kcalPer100g: catalog.kcalPer100g)
    }

    override func setUp() async throws {
        let schema = Schema([
            UserProfile.self, MealEntry.self, WeightEntry.self,
            DayLog.self, GamificationState.self, ActivityEntry.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)

        let profile = UserProfile(
            name: "Michaël",
            sex: .male,
            birthDate: Date(timeIntervalSince1970: 0),
            heightCm: 180,
            initialWeightKg: 90,
            activity: .moderate,
            dailyCalorieTarget: 2000
        )
        context.insert(profile)
        context.insert(GamificationState())
        try context.save()

        service = GameService(modelContext: context, stepsService: FakeStepsService(authorized: false),
                              widgetDefaults: nil)
        catalog = try FoodCatalog.load()
    }

    /// AVANT : "pâtes copieux (650×1,3=845) + 2 bières (300) + dessert gourmand
    /// (300) = 1445 kcal", un nombre recopié du forfait `Dish`/`Extra` v1.
    /// APRÈS : mêmes lignes en intention (pâtes copieux, 2 bières, une barre
    /// chocolatée), kcal attendu recalculé via `MealEstimator.kcal` sur CES lignes
    /// (la composition par défaut des pâtes n'est plus un forfait rond) ET
    /// `entry.lines` est comparé aux lignes loggées terme à terme : on vérifie le
    /// CONTENU exact, pas seulement le total kcal.
    func testLogMealEstimatesKcalAwardsXPAndUpdatesDayLog() async throws {
        let dinnerLines = heartyPastaPlusExtras()
        let first = await service.logMeal(slot: .dinner, lines: dinnerLines)
        XCTAssertEqual(first.lines, dinnerLines)
        XCTAssertEqual(first.estimatedKcal, expectedKcal(dinnerLines))
        XCTAssertEqual(first.xpAwarded, 20)

        let second = await service.logMeal(slot: .lunch, lines: pastaLines)
        XCTAssertEqual(second.lines, pastaLines)
        XCTAssertEqual(second.estimatedKcal, expectedKcal(pastaLines))
        XCTAssertEqual(second.xpAwarded, 20)

        let dayLogs = try context.fetch(FetchDescriptor<DayLog>())
        XCTAssertEqual(dayLogs.count, 1)
        XCTAssertEqual(dayLogs.first?.kcalEaten, expectedKcal(dinnerLines) + expectedKcal(pastaLines))
        XCTAssertEqual(dayLogs.first?.kcalTarget, 2000)

        // XP total = 2 × 20 (repas) + 50 (badge "Premier repas") — inchangé.
        let state = try XCTUnwrap(try context.fetch(FetchDescriptor<GamificationState>()).first)
        XCTAssertEqual(state.totalXP, 90)
        XCTAssertNotNil(state.badgeUnlocks["first_meal"])
        XCTAssertTrue(service.pendingCelebrations.contains {
            if case .badge(let badge) = $0 { badge.id == "first_meal" } else { false }
        })
    }

    /// AVANT/APRÈS : inchangé dans l'intention (plafond 4 repas/jour, robuste aux
    /// relances) — seule la forme du repas répété change (lignes au lieu de
    /// dish/portion), le plafond lui-même ne dépend pas du contenu.
    func testFifthMealOfTheDayGetsNoXP() async throws {
        var awarded: [Int] = []
        for _ in 1...5 {
            let entry = await service.logMeal(slot: .snack, lines: pastaLines)
            awarded.append(entry.xpAwarded)
        }
        XCTAssertEqual(awarded, [20, 20, 20, 20, 0])

        // Le plafond est dérivé des MealEntry persistés → il tient aussi après "relance"
        // (nouvelle instance de service sur le même store).
        let restarted = GameService(modelContext: context, stepsService: FakeStepsService(authorized: false),
                                    widgetDefaults: nil)
        let sixth = await restarted.logMeal(slot: .snack, lines: pastaLines)
        XCTAssertEqual(sixth.xpAwarded, 0)
    }

    /// AVANT/APRÈS : inchangé — ce test ne loggue aucun repas (pesée seulement),
    /// aucun portage nécessaire au-delà du retrait des fixtures Dish/Extra du setUp.
    func testRedrawnQuestReawardsXPInALaterWeek() async throws {
        let state = try XCTUnwrap(try context.fetch(FetchDescriptor<GamificationState>()).first)
        state.questWeekID = QuestEngine.weekID(for: .now, calendar: GameService.calendar)
        state.activeQuestIDs = ["weigh_in_1"] // "Pèse-toi une fois" (target 1)
        try context.save()

        // Semaine 1 : la pesée complète la quête → +150 XP, une seule fois.
        await service.logWeight(kg: 90.0)
        XCTAssertEqual(state.completedQuestIDs, ["weigh_in_1"])
        XCTAssertEqual(state.completedThisWeekQuestIDs, ["weigh_in_1"])
        let xpAfterFirstCompletion = state.totalXP
        XCTAssertEqual(service.pendingCelebrations.count(where: { $0.id == "quest-weigh_in_1" }), 1)

        // Re-refresh dans la même semaine : pas de re-récompense.
        await service.refreshQuestProgress()
        XCTAssertEqual(state.totalXP, xpAfterFirstCompletion)

        // Simule le renouvellement du lundi (Task 18) qui retire la MÊME quête :
        // reset du garde hebdo + progression ; l'historique all-time est conservé.
        state.completedThisWeekQuestIDs = []
        state.questProgress = [:]
        try context.save()
        // L'utilisateur a vu la célébration de la semaine 1 (la file anti-doublon
        // de raise() ignorerait sinon une célébration identique encore en attente).
        service.pendingCelebrations = []

        // "Semaine 2" : la quête déjà dans l'historique doit re-récompenser.
        await service.refreshQuestProgress()
        XCTAssertEqual(state.totalXP, xpAfterFirstCompletion + 150)
        XCTAssertEqual(state.completedQuestIDs, ["weigh_in_1", "weigh_in_1"])
        XCTAssertEqual(state.completedThisWeekQuestIDs, ["weigh_in_1"])
        XCTAssertEqual(service.pendingCelebrations.count(where: { $0.id == "quest-weigh_in_1" }), 1)

        // L'historique (doublons compris) alimente le compteur de badges.
        XCTAssertEqual(service.badgeStats().questsCompleted, 2)
    }

    /// AVANT : édition dish/portion/extras, kcal 650→1445 recalculé, `entry.extras`
    /// relu contre `["beer": 2, "dessert_rich": 1]`. APRÈS : édition sur les lignes,
    /// kcal recalculé pareillement (valeurs recomputées via `MealEstimator.kcal`,
    /// plus rondes), et `entry.lines` relu comparé terme à terme aux lignes
    /// enregistrées — l'équivalent exact du contenu, pas juste le total.
    func testUpdateMealRecomputesKcalWithoutAwardingXP() async throws {
        // Log initial : pâtes normal, +20 XP (+50 badge "Premier repas").
        let entry = await service.logMeal(slot: .dinner, lines: pastaLines)
        let state = try XCTUnwrap(try context.fetch(FetchDescriptor<GamificationState>()).first)
        let xpAfterLog = state.totalXP

        // Édition : copieux + 2 bières + 1 barre chocolatée.
        let updatedLines = heartyPastaPlusExtras()
        await service.updateMeal(entry: entry, slot: .dinner, lines: updatedLines)

        XCTAssertEqual(entry.estimatedKcal, expectedKcal(updatedLines))
        XCTAssertEqual(entry.lines, updatedLines)
        // PAS de nouvel XP : ni sur l'entrée, ni au total.
        XCTAssertEqual(entry.xpAwarded, 20)
        XCTAssertEqual(state.totalXP, xpAfterLog)

        // Le DayLog reflète le delta (pâtes normal → pâtes copieux + extras), pas un cumul.
        let dayLog = try XCTUnwrap(try context.fetch(FetchDescriptor<DayLog>()).first)
        XCTAssertEqual(dayLog.kcalEaten, expectedKcal(updatedLines))

        // Une seule entrée : l'édition ne duplique pas.
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MealEntry>()), 1)
    }

    /// AVANT : "650 (déjeuner) + 455 (dîner léger : 650×0,7)", nombres recopiés du
    /// forfait v1. APRÈS : mêmes deux repas (pâtes normal / pâtes léger) en lignes,
    /// kcal attendu recalculé via `MealEstimator.kcal` sur les grammes réels après
    /// application de `MealPortion.light`.
    func testDeleteMealSubtractsKcalAndKeepsXP() async throws {
        let lunchLines = pastaLines
        let dinnerLines: [MealLine] = [
            .composed(itemID: "pasta",
                     components: MealPortion.light.applied(to: catalog.compositions["pasta"]!))
        ]
        let lunch = await service.logMeal(slot: .lunch, lines: lunchLines)
        await service.logMeal(slot: .dinner, lines: dinnerLines)
        let state = try XCTUnwrap(try context.fetch(FetchDescriptor<GamificationState>()).first)
        let xpBefore = state.totalXP

        await service.deleteMeal(entry: lunch)

        // Le DayLog perd les kcal du repas supprimé…
        let dayLog = try XCTUnwrap(try context.fetch(FetchDescriptor<DayLog>()).first)
        XCTAssertEqual(dayLog.kcalEaten, expectedKcal(dinnerLines))
        // …mais l'XP est conservé (jamais de retrait, spec §7.1).
        XCTAssertEqual(state.totalXP, xpBefore)

        let remaining = try context.fetch(FetchDescriptor<MealEntry>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.slot, .dinner)
    }

    /// AVANT/APRÈS : inchangé — aucun contenu de repas en jeu.
    func testConsumeNextCelebrationDequeuesInOrderThenEmpties() async throws {
        let badge = try XCTUnwrap(try Catalogs.badges().first)
        let quest = try XCTUnwrap(service.questCatalog.first)

        // File vide → nil (et pas de crash).
        XCTAssertNil(service.consumeNextCelebration())

        service.pendingCelebrations = [.levelUp(2), .badge(badge), .quest(quest)]

        // Dépilage FIFO : l'ordre de levée est l'ordre d'affichage.
        XCTAssertEqual(service.consumeNextCelebration(), .levelUp(2))
        XCTAssertEqual(service.consumeNextCelebration(), .badge(badge))
        XCTAssertEqual(service.pendingCelebrations, [.quest(quest)])
        XCTAssertEqual(service.consumeNextCelebration(), .quest(quest))

        // File vidée → nil à nouveau.
        XCTAssertTrue(service.pendingCelebrations.isEmpty)
        XCTAssertNil(service.consumeNextCelebration())
    }

    /// AVANT/APRÈS : inchangé — aucun repas en jeu.
    func testWeighInXPIsCappedOncePerDay() async throws {
        let firstXP = await service.logWeight(kg: 90.5)
        XCTAssertEqual(firstXP, 30)

        let secondXP = await service.logWeight(kg: 90.3)
        XCTAssertEqual(secondXP, 0)

        let entries = try context.fetch(FetchDescriptor<WeightEntry>())
        XCTAssertEqual(entries.count, 2)

        // XP total = 30 (pesée) + 50 (badge "Première pesée").
        let state = try XCTUnwrap(try context.fetch(FetchDescriptor<GamificationState>()).first)
        XCTAssertEqual(state.totalXP, 80)
        XCTAssertNotNil(state.badgeUnlocks["first_weigh"])
    }

    // MARK: - Poids courant (spec v1.14 §5.3) : chemin unique partagé par
    // SettingsView, ProgressScreen, et bientôt DayCloser (Task 5) et l'objectif de
    // dépense affiché à l'accueil (Task 6).

    /// Aucune pesée encore loggée (juste après l'onboarding, en théorie jamais vrai
    /// en pratique puisqu'il en insère une) → repli sur `initialWeightKg`.
    func testCurrentWeightKgSansPeseeReplieSurLePoidsInitial() {
        XCTAssertEqual(service.currentWeightKg(), 90) // initialWeightKg posé au setUp
    }

    /// Plusieurs pesées : la plus RÉCENTE PAR DATE gagne, pas la dernière insérée
    /// (elles peuvent diverger, par ex. une correction a posteriori).
    func testCurrentWeightKgRetientLaPeseeLaPlusRecenteParDate() async throws {
        let later = Date(timeIntervalSince1970: 2_000_000)
        let earlier = Date(timeIntervalSince1970: 1_000_000)
        await service.logWeight(kg: 91, date: later)
        await service.logWeight(kg: 89, date: earlier) // insérée en second, datée AVANT
        XCTAssertEqual(service.currentWeightKg(), 91)
    }

    // MARK: - Objectif de dépense (spec v1.14 §5.3) : sentinelle 0 = jamais réglé

    /// Un profil migré (ou tout juste créé — ni l'un ni l'autre ne pose 0
    /// explicitement, c'est le défaut de déclaration qui le fait) résout son
    /// objectif de dépense depuis le poids courant. Attendu écrit EN DUR (350, et
    /// non `CalorieCalculator.dailyBurnTarget(weightKg: 90)`) : comparer aux deux
    /// implémentations de la même formule ne prouverait rien si la formule
    /// elle-même devenait fausse.
    func testBurnTargetSansReglageEstCalculeDepuisLePoids() throws {
        let profile = try XCTUnwrap(try context.fetch(FetchDescriptor<UserProfile>()).first)
        XCTAssertEqual(profile.dailyBurnTarget, 0)
        XCTAssertEqual(profile.burnTarget(currentWeightKg: 90), 350)
    }

    /// Une valeur réglée explicitement l'emporte sur le calcul, même si le poids
    /// utilisé au calcul donnerait un résultat différent.
    func testBurnTargetRegleExplicitementIgnoreLePoids() throws {
        let profile = try XCTUnwrap(try context.fetch(FetchDescriptor<UserProfile>()).first)
        profile.dailyBurnTarget = 500
        XCTAssertEqual(profile.burnTarget(currentWeightKg: 40), 500) // 40 kg calculerait 200
    }

    /// La composition complète que `SettingsView`, et bientôt `DayCloser` (Task 5)
    /// et l'anneau d'accueil (Task 6), utilisent : `GameService.burnTarget()`
    /// enchaîne le fetch du poids courant (`currentWeightKg()`) et la résolution du
    /// sentinelle (`UserProfile.burnTarget(currentWeightKg:)`). Poids réglé à 110 kg
    /// (pas les 90 kg d'`initialWeightKg` posés au setUp) sur un profil jamais réglé
    /// → 450, et non 350 : seul ce test fait se rencontrer les deux moitiés.
    func testGameServiceBurnTargetComposeLeFetchDuPoidsEtLaResolutionDuSentinelle() async throws {
        await service.logWeight(kg: 110)
        XCTAssertEqual(service.burnTarget(), 450)
    }

    // MARK: - Dépense du jour (spec v1.14 §5.4) : le câblage de BurnCalculator

    /// `burnKcal` sans `weightKg` prend le poids COURANT. Ce défaut est la moitié
    /// symétrique de `burnTarget()` : il évite à l'anneau d'accueil (Task 6) d'avoir à
    /// réapparier poids et calcul lui-même, alors que `profiles.first?.initialWeightKg`
    /// est à un point de distance dans une vue et donnerait un chiffre juste le jour de
    /// l'onboarding, puis faux pour toujours.
    func testBurnKcalSansPoidsUtiliseLePoidsCourant() async throws {
        await service.logWeight(kg: 60) // initialWeightKg vaut 90 au setUp
        // 8 000 pas : 274 kcal à 60 kg, contre 411 kcal à 90 kg.
        XCTAssertEqual(service.burnKcal(on: .now, steps: .measured(8000)), 274)
    }

    /// La table des séances passée à `BurnCalculator` fusionne les TROIS catalogues.
    /// Test structurel, et non de calcul, à dessein : aucune séance posture ou muscu
    /// n'ayant aujourd'hui d'étape marchée, en oublier un ne change AUCUN chiffre —
    /// jusqu'au jour où une séance de programme gagnerait un échauffement marché, qui
    /// serait alors compté deux fois, en silence. C'est ici que ça se voit.
    func testLaTableDesSeancesCouvreLesTroisCatalogues() {
        XCTAssertNotNil(service.sessionsByID["fresh_air"])    // sessions.json
        XCTAssertNotNil(service.sessionsByID["posture_open"]) // posture-sessions.json
        XCTAssertNotNil(service.sessionsByID["muscu_core"])   // muscu-sessions.json
    }

    // MARK: - Quêtes qui lisent le contenu des repas (correction spec §7.1)

    /// NOUVEAU (pas un portage) : preuve que la quête lit les TAGS du catalogue,
    /// pas d'anciens ids figés en dur. Avant le correctif de ce lot, la garde
    /// interne était `Set(["beer", "wine"])` : ces ids n'existent plus depuis le
    /// basculement sur `foods.json` (`beer` → `beer_half`/`beer_pint`), donc plus
    /// aucun repas ne pouvait jamais matcher et la quête restait TOUJOURS
    /// satisfaite, silencieusement. Semaine fixe (mercredi/jeudi de la même semaine
    /// ISO, comme `WidgetSnapshotBuildingTests`) : aucun flake au bord d'une semaine.
    func testDaysWithoutAlcoholQuestReadsTagsNotOldIDs() async throws {
        let day1 = try XCTUnwrap(GameService.calendar.date(from: DateComponents(year: 2026, month: 3, day: 18)))
        let day2 = try XCTUnwrap(GameService.calendar.date(from: DateComponents(year: 2026, month: 3, day: 19)))
        let state = try XCTUnwrap(try context.fetch(FetchDescriptor<GamificationState>()).first)
        state.questWeekID = QuestEngine.weekID(for: day1, calendar: GameService.calendar)
        state.activeQuestIDs = ["no_alcohol_2"]
        try context.save()

        // Jour 1 : un demi (tagué "alcohol") → ne compte PAS comme sans alcool. L'id
        // EST "beer_half", PAS "beer" (l'id v1) : c'est justement le cas qui aurait
        // échappé à l'ancienne garde `Set(["beer", "wine"])" et qu'un test avec
        // "wine" (id inchangé depuis la v1) n'aurait pas détecté.
        await service.logMeal(slot: .dinner, lines: [.simple(MealComponent(itemID: "beer_half", grams: 250))],
                              date: day1)
        // Jour 2 : pâtes seules, aucun alcool → compte.
        await service.logMeal(slot: .lunch, lines: pastaLines, date: day2)

        await service.refreshQuestProgress(now: day2)
        XCTAssertEqual(state.questProgress["no_alcohol_2"], 1,
                       "un seul des deux jours ne contient pas d'alcool")
    }

    /// NOUVEAU, miroir du précédent pour "richDessert". Avant le correctif, la
    /// garde était `$0.extras["dessert_rich"] ?? 0`, un id disparu du catalogue
    /// (les desserts sont devenus des encas) : la quête était donc, là aussi,
    /// toujours satisfaite.
    func testLightDessertDaysQuestReadsTagsNotOldIDs() async throws {
        let day1 = try XCTUnwrap(GameService.calendar.date(from: DateComponents(year: 2026, month: 3, day: 18)))
        let day2 = try XCTUnwrap(GameService.calendar.date(from: DateComponents(year: 2026, month: 3, day: 19)))
        let state = try XCTUnwrap(try context.fetch(FetchDescriptor<GamificationState>()).first)
        state.questWeekID = QuestEngine.weekID(for: day1, calendar: GameService.calendar)
        state.activeQuestIDs = ["light_dessert_3"]
        try context.save()

        // Jour 1 : une barre chocolatée (taguée "richDessert") → ne compte PAS.
        await service.logMeal(slot: .snack, lines: [.simple(MealComponent(itemID: "choco_bar", grams: 45))],
                              date: day1)
        // Jour 2 : un fruit (pas "richDessert") → compte.
        await service.logMeal(slot: .snack, lines: [.simple(MealComponent(itemID: "fruit", grams: 150))],
                              date: day2)

        await service.refreshQuestProgress(now: day2)
        XCTAssertEqual(state.questProgress["light_dessert_3"], 1,
                       "un seul des deux jours n'a pas de dessert gourmand")
    }
}
