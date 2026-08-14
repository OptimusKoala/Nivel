// App/Views/Meals/RecipeDetailSheet.swift
// La fiche recette (spec v1.14 §6.5), présentée au tap sur une carte de la bande
// d'idées : emoji, titre, kcal, les ingrédients avec les manquants signalés, la
// préparation, et « Noter ce repas ».
//
// ⚠️ Cette feuille N'OUVRE PAS la feuille de saisie. Elle se referme et rend sa
// ligne composée à `MealsJournalView` par `onLog`, qui présente `MealLogSheet`
// depuis SON état. C'est ce détour qui garantit le `onDismiss: reloadDayMeals` du
// journal : une feuille de saisie ouverte d'ici ne déclencherait rien, le repas
// validé n'apparaîtrait pas dans le journal et le total du jour resterait faux
// jusqu'au changement de jour. Le défaut se voit tard, et il ressemble à une perte
// de données.
//
// FEUILLE avec pile INTERNE, comme PantryView et MealLogSheet : l'onglet Repas n'a
// pas de pile de navigation où pousser quoi que ce soit.

import SwiftUI
import NivelCore

struct RecipeDetailSheet: View {
    let suggestion: RecipeSuggestion
    let foods: FoodCatalog
    /// Le frigo au moment de l'ouverture. Vide, les ingrédients ne portent AUCUNE
    /// marque : tout cocher en creux dirait « tu n'as rien », ce qui est faux — on ne
    /// sait simplement pas.
    let pantry: Set<String>
    /// Rendue au parent, qui présente la feuille de saisie. Voir l'en-tête.
    let onLog: (MealLine) -> Void

    @Environment(\.dismiss) private var dismiss

    private var recipe: Recipe { suggestion.recipe }
    private var item: FoodItem? { foods.byID[recipe.itemID] }

    /// La ligne que « Noter ce repas » rendra au journal — statique et pure, pour être
    /// éprouvée sans écran (`RecipeStripTests`).
    ///
    /// Elle passe par `FoodCatalog.line(for:)` et ne compose RIEN à la main : c'est ce
    /// qui lui donne l'id de la RECETTE, et donc au journal le nom « Soupe
    /// poireaux-pommes de terre » plutôt que « Légumes de soupe +3 ». Recomposer les
    /// mêmes composants ici marcherait à l'écran de saisie et mentirait au journal.
    ///
    /// `nil` si l'aliment n'est pas au catalogue (JSON corrompu) : plus rien à noter.
    static func basketLine(for recipe: Recipe, foods: FoodCatalog) -> MealLine? {
        foods.byID[recipe.itemID].map { foods.line(for: $0) }
    }

    var body: some View {
        // Composée UNE fois par passe : `line` a trois lecteurs (les ingrédients, le
        // bandeau bas, le bouton), et une propriété calculée les faisait tous les
        // trois retraverser le catalogue.
        let line = Self.basketLine(for: recipe, foods: foods)
        return NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        ingredientsSection(components: line?.components ?? [])
                        stepsSection
                    }
                    .padding(20)
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar(line: line) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Bouton nu, comme PantryView et MealLogSheet : le chrome de barre
                    // d'outils dessine déjà une cible au-delà de 44 pt.
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .tint(Theme.subtext)
                        .accessibilityLabel("Fermer")
                }
            }
        }
        .foregroundStyle(Theme.text)
        .tint(Theme.orange)
        .presentationDetents([.large])
        .presentationCornerRadius(28)
        // Rien à perdre ici : la fiche ne se modifie pas, elle se lit. Le garde de
        // fermeture s'arme plus loin, sur le panier pré-rempli (MealLogSheet).
        .presentationDragIndicator(.visible)
    }

    // MARK: En-tête

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(item?.emoji ?? "🥘")
                    .font(.system(size: 40))
                    // Décoratif, comme partout ailleurs (`RecipeStrip.frCardLabel`,
                    // `PantryView.row`) : sans ça VoiceOver annonce « brocoli » avant
                    // le titre, en croyant le nommer.
                    .accessibilityHidden(true)
                Text(item?.name ?? "Idée de repas")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                // Même règle du tilde que partout ailleurs (spec §5.5) : la fiche
                // estime, elle ne pèse pas.
                Text(MealFormatting.frKcal(suggestion.kcal, isManual: false))
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.orange)
                // Même règle que la carte de la bande, et par la même fonction : frigo
                // vide, la fiche ne dit rien de ce qu'il manque (elle invite à cocher,
                // plus bas). Les deux écrans ne peuvent donc pas se contredire.
                if let state = RecipeStrip.frPantryState(missingCount: suggestion.missingCount,
                                                        pantryIsEmpty: pantry.isEmpty) {
                    // Séparateur graphique : « point médian » entre deux chiffres n'est
                    // pas une information.
                    Text("·").foregroundStyle(Theme.subtext)
                        .accessibilityHidden(true)
                    Text(state)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(suggestion.hasEverything ? Theme.green : Theme.subtext)
                }
            }
        }
        // Un seul élément : « Gaspacho, ~352 kcal, Il manque 2 », d'un seul balayage.
        // Fusionné et non recomposé à la main — c'est ce que fait déjà chaque ligne
        // d'ingrédient plus bas.
        .accessibilityElement(children: .combine)
    }

    // MARK: Ingrédients

    private func ingredientsSection(components: [MealComponent]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Ingrédients")
            if pantry.isEmpty {
                // Une invitation, pas un formulaire : aucun bouton d'ici vers le
                // frigo — une feuille par-dessus une feuille pour une case à cocher
                // coûterait plus cher que le retour de deux taps.
                Text("Coche ton frigo pour voir d'un coup d'œil ce qu'il te manque.")
                    .font(.footnote)
                    .foregroundStyle(Theme.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 8) {
                ForEach(Array(components.enumerated()), id: \.offset) { _, component in
                    ingredientRow(component)
                }
            }
        }
    }

    private func ingredientRow(_ component: MealComponent) -> some View {
        let ingredient = foods.byID[component.itemID]
        let isInPantry = pantry.contains(component.itemID)
        return HStack(spacing: 10) {
            Text(ingredient?.emoji ?? "🥘")
                .font(.title3)
                // Décoratif : fusionnée sans ça, la ligne se faisait nommer par son
                // emoji et VoiceOver lisait « brocoli, Légumes verts, 100 g ».
                .accessibilityHidden(true)
            Text(ingredient?.name ?? component.itemID)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            Text(ingredient?.frQuantity(grams: component.grams) ?? "\(component.grams) g")
                .font(.caption)
                .foregroundStyle(Theme.subtext)
            // Frigo vide : aucune marque du tout. Sinon la même paire de glyphes que
            // le frigo lui-même, avec les mêmes couleurs — c'est le même état, montré
            // depuis l'autre bout.
            if !pantry.isEmpty {
                Image(systemName: isInPantry ? "checkmark.circle.fill" : "circle")
                    .font(.footnote)
                    .foregroundStyle(isInPantry ? Theme.green : Theme.subtext)
            }
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        // L'état ne se dit qu'une fois, et par un trait : « coché » collé au libellé
        // ferait lire « Tomate, 80 g, coché » à VoiceOver comme si c'était le nom.
        .accessibilityAddTraits(!pantry.isEmpty && isInPantry ? [.isSelected] : [])
    }

    // MARK: Préparation

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Préparation")
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Theme.orange, in: Circle())
                        Text(step)
                            .font(.subheadline)
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    // MARK: Bandeau bas

    private func bottomBar(line: MealLine?) -> some View {
        Button("Noter ce repas") { log(line) }
            .buttonStyle(PrimaryButtonStyle())
            // Item introuvable au catalogue (JSON corrompu) : plus de ligne à
            // composer, donc plus rien à noter. La fiche reste lisible.
            .disabled(line == nil)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Theme.card.ignoresSafeArea(edges: .bottom))
            .shadow(color: Theme.floatingShadow, radius: 10, y: -4)
    }

    /// Se referme, PUIS rend la ligne. L'ordre importe : le parent présente la feuille
    /// de saisie depuis son propre état, et il ne peut le faire qu'une fois celle-ci
    /// partie. Rien n'est enregistré ici — la validation reste explicite (spec §6.5).
    private func log(_ line: MealLine?) {
        guard let line else { return }
        dismiss()
        onLog(line)
    }
}

// MARK: - Preview

#Preview("Fiche recette") {
    let foods = try! FoodCatalog.load()
    let recipes = try! RecipeCatalog.load()
    let suggestion = RecipeSuggester.suggestions(
        date: .now, slot: .dinner, pantry: ["potato", "cream"],
        recipes: recipes, foods: foods, calendar: Calendar(identifier: .gregorian)
    ).first!
    return RecipeDetailSheet(suggestion: suggestion, foods: foods,
                             pantry: ["potato", "cream"]) { _ in }
        .fontDesign(.rounded)
}
