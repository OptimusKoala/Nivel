// App/Views/Sport/SportIllustration.swift
// Vignettes et héros des illustrations sport (spec illustrations §3) : affiche
// l'asset "Sport/<name>" ; FALLBACK automatique sur l'emoji en pastille si
// l'asset manque : l'app ne dépend jamais d'une image.

import SwiftUI
import UIKit

/// Vignette carrée (lignes de liste, cartes). `name` = id de catalogue.
struct SportIllustration: View {
    let name: String
    let fallbackEmoji: String
    var size: CGFloat = 52
    var cornerRadius: CGFloat = 12

    var body: some View {
        if UIImage(named: "Sport/\(name)") != nil {
            Image(decorative: "Sport/\(name)")
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            Text(fallbackEmoji)
                .font(.system(size: size * 0.55))
                .frame(width: size, height: size)
                .background(Theme.accent.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: cornerRadius))
                .accessibilityHidden(true)
        }
    }
}

/// Grand format du player (pleine largeur, carré, hauteur plafonnée ~280pt, spec §5.1).
struct SportHeroIllustration: View {
    let name: String
    let fallbackEmoji: String

    var body: some View {
        if UIImage(named: "Sport/\(name)") != nil {
            Image(decorative: "Sport/\(name)")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 280, maxHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .frame(maxWidth: .infinity)
        } else {
            Text(fallbackEmoji)
                .font(.system(size: 80))
                .frame(maxWidth: .infinity, minHeight: 180)
                .background(Theme.accent.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 20))
                .accessibilityHidden(true)
                .frame(maxWidth: .infinity)
        }
    }
}
