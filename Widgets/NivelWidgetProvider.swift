// Widgets/NivelWidgetProvider.swift
import WidgetKit
import SwiftUI
import NivelCore

/// Entrée WidgetKit : une entrée planifiée, ou nil = état d'accueil
/// « Ouvre Nivel pour commencer » (pas de snapshot, spec widgets §9).
struct NivelTimelineEntry: TimelineEntry {
    let date: Date
    let planned: WidgetEntry?
}

struct NivelWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> NivelTimelineEntry {
        NivelTimelineEntry(date: .now, planned: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (NivelTimelineEntry) -> Void) {
        completion(NivelTimelineEntry(date: .now, planned: nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NivelTimelineEntry>) -> Void) {
        completion(Timeline(entries: [NivelTimelineEntry(date: .now, planned: nil)],
                            policy: .never))
    }
}

struct NivelWidgetEntryView: View {
    let entry: NivelTimelineEntry
    var body: some View {
        Text("Nivel")
            .containerBackground(for: .widget) { Color.white }
    }
}
