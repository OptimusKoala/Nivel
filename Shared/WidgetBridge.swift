// Shared/WidgetBridge.swift
// Pont app vers widget : OÙ et COMMENT le snapshot circule (spec widgets §3.2).
// Compilé dans les deux targets — aucune dépendance SwiftData ni service.

import Foundation
import NivelCore

enum WidgetBridge {
    // Doit correspondre aux entitlements des 2 targets (project.yml).
    static let appGroupID = "group.fr.mbernard.nivel"
    static let snapshotKey = "nivel.widget.snapshot"
    /// Kind unique du widget (les 4 familles) — cible de reloadTimelines(ofKind:).
    static let widgetKind = "NivelWidget"
    /// Deep link du bouton « + Repas » du widget moyen — consommé par
    /// RootView.onOpenURL côté app (contrat, comme appGroupID).
    static let logMealURL = URL(string: "nivel://log-meal")!

    static var sharedDefaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }

    /// Fire and forget (spec widgets §5) : une écriture qui échoue laisse le
    /// snapshot précédent en place, jamais d'erreur visible.
    static func save(_ snapshot: WidgetSnapshot, to defaults: UserDefaults?) {
        guard let defaults, let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    static func load(from defaults: UserDefaults?) -> WidgetSnapshot? {
        guard let defaults, let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
