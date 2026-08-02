// App/Views/Home/StatCard.swift
// Carte pas du jour (spec §4.1) : compteur, jauge vers l'objectif, "obj. 8 000".
// Masquée entièrement par HomeView si HealthKit est refusé/indisponible (spec §10).

import SwiftUI

struct StepsCard: View {
    let steps: Int
    let goal: Int

    private var fraction: Double {
        guard goal > 0 else { return 0 }
        return Double(steps) / Double(goal)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                CozyIcon(name: "icon_footprint", size: 15)
                Text("Pas")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.subtext)
            Text(steps.frFormatted)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            ThemedProgressBar(fraction: fraction, fill: Theme.blue)
            Text("obj. \(goal.frFormatted)")
                .font(.caption2)
                .foregroundStyle(Theme.subtext)
        }
        // Le rafraîchissement des pas (refresh HealthKit) anime compteur et jauge
        // (contentTransition numérique) au lieu de sauter d'une valeur à l'autre.
        .animation(.snappy, value: steps)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pas : \(steps) sur un objectif de \(goal)")
    }
}

#Preview {
    StepsCard(steps: 5400, goal: 8000)
        .frame(width: 136, height: 100)
        .padding()
        .background(Theme.background)
}
