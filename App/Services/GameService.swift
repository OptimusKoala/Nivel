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

/// Façade unique consommée par les vues : log de repas/pesée, XP, quêtes, badges,
/// messages de Nivelito. Toute la logique pure vit dans NivelCore ; ici on orchestre
/// SwiftData + StepsProviding.
@Observable @MainActor
final class GameService {
    private let modelContext: ModelContext
    private let stepsService: StepsProviding

    /// Catalogues embarqués (chargés une fois ; vides si le bundle est corrompu — jamais de crash).
    private let questCatalog: [Quest]
    private let badgeCatalog: [Badge]
    private let messageBank: MessageBank?

    /// File des célébrations en attente d'affichage (les vues dépilent).
    var pendingCelebrations: [Celebration] = []

    /// Calendrier ISO 8601 (semaine commençant le lundi) — le renouvellement des quêtes
    /// "du lundi" ne doit pas dépendre du premier jour de semaine du device.
    nonisolated static let calendar: Calendar = {
        var c = Calendar.current
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }()

    /// Extras alcoolisés du catalogue (spec §7.3 : "jours sans alcool" = pas de bière/vin).
    private static let alcoholExtraIDs: Set<String> = ["beer", "wine"]

    init(modelContext: ModelContext, stepsService: StepsProviding) {
        self.modelContext = modelContext
        self.stepsService = stepsService
        self.questCatalog = (try? Catalogs.quests()) ?? []
        self.badgeCatalog = (try? Catalogs.badges()) ?? []
        self.messageBank = try? MessageBank.load()
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

        await refreshQuestProgress()
        evaluateBadges(state: state)
        detectLevelUp(state: state, levelBefore: levelBefore)
        try? modelContext.save()
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
        try? modelContext.save()
        return xp
    }

    // MARK: - Quêtes

    /// Recalcule la progression de chaque quête active depuis SwiftData (+ pas de la semaine
    /// via StepsProviding) et marque les quêtes complétées (+150 XP, une seule fois).
    ///
    /// Rollover : si `questWeekID` ≠ semaine courante, on ne touche à rien — le
    /// renouvellement du lundi (archivage + nouveau tirage) est le travail du
    /// DayCloser (Task 18), qui s'exécute au passage au premier plan.
    /// ⚠️ Task 18 : au renouvellement, remettre `completedThisWeekQuestIDs = []`
    /// (et NE PAS ré-alimenter `completedQuestIDs` — l'historique est déjà
    /// alimenté ici au moment de la complétion).
    func refreshQuestProgress() async {
        let now = Date.now
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
            stepsByDay = await stepsService.dailySteps(from: week.start, to: now)
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
                pendingCelebrations.append(.quest(quest))
            }
        }
        state.questProgress = progress
        state.completedQuestIDs = completedHistory
        state.completedThisWeekQuestIDs = completedThisWeek
        try? modelContext.save()
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
        stats.totalKm = Int(Double(stats.totalSteps) * 0.00075)

        stats.level = LevelSystem.level(forXP: state.totalXP)
        stats.questsCompleted = state.completedQuestIDs.count
        stats.weekWithinTarget = hasSevenConsecutiveDaysWithinTarget(closed) ? 1 : 0
        stats.trendDownFortnight = isTrendDownOverFortnight() ? 1 : 0
        return stats
    }

    private func evaluateBadges(state: GamificationState) {
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
            pendingCelebrations.append(.badge(badge))
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

    /// Tendance de poids en baisse sur 2 semaines — version v1 simple : lissage exponentiel
    /// inline (α = 0,25, même formule que WeightTrend de Task 15 qui la remplacera) ; vrai si
    /// ≥ 2 pesées couvrant ≥ 14 jours et tendance finale < tendance d'il y a 14 jours.
    private func isTrendDownOverFortnight() -> Bool {
        var descriptor = FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date)])
        descriptor.propertiesToFetch = [\.date, \.weightKg]
        let entries = (try? modelContext.fetch(descriptor)) ?? []
        guard entries.count >= 2, let last = entries.last else { return false }

        let cutoff = last.date.addingTimeInterval(-14 * 86_400)
        guard let referenceIndex = entries.lastIndex(where: { $0.date <= cutoff }) else { return false }

        var trend = entries[0].weightKg
        var trendValues = [trend]
        for entry in entries.dropFirst() {
            trend += 0.25 * (entry.weightKg - trend)
            trendValues.append(trend)
        }
        return trendValues[entries.count - 1] < trendValues[referenceIndex]
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
            try? modelContext.save()
        }
        return message.text
    }

    // MARK: - Level-up

    private func detectLevelUp(state: GamificationState, levelBefore: Int) {
        let levelAfter = LevelSystem.level(forXP: state.totalXP)
        if levelAfter > levelBefore {
            pendingCelebrations.append(.levelUp(levelAfter))
        }
    }

    // MARK: - Accès SwiftData

    /// Singleton : fetch + .first ; création uniquement si absent (garde anti-doublon).
    private func fetchOrCreateState() -> GamificationState {
        if let existing = (try? modelContext.fetch(FetchDescriptor<GamificationState>()))?.first {
            return existing
        }
        let state = GamificationState()
        modelContext.insert(state)
        return state
    }

    private func fetchProfile() -> UserProfile? {
        (try? modelContext.fetch(FetchDescriptor<UserProfile>()))?.first
    }

    private func updateDayLog(for date: Date, addingKcal kcal: Int, xp: Int) {
        let dayStart = Self.calendar.startOfDay(for: date)
        let predicate = #Predicate<DayLog> { $0.day == dayStart }
        if let log = (try? modelContext.fetch(FetchDescriptor(predicate: predicate)))?.first {
            log.kcalEaten += kcal
            log.xpEarned += xp
        } else {
            let log = DayLog(
                day: dayStart,
                kcalEaten: kcal,
                kcalTarget: fetchProfile()?.dailyCalorieTarget ?? 0,
                xpEarned: xp
            )
            modelContext.insert(log)
        }
    }

    private func fetchMeals(from start: Date, to end: Date) -> [MealEntry] {
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

    private func dayBounds(for date: Date) -> (Date, Date)? {
        let start = Self.calendar.startOfDay(for: date)
        guard let end = Self.calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        return (start, end)
    }
}
