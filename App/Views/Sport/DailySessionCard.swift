// App/Views/Sport/DailySessionCard.swift
// Carte « Séance du jour » (spec sport §8.2) — partagée entre l'accueil et l'onglet
// Sport. Toujours visible, l'état ✓ n'est jamais punitif.

import SwiftUI
import NivelCore

/// Version « carte » (avec `.card()`) pour l'accueil ; l'onglet Sport utilise
/// directement `DailySessionCardContent` dans une List (le row a déjà son fond).
struct DailySessionCard: View {
    let session: ActivitySession
    let kcal: Int
    let done: Bool

    var body: some View {
        DailySessionCardContent(session: session, kcal: kcal, done: done)
            .card()
    }
}

struct DailySessionCardContent: View {
    let session: ActivitySession
    let kcal: Int
    let done: Bool

    var body: some View {
        HStack(spacing: 12) {
            SportIllustration(name: session.id, fallbackEmoji: session.emoji, size: 56, cornerRadius: 14)
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
                Label("Faite !", systemImage: "checkmark.circle.fill")
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
