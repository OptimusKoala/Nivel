// App/Support/ScreenshotSupport.swift
//
// Mode « captures App Store » — COMPILÉ EN DEBUG UNIQUEMENT : rien de tout ceci
// n'existe dans le binaire envoyé à Apple.
//
// Le but : produire des captures identiques à chaque exécution, sans toucher aux
// vraies données du téléphone. On lance donc l'app sur un store EN MÉMOIRE, garni
// d'un profil de démonstration, avec un fournisseur de pas simulé (le simulateur
// n'a pas de données HealthKit).
//
// Usage (voir scripts/screenshots.sh) :
//   xcrun simctl launch <device> com.elitedangereuse.Nivel \
//       --nivel-screenshots -nivelScreen quests -nivel.theme night
//
// `--nivel-screenshots` active le mode ; `-nivelScreen` choisit l'écran à afficher
// (les arguments préfixés d'un tiret sont lus par UserDefaults, convention Apple).

#if DEBUG

import Foundation
import SwiftData
import SwiftUI          // pour le seul CGFloat/UIKit du défilement d'ouverture, plus bas
import NivelCore

enum ScreenshotMode {
    /// Écran demandé pour cette exécution.
    enum Screen: String {
        case home, meallog, activitylog, meals, sport, session, step, progress, quests
        /// La bande d'idées de saison (v1.14 §6.4), et la fiche recette par-dessus.
        /// Deux écrans et non un seul, pour la même raison que `meallog` est distinct
        /// de `home` : la fiche est présentée en `.large`, elle couvre la bande — une
        /// seule capture ne peut pas montrer les deux.
        case idees, recette
    }

    static let isEnabled = ProcessInfo.processInfo.arguments.contains("--nivel-screenshots")

    static var screen: Screen {
        Screen(rawValue: UserDefaults.standard.string(forKey: "nivelScreen") ?? "") ?? .home
    }

    /// Le splash mange 2,4 s à chaque lancement : inutile quand on capture un onglet.
    static var skipsSplash: Bool { isEnabled }

    /// Ouvre d'office le lecteur de séance (captures « séance du jour » et « étape guidée »).
    static var autoOpensDailySession: Bool { isEnabled && (screen == .session || screen == .step) }

    /// Page du lecteur à l'ouverture : 0 = aperçu de la séance, 1 = première étape.
    static var sessionInitialPage: Int { screen == .step ? 1 : 0 }

    /// Ouvre d'office la feuille de log de repas (capture « catalogue d'aliments »).
    static var autoOpensMealLog: Bool { isEnabled && screen == .meallog }

    /// Section sur laquelle l'écran Sport s'ouvre — `nil` = en haut, comme dans l'app.
    ///
    /// Pour la capture `sport` : `.strong`, « Ça pousse ». C'est la section que le lot F
    /// exige de voir sur `03-sport` (spec v1.14 §7), et elle est TROISIÈME dans
    /// `SportSection.displayOrder` : vingt lignes d'activités douces la précèdent, soit
    /// deux écrans de défilement. Aucun garnissage du jeu de démonstration ne pouvait la
    /// faire remonter — c'est le catalogue lui-même qui est long — donc on déplace le
    /// regard plutôt que le contenu : la capture montre l'app telle qu'elle est, à un
    /// endroit où l'utilisateur peut réellement arriver d'un coup de pouce.
    ///
    /// `nil` pour `session` et `step`, qui rendent le MÊME écran sous leur feuille : ces
    /// deux captures-là n'ont pas à hériter d'un défilement dont on ne voit rien, et une
    /// feuille qui s'ouvre pendant qu'on défile derrière est un tirage de moins bonne
    /// qualité pour rien.
    static var initialSportSection: SportSection? {
        isEnabled ? initialSportSection(for: screen) : nil
    }

    /// La même règle, en fonction pure de l'écran : `isEnabled` dépend des arguments du
    /// processus, qu'un test ne peut pas se donner (`ScreenshotSportTests` appelle
    /// celle-ci, écran par écran).
    static func initialSportSection(for screen: Screen) -> SportSection? {
        screen == .sport ? .strong : nil
    }

    /// La hauteur de la barre d'état, en points : ce qu'il faut dégager en haut d'un
    /// écran ouvert au milieu d'une liste (voir `SportView`, qui s'en sert deux fois).
    ///
    /// Deux choses à savoir sur `scrollTo(anchor: .top)` dans une `List`, toutes deux
    /// vérifiées à l'image plutôt que déduites de la documentation :
    ///
    /// 1. il aligne la vue visée sur le haut de la ZONE SÛRE de la liste, et le contenu
    ///    d'une liste défile SOUS la barre d'état — un écran nu met donc « ÇA POUSSE »
    ///    à cheval sur « 9 h 41 ». Rendre cette hauteur à la liste (`safeAreaInset`)
    ///    redescend le titre juste sous l'heure ;
    /// 2. il aligne le TITRE lui-même, pas la ligne qui le porte : tout blanc ajouté
    ///    au-dessus part hors de l'écran. C'est ce qui permet de chasser la dernière
    ///    ligne de la section précédente, qui sinon dépasse, coupée, derrière l'heure.
    ///
    /// L'`anchor` ne remplace ni l'un ni l'autre : `UnitPoint` est une FRACTION, prise à
    /// l'échelle du contenu défilable — 0,09 y déplaçait la section de 364 pt, et la
    /// moindre activité ajoutée au catalogue changerait ce que vaut la même fraction.
    /// Une hauteur en points, elle, dit ce qu'elle fait et ne dérive pas.
    ///
    /// Lue sur la fenêtre plutôt qu'écrite en dur — le 6,9 pouces d'aujourd'hui ne sera
    /// pas celui de la prochaine version — avec un repli de 62 pt (le sien) tant qu'elle
    /// n'est pas là : mieux vaut un peu de blanc en trop qu'un titre sur l'heure.
    @MainActor
    static var scrolledHeaderCushion: CGFloat {
        let inset = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .safeAreaInsets.top
        return inset.map { $0 > 0 ? $0 : 62 } ?? 62
    }

    /// Ouvre d'office la page « Tu viens de faire quoi ? » (spec v1.13 §6.3) — miroir
    /// exact d'`autoOpensMealLog`, pour pouvoir capturer et relire le second bouton
    /// d'action sans avoir à simuler un tap.
    static var autoOpensActivityPicker: Bool { isEnabled && screen == .activitylog }

    /// Ouvre d'office la fiche de la PREMIÈRE idée de la bande — même montage que les
    /// deux crochets ci-dessus. Le lot D a laissé la fiche présentée depuis un état de
    /// `MealsJournalView` (`shownRecipe`) précisément pour rendre ceci possible.
    static var autoOpensRecipeDetail: Bool { isEnabled && screen == .recette }

    // MARK: - Les idées de saison (écrans `idees` et `recette`)

    /// Les deux écrans qui montrent les idées. Ils partagent le frigo garni et la date
    /// épinglée ci-dessous ; tous les autres gardent le frigo vide et l'horloge réelle.
    static var showsIdeas: Bool { isEnabled && (screen == .idees || screen == .recette) }

    /// Date de référence de la bande d'idées pour ces deux écrans.
    ///
    /// TROIS choses de la bande dépendent de l'instant, et aucune n'est figée par
    /// `scripts/screenshots.sh`, qui ne fige que la barre d'état : le créneau visé
    /// (déjeuner jusqu'à 15 h, dîner ensuite), le mois gravé dans le titre (« · août »),
    /// et la rotation des idées incomplètes, qui tourne avec le jour de l'année. Sans
    /// épinglage, une capture prise l'après-midi grave « Idées pour ce soir » au-dessus
    /// d'une barre d'état à 9 h 41 — l'image se contredit toute seule sur l'App Store —
    /// et deux tournages à deux jours d'écart ne donnent pas les mêmes trois plats.
    ///
    /// 13 août 2026, 9 h 41 : l'heure EXACTE de la barre d'état (d'où « Idées pour ce
    /// midi »), et la date de la 1.14, en pleine saison des recettes d'été. Une sortie
    /// d'hiver n'aura qu'à changer ces quatre nombres — et à revoir `demoPantry`, dont
    /// l'éloquence est vérifiée à cette date-là par `ScreenshotIdeasTests`.
    ///
    /// Le repli est inatteignable (ces composantes-là existent dans tout calendrier
    /// grégorien) mais `Calendar.date(from:)` est optionnel et ne se force pas ici :
    /// un `!` dans du code de captures ferait planter le tournage plutôt que de rendre
    /// une image imparfaite.
    static let ideasReferenceDate: Date = GameService.calendar.date(
        from: DateComponents(year: 2026, month: 8, day: 13, hour: 9, minute: 41)
    ) ?? .now

    /// La même, mais `nil` hors mode captures : c'est ce que `MealsJournalView`
    /// interroge, et l'app y lit son horloge partout ailleurs.
    static var ideasReference: Date? { showsIdeas ? ideasReferenceDate : nil }

    /// Le frigo du profil de démonstration.
    ///
    /// Posé sur le profil pour les SEULS écrans d'idées (voir `seed`), et c'est
    /// essentiel : `NivelUITests/IdeasJourneyTests` part de l'écran `meals` et du frigo
    /// VIDE — cartes muettes sur ce qui manque, carte d'invitation 🧺 en bout de bande —
    /// puis le garnit lui-même. Garnir sans condition casserait
    /// `testLeFrigoChangeCeQueLaBandeDit` dès sa première assertion.
    ///
    /// Ces huit ingrédients-là, à la date épinglée, donnent une bande en GRADATION :
    /// « Omelette et salade de tomates » dont on a tout, « Gaspacho et pain grillé » à
    /// « Il manque 1 », « Salade de lentilles » à « Il manque 2 ». C'est ce qui se
    /// montre le mieux sur une image : deux cartes « Tu as tout ✓ » côte à côte
    /// prouvent surtout que l'exemple a été arrangé, tandis qu'une gradation montre le
    /// classement en train de faire son travail.
    ///
    /// Et rien ne s'y répète en pictogramme — ni les trois cartes entre elles (🍳 🍅
    /// 🥗), ni les ingrédients de la fiche ouverte. Ce n'est pas automatique : le
    /// catalogue donne facilement deux 🍅 côte à côte (« Gaspacho » et « Tomates et
    /// mozzarella ») ou deux 🫒 dans une même fiche (« Olives » et « Huile d'olive »),
    /// et sur une capture App Store deux pictogrammes identiques voisins se lisent
    /// comme un défaut de rendu, pas comme un catalogue. Les répétitions d'emoji du
    /// catalogue RESTENT (décision du propriétaire) : c'est le frigo de démonstration
    /// qui les contourne, et `ScreenshotIdeasTests` qui l'en empêche de dériver.
    static let demoPantry = ["egg", "tomato", "lettuce", "bread",
                             "butter", "green_veg", "tomato_sauce", "grated_cheese"]

    // MARK: - Environnement d'exécution

    /// Store en mémoire : aucune trace sur le disque, état identique à chaque lancement.
    static func makeContainer() -> ModelContainer {
        let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                            DayLog.self, GamificationState.self, ActivityEntry.self])
        return try! ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
        )
    }

    /// Pas simulés sur la semaine — le simulateur n'a aucune donnée HealthKit.
    static func makeStepsService() -> StepsProviding {
        let calendar = GameService.calendar
        let today = calendar.startOfDay(for: .now)
        // Aujourd'hui en premier, puis les six jours précédents.
        let history = [7_240, 9_120, 6_480, 10_350, 8_060, 5_910, 8_740]
        var byDay: [Date: Int] = [:]
        for (offset, steps) in history.enumerated() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            byDay[day] = steps
        }
        return FakeStepsService(stepsByDay: byDay, authorized: true)
    }

    /// Panier pré-rempli de la feuille de log : le catalogue « Déjeuner » est le plus
    /// riche, et deux lignes montrent l'estimation en direct plutôt qu'un panier vide.
    static func demoMealLines(catalog: FoodCatalog) -> [MealLine] {
        ["salad", "fruit"].compactMap { catalog.byID[$0] }.map { catalog.line(for: $0) }
    }

    // MARK: - Jeu de données de démonstration

    /// Garnit le store : profil, huit semaines de pesées, repas de la semaine,
    /// activités, journées clôturées, XP et badges. Miroir de ce que ferait
    /// l'onboarding suivi de quelques semaines d'usage.
    static func seed(into context: ModelContext) {
        let calendar = GameService.calendar
        let today = calendar.startOfDay(for: .now)
        let foods = (try? FoodCatalog.load()) ?? .empty

        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: today) ?? today
        }
        func moment(_ offset: Int, hour: Int, minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day(offset)) ?? day(offset)
        }

        // --- Profil (les valeurs de l'onboarding, 40 jours d'ancienneté) ---
        let birthDate = calendar.date(from: DateComponents(year: 1990, month: 5, day: 12)) ?? .now
        let target = CalorieCalculator.dailyTarget(sex: .female, weightKg: 74.6, heightCm: 168,
                                                   ageYears: 36, activity: .light)
        let profile = UserProfile(
            name: "Camille",
            sex: .female,
            birthDate: birthDate,
            heightCm: 168,
            initialWeightKg: 78.4,
            activity: .light,
            dailyCalorieTarget: target,
            dailyStepGoal: 8_000,
            remindersEnabled: ["lunch": true, "dinner": true, "weigh": true, "steps": true],
            createdAt: day(-40)
        )
        context.insert(profile)
        // Le frigo : garni pour les seuls écrans d'idées, vide partout ailleurs — voir
        // `demoPantry`, dont l'en-tête dit ce que ce `if` protège.
        if showsIdeas { profile.pantryItemIDs = demoPantry }

        // --- Pesées : 78,4 → 74,6 kg en huit semaines, avec les paliers du réel ---
        let weights: [(offset: Int, kg: Double)] = [
            (-40, 78.4), (-36, 78.1), (-33, 77.6), (-29, 77.8), (-26, 77.1),
            (-22, 76.5), (-19, 76.6), (-15, 75.9), (-12, 75.4), (-8, 75.5),
            (-5, 74.9), (-1, 74.6),
        ]
        for weight in weights {
            context.insert(WeightEntry(date: moment(weight.offset, hour: 8), weightKg: weight.kg))
        }

        // --- Repas ---
        func line(_ id: String) -> MealLine? {
            guard let item = foods.byID[id] else { return nil }
            return foods.line(for: item)
        }
        func log(_ offset: Int, hour: Int, _ slot: MealSlot, _ ids: [String]) {
            let lines = ids.compactMap(line)
            guard !lines.isEmpty else { return }
            let kcal = MealEstimator.kcal(lines: lines, kcalPer100g: foods.kcalPer100g)
            context.insert(MealEntry(date: moment(offset, hour: hour), slot: slot,
                                     lines: lines, estimatedKcal: kcal, xpAwarded: 20))
        }

        // Aujourd'hui : trois repas loggés, le dîner reste à venir — l'anneau de
        // l'accueil est partiellement rempli, ce qui raconte mieux l'app qu'un anneau plein.
        log(0, hour: 8, .breakfast, ["toast", "coffee_milk", "fruit"])
        log(0, hour: 12, .lunch, ["salad", "water"])
        log(0, hour: 16, .snack, ["yogurt", "choco_square"])
        // Les jours précédents alimentent le journal, les quêtes et la courbe des kcal.
        for offset in -6 ... -1 {
            log(offset, hour: 8, .breakfast, ["cereal", "tea"])
            log(offset, hour: 12, .lunch, offset % 2 == 0 ? ["pasta", "veggies"] : ["fish", "rice"])
            log(offset, hour: 19, .dinner, offset % 3 == 0 ? ["soup", "toast"] : ["veggies", "salad"])
        }

        // --- Activités ---
        let activities = (try? Catalogs.activities()) ?? []
        let byID = Dictionary(activities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func logActivity(_ offset: Int, hour: Int, _ id: String, minutes: Int) {
            guard let activity = byID[id] else { return }
            context.insert(ActivityEntry(date: moment(offset, hour: hour), kind: .activity, refID: id,
                                         durationMinutes: minutes,
                                         estimatedKcal: activity.estimatedKcal(minutes: minutes),
                                         xpAwarded: 30))
        }
        logActivity(0, hour: 9, "brisk_walk", minutes: 25)
        logActivity(-1, hour: 18, "yoga", minutes: 20)
        logActivity(-3, hour: 17, "dance", minutes: 15)
        logActivity(-5, hour: 8, "stretching", minutes: 10)

        // --- Journées clôturées (courbes de Progrès + quêtes « dans l'objectif ») ---
        let steps = [1: 8_740, 2: 5_910, 3: 8_060, 4: 10_350, 5: 6_480, 6: 9_120]
        for back in 1 ... 6 {
            let eaten = [1_610, 1_720, 1_480, 1_560, 1_690, 1_520][back - 1]
            context.insert(DayLog(day: day(-back), steps: steps[back] ?? 8_000,
                                  kcalEaten: eaten, kcalTarget: target,
                                  xpEarned: 90, withinTarget: eaten <= target, closed: true))
        }

        // --- Progression : niveau 8 à mi-parcours, neuf badges, quêtes de la semaine ---
        let weekID = QuestEngine.weekID(for: .now, calendar: GameService.calendar)
        // Tous les badges que les données ci-dessus méritent — sinon l'évaluation du
        // lancement en débloquerait un « à l'instant » et Nivelito annoncerait un badge
        // sur la capture d'accueil.
        let badges = ["first_meal": day(-40), "first_weigh": day(-40), "sport_first": day(-39),
                      "journal_7": day(-33), "steps_10k": day(-26), "trend_down": day(-24),
                      "quest_first": day(-19), "weigh_10": day(-8), "level_5": day(-6)]
        // Quêtes FIGÉES (et non tirées au sort) : le tirage réel dépend de la semaine ISO
        // en cours, et une capture faite un lundi montrerait trois quêtes à 0 — la semaine
        // vient de commencer. Ces trois-là viennent du catalogue, avec une progression
        // représentative d'un milieu de semaine. `refreshQuestProgress` est neutralisé
        // en mode captures pour ne pas les recalculer depuis les données du store.
        context.insert(GamificationState(
            totalXP: 1_613,
            badgeUnlocks: badges,
            activeQuestIDs: ["log_meals_14", "steps_35k", "activities_3"],
            questWeekID: weekID,
            questProgress: ["log_meals_14": 9, "steps_35k": 22_450, "activities_3": 2],
            // Journée d'hier déjà clôturée : le rattrapage du lancement n'a rien à
            // faire et ne peut donc pas modifier l'état capturé.
            lastClosedDay: day(-1)
        ))

        try? context.save()
    }
}

#endif
