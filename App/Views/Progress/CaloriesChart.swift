// App/Views/Progress/CaloriesChart.swift
// Historique calories (spec §4.3) : barres jour par jour + objectif en pointillés.
// Dépassement en Theme.accent (JAMAIS rouge, spec §7.4) ; dans l'objectif en Theme.green.

import SwiftUI
import Charts

struct CaloriesChart: View {
    struct Day: Identifiable {
        let day: Date
        let kcal: Int
        /// Objectif du jour (pour la couleur de la barre).
        let target: Int
        var id: Date { day }
    }

    /// Jours triés, kcal > 0 uniquement.
    let days: [Day]
    /// Objectif courant — trait pointillé de référence (0 = pas de trait).
    let target: Int

    var body: some View {
        if days.isEmpty {
            emptyState
        } else {
            chart
        }
    }

    private var chart: some View {
        Chart {
            ForEach(days) { day in
                BarMark(
                    x: .value("Jour", day.day, unit: .day),
                    y: .value("kcal", day.kcal)
                )
                // Dépassement neutre-chaleureux (accent), jamais punitif.
                .foregroundStyle(day.target > 0 && day.kcal > day.target ? Theme.accent : Theme.green)
                .cornerRadius(3)
            }
            if target > 0 {
                RuleMark(y: .value("Objectif", target))
                    .foregroundStyle(Theme.subtext)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Objectif \(target.frFormatted)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.subtext)
                    }
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(Theme.track)
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .foregroundStyle(Theme.subtext)
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(Theme.track)
                AxisValueLabel()
                    .foregroundStyle(Theme.subtext)
            }
        }
        .environment(\.locale, Locale(identifier: "fr_FR"))
        .frame(height: 170)
        .accessibilityLabel("Historique des calories par jour, comparé à l'objectif")
    }

    private var emptyState: some View {
        Text("Logge tes repas pour voir ton historique ici 🍽️")
            .font(.subheadline)
            .foregroundStyle(Theme.subtext)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 110)
    }
}

#Preview {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: .now)
    let days = (0..<14).map { i in
        CaloriesChart.Day(
            day: calendar.date(byAdding: .day, value: -(13 - i), to: today)!,
            kcal: 1500 + ((i * 37) % 9) * 110,
            target: 2000
        )
    }
    return CaloriesChart(days: days, target: 2000)
        .card()
        .padding(20)
        .background(Theme.background)
}
