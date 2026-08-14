// App/Models/PersistentModels.swift
import Foundation
import SwiftData
import NivelCore

@Model
final class UserProfile {
    var name: String
    var sexRaw: String
    var birthDate: Date
    var heightCm: Double
    var initialWeightKg: Double
    var activityRaw: String
    var dailyCalorieTarget: Int          // calculé à l'onboarding, modifiable (spec §6)
    var dailyStepGoal: Int               // défaut 8000
    var remindersEnabled: [String: Bool] // id de rappel → actif
    // Défauts au niveau de la DÉCLARATION : requis pour la migration légère SwiftData
    // des stores existants (le défaut de l'init ne suffit pas, leçon de
    // completedThisWeekQuestIDs en v1). Clé absente = valeur du ReminderCatalog.
    var reminderTimes: [String: Int] = [:]      // id → minutes depuis minuit (0...1439)
    var reminderWeekdays: [String: Int] = [:]   // id → jour (1 = dimanche … 7 = samedi)
    // Défaut sur la DÉCLARATION (migration légère SwiftData, même motif que
    // reminderTimes ci-dessus) : 0 = jamais réglé, donc la valeur calculée depuis le
    // poids fait foi (spec v1.14 §5.3). Ni l'onboarding ni l'`init` ne posent 0
    // explicitement — c'est ce défaut de déclaration qui porte le sentinelle, pour
    // les stores d'avant la 1.14 comme pour les profils créés après.
    var dailyBurnTarget: Int = 0
    /// Le frigo (spec v1.14 §6.3) : ids d'ingrédients cochés, qui servent à classer les
    /// idées de repas. Défaut sur la DÉCLARATION, même motif que `reminderTimes` et
    /// `dailyBurnTarget` ci-dessus (migration légère SwiftData) ; pas de paramètre d'init,
    /// un profil neuf comme un profil migré part du frigo vide. Se mute par `Pantry`.
    var pantryItemIDs: [String] = []
    var createdAt: Date
    var lastMessageIDs: [String: String] // contexte → dernier id de message (anti-répétition)

    init(
        name: String,
        sex: Sex,
        birthDate: Date,
        heightCm: Double,
        initialWeightKg: Double,
        activity: ActivityLevel,
        dailyCalorieTarget: Int,
        dailyStepGoal: Int = 8000,
        remindersEnabled: [String: Bool] = [:],
        reminderTimes: [String: Int] = [:],
        reminderWeekdays: [String: Int] = [:],
        createdAt: Date = .now,
        lastMessageIDs: [String: String] = [:]
    ) {
        self.name = name
        self.sexRaw = sex.rawValue
        self.birthDate = birthDate
        self.heightCm = heightCm
        self.initialWeightKg = initialWeightKg
        self.activityRaw = activity.rawValue
        self.dailyCalorieTarget = dailyCalorieTarget
        self.dailyStepGoal = dailyStepGoal
        self.remindersEnabled = remindersEnabled
        self.reminderTimes = reminderTimes
        self.reminderWeekdays = reminderWeekdays
        self.createdAt = createdAt
        self.lastMessageIDs = lastMessageIDs
    }

    var sex: Sex {
        get { Sex(rawValue: sexRaw) ?? .male }
        set { sexRaw = newValue.rawValue }
    }

    var activity: ActivityLevel {
        get { ActivityLevel(rawValue: activityRaw) ?? .sedentary }
        set { activityRaw = newValue.rawValue }
    }

    /// Résout le sentinelle `dailyBurnTarget == 0` (spec v1.14 §5.3) : la valeur
    /// réglée dans les Réglages si elle existe, sinon le calcul à la volée depuis le
    /// poids courant — jamais stocké tant que l'utilisateur ne règle rien lui-même.
    /// `currentWeightKg` en paramètre : `UserProfile` ne porte que `initialWeightKg`,
    /// le poids qui compte ici vient de la dernière `WeightEntry` (même chemin que
    /// `SettingsView.currentWeightKg`), que ce type ne peut pas interroger lui-même.
    func burnTarget(currentWeightKg: Double) -> Int {
        dailyBurnTarget > 0 ? dailyBurnTarget : CalorieCalculator.dailyBurnTarget(weightKg: currentWeightKg)
    }
}

/// Mutations du frigo (spec v1.14 §6.3). Réassignation COMPLÈTE du tableau à chaque
/// fois, jamais de mutation en place : c'est la règle que le code se répète depuis la
/// v1 (`remindersEnabled`, `reminderTimes`) pour que SwiftData voie bien passer le
/// changement. Un type à part plutôt que des méthodes sur la vue : la règle est ainsi
/// écrite à UN endroit, et testable sans écran.
enum Pantry {
    static func toggle(_ itemID: String, on profile: UserProfile) {
        if profile.pantryItemIDs.contains(itemID) {
            profile.pantryItemIDs = profile.pantryItemIDs.filter { $0 != itemID }
        } else {
            profile.pantryItemIDs = profile.pantryItemIDs + [itemID]
        }
    }

    // Pas d'`add` : `toggle` est le seul chemin d'écriture, et une méthode que seuls
    // ses tests appellent n'est pas du code couvert, c'est du code inventé. Le jour où
    // une recette voudra remplir le frigo d'un tap, elle s'écrira alors — avec son
    // appelant.

    static func clear(on profile: UserProfile) {
        profile.pantryItemIDs = []
    }
}

@Model
final class MealEntry {
    var date: Date
    var slotRaw: String
    // Défauts sur la DÉCLARATION : migration légère SwiftData (leçon v1, reconfirmée
    // en v1.9). La suppression de dishID, portionRaw et extras est elle aussi légère ;
    // l'unique repas déjà loggé perd son détail et garde ses kcal (spec v1.10 §3.1).
    var lines: [MealLine] = []
    var manualKcal: Int?
    var estimatedKcal: Int
    var xpAwarded: Int

    init(
        date: Date = .now,
        slot: MealSlot,
        lines: [MealLine] = [],
        manualKcal: Int? = nil,
        estimatedKcal: Int,
        xpAwarded: Int = 0
    ) {
        self.date = date
        self.slotRaw = slot.rawValue
        self.lines = lines
        self.manualKcal = manualKcal
        self.estimatedKcal = estimatedKcal
        self.xpAwarded = xpAwarded
    }

    var slot: MealSlot {
        get { MealSlot(rawValue: slotRaw) ?? .snack }
        set { slotRaw = newValue.rawValue }
    }
}

@Model
final class ActivityEntry {
    var date: Date
    var kindRaw: String                  // ActivityKind (activité libre / séance du jour)
    var refID: String                    // activityID ou sessionID selon kind
    var durationMinutes: Int
    var estimatedKcal: Int               // indicatif — jamais crédité au budget (spec sport §2)
    var xpAwarded: Int

    init(
        date: Date = .now,
        kind: ActivityKind,
        refID: String,
        durationMinutes: Int,
        estimatedKcal: Int,
        xpAwarded: Int = 0
    ) {
        self.date = date
        self.kindRaw = kind.rawValue
        self.refID = refID
        self.durationMinutes = durationMinutes
        self.estimatedKcal = estimatedKcal
        self.xpAwarded = xpAwarded
    }

    var kind: ActivityKind {
        get { ActivityKind(rawValue: kindRaw) ?? .activity }
        set { kindRaw = newValue.rawValue }
    }
}

@Model
final class WeightEntry {
    var date: Date
    var weightKg: Double

    init(date: Date = .now, weightKg: Double) {
        self.date = date
        self.weightKg = weightKg
    }
}

@Model
final class DayLog {
    @Attribute(.unique) var day: Date    // minuit local
    var steps: Int
    var kcalEaten: Int
    var kcalTarget: Int
    var xpEarned: Int
    var withinTarget: Bool
    var closed: Bool                     // clôturé par DayCloser
    // Défauts sur la DÉCLARATION (migration légère SwiftData). Renseignés par
    // DayCloser à la clôture : c'est le seul moment où la dépense du jour est
    // définitive (les pas peuvent encore monter jusqu'à minuit).
    //
    // Deux conséquences à connaître AVANT de lire ce champ :
    // 1. Les journées d'avant la 1.14 restent à 0 et ne sont PAS rétro-calculées.
    //    `steps == 0` y est exactement l'ambiguïté que `DailySteps` a été créé pour
    //    éliminer : impossible de savoir après coup si c'était "HealthKit refusé" ou
    //    "zéro pas". Un rétro-calcul devrait trancher, donc se tromperait sur une
    //    moitié du passé — et réintroduirait EN BASE le zéro silencieux que tout le
    //    reste du code interdit. Ne rien inventer est plus honnête.
    // 2. La journée EN COURS vaut 0 tant qu'elle n'est pas close. Un affichage
    //    d'aujourd'hui (anneau de dépense) doit appeler `GameService.burnKcal(on:
    //    steps:weightKg:)` avec les vrais pas du service, JAMAIS lire ce champ,
    //    sinon il resterait à zéro toute la journée puis sauterait à minuit.
    var kcalBurned: Int = 0
    /// Objectif de dépense du jour, GELÉ à la clôture — exact pendant de `kcalTarget`,
    /// et pour la même raison : sans lui, `burnTargetReached` est un verdict que plus
    /// personne ne peut re-dériver dès que l'objectif change dans les Réglages, et un
    /// historique afficherait « objectif atteint » sans dénominateur.
    /// Ajouté MAINTENANT bien qu'aucun écran ne le lise encore : l'ajouter plus tard
    /// rouvrirait exactement le « on ne rétro-calcule pas » ci-dessus, et il n'y aurait
    /// alors plus aucun moyen de le renseigner pour le passé.
    var burnTarget: Int = 0
    var burnTargetReached: Bool = false

    init(
        day: Date,
        steps: Int = 0,
        kcalEaten: Int = 0,
        kcalTarget: Int = 0,
        xpEarned: Int = 0,
        withinTarget: Bool = false,
        closed: Bool = false,
        kcalBurned: Int = 0,
        burnTarget: Int = 0,
        burnTargetReached: Bool = false
    ) {
        self.day = day
        self.steps = steps
        self.kcalEaten = kcalEaten
        self.kcalTarget = kcalTarget
        self.xpEarned = xpEarned
        self.withinTarget = withinTarget
        self.closed = closed
        self.kcalBurned = kcalBurned
        self.burnTarget = burnTarget
        self.burnTargetReached = burnTargetReached
    }
}

@Model
final class GamificationState {
    var totalXP: Int
    var badgeUnlocks: [String: Date]     // badgeID → date
    var activeQuestIDs: [String]
    var questWeekID: String
    var questProgress: [String: Int]
    var completedQuestIDs: [String]      // historique all-time, doublons permis (pour badges)
    // Défaut au niveau de la déclaration : requis pour la migration légère SwiftData
    // des stores existants (le défaut de l'init ne suffit pas).
    var completedThisWeekQuestIDs: [String] = [] // garde anti re-récompense de la semaine courante
    // Défaut au niveau de la DÉCLARATION : requis pour la migration légère SwiftData
    // des stores existants (le défaut de l'init ne suffit pas — leçon de
    // completedThisWeekQuestIDs en v1, reconfirmée par reminderTimes en v1.9).
    // 1 = courbe d'avant la 1.14, 2 = courbe durcie avec recharge appliquée.
    //
    // SON UNIQUE LECTEUR est `GameService.migrateLevelCurveIfNeeded()`
    // (App/Services/GameService+LevelMigration.swift) : l'en-tête de ce fichier décrit
    // le dispositif entier, dont le défaut de l'`init` ci-dessous, qui vaut 2 et NON 1.
    // Les deux valeurs diffèrent exprès — ne pas les harmoniser sans l'avoir lu.
    //
    // ⚠️ CE 1 N'EST PROTÉGÉ PAR AUCUN TEST, et c'est démontré : le passer à 2 laisse
    // la cible entière verte. Ce serait pourtant le bug catastrophique du
    // lot — chaque joueur d'avant la 1.14 sauterait la migration et tomberait du
    // niveau 13 au niveau 6, sans moyen de le retrouver. Aucune suite ne peut
    // l'attraper : toutes montent des stores `isStoredInMemoryOnly` et fixent la
    // version à la main, alors que ce défaut ne sert QUE lorsque SwiftData lit une
    // colonne absente d'un store créé avant la 1.14. La seule vérification possible
    // est manuelle : installer la 1.13, gagner de l'XP, puis mettre à jour.
    var levelCurveVersion: Int = 1
    var lastClosedDay: Date?

    init(
        totalXP: Int = 0,
        badgeUnlocks: [String: Date] = [:],
        activeQuestIDs: [String] = [],
        questWeekID: String = "",
        questProgress: [String: Int] = [:],
        completedQuestIDs: [String] = [],
        completedThisWeekQuestIDs: [String] = [],
        // 2 et NON 1 (voir GameService+LevelMigration.swift, pièce 2 du dispositif) :
        // le défaut de déclaration ci-dessus sert aux stores d'avant la
        // 1.14, qui n'ont pas la clé. Un état créé PAR le code de la 1.14 (onboarding)
        // naît, lui, sur la nouvelle courbe. Sans cette asymétrie, une installation
        // neuve se ferait « recharger » au lancement suivant une XP déjà gagnée sous la
        // nouvelle courbe : sept niveaux offerts à 3 000 XP.
        levelCurveVersion: Int = 2,
        lastClosedDay: Date? = nil
    ) {
        self.totalXP = totalXP
        self.badgeUnlocks = badgeUnlocks
        self.activeQuestIDs = activeQuestIDs
        self.questWeekID = questWeekID
        self.questProgress = questProgress
        self.completedQuestIDs = completedQuestIDs
        self.completedThisWeekQuestIDs = completedThisWeekQuestIDs
        self.levelCurveVersion = levelCurveVersion
        self.lastClosedDay = lastClosedDay
    }
}
