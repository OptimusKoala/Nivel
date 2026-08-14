// App/Views/Meals/MealsJournalView.swift
// Onglet Repas (spec §4.2) : journal du jour groupé par créneau, total vs objectif
// (neutre si dépassé — jamais de rouge), navigation ← → vers les jours précédents
// en lecture seule. Aujourd'hui uniquement : tap = éditer, swipe = supprimer, et
// bandeau bas « Noter un repas » (spec v1.13 §6.4).

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
    /// Feuille du frigo (spec §6.3) — présentée, jamais poussée : cet onglet n'a pas
    /// de pile de navigation.
    @State private var showPantry = false

    /// Résumé des lignes (spec §6) : nom de la première + le nombre des autres, via
    /// MealFormatting.frSummary, et emoji de cette même première ligne. Partagée
    /// avec la feuille de log pour que la règle ne puisse pas diverger entre les
    /// deux écrans.
    private let catalog: FoodCatalog

    private static let slotOrder: [MealSlot] = [.breakfast, .lunch, .dinner, .snack]

    init() {
        catalog = (try? FoodCatalog.load()) ?? .empty
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

    /// Le total du jour garde le tilde tant qu'AU MOINS UN repas est estimé : la
    /// somme hérite de l'incertitude de sa partie la moins sûre. Il ne disparaît que
    /// si chaque repas loggé ce jour-là a des kcal saisies à la main, seul cas où le
    /// total est vraiment un chiffre connu de bout en bout (spec §6, pas couvert
    /// explicitement, décision prise ici).
    private var isTotalManual: Bool {
        !dayMeals.isEmpty && dayMeals.allSatisfy { $0.manualKcal != nil }
    }

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
        // Bandeau bas : toujours atteignable sans scroller (spec v1.13 §6.4). Réservé
        // à AUJOURD'HUI — les jours passés sont en lecture seule depuis la v1 (§4.2),
        // un bouton d'ajout y serait un mensonge.
        .safeAreaInset(edge: .bottom) {
            if isToday {
                ActionCardButton.meal(size: .compact) { showNewMeal = true }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
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
        // Pas de `onDismiss` : le frigo ne touche qu'au profil, jamais aux repas du
        // jour — recharger la liste ici ne ferait qu'un fetch pour rien.
        .sheet(isPresented: $showPantry) {
            PantryView()
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

    /// Deux boutons à droite depuis la 1.14 (le frigo) contre un à gauche : les
    /// `Spacer()` d'origine auraient décalé le titre d'une vingtaine de points vers la
    /// gauche. Les deux groupes prennent donc une largeur FLEXIBLE identique et le
    /// titre garde la priorité de mise en page, ce qui le laisse exactement au centre.
    private var dayHeader: some View {
        HStack(spacing: 8) {
            chevronButton(systemName: "chevron.left", disabled: false) { moveDay(-1) }
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(dayTitle)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)
            HStack(spacing: 4) {
                // Jamais dans le futur : chevron droit inactif sur aujourd'hui.
                chevronButton(systemName: "chevron.right", disabled: isToday) { moveDay(1) }
                pantryButton
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20)
    }

    /// Le frigo (spec §6.3), même pastille ronde que l'engrenage de l'accueil. Visible
    /// aussi sur les jours passés : ce qu'on a sous la main ne dépend pas du jour
    /// consulté, et la liste sert au classement des idées, pas au journal.
    private var pantryButton: some View {
        Button {
            showPantry = true
        } label: {
            Text("🧺").font(.system(size: 20))
        }
        .buttonStyle(CircleIconButtonStyle())
        .accessibilityLabel("Mon frigo")
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
            // Dépassement en ACCENT, jamais en rouge (spec §7.4). Tilde conditionnel :
            // voir isTotalManual.
            Text("\(isTotalManual ? "" : "~ ")\(totalKcal.frFormatted) / \(targetKcal.frFormatted) kcal")
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

    /// Item de la première ligne du repas, nil si le repas n'a aucune ligne (l'unique
    /// entrée d'avant la migration v1.10, spec §3.1 : elle perd son détail).
    private func firstItem(of entry: MealEntry) -> FoodItem? {
        entry.lines.first.flatMap { catalog.byID[$0.itemID] }
    }

    private func mealRow(_ entry: MealEntry) -> some View {
        let item = firstItem(of: entry)
        return HStack(spacing: 12) {
            Text(item?.emoji ?? "🥘")
                .font(.system(size: 28))
            VStack(alignment: .leading, spacing: 2) {
                Text(MealFormatting.frSummary(lines: entry.lines, catalog: catalog))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
            }
            Spacer()
            // Même règle du tilde que la barre basse de la feuille (spec §6) :
            // un repas aux kcal saisies à la main ne l'affiche pas non plus ici.
            Text(MealFormatting.frKcal(entry.estimatedKcal, isManual: entry.manualKcal != nil))
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

    // MARK: État vide

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            NivelitoView(expression: .happy, size: 84)
            if isToday {
                // Pas de bouton ici depuis la v1.13 : le bandeau bas est toujours
                // visible sur aujourd'hui, celui-ci n'était plus qu'un doublon.
                Text("Rien de noté aujourd'hui pour l'instant.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtext)
            } else {
                Text("Rien de noté ce jour-là, et c'est OK 😌")
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
    let catalog = try! FoodCatalog.load()
    context.insert(MealEntry(slot: .breakfast, lines: [catalog.line(for: catalog.byID["toast"]!)],
                             estimatedKcal: 350, xpAwarded: 20))
    context.insert(MealEntry(
        slot: .lunch,
        lines: [catalog.line(for: catalog.byID["salad"]!), .simple(MealComponent(itemID: "water", grams: 200))],
        estimatedKcal: 350, xpAwarded: 20
    ))
    context.insert(MealEntry(
        slot: .dinner,
        lines: [
            catalog.line(for: catalog.byID["pasta"]!),
            .simple(MealComponent(itemID: "beer_half", grams: 500)),
            .simple(MealComponent(itemID: "choco_bar", grams: 45)),
        ],
        estimatedKcal: 1445, xpAwarded: 20
    ))
    // Le repas d'avant la migration : aucune ligne, kcal et XP intacts (spec §3.1).
    context.insert(MealEntry(slot: .snack, estimatedKcal: 180, xpAwarded: 20))
    try? context.save()

    return (container, GameService(modelContext: context, stepsService: FakeStepsService(),
                                   widgetDefaults: nil))
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
                                 stepsService: FakeStepsService(), widgetDefaults: nil))
}
