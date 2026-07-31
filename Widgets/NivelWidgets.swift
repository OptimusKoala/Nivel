// Widgets/NivelWidgets.swift
import WidgetKit
import SwiftUI

@main
struct NivelWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NivelWidget()
    }
}

/// Widget unique des 4 familles ; le kind vient de WidgetBridge (partagé
/// avec reloadTimelines côté app).
struct NivelWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetBridge.widgetKind,
                            provider: NivelWidgetProvider()) { entry in
            NivelWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Nivel")
        .description("Ta journée en un coup d'œil : calories, niveau et un mot de Nivelito.")
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryCircular, .accessoryRectangular])
    }
}
