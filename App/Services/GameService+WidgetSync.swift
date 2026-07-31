// App/Services/GameService+WidgetSync.swift
// Synchronisation du snapshot widget (spec widgets §5) : construite depuis l'état
// courant, écrite dans l'App Group, puis rechargement des timelines. Fire and
// forget — jamais d'erreur visible.

import Foundation
import WidgetKit
import NivelCore

extension GameService {
    /// nil tant que l'onboarding n'est pas terminé (pas de profil → le widget
    /// garde son état d'accueil « Ouvre Nivel pour commencer »).
    func makeWidgetSnapshot(themeID: String, now: Date = .now) -> WidgetSnapshot? {
        guard let profile = fetchProfile() else { return nil }
        return WidgetSnapshot(
            dayKey: Self.dayKey(for: now),
            kcalEaten: kcalEaten(on: now),
            kcalTarget: profile.dailyCalorieTarget,
            totalXP: fetchState()?.totalXP ?? 0,
            userName: profile.name,
            themeID: themeID,
            generatedAt: now
        )
    }

    /// Appelée après chaque sauvegarde (saveOrAssert), au retour au premier plan
    /// et au changement de thème. Plusieurs appels par action : sans importance,
    /// l'écriture est idempotente et reloadTimelines depuis l'app au premier
    /// plan n'est pas soumis au budget de rafraîchissement.
    func syncWidget() {
        guard let snapshot = makeWidgetSnapshot(themeID: ThemeStore.shared.palette.id) else { return }
        WidgetBridge.save(snapshot, to: widgetDefaults)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetBridge.widgetKind)
    }
}
