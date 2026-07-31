// Widgets/Views/AccessoryWidgetViews.swift
// Écran verrouillé (spec widgets §6) : rendu MONOCHROME imposé par le système,
// la palette ne s'applique pas ici.

import SwiftUI
import WidgetKit
import NivelCore

struct CircularAccessoryView: View {
    let entry: WidgetEntry

    private var fraction: Double {
        guard entry.kcalTarget > 0 else { return 0 }
        return min(1, Double(entry.kcalEaten) / Double(entry.kcalTarget))
    }

    var body: some View {
        Gauge(value: fraction) {
            Text("kcal")
        } currentValueLabel: {
            Text("~\(entry.kcalEaten.frFormatted)")
                .minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircular)
        .accessibilityLabel("Environ \(entry.kcalEaten) calories sur \(entry.kcalTarget)")
    }
}

struct RectangularAccessoryView: View {
    let entry: WidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("~\(entry.kcalEaten.frFormatted) / \(entry.kcalTarget.frFormatted) kcal")
                .font(.headline)
                .minimumScaleFactor(0.7)
            Text("Niveau \(LevelSystem.level(forXP: entry.totalXP))")
                .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct AccessoryWelcomeView: View {
    var body: some View {
        Text("Ouvre Nivel")
            .font(.headline)
            .minimumScaleFactor(0.7)
    }
}
