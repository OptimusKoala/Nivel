// App/Services/ReminderPlan+Device.swift
// Le pont entre les programmes de NivelCore (`ReminderPlan`) et les interrupteurs PAR
// APPAREIL de l'app (`PosturePlanSettings`, `MuscuPlanSettings`).
//
// Fichier à part, et non rangé sous l'un des deux programmes : débrancher un jour la
// muscu supprimerait son fichier et emporterait la traduction du programme posture
// avec lui.

import Foundation
import NivelCore

extension ReminderPlan {
    /// L'état de CET interrupteur-ci, sur CE téléphone.
    ///
    /// `switch` exhaustif VOULU, plutôt qu'une suite de `if` : un troisième programme
    /// ne compilera pas tant qu'il n'aura pas dit où lire son état. Avec des `if`
    /// accolés il compilerait très bien, et son rappel serait alors invisible dans les
    /// Réglages ET jamais planifié — en silence, c'est-à-dire exactement le mode de
    /// panne que ce fichier existe pour empêcher.
    @MainActor
    var isEnabledOnThisDevice: Bool {
        switch self {
        case .posture: PosturePlanSettings.shared.isEnabled
        case .muscu: MuscuPlanSettings.shared.isEnabled
        }
    }

    /// Les programmes allumés sur CE téléphone, tels que les attendent
    /// `ReminderCatalog.visibleReminders` et `ReminderPlanner.planned`.
    ///
    /// Un seul endroit qui construit l'ensemble : les deux appelants (les Réglages, qui
    /// filtrent les LIGNES ; le planificateur, qui filtre les NOTIFICATIONS) forment
    /// ENSEMBLE la garantie qu'un rappel ne sonne pas pour un programme invisible.
    /// `allCases` plutôt qu'une liste écrite à la main, pour la même raison que le
    /// `switch` ci-dessus : c'est le compilateur qui tient la liste à jour.
    @MainActor
    static var enabledOnThisDevice: Set<ReminderPlan> {
        Set(allCases.filter(\.isEnabledOnThisDevice))
    }
}
