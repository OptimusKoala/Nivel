// App/Views/Home/CalorieRing.swift
// Anneau des calories du jour (spec §4.1) : mangé / objectif, restant mis en avant.
// Dépassement = accent chaleureux + message neutre — JAMAIS de rouge (spec §2).

import SwiftUI

struct CalorieRingCard: View {
    let eaten: Int
    let target: Int

    private var isOver: Bool { target > 0 && eaten > target }
    private var fraction: Double {
        guard target > 0 else { return 0 }
        return min(1, Double(eaten) / Double(target))
    }

    var body: some View {
        VStack(spacing: 10) {
            ring
            subtitle
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .card()
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Theme.track, lineWidth: 12)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(isOver ? Theme.accent : Theme.green,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                // "~" : le total mangé est une somme d'estimations (spec §13).
                Text("~\(eaten.frFormatted)")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                // Pas de "~" sur l'objectif : c'est un budget fixé, pas une estimation
                // (cohérent avec le journal Repas et le graphe calories).
                Text("/ \(target.frFormatted) kcal")
                    .font(.caption2)
                    .foregroundStyle(Theme.subtext)
            }
            .padding(.horizontal, 14)
        }
        // Un log/édition de repas anime l'anneau et fait défiler le compteur
        // (contentTransition numérique) au lieu de sauter d'une valeur à l'autre.
        .animation(.snappy, value: eaten)
        .padding(6) // le trait (12 pt) déborde du cercle géométrique
        .frame(maxWidth: 130, maxHeight: 130)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calories : environ \(eaten) sur \(target)")
    }

    @ViewBuilder private var subtitle: some View {
        if isOver {
            Text("Objectif dépassé de ~\((eaten - target).frFormatted), ça arrive 😌")
                .foregroundStyle(Theme.subtext)
        } else {
            HStack(spacing: 4) {
                Text("Reste ~\(max(0, target - eaten).frFormatted) kcal")
                CozyIcon(name: "tab_meals", size: 15)
            }
            .foregroundStyle(Theme.green)
        }
    }
}

#Preview("Sous l'objectif") {
    CalorieRingCard(eaten: 1240, target: 2000)
        .frame(width: 210, height: 210)
        .padding()
        .background(Theme.background)
}

#Preview("Dépassé (jamais rouge)") {
    CalorieRingCard(eaten: 2350, target: 2000)
        .frame(width: 210, height: 210)
        .padding()
        .background(Theme.background)
}
