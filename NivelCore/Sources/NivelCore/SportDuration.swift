// SportDuration.swift
// Choix et enregistrement de la durée d'une activité libre (spec v1.9 §5).

import Foundation

/// Ce que l'utilisateur a choisi dans la section « Durée ».
public enum DurationSelection: Equatable, Hashable, Sendable {
    /// Une des durées du catalogue de l'activité.
    case preset(Int)
    /// Une durée saisie à la roue.
    case custom(Int)

    public var minutes: Int {
        switch self {
        case .preset(let minutes), .custom(let minutes): minutes
        }
    }

    public var isCustom: Bool {
        if case .custom = self { true } else { false }
    }
}

public enum CustomDuration {
    /// Bornes de la roue. 4 h couvre la plus longue randonnée plausible.
    public static let range = 1...240

    /// Valeur d'ouverture de la roue : la durée déjà choisie si elle est plausible,
    /// sinon la médiane du catalogue de l'activité, sinon 20 minutes. On ne part
    /// jamais de 1 minute, qui obligerait à faire défiler toute la roue.
    public static func openingValue(current: Int?, durations: [Int]) -> Int {
        if let current, range.contains(current) { return current }
        let sorted = durations.sorted()
        if !sorted.isEmpty {
            let median = sorted[sorted.count / 2]
            if range.contains(median) { return median }
        }
        return 20
    }
}

/// Durée réellement enregistrée à la validation.
public enum LoggedDuration {
    /// - Parameters:
    ///   - elapsedSeconds: écoulé du modèle de timer. Il est DÉJÀ plafonné à la durée
    ///     choisie côté modèle ; le plafond est répété ici pour que la fonction soit
    ///     juste indépendamment de son appelant.
    ///   - timerUsed: le timer a été lancé au moins une fois.
    public static func resolve(chosenMinutes: Int, elapsedSeconds: TimeInterval,
                               timerUsed: Bool) -> Int {
        guard timerUsed else { return chosenMinutes }
        let rounded = Int((elapsedSeconds / 60).rounded())
        return min(chosenMinutes, max(1, rounded))
    }
}
