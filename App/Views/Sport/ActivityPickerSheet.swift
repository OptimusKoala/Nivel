// App/Views/Sport/ActivityPickerSheet.swift
// « Tu viens de faire quoi ? » (spec v1.13 §6.3) — la page ouverte par le bouton
// « Noter une activité » de l'accueil.
//
// Le CATALOGUE LIBRE uniquement : « À la maison » et « Dehors ». Ni la séance du jour
// ni le programme posture, qui répondent à « qu'est-ce que je fais maintenant » —
// c'est le rôle de l'onglet Sport, et les redoubler ici en ferait un doublon.
//
// Un tap POUSSE la feuille de durée existante au lieu d'empiler une feuille sur une
// feuille ; sa validation referme toute la pile d'un coup, via `onLogged`.

import SwiftUI
import SwiftData
import NivelCore

struct ActivityPickerSheet: View {
    @Environment(GameService.self) private var game
    @Environment(\.dismiss) private var dismiss

    /// Activités poussées dans la pile — le chemin ne contient jamais plus d'un élément
    /// (la feuille de durée est une feuille terminale).
    @State private var path: [Activity] = []

    private var homeActivities: [Activity] {
        game.activityCatalog.filter { $0.location != .outdoor }
    }
    private var outdoorActivities: [Activity] {
        game.activityCatalog.filter { $0.location == .outdoor }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.background.ignoresSafeArea()
                List {
                    Section {
                        ForEach(homeActivities) { activity in
                            ActivityRow(activity: activity) { path.append(activity) }
                        }
                    } header: {
                        Overline("À la maison", icon: "tab_home")
                    }
                    Section {
                        ForEach(outdoorActivities) { activity in
                            ActivityRow(activity: activity) { path.append(activity) }
                        }
                    } header: {
                        Overline("Dehors", icon: "icon_tree")
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Tu viens de faire quoi ?")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Activity.self) { activity in
                // `onLogged` et non `dismiss()` : la validation doit refermer la
                // FEUILLE, pas seulement dépiler l'activité (spec §6.3).
                ActivityLogSheet(activity: activity, onLogged: { dismiss() })
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        // Même présentation que la feuille de durée qu'elle pousse : au medium, les
        // premières activités passeraient sous le pli.
        .presentationDetents([.large])
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
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
    return ActivityPickerSheet()
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(GameService(modelContext: container.mainContext,
                                 stepsService: FakeStepsService(), widgetDefaults: nil))
}
