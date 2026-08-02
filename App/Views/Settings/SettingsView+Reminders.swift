// App/Views/Settings/SettingsView+Reminders.swift
// Section "Rappels" des réglages (spec §4.5) : un toggle par rappel, persisté
// dans profile.remindersEnabled (SwiftData) puis re-planifié via
// NotificationService. Isolé dans son propre fichier car c'est cette section
// que la Task 9 remplace par des sélecteurs d'heure et de jours par rappel.

import SwiftUI
import NivelCore

extension SettingsContent {
    // MARK: - Rappels

    /// Jour de référence pour les bindings d'heure : le 1er janvier 2000, qui n'a
    /// aucun changement d'heure. Construire la date par composantes (et non en
    /// ajoutant des secondes à minuit) évite le décalage des jours de bascule.
    private static let referenceDayComponents = DateComponents(year: 2000, month: 1, day: 1)

    var remindersSection: some View {
        section("Rappels") {
            ForEach(Array(ReminderCatalog.all.enumerated()), id: \.element.id) { index, definition in
                if index > 0 { divider }
                reminderRow(definition)
            }
        }
    }

    private func reminderRow(_ definition: ReminderDefinition) -> some View {
        let isOn = profile.remindersEnabled[definition.id] ?? false
        let minutes = resolvedMinutes(definition)
        let weekday = resolvedWeekday(definition)
        let phrase = ReminderSchedule.frLabel(hour: minutes / 60, minute: minutes % 60,
                                              weekday: weekday)

        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(definition.title).font(.subheadline.weight(.semibold))
                Text(ReminderSchedule.frFrequency(weekday: weekday))
                    .font(.caption).foregroundStyle(Theme.subtext)
            }
            // Le bloc de texte est combiné et porte la phrase entière ; les contrôles
            // gardent chacun leur libellé et restent actionnables séparément.
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(definition.title), \(phrase)")

            Spacer(minLength: 4)

            if definition.isWeekdayEditable {
                Picker("", selection: weekdayBinding(definition)) {
                    ForEach(Array(ReminderSchedule.weekdayRange), id: \.self) { day in
                        Text(ReminderSchedule.frShortWeekday(day)).tag(day)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .disabled(!isOn)
                .accessibilityLabel("Jour du rappel \(definition.title)")
            }

            DatePicker("", selection: timeBinding(definition),
                       displayedComponents: .hourAndMinute)
                .datePickerStyle(.compact)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "fr_FR"))
                // Rappel éteint : iOS grise le contrôle de lui-même, l'heure n'a donc
                // plus l'air active.
                .disabled(!isOn)
                .accessibilityLabel("Heure du rappel \(definition.title)")

            Toggle("", isOn: enabledBinding(definition.id))
                .labelsHidden()
                .accessibilityLabel("Rappel \(definition.title)")
        }
    }

    // MARK: Valeurs résolues (surcharge du profil, sinon défaut du catalogue)

    private func resolvedMinutes(_ definition: ReminderDefinition) -> Int {
        profile.reminderTimes[definition.id]
            .flatMap { ReminderSchedule.minutesRange.contains($0) ? $0 : nil }
            ?? definition.defaultMinutesFromMidnight
    }

    private func resolvedWeekday(_ definition: ReminderDefinition) -> Int? {
        guard definition.isWeekdayEditable else { return definition.defaultWeekday }
        return profile.reminderWeekdays[definition.id]
            .flatMap { ReminderSchedule.weekdayRange.contains($0) ? $0 : nil }
            ?? definition.defaultWeekday
    }

    // MARK: Bindings
    //
    // Règle SwiftData commune aux trois : réassignation COMPLÈTE du dictionnaire,
    // jamais de mutation en place d'une collection d'un @Model.

    private func enabledBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { profile.remindersEnabled[id] ?? false },
            set: { newValue in
                var enabled = profile.remindersEnabled
                enabled[id] = newValue
                profile.remindersEnabled = enabled
                persistReminders()
            }
        )
    }

    private func timeBinding(_ definition: ReminderDefinition) -> Binding<Date> {
        Binding(
            get: {
                let minutes = resolvedMinutes(definition)
                var components = Self.referenceDayComponents
                components.hour = minutes / 60
                components.minute = minutes % 60
                return Calendar.current.date(from: components) ?? .now
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                var times = profile.reminderTimes
                times[definition.id] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                profile.reminderTimes = times
                persistReminders()
            }
        )
    }

    private func weekdayBinding(_ definition: ReminderDefinition) -> Binding<Int> {
        Binding(
            get: { resolvedWeekday(definition) ?? 1 },
            set: { newValue in
                var weekdays = profile.reminderWeekdays
                weekdays[definition.id] = newValue
                profile.reminderWeekdays = weekdays
                persistReminders()
            }
        )
    }

    /// Faire tourner la roue d'heure appelle ceci des dizaines de fois : le compteur
    /// de génération de NotificationService absorbe la rafale, aucun anti-rebond ici.
    private func persistReminders() {
        save()
        NotificationService.reschedule(for: profile)
    }
}
