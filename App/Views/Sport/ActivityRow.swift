// App/Views/Sport/ActivityRow.swift
// Une entrée du catalogue d'activités libres, telle qu'elle apparaît dans une liste
// (spec sport §8.3). Extraite de `SportView` en v1.13 pour être partagée avec
// `ActivityPickerSheet` : deux listes des mêmes activités ne doivent pas pouvoir
// diverger au premier ajustement.

import SwiftUI
import NivelCore

struct ActivityRow: View {
    let activity: Activity
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                SportIllustration(name: activity.id)
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    // Fourchette kcal indicative (spec sport §8.3) sur les durées min/max.
                    Text(activity.durations.map(String.init).joined(separator: " / ")
                         + " min · ~\(activity.estimatedKcal(minutes: activity.durations.first ?? 0).frFormatted)"
                         + " à \(activity.estimatedKcal(minutes: activity.durations.last ?? 0).frFormatted) kcal")
                        .font(.caption)
                        .foregroundStyle(Theme.subtext)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.subtext)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Theme.card)
    }
}
