// App/Views/Celebrations/CelebrationsHost.swift
// Présentation séquentielle des célébrations (Task 19) : UNE à la fois.
// Level-up → LevelUpView plein écran ; badge/quête → bannière compacte (~3 s).
// Appliqué au niveau MainTabView pour fonctionner depuis n'importe quel onglet.

import SwiftUI

struct CelebrationsHost: ViewModifier {
    @Environment(GameService.self) private var game

    /// Célébration actuellement affichée (nil = rien) — la file reste dans GameService.
    @State private var current: Celebration?
    /// Message de Nivelito du level-up courant, calculé UNE fois au dépilage
    /// (`nivelitoSays` persiste le dernier message utilisé — pas d'appel dans body).
    @State private var levelUpMessage = ""

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let banner = bannerContent {
                    CelebrationBanner(emoji: banner.emoji, text: banner.text)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        // id : chaque bannière a SON minuteur de 3 s (une seconde
                        // bannière enchaînée repart de zéro).
                        .task(id: current?.id) {
                            try? await Task.sleep(for: .seconds(3))
                            guard !Task.isCancelled else { return }
                            dismiss()
                        }
                }
            }
            .overlay {
                if case .levelUp(let level) = current {
                    LevelUpView(level: level, message: levelUpMessage) { dismiss() }
                        .transition(.opacity.combined(with: .scale(scale: 1.06)))
                }
            }
            .onAppear { presentNextIfIdle() }
            // Dès qu'une célébration est levée (repas, pesée, clôture de journée…)
            // et que rien n'est affiché, on dépile.
            .onChange(of: game.pendingCelebrations.count) { _, _ in presentNextIfIdle() }
    }

    private var bannerContent: (emoji: String, text: String)? {
        switch current {
        case .badge(let badge): (badge.emoji, "Trophée débloqué : \(badge.title)")
        case .quest(let quest): (quest.emoji, "Quête accomplie : \(quest.title)")
        default: nil
        }
    }

    private func presentNextIfIdle() {
        guard current == nil, let next = game.consumeNextCelebration() else { return }
        if case .levelUp(let level) = next {
            levelUpMessage = game.nivelitoSays(context: .levelUp, value: level)
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            current = next
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.25)) {
            current = nil
        }
        // Laisse la transition de sortie se jouer, puis regarde s'il reste
        // quelque chose dans la file (présentation séquentielle).
        Task {
            try? await Task.sleep(for: .milliseconds(400))
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
    let emoji: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Text(emoji)
                .font(.title2)
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
        .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

#Preview("Bannière") {
    VStack {
        CelebrationBanner(emoji: "🏆", text: "Trophée débloqué : Première pesée")
        CelebrationBanner(emoji: "🥇", text: "Quête accomplie : Pèse-toi une fois")
        Spacer()
    }
    .fontDesign(.rounded)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.background)
}
