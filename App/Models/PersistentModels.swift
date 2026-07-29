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
    var dishID: String
    var portionRaw: String
    var extras: [String: Int]            // extraID → quantité
    var estimatedKcal: Int
    var xpAwarded: Int

    init(
        date: Date = .now,
        slot: MealSlot,
        dishID: String,
        portion: Portion,
        extras: [String: Int] = [:],
        estimatedKcal: Int,
        xpAwarded: Int = 0
    ) {
        self.date = date
        self.slotRaw = slot.rawValue
        self.dishID = dishID
        self.portionRaw = portion.rawValue
        self.extras = extras
        self.estimatedKcal = estimatedKcal
        self.xpAwarded = xpAwarded
    }

    var slot: MealSlot {
        get { MealSlot(rawValue: slotRaw) ?? .snack }
        set { slotRaw = newValue.rawValue }
    }

    var portion: Portion {
        get { Portion(rawValue: portionRaw) ?? .normal }
        set { portionRaw = newValue.rawValue }
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
    var completedThisWeekQuestIDs: [String] // garde anti re-récompense de la semaine courante
    var lastClosedDay: Date?

    init(
        totalXP: Int = 0,
        badgeUnlocks: [String: Date] = [:],
        activeQuestIDs: [String] = [],
        questWeekID: String = "",
        questProgress: [String: Int] = [:],
        completedQuestIDs: [String] = [],
        completedThisWeekQuestIDs: [String] = [],
        lastClosedDay: Date? = nil
    ) {
        self.totalXP = totalXP
        self.badgeUnlocks = badgeUnlocks
        self.activeQuestIDs = activeQuestIDs
        self.questWeekID = questWeekID
        self.questProgress = questProgress
        self.completedQuestIDs = completedQuestIDs
        self.completedThisWeekQuestIDs = completedThisWeekQuestIDs
        self.lastClosedDay = lastClosedDay
    }
}
