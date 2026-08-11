// App/Views/ActionCardButton.swift
// Les deux appels à l'action de l'accueil (spec v1.13 §6.1) : « Noter un repas » et
// « Noter une activité ».
//
// Carte, et NON dégradé plein comme PrimaryButtonStyle. La raison est concrète : les
// deux illustrations sont en COULEURS, et le roux de Nivelito posé sur le dégradé
// accent→primaire se noierait. Le fond reste donc `Theme.card`, et c'est un lavis de
// teinte + un liseré qui portent l'identité du bouton.
//
// La teinte vient de la PALETTE (primary pour le repas, success pour l'activité) :
// les quatre thèmes suivent sans table de correspondance, et les deux boutons se
// distinguent au premier regard.

import SwiftUI
import UIKit

struct ActionCardButton: View {
    enum Size {
        /// Accueil : illustration 42 pt et sous-titre, soit 58 pt de haut.
        ///
        /// L'illustration est passée de 56 à 46 puis à 42 pt (deux retours de Michaël).
        /// **42 pt est le plancher utile** : le bloc titre + sous-titre fait ~38 pt, donc
        /// en dessous c'est le TEXTE qui fixe la hauteur et rapetisser le dessin ne gagne
        /// plus un pixel — ça ne fait que l'écraser.
        case regular
        /// Bandeau bas de l'onglet Repas : illustration 38 pt, sans sous-titre — la
        /// place manque au-dessus de la barre d'onglets, et le titre suffit là où
        /// l'écran dit déjà de quoi il parle.
        case compact
    }

    let title: String
    /// Ce que le bouton fait vraiment, en minuscules — c'est lui qui porte la clarté
    /// que « Logger » n'avait pas (spec §5). Ignoré en `.compact`.
    var subtitle: String?
    /// Nom de l'imageset sous `Buttons/` (scripts/import-button-icons.sh).
    let illustration: String
    /// Teinte du liseré, du lavis et du chevron.
    let tint: Color
    var size: Size = .regular
    let action: () -> Void

    private var illustrationSize: CGFloat { size == .regular ? 42 : 38 }
    private var showsSubtitle: Bool { size == .regular && subtitle != nil }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 14) {
                ButtonIllustration(name: illustration, size: illustrationSize)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.text)
                    if showsSubtitle, let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Theme.subtext)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(tint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, size == .regular ? 8 : 7)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(ActionCardButtonStyle(tint: tint))
        // Le sous-titre décrit le bouton, il ne s'annonce pas comme un second élément.
        .accessibilityElement(children: .combine)
    }
}

/// Le fond de la carte : lavis de teinte depuis le bord gauche (là où se trouve
/// l'illustration), liseré, ombre douce des cartes, et l'enfoncement au tap de
/// `PrimaryButtonStyle` — les deux boutons doivent réagir pareil.
private struct ActionCardButtonStyle: ButtonStyle {
    let tint: Color

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius)
        return configuration.label
            .background {
                shape
                    .fill(Theme.card)
                    .overlay {
                        shape.fill(
                            LinearGradient(colors: [tint.opacity(0.12), tint.opacity(0.02)],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                    }
                    .overlay {
                        shape.strokeBorder(tint.opacity(0.30), lineWidth: 1.5)
                    }
            }
            .clipShape(shape)
            .shadow(color: Theme.shadow, radius: 8, y: 4)
            .opacity(isEnabled ? (configuration.isPressed ? 0.9 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Illustration détourée du bouton. Repli sur un glyphe cozy si l'asset manque :
/// même principe que `SportIllustration`, l'app ne dépend jamais d'une image.
private struct ButtonIllustration: View {
    let name: String
    let size: CGFloat

    var body: some View {
        if UIImage(named: "Buttons/\(name)") != nil {
            Image(decorative: "Buttons/\(name)")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            CozyIcon(name: "icon_meal_log", size: size * 0.7)
                .foregroundStyle(Theme.orange)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Les deux boutons de l'app

extension ActionCardButton {
    /// « Noter un repas » — remplace le « + Logger un repas » de la v1 (spec §5).
    static func meal(size: Size = .regular, action: @escaping () -> Void) -> ActionCardButton {
        ActionCardButton(
            title: "Noter un repas",
            subtitle: "ce que tu viens de manger",
            illustration: "button_icon_eating",
            tint: Theme.orange,
            size: size,
            action: action
        )
    }

    /// « Noter une activité » — ouvre `ActivityPickerSheet` (spec §6.3).
    static func activity(size: Size = .regular, action: @escaping () -> Void) -> ActionCardButton {
        ActionCardButton(
            title: "Noter une activité",
            subtitle: "ce que tu viens de faire",
            illustration: "button_icon_sport",
            tint: Theme.green,
            size: size,
            action: action
        )
    }
}

// MARK: - Previews

#Preview("Les deux boutons") {
    VStack(spacing: 12) {
        ActionCardButton.meal {}
        ActionCardButton.activity {}
        ActionCardButton.meal(size: .compact) {}
    }
    .padding(20)
    .fontDesign(.rounded)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.background)
}

#Preview("Corps XXL") {
    VStack(spacing: 12) {
        ActionCardButton.meal {}
        ActionCardButton.activity {}
    }
    .padding(20)
    .fontDesign(.rounded)
    .environment(\.dynamicTypeSize, .accessibility2)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.background)
}
