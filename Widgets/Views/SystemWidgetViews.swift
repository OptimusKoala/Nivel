// Widgets/Views/SystemWidgetViews.swift
// Vues écran d'accueil (spec widgets §6) : petit = anneau + niveau,
// moyen = anneau + Nivelito + bulle + « + Repas » (deep link).

import SwiftUI
import WidgetKit
import NivelCore

struct NivelWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NivelTimelineEntry

    private var palette: ThemePalette { .byID(entry.planned?.themeID) }

    var body: some View {
        Group {
            if let planned = entry.planned {
                switch family {
                case .systemMedium: MediumWidgetView(entry: planned, palette: palette)
                case .accessoryCircular: CircularAccessoryView(entry: planned)
                case .accessoryRectangular: RectangularAccessoryView(entry: planned)
                default: SmallWidgetView(entry: planned, palette: palette)
                }
            } else {
                switch family {
                case .accessoryCircular, .accessoryRectangular: AccessoryWelcomeView()
                default: WelcomeWidgetView(palette: palette)
                }
            }
        }
        .fontDesign(.rounded)
        .containerBackground(for: .widget) {
            switch family {
            case .accessoryCircular, .accessoryRectangular: Color.clear
            default: palette.background
            }
        }
    }
}

/// Pas encore de snapshot (spec widgets §9) : accueil doux, aucun chiffre.
struct WelcomeWidgetView: View {
    let palette: ThemePalette

    var body: some View {
        VStack(spacing: 8) {
            WidgetNivelito(sleepy: false, palette: palette, size: 64)
            Text("Ouvre Nivel pour commencer")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.text)
                .multilineTextAlignment(.center)
        }
    }
}

struct SmallWidgetView: View {
    let entry: WidgetEntry
    let palette: ThemePalette

    var body: some View {
        VStack(spacing: 8) {
            WidgetCalorieRing(eaten: entry.kcalEaten, target: entry.kcalTarget,
                              palette: palette)
            LevelPill(totalXP: entry.totalXP, palette: palette)
        }
    }
}

struct MediumWidgetView: View {
    let entry: WidgetEntry
    let palette: ThemePalette

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 6) {
                WidgetCalorieRing(eaten: entry.kcalEaten, target: entry.kcalTarget,
                                  palette: palette)
                    .aspectRatio(1, contentMode: .fit)
                LevelPill(totalXP: entry.totalXP, palette: palette)
                XPMiniBar(totalXP: entry.totalXP, palette: palette)
            }
            // Colonne gauche PINNÉE : toute la largeur restante va à la bulle
            // (sinon le HStack partage 50/50 et tronque les messages).
            .frame(width: 96)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    WidgetNivelito(sleepy: entry.expression == .sleepy,
                                   palette: palette, size: 48)
                    Text(entry.message)
                        .font(.caption)
                        .foregroundStyle(palette.text)
                        .lineLimit(4)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(palette.card,
                                    in: RoundedRectangle(cornerRadius: 12))
                }
                .frame(maxHeight: .infinity, alignment: .top)
                // Deep link : ouvre l'app directement sur la sheet repas (spec §7).
                Link(destination: WidgetBridge.logMealURL) {
                    Label("Repas", systemImage: "plus")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(colors: [palette.accent, palette.primary],
                                           startPoint: .leading, endPoint: .trailing),
                            in: Capsule()
                        )
                }
                .accessibilityLabel("Logger un repas")
            }
        }
    }
}

/// Progression XP vers le prochain niveau (spec §6 : « niveau et progression
/// XP ») — mini-jauge dégradée accent vers primaire, même esprit que XPCard.
struct XPMiniBar: View {
    let totalXP: Int
    let palette: ThemePalette

    var body: some View {
        let (current, needed) = LevelSystem.progress(forXP: totalXP)
        let fraction = needed > 0 ? Double(current) / Double(needed) : 0
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.track)
                if fraction > 0 {
                    Capsule()
                        .fill(LinearGradient(colors: [palette.accent, palette.primary],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, geo.size.width * min(1, fraction)))
                }
            }
        }
        .frame(height: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Expérience : \(current) sur \(needed) vers le niveau \(LevelSystem.level(forXP: totalXP) + 1)")
    }
}

/// Pastille « NIVEAU n », même esprit que la levelPill de l'accueil.
struct LevelPill: View {
    let totalXP: Int
    let palette: ThemePalette

    var body: some View {
        HStack(spacing: 4) {
            Text("NIVEAU")
                .font(.system(size: 9, weight: .bold))
                .kerning(0.5)
                .foregroundStyle(palette.subtext)
            Text("\(LevelSystem.level(forXP: totalXP))")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(palette.card, in: Capsule())
    }
}

// MARK: - Previews
// Le provider (UserDefaults) rend `#Preview(as:)` sur NivelWidget inutilisable
// ici : on prévisualise les vues simples, aux tailles réelles des familles.

private let previewMessage = "Petit fait du jour : les pandas roux adorent les câlins. Enfin, moi surtout."

private let previewEntry = WidgetEntry(
    date: .now, kcalEaten: 1240, kcalTarget: 2000, totalXP: 860,
    message: previewMessage, expression: .happy, themeID: "creme", userName: "Michaël"
)

private let previewEntrySleepyNight = WidgetEntry(
    date: .now, kcalEaten: 2350, kcalTarget: 2000, totalXP: 4200,
    message: previewMessage, expression: .sleepy, themeID: "nuit-douce", userName: "Michaël"
)

#Preview("Petit") {
    SmallWidgetView(entry: previewEntry, palette: .creme)
        .padding()
        .frame(width: 158, height: 158)
        .background(ThemePalette.creme.background)
}

#Preview("Moyen") {
    MediumWidgetView(entry: previewEntry, palette: .creme)
        .padding()
        .frame(width: 338, height: 158)
        .background(ThemePalette.creme.background)
}

#Preview("Moyen — Nuit douce, sleepy") {
    MediumWidgetView(entry: previewEntrySleepyNight, palette: .nuitDouce)
        .padding()
        .frame(width: 338, height: 158)
        .background(ThemePalette.nuitDouce.background)
}
