// App/Services/GameService.swift
import Foundation
import SwiftData
import NivelCore

/// Événement UI à célébrer (level-up plein écran, badge, quête) — consommé par les vues.
enum Celebration: Equatable, Identifiable {
    case levelUp(Int)
    case badge(Badge)
    case quest(Quest)

    var id: String {
        switch self {
        case .levelUp(let level): "levelUp-\(level)"
        case .badge(let badge): "badge-\(badge.id)"
        case .quest(let quest): "quest-\(quest.id)"
        }
    }
}

/// Quête active + progression courante, telle que consommée par l'accueil (Task 13)
/// et l'écran Quêtes (Task 16).
struct ActiveQuestStatus: Identifiable {
    let quest: Quest
    let progress: Int
    /// Complétée CETTE semaine (garde `completedThisWeekQuestIDs`).
    let isCompleted: Bool

    var id: String { quest.id }
    /// Avancement 0…1 (les targets du catalogue sont ≥ 1 ; garde anti-division par zéro).
    var fraction: Double { min(1, Double(progress) / Double(max(1, quest.target))) }
}

/// Façade unique consommée par les vues : log de repas/pesée, XP, quêtes, badges,
/// messages de Nivelito. Toute la logique pure vit dans NivelCore ; ici on orchestre
/// SwiftData + StepsProviding.
@Observable @MainActor
final class GameService {
    // `internal` (et non `private`) : partagé avec les extensions Sport et clôture
    // des journées, rangées dans leurs propres fichiers (GameService+Sport.swift,
    // DayCloser.swift) — même type, autre fichier.
    let modelContext: ModelContext
    let stepsService: StepsProviding

    /// Catalogues embarqués (chargés une fois ; vides si le bundle est corrompu — jamais de crash).
    let questCatalog: [Quest]
    private let badgeCatalog: [Badge]
    private let messageBank: MessageBank?
    let activityCatalog: [Activity]
    let sessionCatalog: [ActivitySession]
    /// Index id → Activity (kcal des séances, libellés des vues).
    let activitiesByID: [String: Activity]

    /// File des célébrations en attente d'affichage (les vues dépilent).
    var pendingCelebrations: [Celebration] = []

    /// Garde anti-réentrance de `closeOpenDays()` (DayCloser.swift) : `onAppear` et
    /// `scenePhase == .active` peuvent se déclencher en rafale au lancement.
    var isClosingDays = false

    /// XP attribué au repas qui VIENT d'être loggé (peu importe l'onglet d'origine),
    /// nil sinon — consommé par l'accueil pour la bulle `afterMealLog`, dont certains
    /// messages contiennent "+{value} XP" (spec §4.2). 0 = repas loggé mais XP plafonné
    /// (5ᵉ repas du jour) : l'accueil n'affiche alors PAS de bulle de récompense.
    var lastMealXPAwarded: Int?

    /// XP attribué à l'activité qui VIENT d'être validée — consommé par l'accueil
    /// pour la bulle `afterActivity` (miroir de `lastMealXPAwarded`).
    var lastActivityXPAwarded: Int?

    /// Compteur MONOTONE de célébrations levées (jamais décrémenté) — à utiliser comme
    /// `celebrationTrigger` de NivelitoView : le dépilage de la file (Task 19) ne doit
    /// pas re-déclencher de rebond.
    private(set) var celebrationsRaised = 0

    /// Dépile la prochaine célébration à afficher (FIFO) — nil si la file est vide.
    /// Consommée par `CelebrationsHost` (Task 19) : une seule célébration visible à
    /// la fois ; l'hôte redemande à chaque dismiss.
    func consumeNextCelebration() -> Celebration? {
        guard !pendingCelebrations.isEmpty else { return nil }
        return pendingCelebrations.removeFirst()
    }

    /// Point d'entrée unique pour lever une célébration (file + compteur monotone).
    /// Anti-doublon : deux détections rapprochées avec un `levelBefore` devenu
    /// obsolète (ex. logMeal pendant que closeOpenDays s'achève) ne doivent pas
    /// empiler deux fois la MÊME célébration tant qu'elle n'a pas été affichée.
    private func raise(_ celebration: Celebration) {
        guard !pendingCelebrations.contains(celebration) else { return }
        pendingCelebrations.append(celebration)
        celebrationsRaised += 1
    }

    /// Calendrier ISO 8601 (semaine commençant le lundi) — le renouvellement des quêtes
    /// "du lundi" ne doit pas dépendre du premier jour de semaine du device.
    nonisolated static let calendar: Calendar = {
        var c = Calendar.current
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }()

    /// Normalisateur CANONIQUE des jours persistés : toute valeur ÉCRITE dans
    /// `DayLog.day` doit passer par ici — un seul point de vérité pour
    /// "minuit local" (Task 9/18). Les lectures/regroupements peuvent appeler
    /// `startOfDay` directement, c'est équivalent.
    nonisolated static func dayKey(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    /// Extras alcoolisés du catalogue (spec §7.3 : "jours sans alcool" = pas de bière/vin).
    private static let alcoholExtraIDs: Set<String> = ["beer", "wine"]

    init(modelContext: ModelContext, stepsService: StepsProviding) {
        self.modelContext = modelContext
        self.stepsService = stepsService
        self.questCatalog = Self.loadOrAssert({ try Catalogs.quests() }, fallback: [])
        self.badgeCatalog = Self.loadOrAssert({ try Catalogs.badges() }, fallback: [])
        self.messageBank = Self.loadOrAssert({ try MessageBank.load() }, fallback: nil)
        self.activityCatalog = Self.loadOrAssert({ try Catalogs.activities() }, fallback: [])
        self.sessionCatalog = Self.loadOrAssert({ try Catalogs.sessions() }, fallback: [])
        // uniquingKeysWith (et non uniqueKeysWithValues) : un id dupliqué dans un
        // bundle corrompu ne doit jamais crasher — on garde la première occurrence.
        self.activitiesByID = Dictionary(activityCatalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Fallback silencieux en release (jamais de crash), mais signal en debug :
    /// un catalogue du bundle qui ne charge pas est un bug de packaging.
    private static func loadOrAssert<T>(_ load: () throws -> T, fallback: T) -> T {
        do {
            return try load()
        } catch {
            assertionFailure("Catalogs failed to load: \(error)")
            return fallback
        }
    }

    /// Sauvegarde SwiftData : silencieuse en release, assert en debug (échec = bug).
    /// internal : aussi utilisée par DayCloser.swift.
    func saveOrAssert() {
        do {
            try modelContext.save()
        } catch {
            assertionFailure("SwiftData save failed: \(error)")
        }
    }

    // MARK: - Actions

    /// Crée un MealEntry (kcal via MealEstimator), attribue l'XP plafonné (4 repas/jour),
    /// met à jour le DayLog du jour, recalcule les quêtes, évalue les badges et détecte le level-up.
    @discardableResult
    func logMeal(
        slot: MealSlot,
        dish: Dish,
        portion: Portion,
        extras: [(Extra, Int)] = [],
        date: Date = .now
    ) async -> MealEntry {
        let state = fetchOrCreateState()
        let levelBefore = LevelSystem.level(forXP: state.totalXP)

        let kcal = MealEstimator.estimate(dish: dish, portion: portion, extras: extras)
        // Plafond robuste aux relances : le "déjà récompensé aujourd'hui" est dérivé
        // des MealEntry persistés (xpAwarded > 0), pas d'un compteur en mémoire.
        let xp = XPEngine.award(.mealLogged, todayCount: mealsAwardedXPCount(on: date))

        let entry = MealEntry(
            date: date,
            slot: slot,
            dishID: dish.id,
            portion: portion,
            extras: Dictionary(extras.map { ($0.0.id, $0.1) }, uniquingKeysWith: +),
            estimatedKcal: kcal,
            xpAwarded: xp
        )
        modelContext.insert(entry)
        state.totalXP += xp
        updateDayLog(for: date, addingKcal: kcal, xp: xp)
        lastMealXPAwarded = xp

        await refreshQuestProgress()
        evaluateBadges(state: state)
        detectLevelUp(state: state, levelBefore: levelBefore)
        saveOrAssert()
        return entry
    }

    /// Enregistre une pesée : WeightEntry + XP (.weighIn, plafonné 1/jour), quêtes, badges, level-up.
    /// Retourne l'XP attribué (0 si le plafond du jour est atteint).
    @discardableResult
    func logWeight(kg: Double, date: Date = .now) async -> Int {
        let state = fetchOrCreateState()
        let levelBefore = LevelSystem.level(forXP: state.totalXP)

        // Plafond dérivé du nombre de WeightEntry persistées aujourd'hui (robuste aux relances).
        let xp = XPEngine.award(.weighIn, todayCount: weighInCount(on: date))
        modelContext.insert(WeightEntry(date: date, weightKg: kg))
        state.totalXP += xp

        await refreshQuestProgress()
        evaluateBadges(state: state)
        detectLevelUp(state: state, levelBefore: levelBefore)
        saveOrAssert()
        return xp
    }

    /// Met à jour un repas existant (édition "le jour même", spec §4.2) : recalcule les
    /// kcal et ajuste le DayLog du jour — SANS ré-attribuer d'XP (`xpAwarded` inchangé,
    /// le plafond 4 repas/jour reste dérivé des entrées persistées).
    /// L'édition peut compléter une quête (+150 XP) → badges et level-up sont réévalués.
    func updateMeal(
        entry: MealEntry,
        slot: MealSlot,
        dish: Dish,
        portion: Portion,
        extras: [(Extra, Int)] = []
    ) async {
        assert(Self.calendar.isDateInToday(entry.date), "update/delete réservés au jour même")
        let state = fetchOrCreateState()
        let levelBefore = LevelSystem.level(forXP: state.totalXP)

        let previousKcal = entry.estimatedKcal
        let kcal = MealEstimator.estimate(dish: dish, portion: portion, extras: extras)
        entry.slot = slot
        entry.dishID = dish.id
        entry.portion = portion
        // Réassignation complète (règle SwiftData : pas de mutation en place des collections).
        entry.extras = Dictionary(extras.map { ($0.0.id, $0.1) }, uniquingKeysWith: +)
        entry.estimatedKcal = kcal
        updateDayLog(for: entry.date, addingKcal: kcal - previousKcal, xp: 0)

        await refreshQuestProgress()
        evaluateBadges(state: state)
        detectLevelUp(state: state, levelBefore: levelBefore)
        saveOrAssert()
    }

    /// Supprime un repas (jour même) : soustrait ses kcal du DayLog du jour.
    /// L'XP déjà attribué est CONSERVÉ — jamais de retrait d'XP (spec §7.1, bienveillance).
    func deleteMeal(entry: MealEntry) async {
        assert(Self.calendar.isDateInToday(entry.date), "update/delete réservés au jour même")
        let state = fetchOrCreateState()
        let levelBefore = LevelSystem.level(forXP: state.totalXP)

        updateDayLog(for: entry.date, addingKcal: -entry.estimatedKcal, xp: 0)
        modelContext.delete(entry)

        // Le refresh peut encore COMPLÉTER une quête (les jours "sans alcool"/"dessert
        // léger" peuvent devenir qualifiants après suppression) → badges + level-up.
        await refreshQuestProgress()
        evaluateBadges(state: state)
        detectLevelUp(state: state, levelBefore: levelBefore)
        saveOrAssert()
    }

    // MARK: - Quêtes

    /// Recalcule la progression de chaque quête active depuis SwiftData (+ pas de la semaine
    /// via StepsProviding) et marque les quêtes complétées (+150 XP, une seule fois).
    ///
    /// Rollover : si `questWeekID` ≠ semaine courante, on ne touche à rien — le
    /// renouvellement du lundi (archivage + nouveau tirage) est le travail de
    /// `closeOpenDays()` (DayCloser.swift), qui s'exécute au passage au premier plan.
    /// ⚠️ Contrat du renouvellement (respecté par DayCloser.swift) : remettre
    /// `completedThisWeekQuestIDs = []` et NE PAS ré-alimenter `completedQuestIDs` —
    /// l'historique est déjà alimenté ici au moment de la complétion.
    // ⚠️ La complétion d'une quête ici peut faire monter de niveau — tout appelant
    // doit détecter level-up + badges APRÈS refreshQuestProgress()
    // (logMeal/logWeight/updateMeal/deleteMeal et closeOpenDays le font).
    /// `now` est injectable pour les tests (DayCloser) — défaut : l'instant courant.
    func refreshQuestProgress(now: Date = .now) async {
        let state = fetchOrCreateState()
        guard state.questWeekID == QuestEngine.weekID(for: now, calendar: Self.calendar),
              !state.activeQuestIDs.isEmpty,
              let week = Self.calendar.dateInterval(of: .weekOfYear, for: now)
        else { return }

        let questsByID = Dictionary(uniqueKeysWithValues: questCatalog.map { ($0.id, $0) })
        let activeQuests = state.activeQuestIDs.compactMap { questsByID[$0] }
        guard !activeQuests.isEmpty else { return }

        let weekMeals = fetchMeals(from: week.start, to: week.end)
        let mealsByDay = Dictionary(grouping: weekMeals) { Self.calendar.startOfDay(for: $0.date) }

        var stepsByDay: [Date: Int] = [:]
        if stepsService.isAvailable,
           activeQuests.contains(where: { $0.metric == .weeklySteps || $0.metric == .stepGoalDays }) {
            // Erreur de requête → [:] : la progression des quêtes de pas retombe
            // transitoirement à 0, mais rien n'est figé — recalculée au prochain refresh.
            stepsByDay = await stepsService.dailySteps(from: week.start, to: now) ?? [:]
        }

        // Règle SwiftData : jamais de mutation en place des collections d'un @Model —
        // copie locale, modification, puis réassignation complète.
        var progress = state.questProgress
        var completedHistory = state.completedQuestIDs
        var completedThisWeek = state.completedThisWeekQuestIDs
        for quest in activeQuests {
            let value = questValue(for: quest, week: week, mealsByDay: mealsByDay, stepsByDay: stepsByDay)
            progress[quest.id] = value
            // Garde à la SEMAINE : une quête retirée une semaine ultérieure doit pouvoir
            // re-récompenser. L'historique all-time accepte les doublons (badges).
            if value >= quest.target && !completedThisWeek.contains(quest.id) {
                completedThisWeek.append(quest.id)
                completedHistory.append(quest.id)
                state.totalXP += XPEngine.award(.questCompleted, todayCount: 0)
                raise(.quest(quest))
            }
        }
        state.questProgress = progress
        state.completedQuestIDs = completedHistory
        state.completedThisWeekQuestIDs = completedThisWeek
        saveOrAssert()
    }

    private func questValue(
        for quest: Quest,
        week: DateInterval,
        mealsByDay: [Date: [MealEntry]],
        stepsByDay: [Date: Int]
    ) -> Int {
        switch quest.metric {
        case .mealsLogged:
            return mealsByDay.values.joined().count { quest.slot == nil || $0.slot == quest.slot }
        case .weighIns:
            return weighInCount(from: week.start, to: week.end)
        case .daysWithinTarget:
            // Uniquement les journées clôturées (le jugement "dans l'objectif" est posé
            // le lendemain par le DayCloser, spec §7.1).
            return closedDayLogs(from: week.start, to: week.end).count(where: \.withinTarget)
        case .daysWithoutAlcohol:
            // Jour qualifiant = au moins un repas loggé ET aucun extra bière/vin.
            return mealsByDay.values.count { meals in
                meals.allSatisfy { meal in
                    Self.alcoholExtraIDs.allSatisfy { (meal.extras[$0] ?? 0) == 0 }
                }
            }
        case .lightDessertDays:
            // Jour qualifiant = au moins un repas loggé ET aucun dessert gourmand.
            return mealsByDay.values.count { meals in
                meals.allSatisfy { ($0.extras["dessert_rich"] ?? 0) == 0 }
            }
        case .weeklySteps:
            return stepsByDay.values.reduce(0, +)
        case .stepGoalDays:
            let goal = fetchProfile()?.dailyStepGoal ?? 8000
            return stepsByDay.values.count { $0 >= goal }
        case .activitiesDone:
            return activityCount(from: week.start, to: week.end)
        case .dailySessionsDone:
            return dailySessionDayCount(from: week.start, to: week.end)
        }
    }

    // MARK: - Badges

    /// Compteurs pour BadgeEngine, dérivés de SwiftData.
    func badgeStats() -> BadgeStats {
        let state = fetchOrCreateState()
        var stats = BadgeStats()

        let meals = (try? modelContext.fetch(FetchDescriptor<MealEntry>())) ?? []
        stats.mealsLogged = meals.count
        stats.journalDays = Set(meals.map { Self.calendar.startOfDay(for: $0.date) }).count
        stats.weighIns = (try? modelContext.fetchCount(FetchDescriptor<WeightEntry>())) ?? 0

        // Les pas ne comptent que sur les journées clôturées (snapshot figé par le DayCloser).
        let closed = closedDayLogs()
        stats.stepsInOneDay = closed.map(\.steps).max() ?? 0
        stats.totalSteps = closed.reduce(0) { $0 + $1.steps }
        stats.totalKm = Int(Double(stats.totalSteps) * 0.00075) // ≈ 0,75 m par pas → km = pas × 0.00075

        stats.level = LevelSystem.level(forXP: state.totalXP)
        stats.questsCompleted = state.completedQuestIDs.count
        stats.weekWithinTarget = hasSevenConsecutiveDaysWithinTarget(closed) ? 1 : 0
        stats.trendDownFortnight = isTrendDownOverFortnight() ? 1 : 0

        let activities = (try? modelContext.fetch(FetchDescriptor<ActivityEntry>())) ?? []
        stats.activitiesDone = activities.count
        // Jours distincts (et non entrées) : une double séance le même jour ne
        // compte qu'une fois pour le badge "Rituel du jour" (spec sport §6, amendée).
        stats.dailySessionsDone = Set(
            activities.filter { $0.kind == .dailySession }.map { Self.calendar.startOfDay(for: $0.date) }
        ).count

        return stats
    }

    // internal : aussi appelé après la clôture des journées (DayCloser.swift).
    func evaluateBadges(state: GamificationState) {
        let newly = BadgeEngine.newlyUnlocked(
            badges: badgeCatalog,
            stats: badgeStats(),
            alreadyUnlocked: Set(state.badgeUnlocks.keys)
        )
        guard !newly.isEmpty else { return }
        var unlocks = state.badgeUnlocks
        for badge in newly {
            unlocks[badge.id] = .now
            state.totalXP += XPEngine.award(.badgeUnlocked, todayCount: 0)
            raise(.badge(badge))
        }
        state.badgeUnlocks = unlocks
    }

    /// 7 journées clôturées consécutives (calendaires) toutes dans l'objectif → 1.
    private func hasSevenConsecutiveDaysWithinTarget(_ closed: [DayLog]) -> Bool {
        let sorted = closed.sorted { $0.day < $1.day }
        var run = 0
        var previousDay: Date?
        for log in sorted {
            guard log.withinTarget else {
                run = 0
                previousDay = nil
                continue
            }
            if let previous = previousDay,
               let next = Self.calendar.date(byAdding: .day, value: 1, to: previous),
               Self.calendar.isDate(next, inSameDayAs: log.day) {
                run += 1
            } else {
                run = 1
            }
            if run >= 7 { return true }
            previousDay = log.day
        }
        return false
    }

    /// Tendance de poids en baisse sur 2 semaines — lissage exponentiel `WeightTrend.smooth`
    /// (α = 0,25) ; vrai si ≥ 2 pesées couvrant ≥ 14 jours et tendance finale < tendance
    /// d'il y a 14 jours.
    private func isTrendDownOverFortnight() -> Bool {
        var descriptor = FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date)])
        descriptor.propertiesToFetch = [\.date, \.weightKg]
        let entries = (try? modelContext.fetch(descriptor)) ?? []
        guard entries.count >= 2, let last = entries.last else { return false }

        let cutoff = last.date.addingTimeInterval(-14 * 86_400)
        guard let referenceIndex = entries.lastIndex(where: { $0.date <= cutoff }) else { return false }

        let trendValues = WeightTrend.smooth(entries.map(\.weightKg))
        return trendValues[entries.count - 1] < trendValues[referenceIndex]
    }

    // MARK: - Exposition pour les vues (accueil, écran Quêtes)

    /// Catalogue complet des badges (chargé une fois à l'init) — l'écran Quêtes
    /// l'affiche en entier ; vide seulement si le bundle est corrompu.
    var badges: [Badge] { badgeCatalog }

    /// Quêtes actives avec leur progression courante et l'état "complétée cette semaine".
    /// L'ordre du tirage hebdo est conservé.
    func activeQuestStatuses() -> [ActiveQuestStatus] {
        let state = fetchOrCreateState()
        let questsByID = Dictionary(uniqueKeysWithValues: questCatalog.map { ($0.id, $0) })
        return state.activeQuestIDs.compactMap { id in
            guard let quest = questsByID[id] else { return nil }
            return ActiveQuestStatus(
                quest: quest,
                progress: state.questProgress[id] ?? 0,
                isCompleted: state.completedThisWeekQuestIDs.contains(id)
            )
        }
    }

    /// Pas du jour — nil si HealthKit est refusé/indisponible (la carte de pas
    /// de l'accueil est alors masquée, spec §10).
    func todaySteps() async -> Int? {
        await stepsService.steps(on: .now)
    }

    /// Pas quotidiens sur [from, to[ (clé = minuit local) — vide si HealthKit est
    /// refusé/indisponible : la section Pas de l'écran Progrès est alors masquée (spec §10).
    func dailySteps(from start: Date, to end: Date) async -> [Date: Int] {
        // Indisponible OU erreur de requête → [:] : côté vues, les deux cas
        // s'affichent pareil (section masquée) ; la distinction nil/[:] ne
        // compte que pour la clôture des journées.
        guard stepsService.isAvailable else { return [:] }
        return await stepsService.dailySteps(from: start, to: end) ?? [:]
    }

    /// Contexte du message d'accueil de Nivelito (spec §4.1, §8), par priorité :
    /// 1. événements du jour — level-up en attente, badge en attente ou débloqué aujourd'hui ;
    /// 2. retour après absence (dernier repas loggé il y a ≥ 3 jours) ;
    /// 3. soirée au-dessus de l'objectif (déculpabilisant, jamais de reproche) ;
    /// 4. salutation horaire (matin < 12 h, midi 12-18 h, soir ≥ 18 h).
    func homeMessageContext(now: Date = .now) -> (context: MessageContext, value: Int?) {
        for celebration in pendingCelebrations {
            if case .levelUp(let level) = celebration { return (.levelUp, level) }
        }
        if pendingCelebrations.contains(where: { if case .badge = $0 { true } else { false } }) {
            return (.badge, nil)
        }
        let state = fetchOrCreateState()
        if state.badgeUnlocks.values.contains(where: { Self.calendar.isDate($0, inSameDayAs: now) }) {
            return (.badge, nil)
        }

        // Comeback : au moins un repas loggé un jour, et le dernier date d'il y a ≥ 3 jours.
        if let lastMeal = latestMealDate(),
           let days = Self.calendar.dateComponents(
               [.day],
               from: Self.calendar.startOfDay(for: lastMeal),
               to: Self.calendar.startOfDay(for: now)
           ).day,
           days >= 3 {
            return (.comeback, nil)
        }

        let hour = Self.calendar.component(.hour, from: now)

        // Objectif dépassé en soirée → message qui dédramatise (spec §8 : zéro culpabilité).
        if hour >= 18,
           let target = fetchProfile()?.dailyCalorieTarget, target > 0,
           kcalEaten(on: now) > target {
            return (.overTarget, nil)
        }

        switch hour {
        case ..<12: return (.morning, nil)
        case ..<18: return (.midday, nil)
        default: return (.evening, nil)
        }
    }

    /// Date du repas le plus récent, tous jours confondus — nil si aucun repas loggé.
    private func latestMealDate() -> Date? {
        var descriptor = FetchDescriptor<MealEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first?.date
    }

    /// Total mangé (somme des MealEntry) du jour contenant `date`.
    private func kcalEaten(on date: Date) -> Int {
        guard let (start, end) = dayBounds(for: date) else { return 0 }
        return fetchMeals(from: start, to: end).reduce(0) { $0 + $1.estimatedKcal }
    }

    // MARK: - Nivelito

    /// Message contextuel de Nivelito : `MessageBank.pick` sans répéter le dernier,
    /// et persiste `lastMessageIDs` sur le profil.
    func nivelitoSays(context: MessageContext, value: Int? = nil) -> String {
        let profile = fetchProfile()
        let name = profile?.name ?? ""
        guard let messageBank else { return "Salut \(name) !" }
        let message = messageBank.pick(
            context: context,
            excluding: profile?.lastMessageIDs[context.rawValue],
            name: name,
            value: value
        )
        if let profile {
            var lastIDs = profile.lastMessageIDs
            lastIDs[context.rawValue] = message.id
            profile.lastMessageIDs = lastIDs
            saveOrAssert()
        }
        return message.text
    }

    // MARK: - Level-up

    // internal : aussi appelé après la clôture des journées (DayCloser.swift).
    func detectLevelUp(state: GamificationState, levelBefore: Int) {
        let levelAfter = LevelSystem.level(forXP: state.totalXP)
        if levelAfter > levelBefore {
            raise(.levelUp(levelAfter))
        }
    }

    // MARK: - Accès SwiftData

    /// Singleton : fetch + .first ; création uniquement si absent (garde anti-doublon).
    /// internal : aussi utilisé par DayCloser.swift.
    func fetchOrCreateState() -> GamificationState {
        if let existing = (try? modelContext.fetch(FetchDescriptor<GamificationState>()))?.first {
            return existing
        }
        let state = GamificationState()
        modelContext.insert(state)
        return state
    }

    func fetchProfile() -> UserProfile? {
        (try? modelContext.fetch(FetchDescriptor<UserProfile>()))?.first
    }

    /// DayLog du jour donné, créé (cible kcal actuelle du profil) s'il n'existe pas.
    /// ⚠️ `day` doit être une clé canonique (`Self.dayKey`) — DayLog.day n'est
    /// JAMAIS écrit autrement. internal : aussi utilisé par DayCloser.swift.
    func fetchOrCreateDayLog(day: Date) -> DayLog {
        let predicate = #Predicate<DayLog> { $0.day == day }
        if let existing = (try? modelContext.fetch(FetchDescriptor(predicate: predicate)))?.first {
            return existing
        }
        let log = DayLog(day: day, kcalTarget: fetchProfile()?.dailyCalorieTarget ?? 0)
        modelContext.insert(log)
        return log
    }

    private func updateDayLog(for date: Date, addingKcal kcal: Int, xp: Int) {
        let log = fetchOrCreateDayLog(day: Self.dayKey(for: date))
        // max(0, …) : les deltas négatifs (édition/suppression) ne créent jamais
        // de total négatif, même sur un store incohérent.
        log.kcalEaten = max(0, log.kcalEaten + kcal)
        log.xpEarned += xp
    }

    func fetchMeals(from start: Date, to end: Date) -> [MealEntry] {
        let predicate = #Predicate<MealEntry> { $0.date >= start && $0.date < end }
        return (try? modelContext.fetch(FetchDescriptor(predicate: predicate))) ?? []
    }

    /// Nombre de repas DÉJÀ récompensés en XP ce jour-là (persistant → le plafond tient aux relances).
    private func mealsAwardedXPCount(on date: Date) -> Int {
        guard let (start, end) = dayBounds(for: date) else { return 0 }
        let predicate = #Predicate<MealEntry> { $0.date >= start && $0.date < end && $0.xpAwarded > 0 }
        return (try? modelContext.fetchCount(FetchDescriptor(predicate: predicate))) ?? 0
    }

    private func weighInCount(on date: Date) -> Int {
        guard let (start, end) = dayBounds(for: date) else { return 0 }
        return weighInCount(from: start, to: end)
    }

    private func weighInCount(from start: Date, to end: Date) -> Int {
        let predicate = #Predicate<WeightEntry> { $0.date >= start && $0.date < end }
        return (try? modelContext.fetchCount(FetchDescriptor(predicate: predicate))) ?? 0
    }

    private func closedDayLogs(from start: Date? = nil, to end: Date? = nil) -> [DayLog] {
        let start = start ?? .distantPast
        let end = end ?? .distantFuture
        let predicate = #Predicate<DayLog> { $0.closed && $0.day >= start && $0.day < end }
        return (try? modelContext.fetch(FetchDescriptor(predicate: predicate))) ?? []
    }

    // internal : aussi utilisé par GameService+Sport.swift et DayCloser.swift.
    func dayBounds(for date: Date) -> (Date, Date)? {
        let start = Self.calendar.startOfDay(for: date)
        guard let end = Self.calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        return (start, end)
    }
}
