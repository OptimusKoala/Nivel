// App/Views/Sport/ActivityPickerSheet.swift
// « Tu viens de faire quoi ? » (spec v1.13 §6.3) — la page ouverte par le bouton
// « Noter une activité » de l'accueil.
//
// Le CATALOGUE LIBRE uniquement : « À la maison », « Dehors » et « Ça pousse ». Ni la
// séance du jour ni le programme posture, qui répondent à « qu'est-ce que je fais
// maintenant » — c'est le rôle de l'onglet Sport, et les redoubler ici en ferait un
// doublon.
//
// Les sections viennent de `SportSection` (spec v1.14 §4.3) — ordre, libellés, icônes
// et appartenance —, partagé avec `SportView` : les deux listes des mêmes activités ne
// doivent pas pouvoir diverger, et il n'est même plus possible d'en oublier une.
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

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.background.ignoresSafeArea()
                List {
                    ForEach(SportSection.displayOrder, id: \.self) { section in
                        activitySection(section.frLabel, icon: section.icon,
                                        activities: section.activities(in: game.activityCatalog))
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

    private func activitySection(_ title: String, icon: String, activities: [Activity]) -> some View {
        Section {
            // Ligne partagée avec SportView (v1.13) : les deux listes des mêmes
            // activités ne doivent pas pouvoir diverger.
            ForEach(activities) { activity in
                ActivityRow(activity: activity) { path.append(activity) }
            }
        } header: {
            Overline(title, icon: icon)
        }
    }
}

// MARK: - Preview

#Preview {
    let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                         DayLog.self, GamificationState.self, ActivityEntry.self])
    let container = try! ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
    )
    return ActivityPickerSheet()
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(GameService(modelContext: container.mainContext,
                                 stepsService: FakeStepsService(), widgetDefaults: nil))
}
