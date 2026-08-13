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
        // Filtré par les interrupteurs de programme (spec v1.11 §3, §10 ; v1.14 §4.4) :
        // un rappel qui exige un programme ("posture", "muscu") ne doit apparaître QUE
        // si SON programme est allumé, sinon la ligne casse la promesse "rien ne change
        // chez toi" et laisse allumer un rappel pour un programme jamais vu. La garde
        // vit dans `ReminderCatalog.visibleReminders` (pure, testée), pas ici.
        let visible = ReminderCatalog.visibleReminders(enabledPlans: ReminderPlan.enabledOnThisDevice)
        return section("Rappels") {
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, definition in
                if index > 0 { divider }
                reminderRow(definition)
            }
        }
    }

    private func reminderRow(_ definition: ReminderDefinition) -> some View {
        let isOn = profile.remindersEnabled[definition.id] ?? false
        let minutes = resolvedMinutes(definition)
        let weekday = resolvedWeekday(definition)
        let time = ReminderSchedule.hourMinute(fromMinutesFromMidnight: minutes)
        let phrase = ReminderSchedule.frLabel(hour: time.hour, minute: time.minute,
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
            // Sans ça, le HStack traite ce bloc comme compressible et le sous-titre de
            // fréquence ("chaque semaine") se retrouve coupé en "chaque" / "semaine" à
            // 375 pt et en dessous, alors que la ligne a la place. Mesuré sur la ligne
            // "Pesée" (menu jour + heure + interrupteur) de 320 à 402 pt.
            .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 4)

            if definition.isWeekdayEditable {
                Picker("", selection: weekdayBinding(definition)) {
                    ForEach(Array(ReminderSchedule.weekdayRange), id: \.self) { day in
                        Text(ReminderSchedule.frShortWeekday(day)).tag(day)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                // Même raison que le bloc de texte ci-dessus : sans .fixedSize() le
                // libellé du menu ("sam.") se coupe en "sam" / "." à toutes les largeurs
                // mesurées (320 à 402 pt). Les deux .fixedSize() ensemble n'entrent en
                // compression ni l'un ni l'autre ; poser un seul des deux ne fait que
                // déplacer la coupure sur l'élément resté sans protection.
                // Honnêteté : à 320 pt la ligne "Pesée" déborde alors de la carte plutôt
                // que de rentrer proprement. Aucun iPhone livré ne fait 320 pt de large,
                // et plusieurs autres lignes de cet écran cassent déjà seules à cette
                // largeur, indépendamment de ce correctif.
                .fixedSize()
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
    //
    // Simples relais vers ReminderSchedule (NivelCore) : la règle elle-même vit là-bas,
    // partagée avec ReminderPlanner.planned, pour que l'écran affiche exactement ce que
    // le téléphone va planifier.

    private func resolvedMinutes(_ definition: ReminderDefinition) -> Int {
        ReminderSchedule.resolvedMinutes(profile.reminderTimes[definition.id], for: definition)
    }

    private func resolvedWeekday(_ definition: ReminderDefinition) -> Int? {
        ReminderSchedule.resolvedWeekday(profile.reminderWeekdays[definition.id], for: definition)
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

    /// Calendrier grégorien FIXE, pas `Calendar.current` : ce binding ne fait que de
    /// l'arithmétique heure/minute sur un jour de référence arbitraire, aucune
    /// sémantique calendaire réelle n'est nécessaire. Avec `Calendar.current`, un
    /// appareil réglé sur un calendrier non grégorien (Région > Calendrier) peut
    /// interpréter différemment le 1er janvier 2000, voire échouer à construire la
    /// date : `date(from:)` renvoie alors nil et le getter retombe silencieusement
    /// sur `.now`, affichant l'heure courante au lieu de l'heure enregistrée.
    private static let gregorian = Calendar(identifier: .gregorian)

    private func timeBinding(_ definition: ReminderDefinition) -> Binding<Date> {
        Binding(
            get: {
                let minutes = resolvedMinutes(definition)
                var components = Self.referenceDayComponents
                let time = ReminderSchedule.hourMinute(fromMinutesFromMidnight: minutes)
                components.hour = time.hour
                components.minute = time.minute
                return Self.gregorian.date(from: components) ?? .now
            },
            set: { newValue in
                let parts = Self.gregorian.dateComponents([.hour, .minute], from: newValue)
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
