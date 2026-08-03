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
        assert(durationMinutes > 0, "durée d'activité invalide")
        return await logSport(kind: .activity, refID: activity.id, minutes: durationMinutes,
                              kcal: activity.estimatedKcal(minutes: durationMinutes), date: date)
    }

    /// Valide la séance du jour : +40 XP (max 1/jour, indépendant du plafond activités).
    @discardableResult
    func logDailySession(session: ActivitySession, date: Date = .now) async -> ActivityEntry {
        assert(session.totalMinutes > 0, "séance sans étapes")
        return await logSport(kind: .dailySession, refID: session.id, minutes: session.totalMinutes,
                              kcal: session.estimatedKcal(activitiesByID: activitiesByID), date: date)
    }

    /// Valide la séance posture du soir : +40 XP (max 1/jour, INDÉPENDANT du
    /// plafond de la séance du jour, spec v1.11 §8) — faire les deux le même
    /// soir paie les deux, c'est exactement le comportement qu'on veut installer.
    /// Miroir exact de `logDailySession` ; seul le `kind` change.
    @discardableResult
    func logPostureSession(session: ActivitySession, date: Date = .now) async -> ActivityEntry {
        assert(session.totalMinutes > 0, "séance posture sans étapes")
        return await logSport(kind: .posture, refID: session.id, minutes: session.totalMinutes,
                              kcal: session.estimatedKcal(activitiesByID: activitiesByID), date: date)
    }

    private func logSport(kind: ActivityKind, refID: String, minutes: Int,
                          kcal: Int, date: Date) async -> ActivityEntry {
        let state = fetchOrCreateState()
        let levelBefore = LevelSystem.level(forXP: state.totalXP)

        // Plafond robuste aux relances : dérivé des ActivityEntry persistées (par kind).
        let action: XPAction
        switch kind {
        case .dailySession: action = .dailySessionDone
        case .activity: action = .activityDone
        // Pas encore de caller : `logPostureSession` arrive en Task 5/6 (interrupteur +
        // catalogue posture chargés dans GameService). Le mapping est déjà correct pour
        // ce jour-là — plafond XP indépendant de dailySessionDone (spec §8).
        case .posture: action = .postureSessionDone
        }
        let xp = XPEngine.award(action, todayCount: sportAwardedCount(kind: kind, on: date))

        let entry = ActivityEntry(date: date, kind: kind, refID: refID,
                                  durationMinutes: minutes, estimatedKcal: kcal, xpAwarded: xp)
        // ⚠️ ORDRE contractuel : insert AVANT le premier await — les fetchCount du
        // même contexte voient les inserts non sauvegardés, c'est ce qui rend le
        // plafond robuste à deux validations simultanées (tap-tap rapide).
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

    /// Séance posture du soir + état « déjà faite » (spec v1.11 §6, §9) : miroir
    /// exact de `dailySessionStatus`, sur le catalogue posture CLOISONNÉ — même
    /// rotation générique, même référence fixe, appliquée à un pool distinct.
    func postureSessionStatus(now: Date = .now) -> (session: ActivitySession, done: Bool)? {
        guard let session = postureCatalog.session(for: now, calendar: Self.calendar) else { return nil }
        return (session, sportCount(kind: .posture, on: now) > 0)
    }

    /// Kcal estimées d'une séance (catalogue chargé une fois à l'init).
    func sessionKcal(_ session: ActivitySession) -> Int {
        session.estimatedKcal(activitiesByID: activitiesByID)
    }

    /// XP que rapporterait une activité libre validée maintenant — 0 une fois le
    /// plafond du jour atteint : le CTA de la sheet ne promet pas d'XP fantôme.
    func nextActivityXP(now: Date = .now) -> Int {
        XPEngine.award(.activityDone, todayCount: sportAwardedCount(kind: .activity, on: now))
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

    /// Jours DISTINCTS avec au moins une séance du jour sur [start, end[ — une double
    /// validation le même jour ne compte qu'une fois (quêtes et badge "Rituel du jour").
    func dailySessionDayCount(from start: Date, to end: Date) -> Int {
        let kindRaw = ActivityKind.dailySession.rawValue
        let predicate = #Predicate<ActivityEntry> {
            $0.date >= start && $0.date < end && $0.kindRaw == kindRaw
        }
        let entries = (try? modelContext.fetch(FetchDescriptor(predicate: predicate))) ?? []
        return Set(entries.map { Self.calendar.startOfDay(for: $0.date) }).count
    }

    /// Miroir exact de `dailySessionDayCount`, pour la métrique de quête
    /// `postureSessionsDone` (spec v1.11 §7.2) : comptée en jours DISTINCTS, comme la
    /// séance du jour, sinon la quête récompenserait le bachotage plutôt que la
    /// régularité. Pas encore de caller qui insère des `ActivityEntry(kind: .posture)`
    /// (`logPostureSession` arrive en Task 6) : ce compteur reste correct dès
    /// aujourd'hui, il attend juste des données.
    func postureSessionDayCount(from start: Date, to end: Date) -> Int {
        let kindRaw = ActivityKind.posture.rawValue
        let predicate = #Predicate<ActivityEntry> {
            $0.date >= start && $0.date < end && $0.kindRaw == kindRaw
        }
        let entries = (try? modelContext.fetch(FetchDescriptor(predicate: predicate))) ?? []
        return Set(entries.map { Self.calendar.startOfDay(for: $0.date) }).count
    }

    /// Compteur mensuel de la carte du soir (spec v1.11 §7.3) : jours DISTINCTS du
    /// mois contenant `now`, comme la quête `postureSessionsDone` — les deux doivent
    /// compter pareil, sinon la carte et la quête afficheraient des nombres
    /// différents pour la même semaine sans que personne ne puisse deviner pourquoi.
    func postureSessionsThisMonth(now: Date = .now) -> Int {
        guard let month = Self.calendar.dateInterval(of: .month, for: now) else { return 0 }
        return postureSessionDayCount(from: month.start, to: month.end)
    }

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
