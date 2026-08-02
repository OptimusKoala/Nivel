// App/Views/Sport/ActivityLogSheet.swift
// Validation d'une activité libre (spec sport §8.4) : 3 durées → « C'est fait ! ».

import SwiftUI
import SwiftData
import UIKit
import NivelCore

struct ActivityLogSheet: View {
    @Environment(GameService.self) private var game
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let activity: Activity
    /// Durée choisie : une puce du catalogue ou la valeur de la roue (spec v1.9 §5.1).
    @State private var selection: DurationSelection?
    /// Valeur courante de la roue, indépendante du fait qu'elle soit sélectionnée.
    @State private var customMinutes: Int
    @State private var isSaving = false
    /// XP que rapporterait la validation maintenant — 0 une fois le plafond du jour
    /// atteint : le CTA ne promet alors plus d'XP (honnêteté, spec v1 §13).
    @State private var xpReward = 30
    /// Timer opt-in : nil tant qu'aucune durée n'est choisie (spec timer §3.1). Recréé à
    /// chaque changement de durée (`.onChange(of: selection?.minutes)`), ce qui vaut reset.
    @State private var timer: ExerciseTimerModel?
    /// `initialMinutes` permet aux previews de s'ouvrir directement avec une durée choisie
    /// (anneau du timer visible) sans simuler un tap, sur le modèle d'`initialPage` du player.
    init(activity: Activity, initialMinutes: Int? = nil) {
        self.activity = activity
        _selection = State(initialValue: initialMinutes.map { DurationSelection.preset($0) })
        _timer = State(initialValue: initialMinutes.map { ExerciseTimerModel(durationMinutes: $0) })
        _customMinutes = State(initialValue: CustomDuration.openingValue(
            current: initialMinutes, durations: activity.durations))
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
                        customButton
                    }
                    if selection?.isCustom == true {
                        customWheel
                    }
                }
                .padding(20)
            }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        // Grand détent d'office (retour de Michaël) : au medium, les boutons de durée
        // passaient sous le pli, il fallait scroller avant même de pouvoir choisir.
        // Même présentation que le player (SessionPlayerSheet).
        .presentationDetents([.large])
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
        .onAppear { xpReward = game.nextActivityXP() }
        // La roue met à jour la sélection tant qu'elle est active.
        .onChange(of: customMinutes) { _, minutes in
            if selection?.isCustom == true { selection = .custom(minutes) }
        }
        // Recrée le timer (reset implicite) à chaque nouvelle durée. Re-taper la durée
        // déjà sélectionnée ne relance rien (même valeur, pas d'événement) : c'est le
        // rôle de « Recommencer ».
        .onChange(of: selection?.minutes) { _, minutes in
            timer = minutes.map { ExerciseTimerModel(durationMinutes: $0) }
            UIApplication.shared.isIdleTimerDisabled = false
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
                    // Activité libre : pas de notion de page courante, et le timer va
                    // toujours jusqu'au bout de l'activité, donc chime « terminé ».
                    TimerChime.onTick(timer: timer, at: date, isCurrent: true, chime: .done)
                }
            }
        } else {
            SportIllustration(name: activity.id, fallbackEmoji: activity.emoji,
                              size: 140, cornerRadius: 20)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func durationButton(_ minutes: Int) -> some View {
        let isSelected = selection == .preset(minutes)
        return Button {
            selection = .preset(minutes)
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

    /// Quatrième puce : sous-titre vide tant qu'elle n'a pas servi, valeur courante
    /// ensuite (les trois autres affichent leurs kcal, elle affiche ses minutes).
    private var customButton: some View {
        let isSelected = selection?.isCustom == true
        return Button {
            selection = .custom(customMinutes)
        } label: {
            VStack(spacing: 3) {
                Text("Autre")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isSelected ? .white : Theme.text)
                    .lineLimit(1)
                if isSelected {
                    Text("\(customMinutes) min")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.vertical, 12)
            .background(isSelected ? Theme.orange : Theme.card,
                        in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    /// Roue dépliée SUR PLACE (pas de feuille au-dessus de la feuille) : la sheet est
    /// déjà en détent .large, la place existe, et l'estimation reste visible.
    private var customWheel: some View {
        VStack(spacing: 4) {
            Picker("Durée", selection: $customMinutes) {
                ForEach(Array(CustomDuration.range), id: \.self) { minutes in
                    Text("\(minutes) min").tag(minutes)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(height: 130)
            .accessibilityLabel("Durée en minutes")

            Text("~\(activity.estimatedKcal(minutes: customMinutes).frFormatted) kcal")
                .font(.caption)
                .foregroundStyle(Theme.subtext)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    /// Durée qui sera réellement enregistrée (spec v1.9 §5.2). `now` est injecté par
    /// le TimelineView de la barre basse : le libellé doit suivre le timer qui tourne.
    private func loggedMinutes(at now: Date) -> Int? {
        guard let selection else { return nil }
        guard let timer else { return selection.minutes }
        return LoggedDuration.resolve(chosenMinutes: selection.minutes,
                                      elapsedSeconds: timer.elapsed(at: now),
                                      timerUsed: !timer.isIdle)
    }

    private var bottomBar: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let logged = loggedMinutes(at: context.date)
            VStack(spacing: 6) {
                // Affichée seulement quand l'app s'apprête à noter autre chose que la
                // durée choisie (arrêt anticipé). Le bouton, lui, ne bouge jamais :
                // « C'est fait ! (+30 XP) » y tient déjà tout juste.
                if let logged, let selection, logged != selection.minutes {
                    Text("noté : \(logged) min")
                        .font(.caption)
                        .foregroundStyle(Theme.subtext)
                }
                Button(xpReward > 0 ? "C'est fait ! (+\(xpReward) XP)" : "C'est fait !",
                       action: validate)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(selection == nil || isSaving)
                    // Pulse dérivé de `timer?.isFinished` à chaque rendu (pas de latch
                    // séparé) : « Recommencer » l'éteint du même coup.
                    .gentlePulse(timer?.isFinished == true, reduceMotion: reduceMotion)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Theme.card.ignoresSafeArea(edges: .bottom))
            .shadow(color: Theme.floatingShadow, radius: 10, y: -4)
        }
    }

    private func validate() {
        guard let minutes = loggedMinutes(at: .now), !isSaving else { return }
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
    let game = GameService(modelContext: container.mainContext, stepsService: FakeStepsService(),
                           widgetDefaults: nil)
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
