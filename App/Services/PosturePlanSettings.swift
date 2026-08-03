// App/Services/PosturePlanSettings.swift
// Interrupteur du programme posture, PAR APPAREIL (spec v1.11 §3) : copie conforme
// de SoundSettings.swift — UserDefaults, pas SwiftData, injectable pour les tests.
// Défaut FAUX (et non vrai comme le son) : le programme n'existe que sur le
// téléphone qui l'allume explicitement, jamais par défaut sur les deux.

import Foundation
import Observation

@MainActor
@Observable
final class PosturePlanSettings {
    static let shared = PosturePlanSettings()
    static let defaultsKey = "nivel.posturePlan"

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
    /// rappel de 21 h sur le profil (spec §3, §10) : une clé absente de
    /// `remindersEnabled` vaut désactivée (piège documenté v1.9), donc le rappel
    /// naîtrait éteint si l'on se contentait de basculer l'interrupteur seul.
    /// Réassignation complète du dictionnaire (règle SwiftData : jamais de
    /// mutation en place), puis replanification des notifications.
    ///
    /// N'agit QUE sur l'interrupteur et le rappel : éteindre en cours de semaine
    /// ne touche jamais `activeQuestIDs` ni `questProgress` (spec §7.2) — une
    /// quête posture active devenue inatteignable reste à sa progression, ne se
    /// complète pas, et le lundi suivant en tire une autre sans qu'on l'y force.
    func setEnabled(_ enabled: Bool, on profile: UserProfile) {
        isEnabled = enabled
        var reminders = profile.remindersEnabled
        reminders["posture"] = enabled
        profile.remindersEnabled = reminders
        NotificationService.reschedule(for: profile)
    }
}
