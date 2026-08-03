// App/Views/Meals/MealLogSheet.swift
// Log de repas (spec v1.10 §5) : panier « Ton repas » surmontant un catalogue à
// onglets, avec estimation en direct et validation en un tap. Mode édition : init
// avec un MealEntry existant → lignes pré-remplies, la validation met à jour
// l'entrée SANS ré-attribuer d'XP.
//
// Kcal manuelles et règle du tilde (spec §5.5) : un tap sur le montant de la barre
// basse ouvre une saisie numérique, qui court-circuite l'estimation calculée. La
// même règle d'affichage (MealFormatting.frKcal) est reprise par le journal, pour
// qu'elle ne puisse pas diverger entre les deux écrans.

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
    /// nil = kcal calculées ; rempli = l'utilisateur a saisi un chiffre qui
    /// court-circuite le calcul (spec §3.3, §5.5). Jamais persisté tant que la
    /// feuille n'est pas validée.
    @State private var manualKcal: Int?
    @State private var isEditingManualKcal = false
    @State private var manualKcalText = ""
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
        _manualKcal = State(initialValue: entry?.manualKcal)

        #if DEBUG
        // Capture « catalogue d'aliments » (scripts/screenshots.sh) : créneau déjeuner
        // (le catalogue le plus riche) et panier déjà garni. Absent en release.
        if entry == nil, ScreenshotMode.autoOpensMealLog {
            _slot = State(initialValue: .lunch)
            _lines = State(initialValue: ScreenshotMode.demoMealLines(catalog: catalog))
        }
        #endif
    }

    // MARK: Données dérivées

    private var isEditing: Bool { editedEntry != nil }

    /// Estimation en direct (spec §5.5) — calculée depuis les lignes du panier.
    private var estimatedKcal: Int {
        MealEstimator.kcal(lines: lines, kcalPer100g: catalog.kcalPer100g)
    }

    /// Ce que la barre basse affiche : la saisie manuelle si elle existe, sinon
    /// l'estimation calculée. C'est aussi ce qui est enregistré (spec §3.3).
    private var displayedKcal: Int { manualKcal ?? estimatedKcal }

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
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(manualKcal != nil ? "Saisi" : "Estimation")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.subtext)
                    // Le bouton n'apparaît que si une saisie manuelle est active :
                    // le cas courant (aucune saisie) ne doit pas s'encombrer d'un
                    // contrôle qui ne servirait à rien (spec §5.5).
                    if manualKcal != nil {
                        Button("Revenir à l'estimation") { manualKcal = nil }
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.orange)
                    }
                }
                Button {
                    manualKcalText = "\(displayedKcal)"
                    isEditingManualKcal = true
                } label: {
                    HStack(spacing: 6) {
                        // Règle du tilde (spec §5.5) : partagée avec le journal via
                        // MealFormatting, pour qu'elle ne puisse jamais diverger.
                        Text(MealFormatting.frKcal(displayedKcal, isManual: manualKcal != nil))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.text)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: displayedKcal)
                        // Affordance visible : sans elle, rien ne dit que ce montant
                        // se tape (spec §5.5, retour de Michaël sur la maquette).
                        Image(systemName: "pencil")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.subtext)
                    }
                }
                .buttonStyle(.plain)
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
        .alert("Kcal du repas", isPresented: $isEditingManualKcal) {
            TextField("kcal", text: $manualKcalText)
                .keyboardType(.numberPad)
            Button("Valider", action: commitManualKcal)
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Remplace l'estimation par un chiffre que tu as toi-même mesuré ou lu.")
        }
    }

    /// Valide la saisie manuelle : un entier positif remplace l'estimation, tout le
    /// reste (vide, texte, zéro ou négatif) est ignoré et referme simplement l'alerte.
    private func commitManualKcal() {
        guard let value = Int(manualKcalText), value > 0 else { return }
        manualKcal = value
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
                await game.updateMeal(entry: entry, slot: slot, lines: lines, manualKcal: manualKcal)
            } else {
                // logMeal publie `lastMealXPAwarded` — l'accueil affichera la bulle
                // afterMealLog (+XP), que le log vienne d'ici ou du journal.
                await game.logMeal(slot: slot, lines: lines, manualKcal: manualKcal)
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
