// App/Services/NotificationService.swift
// Rappels locaux bienveillants (spec §10) : 4 rappels répétitifs
// (UNCalendarNotificationTrigger), textes tirés de la banque de messages.
// Re-planifié à chaque passage au premier plan pour renouveler les textes.

import Foundation
import UserNotifications
import NivelCore

enum NotificationService {
    /// Un rappel planifiable : identifiant stable (clé de `profile.remindersEnabled`),
    /// horaire, et contexte de la banque de messages.
    struct Reminder {
        let id: String
        let hour: Int
        let minute: Int
        /// Jour de la semaine (1 = dimanche … 7 = samedi) — nil = tous les jours.
        let weekday: Int?
        let context: MessageContext
    }

    /// Les 4 rappels de la v1 (spec §10).
    static let reminders: [Reminder] = [
        Reminder(id: "lunch", hour: 12, minute: 30, weekday: nil, context: .midday),
        Reminder(id: "dinner", hour: 20, minute: 0, weekday: nil, context: .evening),
        Reminder(id: "weigh", hour: 9, minute: 0, weekday: 7, context: .weighReminder),
        Reminder(id: "steps", hour: 18, minute: 0, weekday: nil, context: .stepsEncouragement),
    ]

    /// Supprime toutes les demandes en attente puis re-planifie chaque rappel ACTIF
    /// avec un texte frais de la banque (tirage aléatoire — varie à chaque appel).
    /// Si les notifications sont refusées : ne fait rien (jamais de crash).
    ///
    /// ⚠️ Le closure de `getNotificationSettings` s'exécute hors du main actor :
    /// on capture ici les valeurs simples du profil (@Model non-Sendable) AVANT.
    static func reschedule(for profile: UserProfile) {
        let name = profile.name
        let enabled = profile.remindersEnabled
        let center = UNUserNotificationCenter.current()

        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional else { return }

            center.removeAllPendingNotificationRequests()

            // Banque chargée une fois par re-planification (un tirage par rappel).
            let bank = try? MessageBank.load()

            for reminder in reminders where enabled[reminder.id] == true {
                let content = UNMutableNotificationContent()
                content.title = "Nivelito 🧡"
                content.body = bank?.pick(
                    context: reminder.context,
                    excluding: nil,
                    name: name,
                    value: nil
                ).text ?? "Petit coucou de Nivelito 🧡"
                content.sound = .default

                var components = DateComponents()
                components.hour = reminder.hour
                components.minute = reminder.minute
                components.weekday = reminder.weekday

                let request = UNNotificationRequest(
                    identifier: reminder.id,
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                )
                center.add(request)
            }
        }
    }
}
