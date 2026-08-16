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
    @Environment(\.scenePhase) private var scenePhase
    @Query private var profiles: [UserProfile]

    @State private var selectedDay = GameService.calendar.startOfDay(for: .now)
    /// Repas du jour sélectionné — fetch BORNÉ au jour (pas de @Query sur tout
    /// l'historique), rechargé au changement de jour et après chaque mutation.
    /// Les cœurs reçus s'affichent sur MES entrées (spec 1.15 §3.8). Sans duo, la liste est
    /// vide et rien ne change à ce journal.
    @Environment(DuoService.self) private var duo
    @State private var dayMeals: [MealEntry] = []
    @State private var editingEntry: MealEntry?
    @State private var showNewMeal = false
    /// Feuille du frigo (spec §6.3) — présentée, jamais poussée : cet onglet n'a pas
    /// de pile de navigation.
    @State private var showPantry = false
    /// Fiche recette ouverte (spec §6.5). Présentée depuis un état du PARENT et non
    /// depuis la carte : c'est ce qui permettra au crochet `ScreenshotMode` du lot F de
    /// forcer cette feuille à l'ouverture, et c'est la moitié du montage ci-dessous.
    @State private var shownRecipe: ShownRecipe?
    /// Ligne composée renvoyée par la fiche recette. Passer par un état du PARENT (et
    /// non présenter la feuille de saisie depuis la fiche) est ce qui garantit que
    /// `reloadDayMeals` s'exécute à sa fermeture — sans quoi le repas validé
    /// n'apparaîtrait pas dans le journal et le total du jour resterait faux jusqu'au
    /// changement de jour.
    @State private var prefilledMeal: PrefilledMeal?
    /// Instant de référence de la bande d'idées : un ÉTAT, et non `Date()` relu à
    /// chaque passe de rendu. Le moteur promet un classement identique à chaque
    /// ouverture d'un même jour, et un instant relu en pleine passe permuterait les
    /// cartes à cheval sur 15 h ou sur minuit. (`today`, plus bas, lit bien `.now` à
    /// chaque passe — mais à la granularité du JOUR, et depuis la v1.)
    ///
    /// Il se REPOSE, en revanche, à chaque changement de jour et à chaque retour au
    /// premier plan (voir `.task(id:)` et `onChange(of: scenePhase)`) : figé pour la
    /// vie de la vue, il annonçait « Idées pour ce soir » à 0 h 30 à qui avait laissé
    /// l'app ouverte depuis 21 h et tapait « → » pour revenir sur le jour nouveau.
    @State private var ideasReference = Self.ideasNow

    /// L'instant que la bande prend pour référence : `.now`, sauf en mode captures où
    /// il est ÉPINGLÉ (`ScreenshotMode.ideasReference` en dit le pourquoi).
    ///
    /// Le point d'injection est ici et nulle part ailleurs parce que `ideasReference`
    /// est déjà l'unique entonnoir par lequel l'instant atteint la bande — le cadrage
    /// et le classement n'en connaissent pas d'autre. Épingler plus haut (l'horloge de
    /// l'app, ou le `today` du journal) déplacerait aussi « aujourd'hui », et le jeu de
    /// démonstration, lui, est daté sur l'instant RÉEL du tournage : le journal du jour
    /// et ses repas se videraient sous la bande.
    private static var ideasNow: Date {
        #if DEBUG
        if let pinned = ScreenshotMode.ideasReference { return pinned }
        #endif
        return .now
    }

    /// La recette dont la fiche est ouverte, AVEC le créneau que la bande visait quand
    /// on a tapé sa carte : c'est lui que la feuille de saisie pré-sélectionnera, et le
    /// relire plus tard donnerait un autre créneau si l'heure a passé 15 h entre-temps.
    private struct ShownRecipe: Identifiable {
        let suggestion: RecipeSuggestion
        let slot: MealSlot
        var id: String { suggestion.id }
    }

    /// Ce que la fiche recette rend au journal. Une struct `Identifiable` parce que
    /// `.sheet(item:)` l'exige — l'`UUID` n'a rien d'astucieux : `.sheet(item:)`
    /// représente à chaque transition nil→valeur quel que soit l'id, comme le montre
    /// `shownRecipe` juste au-dessus, dont l'id est celui (stable) de la recette.
    private struct PrefilledMeal: Identifiable {
        let id = UUID()
        let line: MealLine
        let slot: MealSlot
    }

    /// Résumé des lignes (spec §6) : nom de la première + le nombre des autres, via
    /// MealFormatting.frSummary, et emoji de cette même première ligne. Partagée
    /// avec la feuille de log pour que la règle ne puisse pas diverger entre les
    /// deux écrans.
    private let catalog: FoodCatalog
    /// Recettes de saison (spec §6.2) — repli vide si le JSON est corrompu : la bande
    /// d'idées disparaît, l'onglet continue.
    private let recipes: RecipeCatalog

    private static let slotOrder: [MealSlot] = [.breakfast, .lunch, .dinner, .snack]

    init() {
        catalog = (try? FoodCatalog.load()) ?? .empty
        recipes = (try? RecipeCatalog.load()) ?? .empty
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

    // MARK: Idées de saison (spec §6.4)

    /// Le frigo tel qu'il est MAINTENANT : `profiles` est un `@Query`, donc cocher un
    /// ingrédient dans la feuille du frigo reclasse la bande dès sa fermeture, sans
    /// que rien n'ait à être rechargé à la main.
    private var pantry: Set<String> { Set(profiles.first?.pantryItemIDs ?? []) }

    /// Créneau, mois, et l'affichage même de la bande : TOUT est décidé par une
    /// fonction pure et testée. ⚠️ Et surtout pas par `MealSlot.suggested(forHour:)`,
    /// qui répond à une autre question — voir `RecipeStrip.targetSlot(forHour:)`.
    /// L'instant est un PARAMÈTRE et non `ideasReference` relu ici : l'ouverture
    /// automatique de la fiche (mode captures, plus bas) appelle ces deux fonctions
    /// dans la passe même où l'état vient d'être assigné, et SwiftUI ne promet à
    /// personne qu'un `@State` relu aussitôt après son écriture rende la valeur neuve.
    private func stripFraming(at reference: Date) -> RecipeStrip.Framing? {
        RecipeStrip.framing(at: reference, isToday: isToday, calendar: calendar)
    }

    /// Recalculées à chaque passe de rendu, et c'est voulu : l'appel coûte 10 µs en
    /// release (0,12 % d'une frame à 120 Hz), et tout ce dont il dépend est ÉPINGLÉ —
    /// `ideasReference` est un état, le frigo vient du `@Query`. Le mémoïser ajouterait
    /// un état de plus à réinvalider quand le frigo change, pour rien.
    ///
    /// Ce n'est PAS la moitié chère : `init()` décode trois JSON (aliments,
    /// compositions, recettes) à chaque re-création de la vue, ce qui se compte en
    /// millisecondes et non en microsecondes. Dette connue, assumée, et hors de cette
    /// tâche — chiffrer la moitié bon marché en se taisant sur l'autre serait pire que
    /// ne rien chiffrer.
    private func suggestions(for framing: RecipeStrip.Framing,
                            at reference: Date) -> [RecipeSuggestion] {
        RecipeSuggester.suggestions(date: reference, slot: framing.slot, pantry: pantry,
                                    recipes: recipes, foods: catalog, calendar: calendar)
    }

    #if DEBUG
    /// Ouvre d'office la fiche de la PREMIÈRE idée de la bande — captures App Store
    /// (`scripts/screenshots.sh`, écran `recette`), absent du binaire de release.
    /// Miroir des `autoOpensMealLog` / `autoOpensActivityPicker` de l'accueil, à ceci
    /// près qu'il faut d'abord savoir QUOI ouvrir : la fiche n'existe pas sans sa
    /// suggestion ni sans le créneau que la bande visait.
    private func openFirstIdeaForScreenshots(at reference: Date) {
        guard ScreenshotMode.autoOpensRecipeDetail,
              let framing = stripFraming(at: reference),
              let first = suggestions(for: framing, at: reference).first else { return }
        shownRecipe = ShownRecipe(suggestion: first, slot: framing.slot)
    }
    #endif

    // MARK: Corps

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 12) {
                dayHeader
                totalCard
                // La bande d'idées entre le total et le journal (spec §6.5). Le `nil`
                // du cadrage porte le « aujourd'hui seulement », avec son motif.
                //
                // Rien à ajouter ici pour le cas « aucune suggestion » (catalogue de
                // recettes illisible) : `RecipeStrip` ne rend alors rien du tout, et un
                // enfant qui ne rend rien ne consomme PAS l'espacement du `VStack` —
                // vérifié à l'image, catalogue vidé, les deux rendus sont identiques au
                // pixel près. Un second garde ici ne servirait qu'à écrire deux fois la
                // même règle.
                if let framing = stripFraming(at: ideasReference) {
                    RecipeStrip(suggestions: suggestions(for: framing, at: ideasReference),
                                framing: framing,
                                foods: catalog, pantryIsEmpty: pantry.isEmpty,
                                onPick: { shownRecipe = ShownRecipe(suggestion: $0, slot: framing.slot) },
                                onOpenPantry: { showPantry = true })
                }
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
        // Recharge au premier affichage ET à chaque changement de jour. C'est aussi le
        // point où l'instant de référence des idées se repose : revenir sur
        // aujourd'hui après minuit doit rendre les idées du jour nouveau, pas celles
        // calculées sur l'heure de la veille.
        .task(id: selectedDay) {
            let reference = Self.ideasNow
            ideasReference = reference
            reloadDayMeals()
            #if DEBUG
            openFirstIdeaForScreenshots(at: reference)
            #endif
        }
        // Et au retour de veille : l'app laissée ouverte sur cet onglet ne rejoue
        // aucun `.task`, et garderait « Idées pour ce midi » jusqu'au soir.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { ideasReference = Self.ideasNow }
        }
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
        // La fiche recette rend sa ligne, ne l'enregistre pas : c'est la feuille de
        // saisie ci-dessous qui le fera, et c'est ELLE qui porte le `onDismiss` du
        // rechargement. Voir l'en-tête de RecipeDetailSheet.
        .sheet(item: $shownRecipe) { shown in
            RecipeDetailSheet(suggestion: shown.suggestion, foods: catalog, pantry: pantry) { line in
                prefilledMeal = PrefilledMeal(line: line, slot: shown.slot)
            }
        }
        .sheet(item: $prefilledMeal, onDismiss: reloadDayMeals) { prefilled in
            MealLogSheet(prefilled: prefilled.line, slot: prefilled.slot)
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
            // Le cœur reçu du duo (spec 1.15 §3.8), avant les kcal : il commente le repas,
            // pas son chiffre. Absent sans duo, et absent tout court sur une entrée que
            // personne n'a aimée — aucune place réservée, aucun gris à la ligne.
            if DuoLikeMark.isLiked(publicID: entry.publicID, likedEventIDs: duo.likedEventIDs) {
                DuoLikeMark()
            }
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
        configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
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
        .environment(DuoService(
            identity: DuoIdentity(defaults: UserDefaults(suiteName: "nivel.preview.duo")
                ?? .standard),
            resolveTarget: { _ in nil }))
}

#Preview("Journal vide") {
    let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                         DayLog.self, GamificationState.self, ActivityEntry.self])
    let container = try! ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
    )
    return MealsJournalView()
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(GameService(modelContext: container.mainContext,
                                 stepsService: FakeStepsService(), widgetDefaults: nil))
        .environment(DuoService(
            identity: DuoIdentity(defaults: UserDefaults(suiteName: "nivel.preview.duo")
                ?? .standard),
            resolveTarget: { _ in nil }))
}
