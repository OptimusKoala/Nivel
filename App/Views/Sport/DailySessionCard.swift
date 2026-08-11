// App/Views/Sport/DailySessionCard.swift
// Carte « Séance du jour » (spec sport §8.2) — partagée entre l'accueil et l'onglet
// Sport. Toujours visible, l'état ✓ n'est jamais punitif.

import SwiftUI
import NivelCore

/// Version « carte » pour l'accueil ; l'onglet Sport utilise directement
/// `DailySessionCardContent` dans une List (le row a déjà son fond).
///
/// Sur l'accueil la carte est COMPACTE (v1.13, retour de Michaël) : illustration 46 pt
/// au lieu de 56 et marges verticales 10 au lieu des 14 de `.card()`, soit 66 pt de haut
/// contre 84. C'est ce qui fait tenir tout l'accueil sans défilement, une fois les deux
/// boutons d'action réduits. L'onglet Sport garde le grand format : la place y est, et
/// la séance y est le sujet de l'écran, pas une ligne parmi d'autres.
struct DailySessionCard: View {
    let session: ActivitySession
    let kcal: Int
    let done: Bool

    var body: some View {
        DailySessionCardContent(session: session, kcal: kcal, done: done,
                                illustrationSize: 46)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .shadow(color: Theme.shadow, radius: 8, y: 4)
    }
}

struct DailySessionCardContent: View {
    let session: ActivitySession
    let kcal: Int
    let done: Bool
    /// 56 pt dans l'onglet Sport (défaut), 46 sur l'accueil compacté.
    var illustrationSize: CGFloat = 56

    var body: some View {
        HStack(spacing: 12) {
            SportIllustration(name: session.id, size: illustrationSize, cornerRadius: 14)
            VStack(alignment: .leading, spacing: 3) {
                Text("SÉANCE DU JOUR")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(0.5)
                    .foregroundStyle(Theme.subtext)
                Text(session.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text("\(session.totalMinutes) min · ~\(kcal.frFormatted) kcal")
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
