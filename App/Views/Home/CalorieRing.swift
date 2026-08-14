// App/Views/Home/CalorieRing.swift
// Anneau des calories du jour (spec §4.1) : mangé / objectif, restant mis en avant.
// Anneau intérieur : dépense du jour / cible de dépense (spec v1.14 §5.5).
// Dépassement = accent chaleureux + message neutre — JAMAIS de rouge (spec §2).

import SwiftUI

struct CalorieRingCard: View {
    let eaten: Int
    let target: Int
    /// Dépense estimée du jour — pas + sport non marché (spec v1.14 §5.4). INDICATIVE :
    /// elle n'est jamais créditée au budget alimentaire (règle v1 §2).
    let burned: Int
    let burnTarget: Int

    private var isOver: Bool { target > 0 && eaten > target }
    private var fraction: Double {
        guard target > 0 else { return 0 }
        return min(1, Double(eaten) / Double(target))
    }

    private var burnFraction: Double {
        guard burnTarget > 0 else { return 0 }
        return min(1, Double(burned) / Double(burnTarget))
    }
    private var burnReached: Bool { burnTarget > 0 && burned >= burnTarget }

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
            // Anneau de dépense (spec §5.5), rayon de tracé 45 contre 59 à l'extérieur
            // (le padding de 14 sur une largeur plafonnée à 130). `Theme.orange`
            // et NON `Theme.accent` : l'anneau extérieur passe à `accent` en cas de
            // dépassement calorique, et les deux cercles deviendraient alors
            // indistinguables — précisément les jours où l'on regarde la carte de près.
            // (La façade `Theme` n'expose pas `primary` : c'est `Theme.orange` qui
            // porte `palette.primary`.)
            Circle()
                .stroke(Theme.track, lineWidth: 8)
                .padding(14)
            Circle()
                .trim(from: 0, to: burnFraction)
                .stroke(Theme.orange, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(14)
            // Le centre ne change pas : le chiffre qu'on vient chercher reste le mangé,
            // en grand (spec §5.5).
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
        // Même raison pour la dépense : les pas arrivent APRÈS le premier rendu
        // (lecture HealthKit asynchrone), l'anneau intérieur se remplit au lieu de
        // sauter d'un coup.
        .animation(.snappy, value: burned)
        .padding(6) // le trait (12 pt) déborde du cercle géométrique
        .frame(maxWidth: 130, maxHeight: 130)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calories : environ \(eaten) sur \(target). Dépensé : environ \(burned) sur \(burnTarget)")
    }

    /// Le sous-titre porte les DEUX lignes (reste à manger + dépense) : la légende de
    /// dépense se fond dans le sous-titre existant plutôt que de s'ajouter comme
    /// troisième enfant de la carte (qui aurait coûté 10 pt d'interligne de plus) — la
    /// 1.13 s'est battue pour chaque point de hauteur (spec §5.5).
    @ViewBuilder private var subtitle: some View {
        VStack(spacing: 3) {
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
            HStack(spacing: 4) {
                // La pastille rappelle la couleur de l'anneau intérieur : sans elle,
                // rien ne dit lequel des deux cercles la ligne commente.
                Circle().fill(Theme.orange).frame(width: 7, height: 7)
                // Jamais de reproche au-delà de l'objectif : on a bougé plus que prévu,
                // il n'y a rien à redire (spec §5.5, aucun rouge non plus ici).
                Text(burnReached
                     ? "Objectif de dépense atteint 🎉"
                     : "Dépensé ~\(burned.frFormatted) / \(burnTarget.frFormatted)")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.subtext)
        }
    }
}

#Preview("Sous l'objectif") {
    CalorieRingCard(eaten: 1240, target: 2000, burned: 180, burnTarget: 400)
        .frame(width: 210, height: 210)
        .padding()
        .background(Theme.background)
}

#Preview("Dépassé (jamais rouge)") {
    // Dépassement des DEUX objectifs : l'anneau extérieur passe à `Theme.accent`,
    // c'est le cas où l'intérieur ne doit surtout pas prendre la même couleur.
    CalorieRingCard(eaten: 2350, target: 2000, burned: 520, burnTarget: 400)
        .frame(width: 210, height: 210)
        .padding()
        .background(Theme.background)
}
