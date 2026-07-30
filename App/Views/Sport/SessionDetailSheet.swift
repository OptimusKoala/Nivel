// App/Views/Sport/SessionDetailSheet.swift
// Détail de la séance du jour (spec sport §8.4) : étapes + « C'est fait ! ».
// Déjà faite aujourd'hui → état ✓ inactif (pas de double validation).

import SwiftUI
import SwiftData
import UIKit
import NivelCore

struct SessionDetailSheet: View {
    @Environment(GameService.self) private var game
    @Environment(\.dismiss) private var dismiss

    let session: ActivitySession
    let done: Bool
    @State private var isSaving = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 10) {
                        Text(session.emoji).font(.system(size: 40))
                        VStack(alignment: .leading, spacing: 2) {
                            Overline("Séance du jour")
                            Text(session.title)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.text)
                        }
                    }
                    VStack(spacing: 10) {
                        // offset comme id : une activité peut apparaître deux fois dans la séance.
                        ForEach(Array(session.steps.enumerated()), id: \.offset) { _, step in
                            stepRow(step)
                        }
                    }
                }
                .padding(20)
            }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
    }

    private func stepRow(_ step: SessionStep) -> some View {
        let activity = game.activitiesByID[step.activityID]
        return HStack(spacing: 12) {
            Text(activity?.emoji ?? "🏃").font(.system(size: 26))
            Text(activity?.name ?? step.activityID)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.text)
            Spacer()
            Text("\(step.minutes) min")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.orange)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Total")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.subtext)
                Text("\(session.totalMinutes) min · ~\(game.sessionKcal(session).frFormatted) kcal")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer()
            if done {
                Label("Déjà faite", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.green)
            } else {
                Button(action: validate) {
                    Text("C'est fait ! (+40 XP)")
                        .lineLimit(1)
                }
                .buttonStyle(PrimaryButtonStyle(size: .compact))
                .disabled(isSaving)
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
private func sessionDetailPreviewFixture() -> (container: ModelContainer, game: GameService, session: ActivitySession) {
    let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                         DayLog.self, GamificationState.self, ActivityEntry.self])
    let container = try! ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
    )
    let game = GameService(modelContext: container.mainContext, stepsService: FakeStepsService())
    // Catalogue toujours non vide (chargé depuis le bundle) — force-unwrap acceptable en preview.
    return (container, game, game.sessionCatalog.first!)
}

#Preview("À faire") {
    let (container, game, session) = sessionDetailPreviewFixture()
    SessionDetailSheet(session: session, done: false)
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(game)
}

#Preview("Déjà faite") {
    let (container, game, session) = sessionDetailPreviewFixture()
    SessionDetailSheet(session: session, done: true)
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(game)
}
