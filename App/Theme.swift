// App/Theme.swift
// Thèmes de Nivel (v1.1) : 4 palettes sélectionnables (Réglages > Thème),
// persistées PAR APPAREIL dans UserDefaults ("nivel.theme") — aucune sync.
// L'enum `Theme` reste la façade historique utilisée par toutes les vues
// (Theme.orange, Theme.green...) : ses statics lisent ThemeStore.shared
// (@Observable), donc tout accès pendant l'évaluation d'un body SwiftUI est
// tracké et les vues se re-rendent au changement de palette sans toucher
// les ~20 fichiers appelants.

import SwiftUI

/// Une palette = les 10 rôles de couleur de l'app.
/// `outline` (le bordeaux de Nivelito) est identique dans les 4 palettes :
/// c'est une couleur d'identité de la mascotte, pas une couleur d'ambiance.
struct ThemePalette: Identifiable, Equatable {
    let id: String
    /// Nom affiché dans Réglages > Thème.
    let name: String
    let emoji: String
    /// Pilote `.preferredColorScheme` : le chrome système (clavier, alertes,
    /// pickers) suit l'ambiance de la palette.
    let isDark: Bool

    let background: Color
    let card: Color
    let text: Color
    let subtext: Color
    /// Couleur principale (ex-`orange` v1) : tint global, fin des dégradés de bouton.
    let primary: Color
    /// Accent doux : début des dégradés, dépassement d'objectif (JAMAIS rouge, spec §7.4).
    let accent: Color
    /// Succès / progression (ex-`green` v1) — hue distincte de `primary` dans chaque palette.
    let success: Color
    /// Pas / infos (ex-`blue` v1) — hue distincte de `primary` dans chaque palette.
    let info: Color
    /// Fond des jauges + séparateurs.
    let track: Color
    /// Contour bordeaux de Nivelito (et de sa bulle).
    let outline: Color

    /// Couleurs du mini-aperçu (Réglages > Thème) : le fond, puis les pastilles.
    var previewSwatches: (background: Color, dots: [Color]) {
        (background, [primary, accent])
    }
}

extension ThemePalette {
    /// Le bordeaux du contour de Nivelito — commun aux 4 palettes.
    private static let nivelitoOutline = Color(hex: 0x3A1220)

    /// Palette v1, inchangée — crème/pêche cozy.
    static let creme = ThemePalette(
        id: "creme", name: "Crème", emoji: "🍮", isDark: false,
        background: Color(hex: 0xFDF6EC),
        card: .white,
        text: Color(hex: 0x5B4A3F),
        subtext: Color(hex: 0xB09A8A),
        primary: Color(hex: 0xF57C1F),
        accent: Color(hex: 0xF5B453),
        success: Color(hex: 0x7BC86C),
        info: Color(hex: 0x4DA3C7),
        track: Color(hex: 0xF4E7DB),
        outline: nivelitoOutline
    )

    /// Vert d'eau très clair, sauge + menthe.
    static let menthe = ThemePalette(
        id: "menthe", name: "Menthe", emoji: "🌿", isDark: false,
        background: Color(hex: 0xEDF7F0),
        card: .white,
        text: Color(hex: 0x3D5248),
        subtext: Color(hex: 0x8FB0A0),
        primary: Color(hex: 0x4E9B6F),   // vert sauge
        accent: Color(hex: 0x7FD4B8),    // menthe
        success: Color(hex: 0x8CC63F),   // vert pomme — distinct du sauge et de la menthe
        info: Color(hex: 0x4DA3C7),      // bleu ciel (pas)
        track: Color(hex: 0xDCEEE3),
        outline: nivelitoOutline
    )

    /// Bleu ciel très clair, bleu profond + turquoise.
    static let ocean = ThemePalette(
        id: "ocean", name: "Océan", emoji: "🌊", isDark: false,
        background: Color(hex: 0xECF5FB),
        card: .white,
        text: Color(hex: 0x3B5568),
        subtext: Color(hex: 0x8FAEC2),
        primary: Color(hex: 0x2E6F9E),   // bleu profond
        accent: Color(hex: 0x4EC0CA),    // turquoise
        success: Color(hex: 0x6BC17E),   // vert (progression)
        info: Color(hex: 0x7186D9),      // pervenche (pas) — distinct du bleu primaire
        track: Color(hex: 0xDBEAF4),
        outline: nivelitoOutline
    )

    /// Sombre CHAUD (brun, pas gris iOS) : brun presque noir, accents orange lumineux.
    /// Fond ~#261B18 pour que le contour bordeaux de Nivelito (#3A1220) reste lisible ;
    /// cartes nettement plus claires que le fond.
    static let nuitDouce = ThemePalette(
        id: "nuit-douce", name: "Nuit douce", emoji: "🌙", isDark: true,
        background: Color(hex: 0x261B18),
        card: Color(hex: 0x352822),
        text: Color(hex: 0xF2E4D3),      // crème chaude
        subtext: Color(hex: 0xBDA391),
        primary: Color(hex: 0xFF9142),   // orange lumineux
        accent: Color(hex: 0xFFB763),    // ambre doux
        success: Color(hex: 0x8FD481),
        info: Color(hex: 0x63B8DC),
        track: Color(hex: 0x46352C),
        outline: nivelitoOutline
    )

    /// Les 4 palettes, dans l'ordre d'affichage des Réglages.
    static let all: [ThemePalette] = [.creme, .menthe, .ocean, .nuitDouce]
}

/// Palette choisie, PAR APPAREIL — persistée dans UserDefaults (id de palette).
/// @Observable : les vues qui lisent `palette` (directement ou via la façade
/// `Theme`) pendant leur body se re-rendent automatiquement au changement.
@Observable
final class ThemeStore {
    static let shared = ThemeStore()
    static let defaultsKey = "nivel.theme"

    var palette: ThemePalette {
        didSet { defaults.set(palette.id, forKey: Self.defaultsKey) }
    }

    private let defaults: UserDefaults

    /// `defaults` injectable pour les tests (suite dédiée — pas de pollution
    /// des vrais réglages). Id inconnu ou absent → Crème.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedID = defaults.string(forKey: Self.defaultsKey)
        self.palette = ThemePalette.all.first { $0.id == savedID } ?? .creme
    }
}

/// Façade historique v1 — les vues continuent d'écrire `Theme.orange`,
/// `Theme.green`... ; chaque static lit la palette courante du ThemeStore.
enum Theme {
    static var background: Color { ThemeStore.shared.palette.background }
    static var card: Color { ThemeStore.shared.palette.card }
    static var text: Color { ThemeStore.shared.palette.text }
    static var subtext: Color { ThemeStore.shared.palette.subtext }
    static var orange: Color { ThemeStore.shared.palette.primary }
    static var accent: Color { ThemeStore.shared.palette.accent }
    static var green: Color { ThemeStore.shared.palette.success }
    static var blue: Color { ThemeStore.shared.palette.info }
    static var track: Color { ThemeStore.shared.palette.track }
    static var outline: Color { ThemeStore.shared.palette.outline }

    static let cardRadius: CGFloat = 24
    static let buttonRadius: CGFloat = 22

    /// Ombre douce commune (cartes, pastilles) — thème-aware : noir très léger sur
    /// les palettes claires ; un peu plus présent sur Nuit douce, où 6 % de noir
    /// disparaîtrait complètement et les cartes perdraient leur relief.
    static var shadow: Color {
        .black.opacity(ThemeStore.shared.palette.isDark ? 0.25 : 0.06)
    }
    /// Ombre des éléments flottants (bannière de célébration, barres collantes
    /// des sheets) — légèrement plus marquée que celle des cartes.
    static var floatingShadow: Color {
        .black.opacity(ThemeStore.shared.palette.isDark ? 0.35 : 0.10)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .shadow(color: Theme.shadow, radius: 8, y: 4)
    }
}
extension View { func card() -> some View { modifier(CardStyle()) } }

// MARK: - Styles de boutons partagés (v1.2)

/// Bouton principal de l'app : dégradé accent→primaire, texte blanc, radius 22,
/// léger enfoncement au tap (scale 0.97 + opacité), estompé à 40 % si désactivé.
/// `.regular` prend toute la largeur (CTA d'écran) ; `.compact` épouse son
/// contenu (bandeaux collants des sheets).
struct PrimaryButtonStyle: ButtonStyle {
    enum Size { case regular, compact }
    var size: Size = .regular

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: size == .regular ? .infinity : nil)
            .padding(.horizontal, size == .compact ? 20 : 0)
            .padding(.vertical, size == .compact ? 14 : 16)
            .background(
                LinearGradient(colors: [Theme.accent, Theme.orange],
                               startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: Theme.buttonRadius)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.9 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Bouton secondaire discret : texte primaire semibold, sans fond
/// (« Tout afficher », « Ouvrir les Réglages »…).
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.orange)
            .opacity(isEnabled ? (configuration.isPressed ? 0.5 : 1) : 0.4)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Bouton icône rond (engrenage de l'accueil, chevrons du journal) : pastille
/// card 40 pt, icône primaire, ombre douce, zone de tap 44 pt.
struct CircleIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(isEnabled ? Theme.orange : Theme.subtext.opacity(0.4))
            .frame(width: 40, height: 40)
            .background(Theme.card, in: Circle())
            .shadow(color: Theme.shadow, radius: 8, y: 4)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Typographie partagée (v1.2)

/// Titre de section des cartes et des sheets : « Poids », « Plat », « Durée »…
struct SectionTitle: View {
    private let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.text)
    }
}

/// Sur-titre en petites capitales : en-têtes de section des listes (journal,
/// sport), des Réglages et de l'onboarding.
struct Overline: View {
    private let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote.weight(.bold))
            .kerning(0.5)
            .textCase(.uppercase)
            .foregroundStyle(Theme.subtext)
    }
}
