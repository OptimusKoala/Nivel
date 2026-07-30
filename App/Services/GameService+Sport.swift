// App/Services/GameService+Sport.swift
// Section Sport (spec sport §5-6) : validation d'activités et de séances du jour.
// Miroir de logMeal — XP plafonné dérivé du store, quêtes, badges, level-up.
// AUCUNE écriture dans DayLog : les kcal brûlées sont indicatives, jamais créditées.

import Foundation
import SwiftData
import NivelCore

extension GameService {
    // MARK: - Validation

    /// Valide une activité libre : +30 XP (max 2 activités récompensées/jour).
    @discardableResult
    func logActivity(activity: Activity, durationMinutes: Int, date: Date = .now) async -> ActivityEntry {
        await logSport(kind: .activity, refID: activity.id, minutes: durationMinutes,
                       kcal: activity.estimatedKcal(minutes: durationMinutes), date: date)
    }

    /// Valide la séance du jour : +40 XP (max 1/jour, indépendant du plafond activités).
    @discardableResult
    func logDailySession(session: ActivitySession, date: Date = .now) async -> ActivityEntry {
        await logSport(kind: .dailySession, refID: session.id, minutes: session.totalMinutes,
                       kcal: session.estimatedKcal(activitiesByID: activitiesByID), date: date)
    }

    private func logSport(kind: ActivityKind, refID: String, minutes: Int,
                          kcal: Int, date: Date) async -> ActivityEntry {
        let state = fetchOrCreateState()
        let levelBefore = LevelSystem.level(forXP: state.totalXP)

        // Plafond robuste aux relances : dérivé des ActivityEntry persistées (par kind).
        let action: XPAction = kind == .dailySession ? .dailySessionDone : .activityDone
        let xp = XPEngine.award(action, todayCount: sportAwardedCount(kind: kind, on: date))

        let entry = ActivityEntry(date: date, kind: kind, refID: refID,
                                  durationMinutes: minutes, estimatedKcal: kcal, xpAwarded: xp)
        modelContext.insert(entry)
        state.totalXP += xp
        lastActivityXPAwarded = xp

        await refreshQuestProgress()
        evaluateBadges(state: state)
        detectLevelUp(state: state, levelBefore: levelBefore)
        saveOrAssert()
        return entry
    }

    /// Supprime une validation (jour même). L'XP est CONSERVÉ (spec v1 §7.1) — cas
    /// assumé : un re-log après suppression peut être récompensé à nouveau.
    func deleteActivity(entry: ActivityEntry) async {
        assert(Self.calendar.isDateInToday(entry.date), "suppression réservée au jour même")
        let state = fetchOrCreateState()
        let levelBefore = LevelSystem.level(forXP: state.totalXP)
        modelContext.delete(entry)
        await refreshQuestProgress()
        evaluateBadges(state: state)
        detectLevelUp(state: state, levelBefore: levelBefore)
        saveOrAssert()
    }

    // MARK: - Exposition pour les vues

    /// Séance du jour (rotation déterministe, spec sport §3.3) + état « déjà faite ».
    func dailySessionStatus(now: Date = .now) -> (session: ActivitySession, done: Bool)? {
        guard let session = DailySessionPicker.session(for: now, sessions: sessionCatalog,
                                                       calendar: Self.calendar) else { return nil }
        return (session, sportCount(kind: .dailySession, on: now) > 0)
    }

    /// Kcal estimées d'une séance (catalogue chargé une fois à l'init).
    func sessionKcal(_ session: ActivitySession) -> Int {
        session.estimatedKcal(activitiesByID: activitiesByID)
    }

    /// Validations du jour, chronologiques — liste « Fait aujourd'hui ».
    func todayActivities(now: Date = .now) -> [ActivityEntry] {
        guard let (start, end) = dayBounds(for: now) else { return [] }
        let descriptor = FetchDescriptor<ActivityEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Compteurs

    /// Validations sur [start, end[, optionnellement filtrées par kind (quêtes hebdo).
    func activityCount(from start: Date, to end: Date, kind: ActivityKind? = nil) -> Int {
        let predicate: Predicate<ActivityEntry>
        if let kind {
            let kindRaw = kind.rawValue
            predicate = #Predicate { $0.date >= start && $0.date < end && $0.kindRaw == kindRaw }
        } else {
            predicate = #Predicate { $0.date >= start && $0.date < end }
        }
        return (try? modelContext.fetchCount(FetchDescriptor(predicate: predicate))) ?? 0
    }

    /// Validations du kind ce jour-là (peu importe l'XP).
    private func sportCount(kind: ActivityKind, on date: Date) -> Int {
        guard let (start, end) = dayBounds(for: date) else { return 0 }
        return activityCount(from: start, to: end, kind: kind)
    }

    /// Validations DÉJÀ récompensées en XP ce jour-là, par kind (plafond persistant).
    private func sportAwardedCount(kind: ActivityKind, on date: Date) -> Int {
        guard let (start, end) = dayBounds(for: date) else { return 0 }
        let kindRaw = kind.rawValue
        let predicate = #Predicate<ActivityEntry> {
            $0.date >= start && $0.date < end && $0.kindRaw == kindRaw && $0.xpAwarded > 0
        }
        return (try? modelContext.fetchCount(FetchDescriptor(predicate: predicate))) ?? 0
    }
}
