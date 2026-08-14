// XPEngine.swift
import Foundation

public enum XPAction: String, Codable, Sendable {
    case mealLogged, weighIn, dayWithinTarget, stepGoalReached, questCompleted, badgeUnlocked
    case activityDone, dailySessionDone
    /// Programme posture (spec v1.11 §8) : plafond INDÉPENDANT de `dailySessionDone`.
    /// Réutiliser ce dernier ferait que la séance du jour ET la séance posture le même
    /// soir ne paieraient qu'une fois, ce qui punirait exactement le comportement que
    /// le lot veut installer.
    case postureSessionDone
    /// Programme muscu maison (spec v1.14 §5.7) : troisième plafond INDÉPENDANT,
    /// pour la même raison que `postureSessionDone`. Mutualiser les plafonds ferait
    /// que deux séances faites le même soir ne paieraient qu'une fois, ce qui
    /// punirait exactement le comportement que le lot veut installer.
    case muscuSessionDone
}

public enum XPEngine {
    /// XP attribué pour une action, compte tenu du nombre de fois où elle a DÉJÀ été récompensée aujourd'hui.
    public static func award(_ action: XPAction, todayCount: Int) -> Int {
        switch action {
        case .mealLogged:      todayCount < 4 ? 20 : 0
        case .weighIn:         todayCount < 1 ? 30 : 0
        case .dayWithinTarget: 50
        case .stepGoalReached: 40
        case .questCompleted:  150
        case .badgeUnlocked:   50
        case .activityDone:    todayCount < 2 ? 30 : 0
        case .dailySessionDone: todayCount < 1 ? 40 : 0
        case .postureSessionDone: todayCount < 1 ? 40 : 0
        case .muscuSessionDone: todayCount < 1 ? 40 : 0
        }
    }
}
