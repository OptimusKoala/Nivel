// App/Services/MuscuPlanSettings.swift
// Interrupteur du programme muscu maison, PAR APPAREIL (spec v1.14 §4.4) : miroir de
// PosturePlanSettings — UserDefaults, pas SwiftData, injectable pour les tests.
// Défaut FAUX, pour la même raison que la posture : le programme n'existe que sur le
// téléphone qui l'allume explicitement, jamais par défaut sur les deux.

import Foundation
import Observation

@MainActor
@Observable
final class MuscuPlanSettings {
    static let shared = MuscuPlanSettings()
    static let defaultsKey = "nivel.muscuPlan"

    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.defaultsKey) }
    }

    private let defaults: UserDefaults

    /// `defaults` injectable pour les tests (suite dédiée, jamais les vrais
    /// réglages). `object(forKey:)` et non `bool(forKey:)` : il faut distinguer
    /// "jamais réglé" (donc éteint, ici) de "réglé à false".
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.object(forKey: Self.defaultsKey) as? Bool ?? false
    }

    /// Allumer ou éteindre le programme doit AUSSI (dés)activer explicitement le
    /// rappel de 19 h sur le profil (spec §4.4) : une clé absente de
    /// `remindersEnabled` vaut désactivée (piège documenté v1.9), donc le rappel
    /// naîtrait éteint si l'on se contentait de basculer l'interrupteur seul.
    /// Réassignation complète du dictionnaire (règle SwiftData : jamais de
    /// mutation en place), puis replanification des notifications.
    ///
    /// Ne touche QUE la clé "muscu" : les deux programmes sont indépendants, allumer
    /// la muscu ne doit rien changer au rappel posture du téléphone d'à côté ni à
    /// celui d'ici.
    func setEnabled(_ enabled: Bool, on profile: UserProfile) {
        isEnabled = enabled
        var reminders = profile.remindersEnabled
        reminders["muscu"] = enabled
        profile.remindersEnabled = reminders
        NotificationService.reschedule(for: profile)
    }
}
