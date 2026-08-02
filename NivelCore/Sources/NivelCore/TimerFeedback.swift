// TimerFeedback.swift
// Décision du retour de fin de timer (spec v1.9 §3.4) : PURE, sans UIKit ni
// AVFoundation, pour que les tests n'aient ni son à jouer ni réglage à écrire.

import Foundation

/// Signal sonore de fin d'un timer d'exercice.
public enum TimerChime: String, CaseIterable, Hashable, Sendable {
    /// Étape intermédiaire finie : passe à la suite.
    case step
    /// Dernière étape, ou activité libre : c'est terminé.
    case done
}

extension TimerChime {
    /// Ce qu'il faut jouer quand un timer vient de basculer sur `finished`.
    /// `chime` à nil = haptique seule (son coupé dans les Réglages).
    public struct Feedback: Equatable, Sendable {
        public let chime: TimerChime?
        public init(chime: TimerChime?) { self.chime = chime }
    }

    /// Seuil du « son honnête » (v1.5) : au delà, la fin a été vécue en différé,
    /// app en arrière-plan, et célébrer après coup serait faux.
    public static let overrunTolerance: TimeInterval = 2

    /// - Parameters:
    ///   - overrun: dépassement lu AVANT `syncNow` (nil si le timer ne tournait pas).
    ///   - transitioned: `syncNow` vient de basculer sur `finished`.
    ///   - isCurrent: la surface est bien affichée (pages voisines vivantes du TabView).
    public static func decide(overrun: TimeInterval?, transitioned: Bool,
                              isCurrent: Bool, soundEnabled: Bool,
                              chime: TimerChime) -> Feedback? {
        guard transitioned, isCurrent else { return nil }
        guard (overrun ?? .infinity) < overrunTolerance else { return nil }
        return Feedback(chime: soundEnabled ? chime : nil)
    }

    /// `done` seulement sur la dernière étape d'une séance.
    public static func forStep(number: Int, stepCount: Int) -> TimerChime {
        number >= stepCount ? .done : .step
    }
}
