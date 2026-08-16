// App/Views/Sport/PostureSection.swift
// Section "Posture" en tête de l'onglet Sport (spec v1.11 §9) : visible SEULEMENT
// quand PosturePlanSettings.shared.isEnabled, sinon l'onglet est identique à la
// v1.10. Réutilise les formes existantes : la carte reprend celle de
// `DailySessionCardContent` (compteur mensuel en sous-titre plutôt que min/kcal),
// les lignes d'exercice reprennent le style de `SportView.activitySection`.
// Auto-cloisonnée : la garde vit ICI, pas au call site, pour qu'il n'y ait qu'un
// seul endroit à oublier si jamais on l'oublie.

import SwiftUI
import SwiftData
import NivelCore

struct PostureSection: View {
    let sessionStatus: (session: ActivitySession, done: Bool)?
    let monthCount: Int
    let activities: [Activity]
    let onOpenSession: () -> Void
    let onSelectActivity: (Activity) -> Void

    var body: some View {
        if PosturePlanSettings.shared.isEnabled {
            Section {
                if let status = sessionStatus {
                    Button(action: onOpenSession) {
                        PostureEveningCardContent(session: status.session, done: status.done,
                                                  monthCount: monthCount)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.card)
                }

                ForEach(activities) { activity in
                    Button { onSelectActivity(activity) } label: {
                        HStack(spacing: 12) {
                            SportIllustration(name: activity.id)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(activity.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.text)
                                // Fourchette kcal indicative, même formule que activitySection.
                                Text(activity.durations.map(String.init).joined(separator: " / ")
                                     + " min · ~\(activity.estimatedKcal(minutes: activity.durations.first ?? 0).frFormatted)"
                                     + " à \(activity.estimatedKcal(minutes: activity.durations.last ?? 0).frFormatted) kcal")
                                    .font(.caption)
                                    .foregroundStyle(Theme.subtext)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.subtext)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.card)
                }
            } header: {
                Overline("Posture")
            }
        }
    }
}

/// Carte de la séance du soir (spec v1.11 §9) : la coque commune
/// (`PlanSessionCard.swift`), avec pour sous-titre le compteur mensuel en jours
/// DISTINCTS plutôt que la durée/kcal — cohérent avec la quête
/// `postureSessionsDone`, qui compte pareil (spec §7.3 : les deux doivent parler
/// le même chiffre pour la même semaine).
struct PostureEveningCardContent: View {
    let session: ActivitySession
    let done: Bool
    let monthCount: Int

    var body: some View {
        PlanSessionCardContent(overline: "SÉANCE DU SOIR", session: session,
                               subtitle: monthlyCounterLabel, done: done)
    }

    /// Un fait, pas un jugement (spec §7.3) : jamais "aucune séance encore", juste
    /// le nombre, avec l'accord singulier/pluriel de "soir".
    private var monthlyCounterLabel: String {
        monthCount == 1 ? "1 soir ce mois-ci" : "\(monthCount) soirs ce mois-ci"
    }
}

// MARK: - Previews

@MainActor
private func posturePreviewFixture() -> (container: ModelContainer, game: GameService) {
    let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                         DayLog.self, GamificationState.self, ActivityEntry.self])
    let container = try! ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
    )
    let context = container.mainContext
    context.insert(UserProfile(
        name: "Marion", sex: .female,
        birthDate: Date(timeIntervalSince1970: 0),
        heightCm: 165, initialWeightKg: 62, activity: .light,
        dailyCalorieTarget: 1700
    ))
    try? context.save()
    let game = GameService(modelContext: container.mainContext, stepsService: FakeStepsService(),
                           widgetDefaults: nil)
    return (container, game)
}

#Preview("Posture") {
    let (container, game) = posturePreviewFixture()
    let status = game.postureSessionStatus()
    List {
        PostureSection(
            sessionStatus: status,
            monthCount: game.postureSessionsThisMonth(),
            activities: game.postureCatalog.activities,
            onOpenSession: {},
            onSelectActivity: { _ in }
        )
    }
    .listStyle(.insetGrouped)
    .fontDesign(.rounded)
    .modelContainer(container)
    .environment(game)
}
