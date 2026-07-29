// XPEngine.swift
import Foundation

public enum XPAction: String, Codable, Sendable {
    case mealLogged, weighIn, dayWithinTarget, stepGoalReached, questCompleted, badgeUnlocked
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
        }
    }
}
