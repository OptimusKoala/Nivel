// Widgets/Views/AccessoryWidgetViews.swift
// Écran verrouillé (spec widgets §6) : rendu MONOCHROME imposé par le système,
// la palette ne s'applique pas ici.

import SwiftUI
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
            Text("Niv. \(LevelSystem.level(forXP: entry.totalXP))")
                .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Environ \(entry.kcalEaten) calories sur \(entry.kcalTarget), niveau \(LevelSystem.level(forXP: entry.totalXP))")
    }
}

struct AccessoryWelcomeView: View {
    var body: some View {
        Text("Ouvre Nivel")
            .font(.headline)
            .minimumScaleFactor(0.7)
    }
}

// MARK: - Previews
// Fond noir : simule le fond de l'écran verrouillé, seul contexte de ces vues.

private let previewAccessoryEntry = WidgetEntry(
    date: .now, kcalEaten: 1240, kcalTarget: 2000, totalXP: 860,
    message: "", expression: .happy, themeID: "creme", userName: "Michaël"
)

#Preview("Circulaire") {
    CircularAccessoryView(entry: previewAccessoryEntry)
        .frame(width: 160, height: 160)
        .background(.black)
}

#Preview("Rectangulaire") {
    RectangularAccessoryView(entry: previewAccessoryEntry)
        .frame(width: 160, height: 72)
        .background(.black)
}
