// App/Services/NotificationNavigation.swift
// Routage des rappels locaux qui ouvrent une séance. Le délégué UIKit reçoit le tap
// avant que SwiftUI soit forcément prêt (lancement à froid) : la destination est donc
// aussi conservée dans UserDefaults, puis consommée par MainTabView.

import Foundation

/// Séance cible d'un rappel. Un type dédié évite de confondre un identifiant de
/// notification (« posture ») avec l'état éphémère que consomme l'onglet Sport.
enum SportSessionRoute: String, Equatable, Sendable {
    case posture
    case muscu
}

enum NotificationNavigation {
    /// Les demandes déjà planifiées avant cette version n'ont pas encore cette clé :
    /// `route(userInfo:reminderID:)` retombe volontairement sur leur identifiant.
    static let routeUserInfoKey = "nivel.sport-session-route"

    /// Nom de notification en mémoire, pour le cas où l'app est déjà ouverte au tap.
    static let didReceiveRoute = Notification.Name("nivel.didReceiveSportSessionRoute")

    private static let pendingRouteDefaultsKey = "nivel.pendingSportSessionRoute"

    /// Contrat entre le catalogue des rappels et l'onglet Sport. Les autres rappels ne
    /// représentent pas une séance et ne doivent surtout pas ouvrir un écran au hasard.
    static func route(forReminderID reminderID: String) -> SportSessionRoute? {
        switch reminderID {
        case "posture": .posture
        case "muscu": .muscu
        default: nil
        }
    }

    /// La valeur portée par le contenu est prioritaire ; le repli garde les rappels
    /// planifiés par une version antérieure cliquables jusqu'à leur prochain renouvellement.
    static func route(userInfo: [AnyHashable: Any], reminderID: String) -> SportSessionRoute? {
        if let rawValue = userInfo[routeUserInfoKey] as? String,
           let route = SportSessionRoute(rawValue: rawValue) {
            return route
        }
        return route(forReminderID: reminderID)
    }

    /// Pose d'abord la valeur persistante (lancement à froid), puis diffuse l'événement
    /// immédiat (app déjà affichée). Les deux chemins consomment la même valeur une fois.
    @MainActor
    static func receive(_ route: SportSessionRoute, defaults: UserDefaults = .standard) {
        defaults.set(route.rawValue, forKey: pendingRouteDefaultsKey)
        NotificationCenter.default.post(name: didReceiveRoute, object: route)
    }

    /// Prend la route et l'efface AVANT la présentation : revenir au premier plan plus tard
    /// ne doit jamais rouvrir une séance que la personne a déjà fermée.
    @MainActor
    static func consumePendingRoute(defaults: UserDefaults = .standard) -> SportSessionRoute? {
        defer { defaults.removeObject(forKey: pendingRouteDefaultsKey) }
        guard let rawValue = defaults.string(forKey: pendingRouteDefaultsKey) else { return nil }
        return SportSessionRoute(rawValue: rawValue)
    }
}
