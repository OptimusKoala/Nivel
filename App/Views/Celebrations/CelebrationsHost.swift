// App/Views/Celebrations/CelebrationsHost.swift
// Présentation séquentielle des célébrations (Task 19) : UNE à la fois.
// Level-up → LevelUpView plein écran ; badge/quête → bannière compacte (~3 s).
// Appliqué au niveau MainTabView pour fonctionner depuis n'importe quel onglet.
//
// v1.13 — une célébration s'écarte aussi d'un GLISSEMENT VERS LE HAUT (spec §4) :
// quand on ne veut pas la lire, attendre 3 s ou viser un tap est de trop. Le geste
// s'ajoute au tap et à l'auto-fermeture, il ne remplace rien.

import SwiftUI
import NivelCore

struct CelebrationsHost: ViewModifier {
    /// Toutes les durées de l'orchestration au même endroit.
    private enum Timing {
        /// Auto-dismiss d'une bannière badge/quête (spec Task 19 : ~3 s).
        static let bannerDuration: Duration = .seconds(3)
        /// Transition d'entrée d'une célébration (spring doux, léger settle).
        static let presentAnimation: Animation = .spring(response: 0.35, dampingFraction: 0.8)
        /// Transition de sortie d'une célébration.
        static let dismissTransition: Double = 0.25
        /// Pause après un dismiss avant de dépiler la suivante :
        /// sortie (0,25 s) + un temps de respiration — les célébrations
        /// s'enchaînent séquentiellement, pas en fondu croisé.
        static let postDismissDelay: Duration = .milliseconds(400)
        /// Distance vers le haut au-delà de laquelle le glissement écarte la
        /// célébration (spec v1.13 §4). 20 pt : au-dessus du tremblement d'un tap,
        /// bien en dessous d'un geste volontaire.
        static let dismissDragDistance: CGFloat = 20
        /// Suivi du doigt pendant le geste : borné pour que la bannière ne parte pas
        /// se cacher sous l'encoche avant même d'être relâchée.
        static let maxDragOffset: CGFloat = 60
    }

    @Environment(GameService.self) private var game

    /// Célébration actuellement affichée (nil = rien) — la file reste dans GameService.
    @State private var current: Celebration?
    /// Message de Nivelito du level-up courant, calculé UNE fois au dépilage
    /// (`nivelitoSays` persiste le dernier message utilisé — pas d'appel dans body).
    @State private var levelUpMessage = ""
    /// Dépilage différé post-dismiss — suivi pour être annulé si l'hôte disparaît.
    @State private var advanceTask: Task<Void, Never>?
    /// Suivi du doigt pendant un glissement vers le haut (toujours ≤ 0). Remis à zéro
    /// à chaque nouvelle célébration par le `.id` de la bannière.
    @State private var dragOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let banner = bannerContent {
                    CelebrationBanner(icon: banner.icon, text: banner.text)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .offset(y: dragOffset)
                        // Un tap ferme tout de suite (3 badges enchaînés ≠ 9 s subies).
                        .onTapGesture { dismiss() }
                        .gesture(dismissDrag)
                        // id : chaque bannière a SON minuteur (une seconde bannière
                        // enchaînée repart de zéro).
                        .task(id: current?.id) {
                            try? await Task.sleep(for: Timing.bannerDuration)
                            guard !Task.isCancelled else { return }
                            dismiss()
                        }
                }
            }
            .overlay {
                if case .levelUp(let level) = current {
                    LevelUpView(level: level, message: levelUpMessage) { dismiss() }
                        .transition(.opacity.combined(with: .scale(scale: 1.06)))
                        // Même geste que la bannière, par cohérence : « Continuer »
                        // reste le chemin principal.
                        .offset(y: dragOffset)
                        .gesture(dismissDrag)
                }
            }
            .onAppear { presentNextIfIdle() }
            // Dès qu'une célébration est levée (repas, pesée, clôture de journée…)
            // et que rien n'est affiché, on dépile. NB : un dismiss ne modifie pas
            // `count` (le dépilage a eu lieu à la présentation) → ce onChange ne
            // couvre que les RAISE ; l'après-dismiss passe par le Task de dismiss().
            .onChange(of: game.pendingCelebrations.count) { _, _ in presentNextIfIdle() }
            .onDisappear { advanceTask?.cancel() }
    }

    /// Glissement vers le HAUT pour écarter (spec v1.13 §4). Décision déléguée à
    /// `Self.dragOutcome`, pure et testée (CelebrationDismissTests).
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                dragOffset = Self.followOffset(translationHeight: value.translation.height,
                                               limit: Timing.maxDragOffset)
            }
            .onEnded { value in
                if Self.dismisses(translationHeight: value.translation.height,
                                  threshold: Timing.dismissDragDistance) {
                    dismiss()
                } else {
                    withAnimation(.snappy) { dragOffset = 0 }
                }
            }
    }

    /// Suivi du doigt : uniquement vers le haut (jamais de valeur positive — une
    /// célébration ne se tire pas vers le bas), et borné. Logique PURE, testée.
    static func followOffset(translationHeight: CGFloat, limit: CGFloat) -> CGFloat {
        max(-limit, min(0, translationHeight))
    }

    /// Le geste écarte-t-il la célébration ? Logique PURE, testée.
    static func dismisses(translationHeight: CGFloat, threshold: CGFloat) -> Bool {
        translationHeight < -threshold
    }

    private var bannerContent: (icon: CatalogIcon, text: String)? {
        switch current {
        case .badge(let badge): (badge.icon, "Trophée débloqué : \(badge.title)")
        case .quest(let quest): (quest.icon, "Quête accomplie : \(quest.title)")
        default: nil
        }
    }

    private func presentNextIfIdle() {
        guard current == nil, let next = game.consumeNextCelebration() else { return }
        if case .levelUp(let level) = next {
            levelUpMessage = game.nivelitoSays(context: .levelUp, value: level)
        }
        // Une célébration écartée d'un glissement laisse `dragOffset` en place : sans
        // cette remise à zéro, la SUIVANTE apparaîtrait déjà décalée vers le haut.
        dragOffset = 0
        withAnimation(Timing.presentAnimation) {
            current = next
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: Timing.dismissTransition)) {
            current = nil
        }
        // SEUL chemin de dépilage post-dismiss (voir le NB sur onChange) : laisse
        // la transition de sortie se jouer, puis regarde s'il reste quelque chose.
        advanceTask?.cancel()
        advanceTask = Task {
            try? await Task.sleep(for: Timing.postDismissDelay)
            guard !Task.isCancelled else { return }
            presentNextIfIdle()
        }
    }
}

extension View {
    /// Active la présentation des célébrations en attente (`GameService.pendingCelebrations`).
    func celebrationsHost() -> some View { modifier(CelebrationsHost()) }
}

// MARK: - Bannière compacte (badge / quête)

private struct CelebrationBanner: View {
    let icon: CatalogIcon
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            CatalogGlyph(icon: icon, size: 29)
                .foregroundStyle(Theme.orange)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Image(systemName: "sparkles")
                .font(.headline)
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .shadow(color: Theme.floatingShadow, radius: 10, y: 5)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

#Preview("Bannière") {
    VStack {
        CelebrationBanner(icon: .cozy("icon_scale"), text: "Trophée débloqué : Première pesée")
        CelebrationBanner(icon: .cozy("icon_scale"), text: "Quête accomplie : Pèse-toi une fois")
        Spacer()
    }
    .fontDesign(.rounded)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.background)
}
