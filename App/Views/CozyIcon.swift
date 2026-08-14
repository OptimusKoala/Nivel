// App/Views/CozyIcon.swift
// Icône cozy teintable (spec icônes §4). Un asset PDF ignore `.font()` (contrairement
// à un SF Symbol) : la taille est EXPLICITE. Canvas 28×28 avec ~3,5pt de marge par
// bord (~76 % d'encre) : viser size ≈ encre_voulue / 0,76 pour retrouver le poids
// visuel du symbole SF remplacé. Decorative : VoiceOver n'annonce jamais l'id d'asset
// (le sens est porté par le texte adjacent ou l'accessibilityLabel du parent).

import SwiftUI
import NivelCore

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

/// Identité visuelle d'une entrée de catalogue — badge, quête ou thème (spec catalogues §5).
/// La TEINTE reste au site d'appel (`foregroundStyle`, qui traverse un PDF template et
/// laisse un emoji intact) : ce composant ne prend en charge que ce qui diffère vraiment
/// entre un glyphe et un emoji.
struct CatalogGlyph: View {
    let icon: CatalogIcon
    let size: CGFloat
    /// Badge encore verrouillé : silhouette estompée. Les deux cas demandent des
    /// traitements DIFFÉRENTS, et c'est tout l'intérêt de ce composant.
    ///
    /// - `.cozy` : l'estompage vient ENTIÈREMENT de la teinte posée au site d'appel, sans
    ///   opacité. Un 0,35 supplémentaire — calibré pour un emoji désaturé, qui garde des
    ///   pixels sombres — rendait le glyphe indiscernable du fond (Theme.subtext #B09A8A
    ///   sur Theme.track #F4E7DB : constaté au simulateur, badges verrouillés invisibles).
    /// - `.emoji` : `grayscale` ne ferait rien à un PDF template déjà monochrome, mais
    ///   c'est le bon outil pour un emoji.
    ///
    /// Attention : ce second cas n'a plus d'APPELANT. `locked` n'est passé qu'en un point,
    /// la grille des badges de QuestsView, et depuis la 1.14 aucun badge n'est en emoji.
    /// La branche reste parce que la porte est restée ouverte — quatre quêtes sont encore
    /// en emoji, et rien n'interdit qu'un jour une entrée verrouillée en soit — mais elle
    /// n'est plus vérifiée par l'œil de personne. La rallumer, c'est la re-regarder.
    var locked = false

    var body: some View {
        switch icon {
        case .cozy(let name):
            CozyIcon(name: name, size: size)
        case .emoji(let value):
            // 0,76 = le taux d'encre du canvas 28×28 : au même `size`, un emoji et un
            // glyphe pèsent alors pareil (spec §5).
            Text(value)
                .font(.system(size: size * 0.76))
                .grayscale(locked ? 1 : 0)
                // 0,5 et non le 0,35 d'avant la bascule : à 0,35 l'emoji désaturé pesait
                // visiblement moins que les glyphes teintés qui l'entouraient dans la
                // grille des badges. Ces voisins-là n'existent plus (la grille est
                // entièrement en glyphes) : ce 0,5 n'a donc plus rien à côté de quoi
                // peser, il est à recalibrer sur ce qui entourera le prochain emoji
                // verrouillé, pas à reprendre tel quel.
                .opacity(locked ? 0.5 : 1)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}
