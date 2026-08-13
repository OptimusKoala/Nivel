// App/Views/Sport/PlanSessionCard.swift
// La coque COMMUNE aux trois cartes de séance : séance du jour, posture, muscu.
//
// Les trois avaient le même `body` à l'octet près — illustration, surtitre, titre,
// sous-titre, puis « Faite ! » ou chevron — et n'en différaient que par trois valeurs.
// L'enjeu n'est pas les lignes économisées : aucune des trois ne traite encore
// l'accessibilité (l'état « faite » ne passe aujourd'hui que par une icône et une
// couleur), et le jour où quelqu'un ajoute un `accessibilityLabel`, corrige un
// débordement en Dynamic Type XXL ou traite le mode teinté, il ne doit pas avoir à
// trouver trois fichiers dans deux dossiers.
//
// Le sous-titre est une String toute faite, et NON un compteur : « 1 soir ce mois-ci »,
// « 1 séance ce mois-ci » et « 12 min · ~90 kcal » ne sont pas la même phrase au
// pluriel. Chaque carte reste propriétaire de sa formulation.

import SwiftUI
import NivelCore

struct PlanSessionCardContent: View {
    let overline: String
    let session: ActivitySession
    let subtitle: String
    let done: Bool
    /// 56 pt dans l'onglet Sport (défaut), 46 sur l'accueil compacté.
    var illustrationSize: CGFloat = 56

    var body: some View {
        HStack(spacing: 12) {
            SportIllustration(name: session.id, size: illustrationSize, cornerRadius: 14)
            VStack(alignment: .leading, spacing: 3) {
                Text(overline)
                    .font(.system(size: 10, weight: .bold))
                    .kerning(0.5)
                    .foregroundStyle(Theme.subtext)
                Text(session.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
            }
            Spacer()
            if done {
                Label { Text("Faite !") } icon: { CozyIcon(name: "icon_check", size: 20) }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.green)
            } else {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
