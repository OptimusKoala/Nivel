// App/Views/Meals/MealLogSheet.swift
// Log de repas (spec §4.2) : UNE seule feuille scrollable — créneau, plat, portion,
// extras — avec estimation "≈ kcal" en direct et validation en un tap (< 15 s).
// Mode édition : init avec un MealEntry existant → champs pré-remplis, la validation
// met à jour l'entrée SANS ré-attribuer d'XP.

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

extension Portion {
    var frLabel: String {
        switch self {
        case .light: "Léger"
        case .normal: "Normal"
        case .hearty: "Copieux"
        }
    }
}

// MARK: - Sheet

struct MealLogSheet: View {
    @Environment(GameService.self) private var game
    @Environment(\.dismiss) private var dismiss

    /// Entrée existante en mode édition — nil pour un nouveau log.
    private let editedEntry: MealEntry?

    private let dishes: [Dish]
    private let desserts: [Extra]
    private let drinks: [Extra]

    @State private var slot: MealSlot
    @State private var selectedDishID: String?
    @State private var portion: Portion
    @State private var dessertID: String?
    @State private var waterSelected: Bool
    @State private var drinkQuantities: [String: Int]
    @State private var showAllDishes = false
    @State private var isSaving = false

    init(entry: MealEntry? = nil) {
        self.editedEntry = entry
        // Catalogues du bundle — vides si corrompus (jamais de crash), comme GameService.
        let dishes = (try? Catalogs.dishes()) ?? []
        let extras = (try? Catalogs.extras()) ?? []
        self.dishes = dishes
        self.desserts = extras.filter { $0.category == .dessert }
        self.drinks = extras.filter { $0.category == .drink }

        // Pré-remplissage : entrée existante (édition) ou heure courante (spec §4.2 étape 0).
        let hour = GameService.calendar.component(.hour, from: .now)
        _slot = State(initialValue: entry?.slot ?? MealSlot.suggested(forHour: hour))
        _selectedDishID = State(initialValue: entry?.dishID)
        _portion = State(initialValue: entry?.portion ?? .normal)

        var dessert: String?
        var water = false
        var quantities: [String: Int] = [:]
        for (id, quantity) in entry?.extras ?? [:] where quantity > 0 {
            guard let extra = extras.first(where: { $0.id == id }) else { continue }
            switch extra.category {
            case .dessert: dessert = id
            case .drink: id == "water" ? (water = true) : (quantities[id] = min(9, quantity))
            }
        }
        _dessertID = State(initialValue: dessert)
        _waterSelected = State(initialValue: water)
        _drinkQuantities = State(initialValue: quantities)
    }

    // MARK: Données dérivées

    private var isEditing: Bool { editedEntry != nil }
    private var selectedDish: Dish? { dishes.first { $0.id == selectedDishID } }

    /// Plats du créneau courant d'abord ; les autres derrière "Tout afficher".
    private var matchingDishes: [Dish] { dishes.filter { $0.slots.contains(slot) } }
    private var otherDishes: [Dish] { dishes.filter { !$0.slots.contains(slot) } }

    /// Le groupe "autres" reste visible si le plat sélectionné s'y trouve
    /// (changement de créneau après sélection : la sélection ne disparaît jamais).
    private var showsOtherDishes: Bool {
        showAllDishes || otherDishes.contains { $0.id == selectedDishID }
    }

    private var selectedExtras: [(Extra, Int)] {
        var result: [(Extra, Int)] = []
        if let dessert = desserts.first(where: { $0.id == dessertID }) {
            result.append((dessert, 1))
        }
        for drink in drinks {
            if drink.id == "water" {
                if waterSelected { result.append((drink, 1)) }
            } else if let quantity = drinkQuantities[drink.id], quantity > 0 {
                result.append((drink, quantity))
            }
        }
        return result
    }

    /// Estimation en direct (spec §6) — nil tant qu'aucun plat n'est choisi.
    private var estimatedKcal: Int? {
        selectedDish.map { MealEstimator.estimate(dish: $0, portion: portion, extras: selectedExtras) }
    }

    // MARK: Corps

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(isEditing ? "Modifier le repas" : "Nouveau repas")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.text)
                    slotPicker
                    dishSection
                    portionSection
                    extrasSection
                }
                .padding(20)
            }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
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

    // MARK: Plat

    private var dishSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Plat")
            dishGrid(matchingDishes)
            if showsOtherDishes {
                dishGrid(otherDishes)
            } else if !otherDishes.isEmpty {
                Button {
                    withAnimation(.snappy) { showAllDishes = true }
                } label: {
                    Text("Tout afficher")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.orange)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func dishGrid(_ dishes: [Dish]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())],
                  spacing: 12) {
            ForEach(dishes) { dish in
                dishCard(dish)
            }
        }
    }

    private func dishCard(_ dish: Dish) -> some View {
        let isSelected = selectedDishID == dish.id
        return Button {
            selectedDishID = dish.id
        } label: {
            VStack(spacing: 5) {
                Text(dish.emoji)
                    .font(.system(size: 34))
                Text(dish.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text("~\(dish.kcal.frFormatted) kcal")
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .padding(10)
            .background(isSelected ? Theme.orange.opacity(0.12) : Theme.card,
                        in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isSelected ? Theme.orange : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Portion

    private var portionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Portion")
            HStack(spacing: 8) {
                ForEach(Portion.allCases, id: \.self) { candidate in
                    Button {
                        portion = candidate
                    } label: {
                        Text(candidate.frLabel)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(portion == candidate ? Theme.orange : Theme.card,
                                        in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(portion == candidate ? .white : Theme.text)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Extras

    private var extrasSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Extras")
            HStack(spacing: 8) {
                ForEach(desserts) { dessert in
                    dessertChip(dessert)
                }
            }
            VStack(spacing: 8) {
                ForEach(drinks) { drink in
                    drinkRow(drink)
                }
            }
        }
    }

    /// Desserts léger/gourmand : exclusifs, re-tap pour désélectionner.
    private func dessertChip(_ dessert: Extra) -> some View {
        let isSelected = dessertID == dessert.id
        return Button {
            dessertID = isSelected ? nil : dessert.id
        } label: {
            HStack(spacing: 6) {
                Text(dessert.emoji)
                Text(dessert.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(isSelected ? Theme.orange.opacity(0.12) : Theme.card,
                        in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Theme.orange : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    /// Boissons : eau = simple toggle ; bière/vin/soda = toggle + stepper 1…9.
    private func drinkRow(_ drink: Extra) -> some View {
        let quantity = drink.id == "water"
            ? (waterSelected ? 1 : 0)
            : (drinkQuantities[drink.id] ?? 0)
        let isSelected = quantity > 0

        return HStack(spacing: 10) {
            Button {
                toggleDrink(drink, isSelected: isSelected)
            } label: {
                HStack(spacing: 8) {
                    Text(drink.emoji)
                    Text(drink.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isSelected && drink.id != "water" {
                stepper(for: drink, quantity: quantity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isSelected ? Theme.orange.opacity(0.12) : Theme.card,
                    in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? Theme.orange : .clear, lineWidth: 2)
        )
    }

    private func toggleDrink(_ drink: Extra, isSelected: Bool) {
        if drink.id == "water" {
            waterSelected.toggle()
        } else {
            drinkQuantities[drink.id] = isSelected ? nil : 1
        }
    }

    private func stepper(for drink: Extra, quantity: Int) -> some View {
        HStack(spacing: 12) {
            Button {
                // À 1, le "−" désélectionne la boisson.
                drinkQuantities[drink.id] = quantity > 1 ? quantity - 1 : nil
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.orange)
            }
            .buttonStyle(.plain)

            Text("\(quantity)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(Theme.text)
                .frame(minWidth: 18)

            Button {
                drinkQuantities[drink.id] = min(9, quantity + 1)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(quantity >= 9 ? Theme.subtext : Theme.orange)
            }
            .buttonStyle(.plain)
            .disabled(quantity >= 9)
        }
    }

    // MARK: Bandeau bas collant

    private var bottomBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Estimation")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.subtext)
                // "~" : estimation honnête, jamais présentée comme exacte (spec §13).
                Text(estimatedKcal.map { "~ \($0.frFormatted) kcal" } ?? "~ — kcal")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: estimatedKcal)
            }
            Spacer()
            Button(action: validate) {
                Text(isEditing ? "Enregistrer" : "Valider (+20 XP)")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(colors: [Theme.accent, Theme.orange],
                                       startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: Theme.buttonRadius)
                    )
                    .opacity(selectedDish == nil ? 0.4 : 1)
            }
            .buttonStyle(.plain)
            .disabled(selectedDish == nil || isSaving)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.card.ignoresSafeArea(edges: .bottom))
        .shadow(color: .black.opacity(0.08), radius: 10, y: -4)
    }

    private func validate() {
        guard let dish = selectedDish, !isSaving else { return }
        isSaving = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            if let entry = editedEntry {
                // Édition : recalcul kcal + ajustement DayLog, PAS de nouvel XP.
                await game.updateMeal(entry: entry, slot: slot, dish: dish,
                                      portion: portion, extras: selectedExtras)
            } else {
                // logMeal lève le signal `mealJustLogged` — l'accueil affichera
                // la bulle afterMealLog, que le log vienne d'ici ou du journal.
                await game.logMeal(slot: slot, dish: dish, portion: portion, extras: selectedExtras)
            }
            dismiss()
        }
    }

    // MARK: Aide

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.text)
    }
}

// MARK: - Previews

#Preview("Nouveau repas") {
    let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                         DayLog.self, GamificationState.self])
    let container = try! ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
    )
    return MealLogSheet()
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(GameService(modelContext: container.mainContext,
                                 stepsService: FakeStepsService()))
}

#Preview("Édition") {
    let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                         DayLog.self, GamificationState.self])
    let container = try! ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
    )
    let entry = MealEntry(slot: .dinner, dishID: "pasta", portion: .hearty,
                          extras: ["beer": 2, "dessert_rich": 1],
                          estimatedKcal: 1445, xpAwarded: 20)
    container.mainContext.insert(entry)
    return MealLogSheet(entry: entry)
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(GameService(modelContext: container.mainContext,
                                 stepsService: FakeStepsService()))
}
