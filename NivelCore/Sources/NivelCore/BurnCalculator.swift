// NivelCore/Sources/NivelCore/BurnCalculator.swift
// Dépense calorique du jour (spec v1.14 §5.4) : pas + activités NON marchées.
// Pur, le barème est injecté — testable sans HealthKit ni SwiftData.
//
// Ces kcal restent INDICATIVES et ne sont jamais créditées au budget alimentaire
// (règle v1 §2) : une heure de marche n'autorise pas une pizza. L'estimation est
// fausse de 30 %, et la créditer en ferait un permis de manger.

import Foundation

/// Ce que `BurnCalculator` a besoin de savoir d'une validation sport. Volontairement
/// pas `ActivityEntry` : le paquet ne connaît pas SwiftData.
public struct BurnEntry: Sendable, Equatable {
    public let kind: ActivityKind
    public let refID: String
    public let estimatedKcal: Int
    public init(kind: ActivityKind, refID: String, estimatedKcal: Int) {
        self.kind = kind
        self.refID = refID
        self.estimatedKcal = estimatedKcal
    }
}

/// Les pas du jour, tels que `BurnCalculator` a besoin de les connaître. Un `Int?`
/// se laisserait promouvoir en silence depuis un `Int` (ex. `kcal(steps: log.steps,
/// …)` compilerait alors que `log.steps` n'est jamais nil) : cet enum force l'appelant
/// à énoncer explicitement lequel des deux cas il tient.
public enum DailySteps: Sendable, Equatable {
    case measured(Int)
    /// HealthKit refusé, ou lecture pas encore revenue. Aucun doublon n'est alors
    /// possible : tout compte, marche comprise.
    case unavailable
}

public enum BurnCalculator {
    public static func kcal(
        steps: DailySteps,
        weightKg: Double,
        entries: [BurnEntry],
        activitiesByID: [String: Activity],
        sessionsByID: [String: ActivitySession]
    ) -> Int {
        let stepsKcal: Int
        let excludesWalking: Bool
        switch steps {
        case .measured(let count):
            // `.measured(0)` compte quand même : les pas SONT disponibles, il n'y en a
            // eu aucun, mais le doublon reste possible en théorie — la marche est donc
            // exclue comme pour tout autre décompte mesuré.
            stepsKcal = StepsEstimator.kcal(steps: count, weightKg: weightKg)
            excludesWalking = true
        case .unavailable:
            stepsKcal = 0
            excludesWalking = false
        }

        // Un seul arrondi, à la fin (même règle que MealEstimator) : arrondir
        // séance par séance ferait dériver une journée chargée de plusieurs kcal.
        let fromEntries = entries.reduce(0.0) { total, entry in
            total + contribution(of: entry, excludesWalking: excludesWalking,
                                 activitiesByID: activitiesByID, sessionsByID: sessionsByID)
        }
        return stepsKcal + Int(fromEntries.rounded())
    }

    private static func contribution(
        of entry: BurnEntry,
        excludesWalking: Bool,
        activitiesByID: [String: Activity],
        sessionsByID: [String: ActivitySession]
    ) -> Double {
        guard excludesWalking else { return Double(entry.estimatedKcal) }

        if entry.kind == .activity {
            // Activité inconnue du catalogue : on garde son total, comme pour une
            // séance disparue — mieux vaut un chiffre daté qu'une dépense effacée.
            let isWalking = activitiesByID[entry.refID]?.stepsBased ?? false
            return isWalking ? 0 : Double(entry.estimatedKcal)
        }

        // Séance : une entrée ne stocke qu'un TOTAL, or `fresh_air` est une marche
        // et `home_cardio` contient des escaliers. L'inclure ou l'exclure en bloc
        // serait faux dans les deux sens : on la redécompose par ses étapes.
        guard let session = sessionsByID[entry.refID] else {
            return Double(entry.estimatedKcal)
        }

        var resolvedSteps = 0
        var kept = 0.0
        for step in session.steps {
            guard let activity = activitiesByID[step.activityID] else { continue }
            resolvedSteps += 1
            guard !activity.stepsBased else { continue }
            kept += activity.kcalPerMin * Double(step.minutes)
        }
        // La décomposition n'est retenue que si TOUTES les étapes se résolvent — pas
        // seulement une partie : une étape irrésolue empêcherait de savoir si son kcal
        // manquant aurait été gardé ou exclu, donc pas de décompte partiel (une seule
        // étape marchée résolue sur deux, l'autre introuvable, ne doit pas rendre 0 en
        // silence). Même politique que l'id de séance inconnu ci-dessus : incomplet
        // vaut inconnu, repli sur le total stocké. Distinct de `fresh_air`, dont
        // l'unique étape SE résout (`resolvedSteps == session.steps.count`) mais est
        // marchée — 0 kcal y reste légitime, sans repli.
        //
        // Défense en profondeur plutôt que scénario observé aujourd'hui :
        // `GameService` fusionne déjà `postureActivities()` dans `activitiesByID`
        // (GameService.swift), donc une séance posture connue n'a normalement aucune
        // étape irrésolue. Le vrai risque à surveiller à la Task 5 — une séance
        // ENTIÈRE absente de `sessionsByID` — retombe de toute façon sur le repli
        // préexistant juste au-dessus (`guard let session = … else`), pas sur celui-ci.
        guard resolvedSteps == session.steps.count else { return Double(entry.estimatedKcal) }
        return kept
    }
}
