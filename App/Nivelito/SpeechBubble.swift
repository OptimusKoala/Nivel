// App/Nivelito/SpeechBubble.swift
// Bulle de dialogue de Nivelito — fond blanc arrondi (18, 4 en bas-gauche), ombre douce.

import SwiftUI

struct SpeechBubble: View {
    let text: String
    /// Une seconde ligne, plus discrète, sous le message. Sert au libellé de l'événement
    /// aimé (spec 1.15 §3.9) : il vit SOUS la phrase et jamais dedans, la phrase étant
    /// l'une des douze de la banque.
    var detail: String?
    /// Le liseré du cœur reçu (maquette C). En `Theme.accent`, bordeaux, JAMAIS en rouge.
    var highlighted = false
    /// Le cœur épinglé bat. Coupé par Reduce Motion, auquel cas il reste posé au coin,
    /// immobile — c'est le liseré qui porte l'information, l'animation est un renfort.
    var heartBeats = false

    /// Amplitude du battement. Une VALEUR d'état, pas une animation lancée à la main : voir
    /// `battement` plus bas.
    @State private var bat = false

    private var forme: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 18,
            bottomLeadingRadius: 4,
            bottomTrailingRadius: 18,
            topTrailingRadius: 18,
            style: .continuous
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.text)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            forme
                .fill(Theme.card)
                .shadow(color: Theme.shadow, radius: 8, y: 4)
        )
        // Le liseré est posé en overlay et non en `border` : la forme a quatre rayons
        // différents, et seule la même forme la suit exactement.
        .overlay(forme.stroke(Theme.accent, lineWidth: highlighted ? 2 : 0))
        .overlay(alignment: .topTrailing) { if highlighted { coeur } }
    }

    /// Le cœur épinglé au coin. Bordeaux lui aussi.
    private var coeur: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Theme.accent)
            .padding(4)
            .background(Theme.card, in: Circle())
            .overlay(Circle().stroke(Theme.accent, lineWidth: 1.5))
            .scaleEffect(bat ? 1.18 : 1)
            .offset(x: 6, y: -6)
            .animation(battement, value: bat)
            // ⚠️ Le `repeatForever` est porté par l'ANIMATION dérivée d'un booléen, jamais
            // lancé nu dans un `withAnimation` sur un état qui se relatche : c'est le piège
            // SwiftUI attrapé en review à la v1.5, où l'animation survivait à la disparition
            // de sa cause et se superposait à elle-même à chaque réapparition.
            .onAppear { bat = heartBeats }
            .onChange(of: heartBeats) { _, actif in bat = actif }
            .accessibilityHidden(true)  // l'information est dans le texte, qui est lu.
    }

    private var battement: Animation? {
        heartBeats ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true) : nil
    }
}

#Preview("Ordinaire") {
    SpeechBubble(text: "Bien joué pour ce repas ! +20 XP 🧡")
        .padding(32)
        .background(Theme.background)
}

#Preview("Un cœur reçu") {
    SpeechBubble(text: "Marion a aimé ta journée 💛",
                 detail: "Poisson et purée maison",
                 highlighted: true, heartBeats: true)
        .padding(32)
        .background(Theme.background)
}
