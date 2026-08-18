// App/NivelAppDelegate.swift
// Le petit pont UIKit nécessaire aux notifications distantes CloudKit du duo.
//
// **Pourquoi ce fichier existe alors que Nivel est une app SwiftUI pure.** Les alertes
// CloudKit et leur mise à jour en arrière-plan passent par `UIApplicationDelegate` et
// `UNUserNotificationCenterDelegate`. SwiftUI n'expose aucun équivalent pour ces callbacks.
//
// Il est volontairement MINUSCULE : s'enregistrer aux notifications distantes, et router un
// push vers `DuoService`. Rien d'autre n'a le droit d'y entrer.
//
// En particulier, **pas de `windowScene(_:userDidAcceptCloudKitShareWith:)`** : notre
// appairage passe par notre propre scanner et notre propre champ (§3.6), et ouvrir un second
// chemin d'acceptation doublerait la surface à tester pour un gain nul.

import CloudKit
import UIKit
import UserNotifications

final class NivelAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Une alerte distante ne se présente pas d'elle-même au premier plan. Le délégué
        // doit être installé avant la fin du lancement pour autoriser la bannière du cœur.
        UNUserNotificationCenter.current().delegate = self

        // Nécessaire à la livraison de l'alerte CloudKit et au rafraîchissement associé.
        // L'autorisation de l'utilisateur reste, elle, gérée par le flux existant.
        application.registerForRemoteNotifications()
        return true
    }

    /// L'alerte CloudKit est déjà visible en arrière-plan et même après un force-quit : ici,
    /// on autorise la même bannière quand Nivel est au premier plan. Les rappels existants
    /// restent discrets, et une notification inconnue n'obtient aucun privilège par défaut.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        guard let cloud = CKNotification(
            fromRemoteNotificationDictionary: notification.request.content.userInfo),
              cloud.subscriptionID == DuoService.subscriptionID,
              DuoService.shared.likeNotificationsEnabled
        else { return [] }
        return [.banner, .sound]
    }

    /// Toucher un rappel local de programme ouvre sa séance, y compris si l'app doit être
    /// lancée pour répondre. Les réponses CloudKit ne correspondent à aucune route locale
    /// et sont donc simplement ignorées ici.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }

        let request = response.notification.request
        guard let route = NotificationNavigation.route(
            userInfo: request.content.userInfo,
            reminderID: request.identifier
        ) else { return }

        await MainActor.run {
            NotificationNavigation.receive(route)
        }
    }

    /// Le réveil. Rendre le bon `UIBackgroundFetchResult` n'est pas cosmétique : iOS observe
    /// ce qu'on rapporte pour décider s'il continue à nous réveiller. Annoncer `.newData` à
    /// chaque fois pour un lot vide finirait par nous faire réveiller moins souvent.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        // Un réveil qui ne vient pas de CloudKit ne nous regarde pas. Nivel n'a aucun autre
        // émetteur de push, mais le vérifier coûte une ligne et évite d'aller lire une zone
        // pour une notification étrangère.
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else {
            return .noData
        }

        return await handleDuoWake()
    }

    /// Tout le travail du réveil, en UN saut sur le `MainActor` : `DuoService` y est isolé,
    /// et l'y appeler morceau par morceau ferait traverser la frontière à chaque ligne.
    @MainActor
    private func handleDuoWake() async -> UIBackgroundFetchResult {
        let service = DuoService.shared
        let nouveaux = await service.handleRemoteWake()
        // L'alerte visible a déjà été composée par CloudKit. Le réveil silencieux associé
        // sert uniquement à ranger le cœur et mettre à jour la bulle d'accueil ; poster une
        // seconde notification locale ici ferait vibrer deux fois le même geste.
        return nouveaux.isEmpty ? .noData : .newData
    }
}
