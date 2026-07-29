// App/Views/Progress/StepsChart.swift
// Historique de pas (spec §4.3) : barres bleues par jour, record personnel célébré 🏆.
// La SECTION entière est masquée par ProgressScreen si HealthKit est indisponible (spec §10).

import SwiftUI
import Charts

struct StepsChart: View {
    struct Day: Identifiable {
        let day: Date
        let steps: Int
        var id: Date { day }
    }

    /// Jours triés par date croissante.
    let days: [Day]

    /// Jour du record personnel sur la période (premier en cas d'égalité) — annoté 🏆.
    private static func recordDay(in days: [Day]) -> Date? {
        guard let best = days.max(by: { $0.steps < $1.steps }), best.steps > 0 else { return nil }
        return days.first { $0.steps == best.steps }?.day
    }

    var body: some View {
        // Record calculé UNE fois par rendu (pas par barre).
        let recordDay = Self.recordDay(in: days)
        return Chart {
            ForEach(days) { day in
                BarMark(
                    x: .value("Jour", day.day, unit: .day),
                    y: .value("Pas", day.steps)
                )
                .foregroundStyle(Theme.blue)
                .cornerRadius(3)
                .annotation(position: .top, spacing: 2) {
                    if day.day == recordDay {
                        Text("🏆")
                            .font(.caption)
                    }
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
        .accessibilityLabel("Historique des pas par jour, record personnel marqué d'un trophée")
    }
}

#Preview {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: .now)
    let days = (0..<14).map { i in
        StepsChart.Day(
            day: calendar.date(byAdding: .day, value: -(13 - i), to: today)!,
            steps: 4000 + ((i * 53) % 11) * 800
        )
    }
    return StepsChart(days: days)
        .card()
        .padding(20)
        .background(Theme.background)
}
