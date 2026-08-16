// App/Views/Sport/MuscuSection.swift
// Section "Muscu" de l'onglet Sport (spec v1.14 §4.4) : visible SEULEMENT quand
// MuscuPlanSettings.shared.isEnabled, sinon l'onglet est identique à la v1.13.
// Auto-cloisonnée : la garde vit ICI, pas au call site, comme PostureSection.
//
// Décalque ALLÉGÉ de PostureSection : la carte de la séance du jour et le compteur
// mensuel, mais PAS de liste d'exercices. Le programme muscu n'a pas de catalogue
// d'exercices propre — ses étapes pointent vers le catalogue commun, dont les
// activités intenses sont déjà listées par la section « Ça pousse » du même écran.
// En dupliquer une partie ici donnerait deux fois les mêmes lignes.

import SwiftUI
import SwiftData
import NivelCore

struct MuscuSection: View {
    /// Interrupteur INJECTABLE (défaut : le vrai). Sans ce paramètre la garde lirait un
    /// global, et une preview ne pourrait montrer la section allumée qu'en recopiant sa
    /// mise en page à côté — une quatrième copie qui n'exercerait ni le bouton, ni la garde.
    var settings: MuscuPlanSettings = .shared
    let sessionStatus: (session: ActivitySession, done: Bool)?
    let monthCount: Int
    let onOpenSession: () -> Void

    var body: some View {
        // Les deux conditions ensemble, contrairement à PostureSection qui garde une
        // liste d'exercices sous sa carte : ici la carte EST la section, un `sessionStatus`
        // nil (catalogue corrompu) ne doit pas laisser un en-tête « Muscu » seul à l'écran.
        if settings.isEnabled, let status = sessionStatus {
            Section {
                Button(action: onOpenSession) {
                    MuscuSessionCardContent(session: status.session, done: status.done,
                                            monthCount: monthCount)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Theme.card)
            } header: {
                Overline("Muscu")
            }
        }
    }
}

/// Carte de la séance muscu du jour : la coque commune (`PlanSessionCard.swift`),
/// avec le compteur mensuel en jours DISTINCTS en sous-titre (`muscuSessionsThisMonth`).
struct MuscuSessionCardContent: View {
    let session: ActivitySession
    let done: Bool
    let monthCount: Int

    var body: some View {
        PlanSessionCardContent(overline: "SÉANCE MUSCU", session: session,
                               subtitle: monthlyCounterLabel, done: done)
    }

    /// Un fait, pas un jugement (spec §7.3) : jamais "aucune séance encore", juste
    /// le nombre, avec l'accord singulier/pluriel de "séance".
    private var monthlyCounterLabel: String {
        monthCount == 1 ? "1 séance ce mois-ci" : "\(monthCount) séances ce mois-ci"
    }
}

// MARK: - Previews

@MainActor
private func muscuPreviewFixture() -> (container: ModelContainer, game: GameService) {
    let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                         DayLog.self, GamificationState.self, ActivityEntry.self])
    let container = try! ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
    )
    let context = container.mainContext
    context.insert(UserProfile(
        name: "Michaël", sex: .male,
        birthDate: Date(timeIntervalSince1970: 0),
        heightCm: 180, initialWeightKg: 90, activity: .moderate,
        dailyCalorieTarget: 2000
    ))
    try? context.save()
    let game = GameService(modelContext: container.mainContext, stepsService: FakeStepsService(),
                           widgetDefaults: nil)
    return (container, game)
}

/// Interrupteur allumé sur une suite ÉPHÉMÈRE, JAMAIS `.shared` : celui-ci écrit dans
/// `UserDefaults.standard`, donc un simple rendu de preview allumerait pour de bon le
/// programme dans l'app installée du simulateur.
@MainActor
private func muscuPreviewSettings() -> MuscuPlanSettings {
    // Force-unwrap assumé (comme les autres fixtures de preview) : un repli sur
    // `.standard` reviendrait précisément à écrire là où il ne faut pas.
    let settings = MuscuPlanSettings(defaults: UserDefaults(suiteName: "preview.muscu")!)
    settings.isEnabled = true
    return settings
}

#Preview("Muscu") {
    let (container, game) = muscuPreviewFixture()
    List {
        MuscuSection(
            settings: muscuPreviewSettings(),
            sessionStatus: game.muscuSessionStatus(),
            monthCount: game.muscuSessionsThisMonth(),
            onOpenSession: {}
        )
    }
    .listStyle(.insetGrouped)
    .fontDesign(.rounded)
    .modelContainer(container)
    .environment(game)
}
