// App/Views/Meals/MealLogSheet.swift
// Log de repas (spec v1.10 §5) : panier « Ton repas » surmontant un catalogue à
// onglets, avec estimation en direct et validation en un tap. Mode édition : init
// avec un MealEntry existant → lignes pré-remplies, la validation met à jour
// l'entrée SANS ré-attribuer d'XP.
//
// La saisie manuelle des kcal et la règle du tilde (spec §5.5) arrivent à la
// Task 7 : cette feuille n'affiche pour l'instant que l'estimation calculée.

import SwiftUI
import SwiftData
import UIKit
import NivelCore

// MARK: - Libellés français

extension MealSlot {
    /// Libellé court (chips de la sheet).
    var frShort: String {
        switch self {
        case .breakfast: "Petit-déj"
        case .lunch: "Déjeuner"
        case .dinner: "Dîner"
        case .snack: "Encas"
        }
    }

    /// Libellé long (sections du journal).
    var frLong: String {
        switch self {
        case .breakfast: "Petit-déjeuner"
        default: frShort
        }
    }
}

// MARK: - Sheet

struct MealLogSheet: View {
    @Environment(GameService.self) private var game
    @Environment(\.dismiss) private var dismiss

    /// Entrée existante en mode édition — nil pour un nouveau log.
    private let editedEntry: MealEntry?
    private let catalog: FoodCatalog

    @State private var slot: MealSlot
    @State private var lines: [MealLine]
    @State private var isSaving = false
    /// Chemin de navigation : l'index de la ligne dont le détail est poussé.
    @State private var path: [Int] = []

    init(entry: MealEntry? = nil) {
        self.editedEntry = entry
        // Catalogue du bundle — vide s'il est corrompu (jamais de crash), comme GameService.
        self.catalog = (try? FoodCatalog.load()) ?? .empty

        // Pré-remplissage : entrée existante (édition) ou heure courante (spec §5, étape 0).
        let hour = GameService.calendar.component(.hour, from: .now)
        _slot = State(initialValue: entry?.slot ?? MealSlot.suggested(forHour: hour))
        _lines = State(initialValue: entry?.lines ?? [])
    }

    // MARK: Données dérivées

    private var isEditing: Bool { editedEntry != nil }

    /// Estimation en direct (spec §5.5) — calculée depuis les lignes du panier.
    private var estimatedKcal: Int {
        MealEstimator.kcal(lines: lines, kcalPer100g: catalog.kcalPer100g)
    }

    // MARK: Corps

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Text(isEditing ? "Modifier le repas" : "Nouveau repas")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.text)
                        slotPicker
                        MealBasketView(lines: $lines, catalog: catalog) { index in
                            path.append(index)
                        }
                        FoodCatalogView(catalog: catalog, slot: slot) { item in
                            withAnimation(.snappy) { lines.append(catalog.line(for: item)) }
                        }
                    }
                    .padding(20)
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationDestination(for: Int.self) { index in
                MealLineDetailView(line: $lines[index], catalog: catalog)
            }
        }
        // Grand détent d'office (même raison que ActivityLogSheet) : au medium, le
        // catalogue à onglets passerait sous le pli.
        .presentationDetents([.large])
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
    }

    // MARK: Créneau

    private var slotPicker: some View {
        HStack(spacing: 8) {
            ForEach(MealSlot.allCases, id: \.self) { candidate in
                Button {
                    slot = candidate
                } label: {
                    Text(candidate.frShort)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background(slot == candidate ? Theme.orange : Theme.card, in: Capsule())
                        .foregroundStyle(slot == candidate ? .white : Theme.text)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Bandeau bas collant

    private var bottomBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Estimation")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.subtext)
                // "~" : estimation honnête, jamais présentée comme exacte (spec §13).
                Text("~ \(estimatedKcal.frFormatted) kcal")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: estimatedKcal)
            }
            Spacer()
            Button(isEditing ? "Enregistrer" : "Valider (+20 XP)", action: validate)
                .buttonStyle(PrimaryButtonStyle(size: .compact))
                .disabled(lines.isEmpty || isSaving)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.card.ignoresSafeArea(edges: .bottom))
        .shadow(color: Theme.floatingShadow, radius: 10, y: -4)
    }

    private func validate() {
        // Le plat est facultatif mais un repas est au moins une ligne (spec §2) :
        // une bière seule est un repas, un panier vide ne se valide pas.
        guard !lines.isEmpty, !isSaving else { return }
        isSaving = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            if let entry = editedEntry {
                // Édition : recalcul kcal + ajustement DayLog, PAS de nouvel XP.
                await game.updateMeal(entry: entry, slot: slot, lines: lines)
            } else {
                // logMeal publie `lastMealXPAwarded` — l'accueil affichera la bulle
                // afterMealLog (+XP), que le log vienne d'ici ou du journal.
                await game.logMeal(slot: slot, lines: lines)
            }
            dismiss()
        }
    }
}

// MARK: - Previews

#Preview("Nouveau repas") {
    let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                         DayLog.self, GamificationState.self, ActivityEntry.self])
    let container = try! ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
    )
    return MealLogSheet()
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(GameService(modelContext: container.mainContext,
                                 stepsService: FakeStepsService(), widgetDefaults: nil))
}

#Preview("Édition") {
    let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                         DayLog.self, GamificationState.self, ActivityEntry.self])
    let container = try! ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
    )
    let catalog = try! FoodCatalog.load()
    let lines: [MealLine] = [
        catalog.line(for: catalog.byID["pasta"]!),
        .simple(MealComponent(itemID: "beer_half", grams: 500)),
        .simple(MealComponent(itemID: "choco_bar", grams: 45)),
    ]
    let entry = MealEntry(slot: .dinner, lines: lines,
                          estimatedKcal: MealEstimator.kcal(lines: lines, kcalPer100g: catalog.kcalPer100g),
                          xpAwarded: 20)
    container.mainContext.insert(entry)
    return MealLogSheet(entry: entry)
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(GameService(modelContext: container.mainContext,
                                 stepsService: FakeStepsService(), widgetDefaults: nil))
}
