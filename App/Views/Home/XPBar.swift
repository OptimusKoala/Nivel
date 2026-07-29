// App/Views/Home/XPBar.swift
// Carte XP (spec §4.1) : jauge dégradée accent→orange vers le prochain niveau,
// libellé "650 / 1 000 → niv. 8". + ThemedProgressBar, la jauge commune de l'app.

import SwiftUI
import NivelCore

struct XPCard: View {
    let totalXP: Int

    private var level: Int { LevelSystem.level(forXP: totalXP) }
    private var progress: (current: Int, needed: Int) { LevelSystem.progress(forXP: totalXP) }

    var body: some View {
        let (current, needed) = progress
        VStack(alignment: .leading, spacing: 6) {
            Text("XP")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.subtext)
            ThemedProgressBar(
                fraction: needed > 0 ? Double(current) / Double(needed) : 0,
                fill: LinearGradient(colors: [Theme.accent, Theme.orange],
                                     startPoint: .leading, endPoint: .trailing)
            )
            Text("\(current.frFormatted) / \(needed.frFormatted) → niv. \(level + 1)")
                .font(.caption2)
                .foregroundStyle(Theme.subtext)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Expérience : \(current) sur \(needed) vers le niveau \(level + 1)")
    }
}

/// Jauge arrondie sur piste `Theme.track` — remplissage Color ou dégradé.
struct ThemedProgressBar<Fill: ShapeStyle>: View {
    let fraction: Double
    let fill: Fill
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let clamped = min(1, max(0, fraction))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                if clamped > 0 {
                    Capsule()
                        .fill(fill)
                        .frame(width: max(height, geo.size.width * clamped))
                }
            }
        }
        .frame(height: height)
    }
}

#Preview {
    VStack(spacing: 16) {
        XPCard(totalXP: 780)
            .frame(width: 136, height: 100)
        ThemedProgressBar(fraction: 0.4, fill: Theme.blue)
        ThemedProgressBar(fraction: 0, fill: Theme.accent)
    }
    .padding()
    .background(Theme.background)
}
