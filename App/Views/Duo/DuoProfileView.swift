// App/Views/Duo/DuoProfileView.swift
// La page du partenaire (spec 1.15 §3.9, maquette A validée), présentée en feuille depuis
// l'accueil : identité, anneau du jour, quête la plus avancée, « Sa journée ».
//
// Elle lit le CACHE (`DuoIdentity.partnerSnapshot`) et non le réseau : elle s'ouvre donc
// instantanément, et hors ligne elle s'ouvre quand même. C'est la ligne de fraîcheur qui
// dit l'âge de ce qu'on montre, et elle n'est pas décorative — les chiffres peuvent être en
// retard, et il vaut mieux le dire que laisser croire à un chiffre juste.
//
// Trois choses qu'on ne fait PAS ici, et qui sont des décisions (§3.11) :
//
// - aucune comparaison, nulle part. On ne dit jamais qui a fait mieux, et les deux journées
//   ne sont jamais affichées côte à côte ;
// - aucun recalcul. Le niveau et sa progression arrivent DÉJÀ CALCULÉS (§3.4) : les deux
//   téléphones peuvent tourner sur deux courbes de niveaux différentes, et rejouer le
//   calcul avec la nôtre afficherait un niveau faux. `XPCard` de l'accueil, qui dérive tout
//   de `totalXP`, ne convient donc PAS ici, et ce n'est pas un oubli de réemploi ;
// - aucun jugement sur une journée vide.

import SwiftUI
import NivelCore

struct DuoProfileView: View {
    @Environment(DuoService.self) private var duo

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if let instantane = duo.partnerSnapshot {
                contenu(instantane)
            } else {
                // Appairé mais rien reçu : l'autre n'a pas encore publié. On le dit sans
                // en faire une panne, c'est l'affaire de quelques secondes.
                Text("La journée de ton duo n'est pas encore arrivée")
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtext)
                    .multilineTextAlignment(.center)
                    .padding(32)
            }
        }
        .foregroundStyle(Theme.text)
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
        // Ouvrir la page éteint la pastille (§3.9), et relit la zone au passage.
        .task {
            duo.markProfileSeen()
            await duo.refresh()
        }
    }

    private func contenu(_ instantane: DuoSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                identite(instantane)

                // Sous le bloc d'identité, comme le §3.9 la place : c'est la première chose
                // à savoir de tout ce qui suit, puisqu'elle en dit l'âge.
                Text(Self.freshness(generatedAt: instantane.generatedAt, now: .now))
                    .font(.caption2)
                    .foregroundStyle(Theme.subtext)
                    .frame(maxWidth: .infinity, alignment: .center)

                if Self.isStale(dayKey: instantane.dayKey,
                                today: GameService.duoDayKey(for: .now)) {
                    // Journée périmée : on n'affiche NI l'anneau NI le fil. Les chiffres
                    // d'hier présentés comme ceux d'aujourd'hui seraient un mensonge, et
                    // c'est le seul mensonge que cette page pourrait dire.
                    carte { Text(Self.staleNotice(partner: instantane.name))
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtext) }
                } else {
                    anneau(instantane)
                    if let quete = instantane.quest { carteDeQuete(quete) }
                    journee(instantane)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    // MARK: - 1. Identité

    private func identite(_ instantane: DuoSnapshot) -> some View {
        HStack(spacing: 14) {
            Image(decorative: Self.avatarName(sexRaw: instantane.sexRaw))
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .overlay(Circle().stroke(Theme.accent, lineWidth: 2).padding(-3))

            VStack(alignment: .leading, spacing: 6) {
                Text(instantane.name)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("Niveau \(instantane.level)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.subtext)
                // Les trois nombres viennent tels quels de l'autre téléphone : aucun n'est
                // recalculé ici. Voir l'en-tête du fichier.
                ThemedProgressBar(
                    fraction: instantane.xpForNextLevel > 0
                        ? Double(instantane.xpIntoLevel) / Double(instantane.xpForNextLevel)
                        : 0,
                    fill: LinearGradient(colors: [Theme.accent, Theme.orange],
                                         startPoint: .leading, endPoint: .trailing))
                Text("\(instantane.xpIntoLevel.frFormatted) / \(instantane.xpForNextLevel.frFormatted) XP")
                    .font(.caption2)
                    .foregroundStyle(Theme.subtext)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(instantane.name), niveau \(instantane.level), \(instantane.xpIntoLevel) sur \(instantane.xpForNextLevel) XP")
    }

    // MARK: - 2. L'anneau du jour

    /// `CalorieRingCard` telle quelle, pas une seconde version : le lot B lui a donné une
    /// géométrie mesurée au dixième de point et quatre constantes qui la tiennent. En
    /// redessiner une divergerait au premier ajustement, et c'est l'anneau que les deux
    /// personnes comparent du coin de l'œil — il doit être le MÊME.
    ///
    /// Un seul ajout côté carte : un préfixe de libellé d'accessibilité, pour que VoiceOver
    /// dise « Marion, calories… » et non « Calories… » sur une page qui parle de quelqu'un
    /// d'autre.
    private func anneau(_ instantane: DuoSnapshot) -> some View {
        VStack(spacing: 10) {
            CalorieRingCard(eaten: instantane.kcalEaten, target: instantane.kcalTarget,
                            burned: instantane.burned, burnTarget: instantane.burnTarget,
                            accessibilityOwner: instantane.name)
                .frame(height: 210)

            if instantane.steps != DuoSnapshot.stepsUnavailable {
                HStack(spacing: 6) {
                    CozyIcon(name: "icon_footprints", size: 16)
                    Text("\(instantane.steps.frFormatted) pas")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.subtext)
            }
            // Pas de ligne « 0 pas » quand les pas sont indisponibles : la sentinelle du
            // §3.3 existe pour ça, et afficher un zéro à quelqu'un qui a marché toute la
            // journée serait faux.
        }
    }

    // MARK: - 3. Sa quête la plus avancée

    private func carteDeQuete(_ quete: DuoQuestLine) -> some View {
        carte {
            VStack(alignment: .leading, spacing: 6) {
                Overline("Sa quête")
                Text(quete.title).font(.subheadline.weight(.semibold))
                ThemedProgressBar(fraction: quete.total > 0
                                    ? min(1, Double(quete.done) / Double(quete.total)) : 0,
                                  fill: Theme.green)
                Text("\(quete.done) / \(quete.total)")
                    .font(.caption2)
                    .foregroundStyle(Theme.subtext)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sa quête : \(quete.title), \(quete.done) sur \(quete.total)")
    }

    // MARK: - 4. Sa journée

    private func journee(_ instantane: DuoSnapshot) -> some View {
        carte {
            VStack(alignment: .leading, spacing: 10) {
                Overline("Sa journée")

                if instantane.events.isEmpty {
                    Text(Self.emptyFeedText(partner: instantane.name))
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtext)
                } else {
                    ForEach(Array(instantane.events.enumerated()), id: \.element.id) { rang, evenement in
                        if rang > 0 { Rectangle().fill(Theme.track).frame(height: 1) }
                        DuoFeedRow(event: evenement,
                                   isLiked: duo.givenLikeEventIDs.contains(evenement.id)) {
                            Task { await duo.toggleLike(on: evenement) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func carte(@ViewBuilder _ contenu: () -> some View) -> some View {
        contenu()
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
    }

    // MARK: - Décisions

    /// « mis à jour il y a 4 min ». Quatre paliers, du plus fin au plus grossier : on veut
    /// savoir si le chiffre date de la minute ou de l'avant-veille, pas connaître la seconde.
    ///
    /// Un instantané venu du « futur » (deux téléphones ne sont pas à la seconde près) est
    /// ramené à l'instant plutôt que d'afficher un âge négatif.
    static func freshness(generatedAt: Date, now: Date = .now) -> String {
        let secondes = max(0, now.timeIntervalSince(generatedAt))
        switch secondes {
        case ..<60: return "mis à jour à l'instant"
        case ..<3_600: return "mis à jour il y a \(Int(secondes / 60)) min"
        case ..<86_400: return "mis à jour il y a \(Int(secondes / 3_600)) h"
        default: return "mis à jour il y a \(Int(secondes / 86_400)) j"
        }
    }

    /// La journée vide, dite sans reproche. Ni « seulement », ni « déjà », ni « toujours
    /// rien » : le reproche serait lu par quelqu'un d'autre que celui qu'il vise, ce qui le
    /// rend plus lourd qu'ailleurs. Un test refuse ces mots.
    static func emptyFeedText(partner: String?) -> String {
        guard let partner, !partner.isEmpty else { return "Rien de noté pour l'instant" }
        return "\(partner) n'a rien noté pour l'instant"
    }

    /// L'instantané est-il d'un autre jour que celui qu'on regarde ? Comparaison de chaînes
    /// `AAAA-MM-JJ`, jamais de dates : c'est une étiquette de journée LOCALE, et deux fuseaux
    /// ne doivent pas pouvoir la faire glisser d'un jour (§3.3).
    ///
    /// « Différent », et pas « antérieur » : un instantané daté de demain n'est pas la
    /// journée qu'on regarde non plus.
    static func isStale(dayKey: String, today: String) -> Bool { dayKey != today }

    /// Ce qu'on montre à la place des chiffres d'hier. Une attente, pas une panne : le
    /// téléphone de l'autre n'a simplement pas encore publié sa journée.
    static func staleNotice(partner: String?) -> String {
        guard let partner, !partner.isEmpty else {
            return "La journée d'aujourd'hui n'est pas encore arrivée"
        }
        return "La journée de \(partner) n'est pas encore arrivée"
    }

    /// L'illustration du partenaire, parmi les deux présentes depuis la v1.1. `sexRaw`
    /// voyage en clair (§3.3) : une valeur qu'une version future publierait ne doit pas
    /// laisser un trou à la place du visage, d'où le repli.
    static func avatarName(sexRaw: String) -> String {
        sexRaw == Sex.female.rawValue ? "Avatars/girl" : "Avatars/boy"
    }
}
