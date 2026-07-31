// App/Views/CozyIcon.swift
// Icône cozy teintable (spec icônes §4). Un asset PDF ignore `.font()` (contrairement
// à un SF Symbol) : la taille est EXPLICITE. Canvas 28×28 avec ~3,5pt de marge par
// bord (~76 % d'encre) : viser size ≈ encre_voulue / 0,76 pour retrouver le poids
// visuel du symbole SF remplacé. Decorative : VoiceOver n'annonce jamais l'id d'asset
// (le sens est porté par le texte adjacent ou l'accessibilityLabel du parent).

import SwiftUI

struct CozyIcon: View {
    let name: String
    let size: CGFloat

    var body: some View {
        Image(decorative: "Icons/\(name)")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}
