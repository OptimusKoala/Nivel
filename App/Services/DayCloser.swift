// App/Services/DayCloser.swift
import Foundation
import NivelCore

/// Clôture des journées passées (spec §9 "Traitements différés", Task 18).
///
/// Choix structurel : la clôture partage l'orchestration interne du service
/// (contexte SwiftData, catalogue de quêtes, évaluation badges/level-up) — elle
/// fait donc PARTIE de GameService, simplement rangée dans sa propre extension.
/// Les membres concernés de GameService sont `internal` (annotés dans le fichier
/// principal), `private` étant limité au fichier en Swift.
extension GameService {
    /// Rattrapage exécuté au passage au premier plan (pas de background task
    /// garantie sans backend) :
    /// 1. clôture chaque journée de `lastClosedDay` (exclu ; sinon depuis la
    ///    création du profil) jusqu'à HIER inclus — snapshot de pas HealthKit,
    ///    kcal recalculées depuis les MealEntry, jugement `withinTarget`, XP ;
    /// 2. renouvelle les quêtes hebdo si la semaine ISO a changé (lundi) ;
    /// 3. recalcule la progression des quêtes puis évalue badges et level-up
    ///    (une quête complétée par les pas clôturés peut faire monter de niveau) ;
    /// 4. avance `lastClosedDay` à hier.
    ///
    /// `today` est injectable pour les tests — la logique de clôture ne lit
    /// jamais `.now` directement.
    func closeOpenDays(today: Date = .now) async {
        // Garde anti-réentrance : `onAppear` et `scenePhase == .active` peuvent
        // se déclencher quasi simultanément au lancement à froid.
        guard !isClosingDays else { return }
        isClosingDays = true
        defer { isClosingDays = false }

        // Pas de profil = onboarding non terminé → rien à clôturer.
        guard let profile = fetchProfile() else { return }
        let state = fetchOrCreateState()
        let levelBefore = LevelSystem.level(forXP: state.totalXP)

        let todayKey = Self.dayKey(for: today)
        guard let yesterday = Self.calendar.date(byAdding: .day, value: -1, to: todayKey) else { return }

        // Premier jour à clôturer : lendemain de `lastClosedDay`, sinon le jour
        // de création du profil (jamais de journée d'avant l'app).
        let firstDay: Date
        if let lastClosed = state.lastClosedDay {
            guard let next = Self.calendar.date(byAdding: .day, value: 1, to: Self.dayKey(for: lastClosed))
            else { return }
            firstDay = next
        } else {
            firstDay = Self.dayKey(for: profile.createdAt)
        }

        if firstDay <= yesterday {
            // Historique de pas lu en UNE requête sur [firstDay, aujourd'hui[.
            // nil = HealthKit refusé/indisponible → snapshot 0 et AUCUN XP de pas
            // (pas de données ≠ échec, spec §10/§13).
            var stepsByDay: [Date: Int]?
            if stepsService.isAvailable {
                guard let fetched = await stepsService.dailySteps(from: firstDay, to: todayKey) else {
                    // ERREUR de requête (≠ refus : isAvailable est vrai) : ne SURTOUT
                    // pas figer des journées à 0 pas — on abandonne toute la passe,
                    // le prochain passage au premier plan réessaiera.
                    return
                }
                stepsByDay = fetched
            }

            var day = firstDay
            while day <= yesterday {
                close(day: day, state: state, profile: profile, stepsByDay: stepsByDay)
                guard let next = Self.calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
            state.lastClosedDay = yesterday
        }

        // Renouvellement hebdo (lundi ISO) : les quêtes complétées sont DÉJÀ dans
        // `completedQuestIDs` (alimenté à la complétion par refreshQuestProgress) —
        // on n'archive RIEN de plus ; les inachevées disparaissent sans message
        // (spec §7.3). Seul le garde hebdo et la progression sont remis à zéro.
        let weekID = QuestEngine.weekID(for: today, calendar: Self.calendar)
        if state.questWeekID != weekID {
            state.completedThisWeekQuestIDs = []
            state.questProgress = [:]
            state.activeQuestIDs = QuestEngine.weeklyDraw(
                pool: questCatalog,
                weekID: weekID,
                stepsAvailable: stepsService.isAvailable,
                // TODO(lot C, Task 5) : PosturePlanSettings.shared.isEnabled. En dur à faux
                // pour l'instant : l'interrupteur par appareil n'existe pas encore, et une
                // quête posture ne doit jamais être tirée avant qu'il existe.
                postureAvailable: false
            ).map(\.id)
            state.questWeekID = weekID
        }

        // Les clôtures font avancer les quêtes (daysWithinTarget, stepGoalDays…)
        // et une complétion peut faire monter de niveau → badges et level-up
        // s'évaluent APRÈS le refresh (contrat documenté sur refreshQuestProgress).
        await refreshQuestProgress(now: today)
        evaluateBadges(state: state)
        detectLevelUp(state: state, levelBefore: levelBefore)
        saveOrAssert()
    }

    /// Fige la journée `day` (clé canonique, minuit local) : kcal recalculées
    /// depuis les MealEntry (source de vérité — le cumul incrémental du DayLog
    /// pourrait avoir dérivé), snapshot de pas, jugement `withinTarget` et XP.
    /// `stepsByDay` nil = données de pas indisponibles (pas d'XP de pas).
    private func close(
        day: Date,
        state: GamificationState,
        profile: UserProfile,
        stepsByDay: [Date: Int]?
    ) {
        guard let dayEnd = Self.calendar.date(byAdding: .day, value: 1, to: day) else { return }

        let log = fetchOrCreateDayLog(day: day)
        guard !log.closed else { return } // défense en profondeur : jamais de double clôture

        let meals = fetchMeals(from: day, to: dayEnd)
        log.kcalEaten = meals.reduce(0) { $0 + $1.estimatedKcal }
        // Cible FIGÉE : on garde celle du DayLog si déjà posée (elle reflète la
        // cible du moment), sinon la cible actuelle du profil.
        if log.kcalTarget == 0 { log.kcalTarget = profile.dailyCalorieTarget }

        let steps = stepsByDay.map { $0[day] ?? 0 }
        log.steps = steps ?? 0
        // "Dans l'objectif" = kcal ≤ cible ET ≥ 2 repas loggés ce jour-là —
        // sans journal, pas de jugement (spec §7.1, bienveillance).
        log.withinTarget = meals.count >= 2 && log.kcalEaten <= log.kcalTarget

        var xp = 0
        if log.withinTarget {
            xp += XPEngine.award(.dayWithinTarget, todayCount: 0) // +50
        }
        if let steps, steps >= profile.dailyStepGoal {
            xp += XPEngine.award(.stepGoalReached, todayCount: 0) // +40
        }
        log.xpEarned += xp
        state.totalXP += xp
        log.closed = true
    }
}
