// Shared/ThemePalette.swift
// Palettes de Nivel — PARTAGÉES entre l'app et l'extension widget (le widget
// résout sa palette depuis l'id porté par le snapshot, via `byID`).
// Le choix de palette et la façade `Theme` restent côté app (App/Theme.swift).

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

    /// Palette par id — id inconnu ou nil : Crème (utilisée par le widget, dont
    /// le snapshot peut venir d'une version antérieure de l'app).
    static func byID(_ id: String?) -> ThemePalette {
        all.first { $0.id == id } ?? .creme
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
