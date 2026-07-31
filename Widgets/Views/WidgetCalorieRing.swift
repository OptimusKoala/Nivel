// Widgets/Views/WidgetCalorieRing.swift
// Anneau calories du widget — mêmes règles que CalorieRingCard (spec §7.4) :
// "~mangé / objectif", dépassement = accent chaleureux, JAMAIS de rouge.

import SwiftUI

struct WidgetCalorieRing: View {
    let eaten: Int
    let target: Int
    let palette: ThemePalette
    private let lineWidth: CGFloat = 9

    private var isOver: Bool { target > 0 && eaten > target }
    private var fraction: Double {
        guard target > 0 else { return 0 }
        return min(1, Double(eaten) / Double(target))
    }

    var body: some View {
        ZStack {
            Circle().stroke(palette.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(isOver ? palette.accent : palette.success,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("~\(eaten.frFormatted)")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.text)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("/ \(target.frFormatted) kcal")
                    .font(.system(size: 9))
                    .foregroundStyle(palette.subtext)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
        }
        .padding(lineWidth / 2)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Environ \(eaten) calories sur \(target)")
    }
}

// MARK: - Previews

#Preview("Sous l'objectif") {
    WidgetCalorieRing(eaten: 1240, target: 2000, palette: .creme)
        .frame(width: 120, height: 120)
        .padding()
        .background(ThemePalette.creme.background)
}

#Preview("Dépassé (jamais rouge)") {
    WidgetCalorieRing(eaten: 2350, target: 2000, palette: .creme)
        .frame(width: 120, height: 120)
        .padding()
        .background(ThemePalette.creme.background)
}

#Preview("Cible à 0") {
    WidgetCalorieRing(eaten: 0, target: 0, palette: .creme)
        .frame(width: 120, height: 120)
        .padding()
        .background(ThemePalette.creme.background)
}
