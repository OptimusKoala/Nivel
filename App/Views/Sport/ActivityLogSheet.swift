// App/Views/Sport/ActivityLogSheet.swift
// Validation d'une activité libre (spec sport §8.4) : 3 durées → « C'est fait ! ».

import SwiftUI
import SwiftData
import UIKit
import NivelCore

struct ActivityLogSheet: View {
    @Environment(GameService.self) private var game
    @Environment(\.dismiss) private var dismiss

    let activity: Activity
    @State private var selectedMinutes: Int?
    @State private var isSaving = false
    /// XP que rapporterait la validation maintenant — 0 une fois le plafond du jour
    /// atteint : le CTA ne promet alors plus d'XP (honnêteté, spec v1 §13).
    @State private var xpReward = 30

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 10) {
                        Text(activity.emoji).font(.system(size: 40))
                        Text(activity.name)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.text)
                    }
                    SectionTitle("Durée")
                    HStack(spacing: 8) {
                        ForEach(activity.durations, id: \.self) { minutes in
                            durationButton(minutes)
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
        .onAppear { xpReward = game.nextActivityXP() }
    }

    private func durationButton(_ minutes: Int) -> some View {
        let isSelected = selectedMinutes == minutes
        return Button {
            selectedMinutes = minutes
        } label: {
            VStack(spacing: 3) {
                Text("\(minutes) min")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isSelected ? .white : Theme.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text("~\(activity.estimatedKcal(minutes: minutes).frFormatted) kcal")
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .white.opacity(0.85) : Theme.subtext)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.vertical, 12)
            .background(isSelected ? Theme.orange : Theme.card,
                        in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
        Button(xpReward > 0 ? "C'est fait ! (+\(xpReward) XP)" : "C'est fait !",
               action: validate)
            .buttonStyle(PrimaryButtonStyle())
            .disabled(selectedMinutes == nil || isSaving)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Theme.card.ignoresSafeArea(edges: .bottom))
            .shadow(color: Theme.floatingShadow, radius: 10, y: -4)
    }

    private func validate() {
        guard let minutes = selectedMinutes, !isSaving else { return }
        isSaving = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            await game.logActivity(activity: activity, durationMinutes: minutes)
            dismiss()
        }
    }
}

// MARK: - Preview

#Preview {
    let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                         DayLog.self, GamificationState.self, ActivityEntry.self])
    let container = try! ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
    )
    let game = GameService(modelContext: container.mainContext, stepsService: FakeStepsService())
    // Catalogue toujours non vide (chargé depuis le bundle) — force-unwrap acceptable en preview.
    ActivityLogSheet(activity: game.activityCatalog.first!)
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(game)
}
