// Widgets/NivelWidgetProvider.swift
import WidgetKit
import SwiftUI
import NivelCore

/// Entrée WidgetKit : une entrée planifiée, ou nil = état d'accueil
/// « Ouvre Nivel pour commencer » (spec widgets §9). `planned == nil` veut dire
/// « pas encore de snapshot » — y compris dans la galerie d'un nouvel
/// utilisateur, qui passe par getSnapshot(context.isPreview). À ne pas
/// confondre avec le squelette de chargement de placeholder(in:), traité en
/// Task 7.
struct NivelTimelineEntry: TimelineEntry {
    let date: Date
    let planned: WidgetEntry?
}

struct NivelWidgetProvider: TimelineProvider {
    // Squelette de chargement d'un widget déjà configuré : la vraie donnée si
    // elle existe, sinon l'état d'accueil (nouvel utilisateur).
    func placeholder(in context: Context) -> NivelTimelineEntry {
        NivelTimelineEntry(date: .now, planned: plannedEntries().first)
    }

    func getSnapshot(in context: Context, completion: @escaping (NivelTimelineEntry) -> Void) {
        // Une seule lecture d'horloge : l'entrée et la planification datent du
        // même instant.
        let now = Date.now
        completion(NivelTimelineEntry(date: now, planned: plannedEntries(now: now).first))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NivelTimelineEntry>) -> Void) {
        let planned = plannedEntries()
        guard let last = planned.last else {
            // Pas de snapshot (onboarding pas fini, app jamais ouverte) : état
            // d'accueil, on retentera — l'app forcera de toute façon un reload
            // au premier syncWidget().
            completion(Timeline(entries: [NivelTimelineEntry(date: .now, planned: nil)],
                                policy: .after(.now.addingTimeInterval(4 * 3600))))
            return
        }
        let entries = planned.map { NivelTimelineEntry(date: $0.date, planned: $0) }
        // La dernière entrée est 7 h du lendemain : recharger après elle pour
        // reprendre la rotation même app fermée (spec widgets §4.2).
        completion(Timeline(entries: entries, policy: .after(last.date)))
    }

    private func plannedEntries(now: Date = .now) -> [WidgetEntry] {
        // Pas de snapshot : cas bénin et attendu (app jamais ouverte).
        guard let snapshot = WidgetBridge.load(from: WidgetBridge.sharedDefaults) else { return [] }
        // Le catalogue, lui, est embarqué dans l'appex : son absence est une
        // régression de build, pas un état utilisateur.
        guard let bank = try? MessageBank.load() else {
            assertionFailure("MessageBank.load() a échoué dans l'extension : NivelCore_NivelCore.bundle absent de l'appex ?")
            return []
        }
        return WidgetTimelinePlanner.entries(snapshot: snapshot, from: now,
                                             bank: bank, calendar: .current)
    }
}
