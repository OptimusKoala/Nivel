// App/Services/NotificationService.swift
// Rappels locaux bienveillants (spec v1 §10, horaires réglables spec v1.9 §4.3) :
// le CALCUL de ce qu'il faut planifier vit dans NivelCore (ReminderPlanner, pur et
// testé) ; ce fichier ne garde que le dialogue avec UNUserNotificationCenter.
// Re-planifié à chaque passage au premier plan pour renouveler les textes.

import Foundation
import UserNotifications
import NivelCore

@MainActor
enum NotificationService {
    /// Sérialisation des re-planifications : chaque appel incrémente la génération ;
    /// une invocation devenue obsolète après son await (roue d'heure que l'on fait
    /// tourner, retour au premier plan et toggle quasi simultanés) est abandonnée.
    /// C'est ce qui absorbe la rafale de changements d'un DatePicker.
    private static var generation = 0

    /// Supprime toutes les demandes en attente puis re-planifie chaque rappel ACTIF
    /// avec un texte frais de la banque (tirage aléatoire, varie à chaque appel).
    /// Si les notifications sont refusées : ne fait rien (jamais de crash).
    ///
    /// L'instantané des champs du profil (@Model non-Sendable) est capturé ICI,
    /// avant tout passage asynchrone, et le profil n'est plus jamais relu ensuite.
    static func reschedule(for profile: UserProfile) {
        let name = profile.name
        let planned = ReminderPlanner.planned(enabled: profile.remindersEnabled,
                                              times: profile.reminderTimes,
                                              weekdays: profile.reminderWeekdays,
                                              planEnabled: PosturePlanSettings.shared.isEnabled)
        generation += 1
        let gen = generation
        Task { await perform(name: name, planned: planned, generation: gen) }
    }

    private static func perform(name: String, planned: [PlannedReminder],
                                generation gen: Int) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        // Un appel plus récent est passé pendant l'await → cet instantané est périmé.
        guard gen == generation else { return }
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }

        // Banque chargée une fois par re-planification (un tirage par rappel).
        let bank = try? MessageBank.load()

        // removeAll + adds SYNCHRONES (aucun await entre les deux) : le bloc est
        // atomique du point de vue du main actor, aucun entrelacement possible.
        schedule(planned: planned, name: name, bank: bank, center: center)
    }

    /// Bloc SYNCHRONE de re-planification. Isolé dans sa propre fonction (non-async)
    /// pour deux raisons : garantir qu'aucun point de suspension ne s'y glisse, et
    /// laisser `center.add(_:withCompletionHandler:)` s'utiliser sans que le
    /// compilateur ne réclame son overload async (que l'on évite VOLONTAIREMENT ici).
    private static func schedule(planned: [PlannedReminder], name: String,
                                 bank: MessageBank?, center: UNUserNotificationCenter) {
        center.removeAllPendingNotificationRequests()
        for reminder in planned {
            let content = UNMutableNotificationContent()
            content.title = "Nivelito 🧡"
            content.body = bank?.pick(
                context: reminder.context,
                excluding: nil,
                name: name,
                value: nil
            ).text ?? "Petit coucou de Nivelito 🧡"
            // Son SYSTÈME, volontairement : les chimes embarqués de la v1.9 sont ceux
            // du timer d'exercice. Un son propre aux notifications est hors périmètre
            // (spec v1.9 §7), ce n'est pas un oubli de câblage.
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
