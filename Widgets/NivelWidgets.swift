// Widgets/NivelWidgets.swift
import WidgetKit
import SwiftUI

@main
struct NivelWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NivelWidget()
    }
}

/// Rempli en Task 6 — placeholder compilable pour valider la target.
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
