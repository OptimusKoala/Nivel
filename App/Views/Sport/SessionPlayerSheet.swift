// App/Views/Sport/SessionPlayerSheet.swift
// Player pas-à-pas de la séance du jour (spec illustrations §5.1) : page 0 aperçu,
// une page par étape (grande illustration, consignes, tempo), navigation LIBRE
// (guide, pas chrono). Validation sur la dernière page uniquement.
// Remplace SessionDetailSheet.

import SwiftUI
import SwiftData
import UIKit
import NivelCore

struct SessionPlayerSheet: View {
    @Environment(GameService.self) private var game
    @Environment(\.dismiss) private var dismiss

    let session: ActivitySession
    let done: Bool
    @State private var page: Int
    @State private var isSaving = false

    /// `initialPage` permet aux previews de s'ouvrir directement sur une étape
    /// (états à risque : puces longues, tempo, AX3) sans naviguer manuellement.
    init(session: ActivitySession, done: Bool, initialPage: Int = 0) {
        self.session = session
        self.done = done
        _page = State(initialValue: initialPage)
    }

    /// Contrat du bouton bas (spec §5.1) : logique PURE, testée (SessionPlayerTests).
    enum PlayerButton: Equatable { case start, next, validate, alreadyDone }

    static func buttonState(page: Int, stepCount: Int, done: Bool) -> PlayerButton {
        // Pré-condition : stepCount ≥ 1 — garanti par le catalogue
        // (ActivityCatalogTests.testSessionsLoadAndStepsResolve).
        if page == 0 { return done ? .alreadyDone : .start }
        if page < stepCount { return .next }
        return done ? .alreadyDone : .validate
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                dots
                TabView(selection: $page) {
                    overviewPage.tag(0)
                    ForEach(Array(session.steps.enumerated()), id: \.offset) { index, step in
                        stepPage(step, number: index + 1).tag(index + 1)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .presentationDetents([.large])
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
    }

    // MARK: Progression

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(0...session.steps.count, id: \.self) { index in
                Circle()
                    .fill(index == page ? Theme.orange : Theme.track)
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.top, 14)
        // Même pattern que les points de l'onboarding : position exposée à VoiceOver.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Étape \(page + 1) sur \(session.steps.count + 1)")
        .animation(.spring(duration: 0.4), value: page)
    }

    // MARK: Page 0 : aperçu

    private var overviewPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SportHeroIllustration(name: session.id, fallbackEmoji: session.emoji)
                VStack(alignment: .leading, spacing: 3) {
                    Overline("Séance du jour")
                    Text(session.title)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.text)
                    Text("\(session.totalMinutes) min · ~\(game.sessionKcal(session).frFormatted) kcal")
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtext)
                }
                VStack(spacing: 8) {
                    ForEach(Array(session.steps.enumerated()), id: \.offset) { _, step in
                        summaryRow(step)
                    }
                }
            }
            .padding(20)
        }
    }

    private func summaryRow(_ step: SessionStep) -> some View {
        let activity = game.activitiesByID[step.activityID]
        return HStack(spacing: 10) {
            SportIllustration(name: step.activityID,
                              fallbackEmoji: activity?.emoji ?? "🏃",
                              size: 40, cornerRadius: 10)
            Text(activity?.name ?? step.activityID)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.text)
            Spacer()
            Text("\(step.minutes) min")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.orange)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Pages 1..n : étapes

    private func stepPage(_ step: SessionStep, number: Int) -> some View {
        let activity = game.activitiesByID[step.activityID]
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SportHeroIllustration(name: step.activityID,
                                      fallbackEmoji: activity?.emoji ?? "🏃")
                HStack(alignment: .firstTextBaseline) {
                    Text(activity?.name ?? step.activityID)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Text("Étape \(number)/\(session.steps.count) · \(step.minutes) min")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.subtext)
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(activity?.instructions ?? [], id: \.self) { line in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•").foregroundStyle(Theme.orange)
                            Text(line)
                                .font(.subheadline)
                                .foregroundStyle(Theme.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Text(step.tempo)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.accent.opacity(0.15), in: Capsule())
            }
            .padding(20)
        }
    }

    // MARK: Bouton bas

    private var bottomBar: some View {
        HStack {
            switch Self.buttonState(page: page, stepCount: session.steps.count, done: done) {
            case .start:
                Button("C'est parti !") { withAnimation(.snappy) { page = 1 } }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isSaving)
            case .next:
                Button("Étape suivante →") { withAnimation(.snappy) { page += 1 } }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isSaving)
            case .validate:
                // Montant depuis XPEngine : le libellé ne peut pas mentir si la règle change.
                Button("C'est fait ! (+\(XPEngine.award(.dailySessionDone, todayCount: 0)) XP)", action: validate)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isSaving)
            case .alreadyDone:
                Label("Déjà faite", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.green)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.card.ignoresSafeArea(edges: .bottom))
        .shadow(color: Theme.floatingShadow, radius: 10, y: -4)
    }

    private func validate() {
        guard !isSaving else { return }
        isSaving = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            await game.logDailySession(session: session)
            dismiss()
        }
    }
}

// MARK: - Previews

@MainActor
private func sessionPlayerPreviewFixture() -> (container: ModelContainer, game: GameService, session: ActivitySession) {
    let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                         DayLog.self, GamificationState.self, ActivityEntry.self])
    let container = try! ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
    )
    let game = GameService(modelContext: container.mainContext, stepsService: FakeStepsService(),
                           widgetDefaults: nil)
    // Catalogue toujours non vide (chargé depuis le bundle) — force-unwrap acceptable en preview.
    return (container, game, game.sessionCatalog.first!)
}

#Preview("À faire") {
    let (container, game, session) = sessionPlayerPreviewFixture()
    SessionPlayerSheet(session: session, done: false)
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(game)
}

#Preview("Déjà faite") {
    let (container, game, session) = sessionPlayerPreviewFixture()
    SessionPlayerSheet(session: session, done: true)
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(game)
}

#Preview("Étape") {
    let (container, game, session) = sessionPlayerPreviewFixture()
    SessionPlayerSheet(session: session, done: false, initialPage: 1)
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(game)
}

#Preview("Étape (AX3)") {
    let (container, game, session) = sessionPlayerPreviewFixture()
    SessionPlayerSheet(session: session, done: false, initialPage: 1)
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(game)
        .environment(\.dynamicTypeSize, .accessibility3)
}
