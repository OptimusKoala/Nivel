// App/Services/NotificationService.swift
// Rappels locaux bienveillants (spec §10) : 4 rappels répétitifs
// (UNCalendarNotificationTrigger), textes tirés de la banque de messages.
// Re-planifié à chaque passage au premier plan pour renouveler les textes.

import Foundation
import UserNotifications
import NivelCore

@MainActor
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

    /// Sérialisation des re-planifications : chaque appel incrémente la génération ;
    /// une invocation devenue obsolète après son await (retour au premier plan +
    /// toggle quasi simultanés) est abandonnée — seul le dernier instantané gagne.
    private static var generation = 0

    /// Supprime toutes les demandes en attente puis re-planifie chaque rappel ACTIF
    /// avec un texte frais de la banque (tirage aléatoire — varie à chaque appel).
    /// Si les notifications sont refusées : ne fait rien (jamais de crash).
    ///
    /// L'instantané des champs du profil (@Model non-Sendable) est capturé ICI,
    /// avant tout passage asynchrone.
    static func reschedule(for profile: UserProfile) {
        let name = profile.name
        let enabled = profile.remindersEnabled
        generation += 1
        let gen = generation
        Task { await perform(name: name, enabled: enabled, generation: gen) }
    }

    private static func perform(name: String, enabled: [String: Bool], generation gen: Int) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        // Un appel plus récent est passé pendant l'await → cet instantané est périmé.
        guard gen == generation else { return }
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }

        // Banque chargée une fois par re-planification (un tirage par rappel).
        let bank = try? MessageBank.load()

        // removeAll + adds SYNCHRONES (aucun await entre les deux) : le bloc est
        // atomique du point de vue du main actor — aucun entrelacement possible.
        center.removeAllPendingNotificationRequests()
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
            // Variante à completion (et non l'overload async) : l'ajout reste
            // synchrone → pas de point de suspension dans le bloc removeAll + adds.
            center.add(request, withCompletionHandler: nil)
        }
    }
}
