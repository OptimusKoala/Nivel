// App/Views/Meals/MealsJournalView.swift
// Onglet Repas (spec §4.2) : journal du jour groupé par créneau, total vs objectif
// (neutre si dépassé — jamais de rouge), navigation ← → vers les jours précédents
// en lecture seule. Aujourd'hui uniquement : tap = éditer, swipe = supprimer.

import SwiftUI
import SwiftData
import NivelCore

struct MealsJournalView: View {
    @Environment(GameService.self) private var game
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    @State private var selectedDay = GameService.calendar.startOfDay(for: .now)
    /// Repas du jour sélectionné — fetch BORNÉ au jour (pas de @Query sur tout
    /// l'historique), rechargé au changement de jour et après chaque mutation.
    @State private var dayMeals: [MealEntry] = []
    @State private var editingEntry: MealEntry?
    @State private var showNewMeal = false

    private let dishesByID: [String: Dish]
    private let extrasByID: [String: Extra]

    private static let slotOrder: [MealSlot] = [.breakfast, .lunch, .dinner, .snack]

    init() {
        let dishes = (try? Catalogs.dishes()) ?? []
        let extras = (try? Catalogs.extras()) ?? []
        dishesByID = Dictionary(uniqueKeysWithValues: dishes.map { ($0.id, $0) })
        extrasByID = Dictionary(uniqueKeysWithValues: extras.map { ($0.id, $0) })
    }

    // MARK: Données dérivées

    private var calendar: Calendar { GameService.calendar }
    private var today: Date { calendar.startOfDay(for: .now) }
    private var isToday: Bool { selectedDay == today }

    private var mealsBySlot: [MealSlot: [MealEntry]] {
        Dictionary(grouping: dayMeals, by: \.slot)
    }

    private var totalKcal: Int { dayMeals.reduce(0) { $0 + $1.estimatedKcal } }
    private var targetKcal: Int { profiles.first?.dailyCalorieTarget ?? 0 }

    /// "Aujourd'hui" / "Hier" / "Mardi 28 juillet".
    private var dayTitle: String {
        if isToday { return "Aujourd'hui" }
        if calendar.date(byAdding: .day, value: 1, to: selectedDay) == today { return "Hier" }
        let raw = selectedDay.formatted(
            .dateTime.weekday(.wide).day().month(.wide)
                .locale(Locale(identifier: "fr_FR"))
        )
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }

    // MARK: Corps

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 12) {
                dayHeader
                totalCard
                if dayMeals.isEmpty {
                    emptyState
                } else {
                    mealsList
                }
            }
            .padding(.top, 8)
        }
        // Recharge au premier affichage ET à chaque changement de jour.
        .task(id: selectedDay) { reloadDayMeals() }
        // Les sheets mutent le store (log/édition) → recharge à la fermeture.
        .sheet(item: $editingEntry, onDismiss: reloadDayMeals) { entry in
            MealLogSheet(entry: entry)
        }
        .sheet(isPresented: $showNewMeal, onDismiss: reloadDayMeals) {
            MealLogSheet()
        }
    }

    /// Fetch borné au jour sélectionné, trié par heure.
    private func reloadDayMeals() {
        let start = selectedDay
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }
        let descriptor = FetchDescriptor<MealEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date)]
        )
        dayMeals = (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: Navigation par jour

    private var dayHeader: some View {
        HStack {
            chevronButton(systemName: "chevron.left", disabled: false) { moveDay(-1) }
            Spacer()
            Text(dayTitle)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.text)
            Spacer()
            // Jamais dans le futur : chevron droit inactif sur aujourd'hui.
            chevronButton(systemName: "chevron.right", disabled: isToday) { moveDay(1) }
        }
        .padding(.horizontal, 20)
    }

    private func chevronButton(systemName: String, disabled: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
        }
        .buttonStyle(CircleIconButtonStyle())
        .disabled(disabled)
    }

    private func moveDay(_ delta: Int) {
        guard let day = calendar.date(byAdding: .day, value: delta, to: selectedDay) else { return }
        selectedDay = min(day, today)
    }

    // MARK: Total du jour

    private var totalCard: some View {
        HStack {
            Text("Total du jour")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.subtext)
            Spacer()
            // Dépassement en ACCENT, jamais en rouge (spec §7.4).
            Text("~ \(totalKcal.frFormatted) / \(targetKcal.frFormatted) kcal")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(targetKcal > 0 && totalKcal > targetKcal ? Theme.accent : Theme.text)
        }
        .card()
        .padding(.horizontal, 20)
    }

    // MARK: Liste par créneau

    private var mealsList: some View {
        List {
            ForEach(Self.slotOrder, id: \.self) { slot in
                if let entries = mealsBySlot[slot] {
                    Section {
                        ForEach(entries) { entry in
                            mealRow(entry)
                        }
                    } header: {
                        Overline(slot.frLong)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func mealRow(_ entry: MealEntry) -> some View {
        let dish = dishesByID[entry.dishID]
        return HStack(spacing: 12) {
            Text(dish?.emoji ?? "🍽️")
                .font(.system(size: 28))
            VStack(alignment: .leading, spacing: 2) {
                Text(dish?.name ?? "Plat")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text(subtitle(for: entry))
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
                    .lineLimit(1)
            }
            Spacer()
            Text("~\(entry.estimatedKcal.frFormatted) kcal")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.orange)
        }
        .padding(.vertical, 2)
        .listRowBackground(Theme.card)
        .contentShape(Rectangle())
        // Modifiable le jour même uniquement (spec §4.2) — les jours passés sont
        // en lecture seule : pas de tap, pas de swipe.
        .onTapGesture {
            if isToday { editingEntry = entry }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if isToday {
                Button {
                    Task {
                        await game.deleteMeal(entry: entry)
                        reloadDayMeals()
                    }
                } label: {
                    Label("Supprimer", systemImage: "trash")
                }
                // Accent, pas rouge (spec §7.4) — supprimer n'est pas un échec.
                .tint(Theme.accent)
            }
        }
    }

    /// "Copieux · 🍰 · 🍺×2" — portion puis extras compacts.
    private func subtitle(for entry: MealEntry) -> String {
        var parts = [entry.portion.frLabel]
        for (id, quantity) in entry.extras.sorted(by: { $0.key < $1.key }) where quantity > 0 {
            guard let extra = extrasByID[id] else { continue }
            parts.append(quantity > 1 ? "\(extra.emoji)×\(quantity)" : extra.emoji)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: État vide

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            NivelitoView(expression: .happy, size: 84)
            if isToday {
                Text("Rien de loggé aujourd'hui pour l'instant.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtext)
                Button("+ Logger un repas") {
                    showNewMeal = true
                }
                .buttonStyle(PrimaryButtonStyle(size: .compact))
            } else {
                Text("Rien de loggé ce jour-là, et c'est OK 😌")
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtext)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Previews

@MainActor
private func journalPreviewFixture() -> (container: ModelContainer, game: GameService) {
    let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                         DayLog.self, GamificationState.self, ActivityEntry.self])
    let container = try! ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
    )
    let context = container.mainContext

    context.insert(UserProfile(
        name: "Marion", sex: .female,
        birthDate: Date(timeIntervalSince1970: 0),
        heightCm: 165, initialWeightKg: 70, activity: .light,
        dailyCalorieTarget: 1800
    ))
    context.insert(MealEntry(slot: .breakfast, dishID: "toast", portion: .normal,
                             estimatedKcal: 350, xpAwarded: 20))
    context.insert(MealEntry(slot: .lunch, dishID: "salad", portion: .normal,
                             extras: ["water": 1], estimatedKcal: 350, xpAwarded: 20))
    context.insert(MealEntry(slot: .dinner, dishID: "pasta", portion: .hearty,
                             extras: ["beer": 2, "dessert_rich": 1],
                             estimatedKcal: 1445, xpAwarded: 20))
    try? context.save()

    return (container, GameService(modelContext: context, stepsService: FakeStepsService()))
}

#Preview("Journal") {
    let (container, game) = journalPreviewFixture()
    return MealsJournalView()
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(game)
}

#Preview("Journal vide") {
    let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                         DayLog.self, GamificationState.self, ActivityEntry.self])
    let container = try! ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
    )
    return MealsJournalView()
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(GameService(modelContext: container.mainContext,
                                 stepsService: FakeStepsService()))
}
