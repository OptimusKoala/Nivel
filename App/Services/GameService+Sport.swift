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

    /// Valide une séance du programme muscu : +40 XP (max 1/jour, INDÉPENDANT des
    /// plafonds séance du jour ET posture, spec v1.14 §5.7). Miroir exact de
    /// `logPostureSession` ; seul le `kind` change. Les kcal passent par
    /// `activitiesByID` comme les autres : les étapes muscu pointent vers le
    /// catalogue commun, elles y sont donc toutes résolues.
    @discardableResult
    func logMuscuSession(session: ActivitySession, date: Date = .now) async -> ActivityEntry {
        assert(session.totalMinutes > 0, "séance muscu sans étapes")
        return await logSport(kind: .muscu, refID: session.id, minutes: session.totalMinutes,
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
        // Plafond INDÉPENDANT de dailySessionDone (spec §8) : faire la séance
        // posture ET la séance du jour le même soir paie les deux XP.
        case .posture: action = .postureSessionDone
        // Troisième plafond indépendant (spec v1.14 §5.7) : mutualiser ferait qu'une
        // séance muscu et une séance posture le même soir n'en paieraient qu'une.
        case .muscu: action = .muscuSessionDone
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

    /// Séance muscu du jour + état « déjà faite » (spec v1.14 §4.4) : miroir exact de
    /// `postureSessionStatus`, sur le catalogue muscu CLOISONNÉ — même rotation
    /// générique, même référence fixe, appliquée à un troisième pool distinct.
    func muscuSessionStatus(now: Date = .now) -> (session: ActivitySession, done: Bool)? {
        guard let session = muscuCatalog.session(for: now, calendar: Self.calendar) else { return nil }
        return (session, sportCount(kind: .muscu, on: now) > 0)
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

    /// Validations d'une journée quelconque, non triées. Prédicat UNIQUE des
    /// validations d'un jour : `todayActivities` et `burnKcal` en dérivent tous les
    /// deux, plutôt que d'écrire deux fois les mêmes bornes.
    func activities(on day: Date) -> [ActivityEntry] {
        guard let (start, end) = dayBounds(for: day) else { return [] }
        let predicate = #Predicate<ActivityEntry> { $0.date >= start && $0.date < end }
        return (try? modelContext.fetch(FetchDescriptor(predicate: predicate))) ?? []
    }

    /// Validations du jour, chronologiques — liste « Fait aujourd'hui ». Nom distinct
    /// de `activities(on:)` à dessein : « today » dit à ses appelants (les vues) que
    /// c'est la journée en cours, et la clôture d'une journée de la semaine dernière
    /// n'a pas à passer par une méthode qui la contredit.
    func todayActivities(now: Date = .now) -> [ActivityEntry] {
        activities(on: now).sorted { $0.date < $1.date }
    }

    // MARK: - Dépense du jour

    /// Dépense calorique estimée de la journée `day` (spec v1.14 §5.4) : les pas, plus
    /// les validations sport de ce jour-là dont la dépense ne fait pas doublon avec eux.
    /// Chemin UNIQUE de l'assemblage des `BurnEntry` — la clôture (DayCloser, Task 5) et
    /// l'anneau d'accueil (Task 6) doivent afficher le MÊME chiffre pour un même jour.
    ///
    /// `steps` est un `DailySteps` et non un `Int` : passer 0 quand HealthKit est refusé
    /// ferait exclure les activités marchées comme si le podomètre les avait déjà
    /// comptées, et une journée de marche sans HealthKit afficherait une dépense nulle.
    /// Il reste un PARAMÈTRE parce que ses deux appelants ne l'obtiennent pas pareil :
    /// la clôture tient un lot de journées lu en une requête, l'anneau une lecture live.
    ///
    /// `weightKg` est optionnel et vaut par défaut le poids courant : le passer est une
    /// OPTIMISATION (la clôture le hisse hors de sa boucle), pas une décision. L'exiger
    /// rouvrirait l'appariement que `burnTarget()` existe justement pour supprimer —
    /// `profiles.first?.initialWeightKg` est à un point de distance dans une vue, compile,
    /// et donnerait un anneau juste le jour de l'onboarding puis faux pour toujours.
    /// (`weightKg: Double = currentWeightKg()` est refusé par le compilateur : un membre
    /// d'instance ne peut pas servir de valeur par défaut.)
    ///
    /// Ces kcal restent INDICATIVES : elles ne sont jamais créditées au budget (règle v1 §2).
    func burnKcal(on day: Date, steps: DailySteps, weightKg: Double? = nil) -> Int {
        BurnCalculator.kcal(
            steps: steps,
            weightKg: weightKg ?? currentWeightKg(),
            entries: activities(on: day).map {
                BurnEntry(kind: $0.kind, refID: $0.refID, estimatedKcal: $0.estimatedKcal)
            },
            activitiesByID: activitiesByID,
            sessionsByID: sessionsByID
        )
    }

    // MARK: - Compteurs

    /// Jours DISTINCTS avec au moins une séance du jour sur [start, end[ — une double
    /// validation le même jour ne compte qu'une fois (quêtes et badge "Rituel du jour").
    func dailySessionDayCount(from start: Date, to end: Date) -> Int {
        sessionDayCount(kind: .dailySession, from: start, to: end)
    }

    /// Le comptage lui-même, écrit une seule fois pour les trois natures de séance :
    /// jours DISTINCTS d'un `kind` sur [start, end[. Trois copies du même prédicat
    /// auraient fini par diverger, et une seule d'entre elles corrigée aurait fait
    /// afficher deux chiffres différents pour la même semaine.
    private func sessionDayCount(kind: ActivityKind, from start: Date, to end: Date) -> Int {
        let kindRaw = kind.rawValue
        let predicate = #Predicate<ActivityEntry> {
            $0.date >= start && $0.date < end && $0.kindRaw == kindRaw
        }
        let entries = (try? modelContext.fetch(FetchDescriptor(predicate: predicate))) ?? []
        return Set(entries.map { Self.calendar.startOfDay(for: $0.date) }).count
    }

    /// Miroir exact de `dailySessionDayCount`, pour la métrique de quête
    /// `postureSessionsDone` (spec v1.11 §7.2) : comptée en jours DISTINCTS, comme la
    /// séance du jour, sinon la quête récompenserait le bachotage plutôt que la
    /// régularité. Alimenté par `logPostureSession`, et par le compteur mensuel
    /// de la carte du soir (`postureSessionsThisMonth`) qui compte pareil.
    func postureSessionDayCount(from start: Date, to end: Date) -> Int {
        sessionDayCount(kind: .posture, from: start, to: end)
    }

    /// Compteur mensuel de la carte du soir (spec v1.11 §7.3) : jours DISTINCTS du
    /// mois contenant `now`, comme la quête `postureSessionsDone` — les deux doivent
    /// compter pareil, sinon la carte et la quête afficheraient des nombres
    /// différents pour la même semaine sans que personne ne puisse deviner pourquoi.
    func postureSessionsThisMonth(now: Date = .now) -> Int {
        guard let month = Self.calendar.dateInterval(of: .month, for: now) else { return 0 }
        return postureSessionDayCount(from: month.start, to: month.end)
    }

    /// Compteur mensuel de la carte muscu (spec v1.14 §4.4) : jours DISTINCTS du mois
    /// contenant `now`, exactement comme la posture — c'est le chiffre affiché sur la
    /// carte, et il dit la régularité plutôt que le bachotage. Ce n'est PAS la métrique
    /// `muscuSessionsDone`, qui compte des entrées ; `questValue` détaille pourquoi.
    func muscuSessionsThisMonth(now: Date = .now) -> Int {
        guard let month = Self.calendar.dateInterval(of: .month, for: now) else { return 0 }
        return sessionDayCount(kind: .muscu, from: month.start, to: month.end)
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

extension GameService {
    /// Le nom lisible d'une activité validée : « Vélo tranquille », « Nuque et haut du
    /// dos ». Vivait inline dans `SportView.doneRow` jusqu'à la 1.15 ; extrait ici parce
    /// que le fil du duo en a besoin lui aussi (spec §3.4) et que ce `switch` porte deux
    /// pièges qu'il serait absurde de dupliquer — un second exemplaire divergerait un
    /// jour, et l'un des deux écrans afficherait des identifiants bruts.
    ///
    /// Le repli sur `refID` n'est jamais joli, mais il est volontaire : une entrée dont
    /// le catalogue a perdu la référence reste affichable plutôt que de disparaître.
    func activityTitle(for entry: ActivityEntry) -> String {
        switch entry.kind {
        case .activity:
            return activitiesByID[entry.refID]?.name ?? entry.refID
        case .dailySession:
            return sessionCatalog.first { $0.id == entry.refID }?.title ?? entry.refID
        case .posture:
            // Une entrée posture porte un id de SÉANCE, comme .dailySession, et non
            // un id d'exercice : `logPostureSession` est le miroir de
            // `logDailySession`. Chercher dans le catalogue d'exercices retomberait
            // silencieusement sur l'id brut (« posture_evening ») dans la liste du jour.
            return postureCatalog.sessions.first { $0.id == entry.refID }?.title
                ?? activitiesByID[entry.refID]?.name
                ?? entry.refID
        case .muscu:
            // Même piège que .posture — un id de SÉANCE, jamais d'exercice — mais
            // SANS le repli par `activitiesByID` : le programme muscu n'a pas
            // d'exercices à lui, aucun id `muscu_*` n'existe dans cette table, et
            // le maillon serait donc du code mort qui retomberait toujours sur l'id brut.
            return muscuCatalog.sessions.first { $0.id == entry.refID }?.title ?? entry.refID
        }
    }
}
