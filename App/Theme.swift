// App/Theme.swift
// Thèmes de Nivel (v1.1) : 4 palettes sélectionnables (Réglages > Thème),
// persistées PAR APPAREIL dans UserDefaults ("nivel.theme") — aucune sync.
// Les palettes elles-mêmes vivent dans `Shared/ThemePalette.swift` (partagées
// avec l'extension widget) ; ce fichier garde le CHOIX de palette et le style.
// L'enum `Theme` reste la façade historique utilisée par toutes les vues
// (Theme.orange, Theme.green...) : ses statics lisent ThemeStore.shared
// (@Observable), donc tout accès pendant l'évaluation d'un body SwiftUI est
// tracké et les vues se re-rendent au changement de palette sans toucher
// les ~20 fichiers appelants.

import SwiftUI

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
        self.palette = ThemePalette.byID(defaults.string(forKey: Self.defaultsKey))
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
    /// Glyphe cozy optionnel devant le libellé (en-têtes du catalogue sport).
    private let icon: String?
    init(_ text: String, icon: String? = nil) { self.text = text; self.icon = icon }

    var body: some View {
        HStack(spacing: 5) {
            if let icon { CozyIcon(name: icon, size: 15) }
            Text(text)
        }
        .font(.footnote.weight(.bold))
        .kerning(0.5)
        .textCase(.uppercase)
        .foregroundStyle(Theme.subtext)
    }
}
