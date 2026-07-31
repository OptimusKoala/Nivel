// Widgets/NivelWidgetProvider.swift
import WidgetKit
import SwiftUI
import NivelCore

/// Entrée WidgetKit : une entrée planifiée, ou nil = état d'accueil
/// « Ouvre Nivel pour commencer » (pas de snapshot, spec widgets §9) —
/// c'est aussi le placeholder de la galerie.
struct NivelTimelineEntry: TimelineEntry {
    let date: Date
    let planned: WidgetEntry?
}

struct NivelWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> NivelTimelineEntry {
        NivelTimelineEntry(date: .now, planned: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (NivelTimelineEntry) -> Void) {
        completion(NivelTimelineEntry(date: .now, planned: plannedEntries().first))
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

    private func plannedEntries() -> [WidgetEntry] {
        guard let snapshot = WidgetBridge.load(from: WidgetBridge.sharedDefaults),
              let bank = try? MessageBank.load() else { return [] }
        return WidgetTimelinePlanner.entries(snapshot: snapshot, from: .now,
                                             bank: bank, calendar: .current)
    }
}

/// Placeholder remplacé en Task 7 par les vraies vues (SystemWidgetViews.swift).
struct NivelWidgetEntryView: View {
    let entry: NivelTimelineEntry
    var body: some View {
        Text("Nivel")
            .containerBackground(for: .widget) { Color.white }
    }
}
