// App/Nivelito/SpeechBubble.swift
// Bulle de dialogue de Nivelito — fond blanc arrondi (18, 4 en bas-gauche), ombre douce.

import SwiftUI

struct SpeechBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Theme.text)
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 18,
                    bottomLeadingRadius: 4,
                    bottomTrailingRadius: 18,
                    topTrailingRadius: 18,
                    style: .continuous
                )
                .fill(Theme.card)
                .shadow(color: Theme.shadow, radius: 8, y: 4)
            )
    }
}

#Preview {
    SpeechBubble(text: "Bien joué pour ce repas ! +20 XP 🧡")
        .padding(32)
        .background(Theme.background)
}
