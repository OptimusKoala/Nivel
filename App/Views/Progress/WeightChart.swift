// App/Views/Progress/WeightChart.swift
// Courbe de poids (spec §4.3) : points de pesée discrets (subtext) + tendance lissée
// WeightTrend.smooth mise en avant (orange, épaisse). Axe Y cadré sur les données ± 1 kg.

import SwiftUI
import Charts
import NivelCore

struct WeightChart: View {
    /// Pesées triées par date croissante.
    let entries: [(date: Date, kg: Double)]

    private var yDomain: ClosedRange<Double> {
        let kgs = entries.map(\.kg)
        guard let min = kgs.min(), let max = kgs.max() else { return 0...1 }
        return (min - 1)...(max + 1)
    }

    var body: some View {
        if entries.count < 2 {
            emptyState
        } else {
            chart
        }
    }

    private var chart: some View {
        // Tendance calculée UNE fois par rendu (pas par point).
        let trend = WeightTrend.smooth(entries.map(\.kg))
        return Chart {
            ForEach(entries.indices, id: \.self) { index in
                PointMark(
                    x: .value("Date", entries[index].date),
                    y: .value("Poids", entries[index].kg)
                )
                .foregroundStyle(Theme.subtext)
                .symbolSize(28)

                LineMark(
                    x: .value("Date", entries[index].date),
                    y: .value("Tendance", trend[index])
                )
                .foregroundStyle(Theme.orange)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom)
            }
        }
        .chartYScale(domain: yDomain)
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
        .frame(height: 190)
        .accessibilityLabel("Courbe de poids avec tendance lissée")
    }

    /// Moins de 2 pesées sur la période : pas de courbe, un message doux.
    private var emptyState: some View {
        Text("Ta courbe apparaîtra après quelques pesées 🌱")
            .font(.subheadline)
            .foregroundStyle(Theme.subtext)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 120)
    }
}

#Preview("Courbe") {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: .now)
    var entries: [(date: Date, kg: Double)] = []
    for i in 0..<10 {
        let date = calendar.date(byAdding: .day, value: -3 * (9 - i), to: today)!
        let wobble = Double((i * 7) % 3) * 0.4
        let kg = 91 - Double(i) * 0.3 + wobble
        entries.append((date, kg))
    }
    return WeightChart(entries: entries)
        .card()
        .padding(20)
        .background(Theme.background)
}

#Preview("Vide") {
    WeightChart(entries: [])
        .card()
        .padding(20)
        .background(Theme.background)
}
