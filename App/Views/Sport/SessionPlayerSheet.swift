// App/Views/Sport/SessionPlayerSheet.swift
// Player pas-à-pas de la séance du jour (spec illustrations §5.1) : page 0 aperçu,
// une page par étape (grande illustration, consignes, tempo), navigation LIBRE
// (guide, pas chrono). Validation sur la dernière page uniquement.
// Remplace SessionDetailSheet.

import SwiftUI
import SwiftData
import UIKit
import NivelCore

extension View {
    /// Pulse doux du CTA quand le timer de la page est fini (spec timer §5) : scale +3%
    /// aller-retour en continu, jamais figé sur 1.03 (le retour à 1 se fait toujours en
    /// douceur, `active` ou non). Reduce Motion coupe l'oscillation, garde un fondu bref.
    func gentlePulse(_ active: Bool, reduceMotion: Bool) -> some View {
        self
            .scaleEffect(active && !reduceMotion ? 1.03 : 1)
            .animation(active && !reduceMotion
                       ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
                       : .easeOut(duration: 0.2),
                       value: active)
    }
}

/// Quelle séance ce player valide (spec v1.11 §9) : discriminant EXPLICITE, sans
/// valeur par défaut, pour que chaque appelant déclare son intention au lieu d'en
/// hériter silencieusement. Un `Bool` par défaut (`isPosture = false`) aurait
/// compilé sans broncher à un futur appel qui l'oublie, et aurait alors loggé une
/// séance posture comme séance du jour (mauvais plafond XP, mauvaise métrique de
/// quête) sans qu'aucune erreur ne le signale.
enum SessionPlayerKind {
    case dailySession
    case posture
    case muscu

    /// Titre de l'aperçu (page 0) : seule différence de texte entre les trois.
    var overlineText: String {
        switch self {
        case .dailySession: "Séance du jour"
        case .posture: "Séance du soir"
        case .muscu: "Séance muscu"
        }
    }

    /// Action d'XP à créditer à la validation (spec §8, v1.14 §5.7 : plafonds indépendants).
    var xpAction: XPAction {
        switch self {
        case .dailySession: .dailySessionDone
        case .posture: .postureSessionDone
        case .muscu: .muscuSessionDone
        }
    }
}

struct SessionPlayerSheet: View {
    @Environment(GameService.self) private var game
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let session: ActivitySession
    let done: Bool
    let kind: SessionPlayerKind
    @State private var page: Int
    @State private var isSaving = false
    /// Fait pulser le CTA bas quand un timer d'étape se termine sur la page courante
    /// (spec timer §5) ; jamais appliqué à `.alreadyDone`. Remis à false au changement de page.
    @State private var pulsingCTA = false

    /// `initialPage` permet aux previews de s'ouvrir directement sur une étape
    /// (états à risque : puces longues, tempo, AX3) sans naviguer manuellement.
    init(session: ActivitySession, done: Bool, kind: SessionPlayerKind, initialPage: Int = 0) {
        self.session = session
        self.done = done
        self.kind = kind
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
                        StepPageView(step: step, number: index + 1, stepCount: session.steps.count,
                                     activity: game.activitiesByID[step.activityID],
                                     isCurrent: page == index + 1,
                                     onTimerFinishedChanged: { pulsingCTA = $0 })
                            .tag(index + 1)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .presentationDetents([.large])
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
        .onChange(of: page) { pulsingCTA = false }
        // Filet racine (spec §10) : le dismiss de la sheet relâche l'écran quoi qu'il
        // arrive aux pages enfants — symétrique d'ActivityLogSheet.
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
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
                SportHeroIllustration(name: session.id)
                VStack(alignment: .leading, spacing: 3) {
                    Overline(kind.overlineText)
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
            SportIllustration(name: step.activityID, size: 40, cornerRadius: 10)
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
                    .gentlePulse(pulsingCTA, reduceMotion: reduceMotion)
            case .validate:
                // Montant depuis XPEngine : le libellé ne peut pas mentir si la règle change.
                Button("C'est fait ! (+\(XPEngine.award(kind.xpAction, todayCount: 0)) XP)", action: validate)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isSaving)
                    .gentlePulse(pulsingCTA, reduceMotion: reduceMotion)
            case .alreadyDone:
                Label { Text("Déjà faite") } icon: { CozyIcon(name: "icon_check", size: 20) }
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
            switch kind {
            case .dailySession: await game.logDailySession(session: session)
            case .posture: await game.logPostureSession(session: session)
            case .muscu: await game.logMuscuSession(session: session)
            }
            dismiss()
        }
    }
}

// MARK: - Page d'étape (timer opt-in)

/// Page d'une étape de séance : illustration/anneau, consignes, tempo, timer.
/// `isCurrent` distingue la page réellement affichée des pages voisines gardées
/// VIVANTES par `TabView(.page)` (le swipe ne déclenche pas `onDisappear`) : quitter
/// la page abandonne le timer et relâche l'écran (spec timer §3.1, piège #3).
private struct StepPageView: View {
    let step: SessionStep
    let number: Int
    let stepCount: Int
    let activity: Activity?
    let isCurrent: Bool
    /// État dérivé (pas un événement) : reflète `timer.isFinished`, tant que la page est
    /// courante. Ainsi « Recommencer » (qui fait retomber `isFinished` à false) éteint le
    /// pulse du CTA au même titre qu'un changement de page — un seul mécanisme, pas un latch.
    let onTimerFinishedChanged: (Bool) -> Void

    @State private var timer: ExerciseTimerModel

    init(step: SessionStep, number: Int, stepCount: Int, activity: Activity?,
         isCurrent: Bool, onTimerFinishedChanged: @escaping (Bool) -> Void) {
        self.step = step
        self.number = number
        self.stepCount = stepCount
        self.activity = activity
        self.isCurrent = isCurrent
        self.onTimerFinishedChanged = onTimerFinishedChanged
        _timer = State(initialValue: ExerciseTimerModel(durationMinutes: step.minutes))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TimerRingView(illustrationName: step.activityID,
                                  fraction: timer.fraction(at: context.date),
                                  finished: timer.isFinished,
                                  segments: step.segments)
                        .frame(maxWidth: .infinity)
                    TimerTimeLabel(timer: timer, now: context.date)
                        .frame(maxWidth: .infinity)
                    HStack(alignment: .firstTextBaseline) {
                        Text(activity?.name ?? step.activityID)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.text)
                        Spacer()
                        Text("Étape \(number)/\(stepCount) · \(step.minutes) min")
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
                    TimerButtons(timer: timer)
                        .frame(maxWidth: .infinity)
                }
                .padding(20)
            }
            .onChange(of: context.date) { _, date in
                TimerChime.onTick(timer: timer, at: date, isCurrent: isCurrent,
                                  chime: .forStep(number: number, stepCount: stepCount))
            }
        }
        .onChange(of: timer.isFinished) { _, finished in
            if isCurrent { onTimerFinishedChanged(finished) }
        }
        .onChange(of: timer.isRunning) { _, running in
            UIApplication.shared.isIdleTimerDisabled = running
        }
        .onChange(of: isCurrent) { _, current in
            if !current {
                timer.reset()
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
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
    SessionPlayerSheet(session: session, done: false, kind: .dailySession)
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(game)
}

#Preview("Déjà faite") {
    let (container, game, session) = sessionPlayerPreviewFixture()
    SessionPlayerSheet(session: session, done: true, kind: .dailySession)
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(game)
}

#Preview("Étape") {
    let (container, game, session) = sessionPlayerPreviewFixture()
    SessionPlayerSheet(session: session, done: false, kind: .dailySession, initialPage: 1)
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(game)
}

// kind: .posture — le player reste le même composant (spec v1.11 §9) : seul
// l'aperçu ("Séance du soir") et le CTA de validation (logPostureSession) changent.
#Preview("Posture, à faire") {
    let (container, game, _) = sessionPlayerPreviewFixture()
    SessionPlayerSheet(session: game.postureCatalog.sessions.first!, done: false, kind: .posture)
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(game)
}

#Preview("Étape (AX3)") {
    let (container, game, session) = sessionPlayerPreviewFixture()
    SessionPlayerSheet(session: session, done: false, kind: .dailySession, initialPage: 1)
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(game)
        .environment(\.dynamicTypeSize, .accessibility3)
}

// Séance déjà validée : le timer d'étape reste utilisable (spec §3.1), et le CTA bas est
// `.alreadyDone` (jamais de pulse possible, cf. gentlePulse appliqué uniquement à .next/.validate).
#Preview("Séance faite, étape") {
    let (container, game, session) = sessionPlayerPreviewFixture()
    SessionPlayerSheet(session: session, done: true, kind: .dailySession, initialPage: 1)
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(game)
}
