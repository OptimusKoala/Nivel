// App/Views/Sport/ActivityLogSheet.swift
// Validation d'une activité libre (spec sport §8.4) : 3 durées → « C'est fait ! ».

import SwiftUI
import SwiftData
import UIKit
import AudioToolbox
import NivelCore

struct ActivityLogSheet: View {
    @Environment(GameService.self) private var game
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let activity: Activity
    @State private var selectedMinutes: Int?
    @State private var isSaving = false
    /// XP que rapporterait la validation maintenant — 0 une fois le plafond du jour
    /// atteint : le CTA ne promet alors plus d'XP (honnêteté, spec v1 §13).
    @State private var xpReward = 30
    /// Timer opt-in : nil tant qu'aucune durée n'est choisie (spec timer §3.1). Recréé à
    /// chaque changement de durée (`.onChange(of: selectedMinutes)`), ce qui vaut reset.
    @State private var timer: ExerciseTimerModel?
    /// Promu à `.large` dès qu'une durée est choisie : révèle l'anneau + les contrôles au lieu
    /// de les insérer hors écran dans une sheet restée à `.medium` (review Task 5).
    @State private var detent: PresentationDetent = .medium

    /// `initialMinutes` permet aux previews de s'ouvrir directement avec une durée choisie
    /// (anneau du timer visible) sans simuler un tap, sur le modèle d'`initialPage` du player.
    init(activity: Activity, initialMinutes: Int? = nil) {
        self.activity = activity
        _selectedMinutes = State(initialValue: initialMinutes)
        _timer = State(initialValue: initialMinutes.map { ExerciseTimerModel(durationMinutes: $0) })
        _detent = State(initialValue: initialMinutes != nil ? .large : .medium)
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    Text(activity.name)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.text)
                    SectionTitle("Comment faire")
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(activity.instructions, id: \.self) { line in
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
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
        .onAppear { xpReward = game.nextActivityXP() }
        // Recrée le timer (reset implicite) à chaque nouvelle durée choisie ; re-taper la durée
        // déjà sélectionnée ne relance pas le timer (même valeur, pas d'événement) : Recommencer
        // couvre ce geste. Le passage à `.large` révèle l'anneau + les contrôles au lieu de les
        // insérer hors écran dans une sheet restée à `.medium`.
        .onChange(of: selectedMinutes) { _, minutes in
            timer = minutes.map { ExerciseTimerModel(durationMinutes: $0) }
            UIApplication.shared.isIdleTimerDisabled = false
            if minutes != nil { detent = .large }
        }
        .onChange(of: timer?.isRunning ?? false) { _, running in
            UIApplication.shared.isIdleTimerDisabled = running
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    // MARK: En-tête (vignette statique, ou bloc anneau/temps/contrôles une fois une durée choisie)

    @ViewBuilder
    private var header: some View {
        if let timer {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 10) {
                    TimerRingView(illustrationName: activity.id, fallbackEmoji: activity.emoji,
                                  fraction: timer.fraction(at: context.date),
                                  finished: timer.isFinished,
                                  segments: nil, size: 180)
                    TimerTimeLabel(timer: timer, now: context.date)
                    TimerButtons(timer: timer)
                }
                .frame(maxWidth: .infinity)
                .onChange(of: context.date) { _, date in
                    // Ordre exigé : lire l'overrun AVANT syncNow (spec §5), comme StepPageView.
                    let overrun = timer.overrun(at: date)
                    guard timer.syncNow(at: date) else { return }
                    if (overrun ?? .infinity) < 2 {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        AudioServicesPlaySystemSound(1103)
                    }
                }
            }
        } else {
            SportIllustration(name: activity.id, fallbackEmoji: activity.emoji,
                              size: 140, cornerRadius: 20)
                .frame(maxWidth: .infinity, alignment: .center)
        }
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
            // Pulse dérivé de `timer?.isFinished` à chaque rendu (pas de latch séparé) :
            // « Recommencer » fait retomber isFinished à false et éteint le pulse du même coup.
            // La validation reste possible à tout moment, pulse ou non (spec timer §5).
            .gentlePulse(timer?.isFinished == true, reduceMotion: reduceMotion)
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

#Preview("Durée choisie (timer)") {
    let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                         DayLog.self, GamificationState.self, ActivityEntry.self])
    let container = try! ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
    )
    let game = GameService(modelContext: container.mainContext, stepsService: FakeStepsService())
    let activity = game.activityCatalog.first!
    ActivityLogSheet(activity: activity, initialMinutes: activity.durations.first!)
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(game)
}
