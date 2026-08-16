// App/NivelAppDelegate.swift
// Le strict minimum d'UIKit qu'exige le réveil silencieux du duo (spec 1.15 §3.7).
//
// **Pourquoi ce fichier existe alors que Nivel est une app SwiftUI pure.** Un réveil
// silencieux est livré par `application(_:didReceiveRemoteNotification:)`, une méthode de
// `UIApplicationDelegate`. SwiftUI n'expose aucun équivalent : ni modificateur de scène, ni
// environnement, ni `onReceive` système. `BackgroundTasks` ne remplace pas non plus le
// besoin, n'étant pas déclenché par un changement distant mais par le bon vouloir du
// système. Il n'existe donc pas d'autre voie que `@UIApplicationDelegateAdaptor`.
//
// Il est volontairement MINUSCULE : s'enregistrer aux notifications distantes, et router un
// réveil vers `DuoService`. Rien d'autre n'a le droit d'y entrer.
//
// En particulier, **pas de `windowScene(_:userDidAcceptCloudKitShareWith:)`** : notre
// appairage passe par notre propre scanner et notre propre champ (§3.6), et ouvrir un second
// chemin d'acceptation doublerait la surface à tester pour un gain nul.

import CloudKit
import UIKit

final class NivelAppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Nécessaire pour que le serveur puisse réveiller l'app. Ne demande AUCUNE
        // autorisation à l'utilisateur et n'affiche rien : les réveils silencieux ne sont pas
        // des notifications visibles. Celle qu'on postera ensuite, elle, passe par
        // l'autorisation déjà demandée pour les rappels.
        application.registerForRemoteNotifications()
        return true
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
        guard !nouveaux.isEmpty else { return .noData }

        await DuoNotifications.post(for: nouveaux,
                                    partner: service.partnerSnapshot?.name,
                                    enabled: service.likeNotificationsEnabled)
        return .newData
    }
}
