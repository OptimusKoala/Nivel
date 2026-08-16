// App/Views/Duo/DuoFeedRow.swift
// Une ligne du fil du partenaire (spec 1.15 §3.9) : l'heure, le libellé, le sous-titre, et
// le cœur.
//
// Rien n'est recalculé ici. `title` et `subtitle` arrivent tels qu'ils ont été composés
// CHEZ L'AUTRE, à la publication (§3.4) : il a ses catalogues, on n'a pas forcément les
// mêmes, et une entrée récente qu'on ne connaîtrait pas s'afficherait sinon en trou. Cette
// ligne est un afficheur, pas un formateur.

import SwiftUI
import NivelCore

struct DuoFeedRow: View {
    let event: DuoEvent
    let isLiked: Bool
    /// Appelé au tap. Le geste est OPTIMISTE côté service : le cœur change d'état tout de
    /// suite, l'écriture suit.
    let onToggleLike: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CozyIcon(name: Self.iconName(for: event.kind), size: 22)
                .foregroundStyle(Theme.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(event.subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(Self.time(for: event.at))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.subtext)
                .monospacedDigit()

            coeur
        }
        .padding(.vertical, 4)
    }

    private var coeur: some View {
        Button(action: onToggleLike) {
            // `heart.fill` en BORDEAUX (`Theme.accent`), jamais en rouge : la règle
            // fondatrice de la v1 vaut ici comme partout, et un cœur bordeaux ne dit pas
            // autre chose qu'un cœur rouge.
            Image(systemName: isLiked ? "heart.fill" : "heart")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isLiked ? Theme.accent : Theme.subtext)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                // Le cœur change d'état sous le doigt : l'animation vient du changement de
                // symbole, pas d'un `repeatForever` posé sur un état qui se relatche.
                .animation(.snappy, value: isLiked)
        }
        .buttonStyle(.plain)
        // Un BOUTON qui dit ce qu'il fait ET sur quoi (§3.9). Sans le nom de l'événement,
        // VoiceOver annoncerait « Aimer, bouton » quatre fois dans la même journée sans
        // qu'on sache jamais lequel on active.
        .accessibilityLabel(Self.heartLabel(isLiked: isLiked, eventTitle: event.title))
    }

    // MARK: - Décisions

    /// L'icône d'un genre d'événement.
    ///
    /// **Le cas `unknown` est le point de ce petit tableau** : c'est le genre qu'une version
    /// future publierait, et sur lequel le décodage se replie (§3.4). La ligne reste
    /// parfaitement lisible — son texte a été composé chez celui qui la publie — et reste
    /// AIMABLE. Seule son icône est indéterminée, et une icône neutre vaut infiniment mieux
    /// qu'une ligne escamotée.
    static func iconName(for kind: DuoEvent.Kind) -> String {
        switch kind {
        case .meal: "tab_meals"
        case .activity: "tab_sport"
        case .unknown: "icon_star"
        }
    }

    /// « Aimer Salade de lentilles » / « Ne plus aimer Salade de lentilles ».
    static func heartLabel(isLiked: Bool, eventTitle: String) -> String {
        (isLiked ? "Ne plus aimer " : "Aimer ") + eventTitle
    }

    /// L'heure de l'événement, sans secondes. Le fuseau est injectable pour que le test dise
    /// quelque chose de stable où qu'il tourne ; en vrai c'est celui du téléphone qui lit,
    /// et c'est le bon : deux personnes qui se suivent vivent à la même heure.
    static func time(for date: Date, timeZone: TimeZone = .current) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "fr_FR")
        format.timeZone = timeZone
        format.dateFormat = "HH:mm"
        return format.string(from: date)
    }
}
