// Widgets/Views/SystemWidgetViews.swift
// Vues écran d'accueil (spec widgets §6) : petit = anneau + niveau,
// moyen = anneau + Nivelito + bulle + « + Repas » (deep link).
//
// MODE TEINTÉ (spec v1.13 §3) — quand l'écran d'accueil est teinté, WidgetKit passe
// ces vues en `widgetRenderingMode == .accented` et REMPLACE leurs couleurs : seul
// l'alpha survit. Un seul point de décision ici (`palette`), et tout le reste suit,
// puisque chaque sous-vue reçoit déjà sa palette en paramètre.

import SwiftUI
import WidgetKit
import NivelCore

struct NivelWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: NivelTimelineEntry

    /// Vrai quand l'écran d'accueil est teinté (« transparent »).
    private var isTinted: Bool { renderingMode == .accented }

    /// LE point de décision du mode teinté : une palette tout-en-alpha remplace celle
    /// du thème, et `WidgetCalorieRing`, `LevelPill` et `XPMiniBar` sont corrigées sans
    /// une ligne de changement.
    private var palette: ThemePalette {
        isTinted ? .accented : .byID(entry.planned?.themeID)
    }

    private var ink: NivelitoInk { isTinted ? .tinted : .full }

    var body: some View {
        Group {
            if let planned = entry.planned {
                switch family {
                case .systemMedium:
                    MediumWidgetView(entry: planned, palette: palette, ink: ink, tinted: isTinted)
                case .accessoryCircular: CircularAccessoryView(entry: planned)
                case .accessoryRectangular: RectangularAccessoryView(entry: planned)
                default: SmallWidgetView(entry: planned, palette: palette)
                }
            } else {
                switch family {
                case .accessoryCircular, .accessoryRectangular: AccessoryWelcomeView()
                default: WelcomeWidgetView(palette: palette, ink: ink)
                }
            }
        }
        .fontDesign(.rounded)
        .containerBackground(for: .widget) {
            switch family {
            // Teinté : le système fournit lui-même le fond translucide de la tuile —
            // `palette.background` y est déjà `.clear`, mais l'écrire ici évite qu'un
            // futur ajustement de la palette réintroduise un fond.
            case .accessoryCircular, .accessoryRectangular: Color.clear
            default: isTinted ? Color.clear : palette.background
            }
        }
    }
}

/// Pas encore de snapshot (spec widgets §9) : accueil doux, aucun chiffre.
struct WelcomeWidgetView: View {
    let palette: ThemePalette
    var ink: NivelitoInk = .full

    var body: some View {
        VStack(spacing: 8) {
            WidgetNivelito(sleepy: false, palette: palette, size: 64, ink: ink)
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
        // Groupe ACCENTUÉ du mode teinté (spec v1.13 §3.3) : le système lui donne la
        // couleur vive choisie par l'utilisateur, et sa déclinaison désaturée au reste.
        // Sans ce découpage le widget serait lisible, mais parfaitement plat.
        .widgetAccentable()
    }
}

struct MediumWidgetView: View {
    let entry: WidgetEntry
    let palette: ThemePalette
    var ink: NivelitoInk = .full
    /// Le bouton « Repas » est le seul élément dont la FORME change en mode teinté :
    /// un dégradé y devient un aplat sans bord (voir `mealLink`).
    var tinted = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 6) {
                WidgetCalorieRing(eaten: entry.kcalEaten, target: entry.kcalTarget,
                                  palette: palette)
                LevelPill(totalXP: entry.totalXP, palette: palette)
                XPMiniBar(totalXP: entry.totalXP, palette: palette)
            }
            // Colonne gauche PINNÉE : toute la largeur restante va à la bulle
            // (sinon le HStack partage 50/50 et tronque les messages).
            .frame(width: 96)
            // Colonne des chiffres = groupe accentué (voir SmallWidgetView).
            .widgetAccentable()
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    WidgetNivelito(sleepy: entry.expression == .sleepy,
                                   palette: palette, size: 72, ink: ink)
                    Text(entry.message)
                        .font(.caption)
                        .foregroundStyle(palette.text)
                        .lineLimit(5)
                        // 5 lignes + scale 0,75 : les 51 messages du catalogue passent
                        // sans troncature jusqu'à 321 pt (mesuré au harnais, spec vivant §4).
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(palette.card,
                                    in: RoundedRectangle(cornerRadius: 12))
                }
                .frame(maxHeight: .infinity, alignment: .top)
                mealLink
            }
        }
    }

    /// Deep link : ouvre l'app directement sur la sheet repas (spec §7).
    ///
    /// En mode teinté, le dégradé accent→primaire se réduit à un aplat uni sans bord —
    /// le bouton ne se lit plus comme un bouton. On le remplace donc par une capsule
    /// cerclée : c'est le SEUL endroit du widget où la forme change, et pas seulement
    /// la couleur (spec v1.13 §3.3).
    @ViewBuilder
    private var mealLink: some View {
        Link(destination: WidgetBridge.logMealURL) {
            Label("Repas", systemImage: "plus")
                .font(.footnote.weight(.bold))
                .foregroundStyle(tinted ? palette.text : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if tinted {
                        Capsule()
                            .fill(.white.opacity(0.22))
                            .overlay { Capsule().strokeBorder(.white.opacity(0.9), lineWidth: 1.5) }
                    } else {
                        Capsule()
                            .fill(LinearGradient(colors: [palette.accent, palette.primary],
                                                 startPoint: .leading, endPoint: .trailing))
                    }
                }
        }
        .accessibilityLabel("Noter un repas")
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

private let previewMessage = "Je m'entraîne à faire la roue. Pour l'instant, ça ressemble à une roulade."

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

#Preview("Moyen (321, pire cas)") {
    MediumWidgetView(entry: previewEntry, palette: .creme)
        .padding()
        .frame(width: 321, height: 148)
        .background(ThemePalette.creme.background)
}

#Preview("Moyen (nuit douce, sleepy)") {
    MediumWidgetView(entry: previewEntrySleepyNight, palette: .nuitDouce)
        .padding()
        .frame(width: 338, height: 158)
        .background(ThemePalette.nuitDouce.background)
}

// Mode teinté (spec v1.13 §3.4) : ces previews montrent la palette et les encres
// tout-en-alpha, mais PAS le remplacement de couleurs — il a lieu dans WidgetKit, pas
// dans SwiftUI, et `\.widgetRenderingMode` est en lecture seule. Le fond gris moyen
// approche la tuile translucide ; la preuve reste la capture sur l'écran d'accueil.

#Preview("Teinté — petit") {
    SmallWidgetView(entry: previewEntry, palette: .accented)
        .padding()
        .frame(width: 158, height: 158)
        .background(Color(white: 0.32))
}

#Preview("Teinté — moyen") {
    MediumWidgetView(entry: previewEntry, palette: .accented, ink: .tinted, tinted: true)
        .padding()
        .frame(width: 338, height: 158)
        .background(Color(white: 0.32))
}
