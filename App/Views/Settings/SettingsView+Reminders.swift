// App/Views/Settings/SettingsView+Reminders.swift
// Section "Rappels" des réglages (spec §4.5) : un toggle par rappel, persisté
// dans profile.remindersEnabled (SwiftData) puis re-planifié via
// NotificationService. Isolé dans son propre fichier car c'est cette section
// que la Task 9 remplace par des sélecteurs d'heure et de jours par rappel.

import SwiftUI
import NivelCore

extension SettingsContent {
    // MARK: - Rappels

    var remindersSection: some View {
        section("Rappels") {
            reminderToggle("lunch", "Déjeuner", "tous les jours à 12 h 30")
            divider
            reminderToggle("dinner", "Dîner", "tous les jours à 20 h")
            divider
            reminderToggle("weigh", "Pesée", "le samedi à 9 h")
            divider
            reminderToggle("steps", "Pas", "tous les jours à 18 h")
        }
    }

    func reminderToggle(_ id: String, _ title: String, _ subtitle: String) -> some View {
        Toggle(isOn: reminderBinding(id)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(Theme.subtext)
            }
        }
    }

    /// Binding d'un rappel — réassignation COMPLÈTE du dictionnaire (règle SwiftData :
    /// pas de mutation en place des collections d'un @Model), puis re-planification.
    func reminderBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { profile.remindersEnabled[id] ?? false },
            set: { newValue in
                var enabled = profile.remindersEnabled
                enabled[id] = newValue
                profile.remindersEnabled = enabled
                save()
                NotificationService.reschedule(for: profile)
            }
        )
    }
}
