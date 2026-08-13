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

    init(
        day: Date,
        steps: Int = 0,
        kcalEaten: Int = 0,
        kcalTarget: Int = 0,
        xpEarned: Int = 0,
        withinTarget: Bool = false,
        closed: Bool = false
    ) {
        self.day = day
        self.steps = steps
        self.kcalEaten = kcalEaten
        self.kcalTarget = kcalTarget
        self.xpEarned = xpEarned
        self.withinTarget = withinTarget
        self.closed = closed
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
    // ⚠️ CE 1 N'EST PROTÉGÉ PAR AUCUN TEST, et c'est démontré : le passer à 2 laisse
    // les 132 tests de la cible verts. Ce serait pourtant le bug catastrophique du
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
        // 2 et NON 1 : le défaut de déclaration ci-dessus sert aux stores d'avant la
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
