// App/Services/GameService+DuoSnapshot.swift
// Construction de l'instantané publié vers le partenaire (spec 1.15 §3.3 et §3.5).
//
// Calqué sur `GameService+WidgetSync.swift`, et volontairement : ce sont deux fois le
// même geste — lire l'état du jour, en tirer une petite valeur autonome, la remettre à
// qui la consommera. La différence est le destinataire, l'App Group là-bas, une zone
// iCloud partagée ici.
//
// Ce fichier ne contient QUE la moitié qui se prouve : `makeDuoSnapshot` est synchrone,
// n'émet aucune requête, ne touche à rien, et se teste sur un conteneur en mémoire.
// L'écriture CloudKit (`DuoPublisher.publish`) viendra à part, et elle n'aura pas cette
// chance.

import Foundation
import NivelCore

extension GameService {
    /// L'instantané du jour, ou `nil` tant que l'onboarding n'est pas terminé —
    /// exactement comme `makeWidgetSnapshot`, et pour la même raison : sans profil il
    /// n'y a ni prénom, ni cible, ni rien à montrer. Publier une coquille ferait
    /// apparaître un partenaire sans nom chez l'autre.
    ///
    /// `steps` est passé par l'appelant plutôt que lu ici, parce que sa lecture est
    /// asynchrone (HealthKit) et que cette fonction ne l'est pas. `nil` y recouvre les
    /// DEUX situations que rien ne distingue — permission refusée, ou lecture pas encore
    /// revenue — et se publie en `DuoSnapshot.stepsUnavailable`. Un `0` ferait afficher
    /// « 0 pas » au partenaire de quelqu'un qui a marché toute la journée.
    ///
    /// `memberID` est passé de la même façon, depuis `DuoIdentity`, pour que cette
    /// fonction reste sans état d'appareil et donc testable sans toucher aux réglages.
    func makeDuoSnapshot(memberID: String, steps: Int?, now: Date = .now) -> DuoSnapshot? {
        guard let profile = fetchProfile() else { return nil }

        // Niveau publié DÉJÀ CALCULÉ, jamais le seul `totalXP` à interpréter : les deux
        // téléphones peuvent tourner sur des courbes différentes (spec §3.4). C'est
        // `LevelSystem` d'ICI qui fait foi, pas celui d'en face.
        let totalXP = fetchState()?.totalXP ?? 0
        let progression = LevelSystem.progress(forXP: totalXP)

        // La quête la plus avancée non terminée : `HomeView.featuredQuest`, la même
        // fonction que la carte de l'accueil. Le partenaire voit donc EXACTEMENT la
        // quête que l'autre a sous les yeux, ce qu'une seconde règle écrite ici ne
        // garantirait plus le jour où l'une des deux changerait.
        let quete = HomeView.featuredQuest(from: activeQuestStatuses())

        return DuoSnapshot(
            memberID: memberID,
            name: profile.name,
            sexRaw: profile.sexRaw,
            level: LevelSystem.level(forXP: totalXP),
            totalXP: totalXP,
            xpIntoLevel: progression.current,
            xpForNextLevel: progression.needed,
            dayKey: Self.duoDayKey(for: now),
            kcalEaten: kcalEaten(on: now),
            kcalTarget: profile.dailyCalorieTarget,
            // Même appariement que l'anneau de l'accueil : `HomeView.dailySteps` traduit
            // le `Int?` en `DailySteps`, dont le cas `.unavailable` compte les activités
            // marchées au lieu de les exclure (spec 1.14 §5.4).
            burned: burnKcal(on: now, steps: HomeView.dailySteps(from: steps)),
            burnTarget: burnTarget(),
            steps: steps ?? DuoSnapshot.stepsUnavailable,
            quest: quete.map {
                DuoQuestLine(title: $0.quest.title, done: $0.progress, total: $0.quest.target)
            },
            events: duoFeed(on: now),
            generatedAt: now
        )
    }

    /// Le fil du jour, composé ICI et pas chez le partenaire : les titres et sous-titres
    /// sont résolus contre NOS catalogues, si bien qu'une entrée que sa version de l'app
    /// ne connaît pas s'affiche quand même correctement chez lui (spec §3.4).
    ///
    /// Les entrées sans `publicID` sont écartées par `DuoFeedBuilder.build`, et ce n'est
    /// pas un oubli à réparer ici : c'est `publish()` qui devra appeler
    /// `assignMissingIDs` et persister AVANT de construire. Tant que ce chaînage n'existe
    /// pas, une entrée d'avant la 1.15 manque simplement au fil, ce qui est le bon
    /// comportement dégradé — bien préférable à deux entrées partageant un cœur.
    private func duoFeed(on now: Date) -> [DuoEvent] {
        guard let (debut, fin) = dayBounds(for: now) else { return [] }
        return DuoFeedBuilder.build(
            meals: duoMealInputs(fetchMeals(from: debut, to: fin)),
            activities: duoActivityInputs(activities(on: now)))
    }

    /// Les deux projections vers NivelCore, partagées avec `assignMissingDuoIDs`
    /// (DuoPublisher). Un seul exemplaire, et ce n'est pas qu'une économie : ces
    /// tableaux sont désignés PAR RANG par `MissingIDAssignment`, donc les deux
    /// appelants doivent projeter exactement de la même façon. Deux mappings jumeaux
    /// finiraient par différer, et un identifiant atterrirait sur la mauvaise entrée.
    func duoMealInputs(_ repas: [MealEntry]) -> [MealFeedInput] {
        repas.map { repas in
            MealFeedInput(
                publicID: repas.publicID,
                date: repas.date,
                slot: repas.slot,
                title: MealFormatting.frSummary(lines: repas.lines, catalog: foodCatalog),
                kcal: repas.estimatedKcal,
                // `manualKcal` non nil veut dire « chiffre saisi à la main », donc pas de
                // tilde : la règle du journal depuis la 1.10, telle quelle.
                isManual: repas.manualKcal != nil)
        }
    }

    func duoActivityInputs(_ activites: [ActivityEntry]) -> [ActivityFeedInput] {
        activites.map { activite in
            ActivityFeedInput(
                publicID: activite.publicID,
                date: activite.date,
                title: activityTitle(for: activite),
                durationMinutes: activite.durationMinutes,
                xp: activite.xpAwarded)
        }
    }

    /// « AAAA-MM-JJ » dans le calendrier LOCAL. Une chaîne et non une `Date` : c'est une
    /// étiquette de journée, et deux fuseaux ne doivent pas pouvoir la faire glisser d'un
    /// jour chez le partenaire.
    static func duoDayKey(for date: Date) -> String {
        let jour = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", jour.year ?? 0, jour.month ?? 0, jour.day ?? 0)
    }
}
