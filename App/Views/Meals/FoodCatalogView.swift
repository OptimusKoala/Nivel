// App/Views/Meals/FoodCatalogView.swift
// Le catalogue à onglets (spec v1.10 §5.3) : Plats · Ingrédients · Boissons ·
// Encas · Desserts. Un tap ajoute la ligne avec son `defaultGrams` et rien
// d'autre, le chemin de quinze secondes. Pas de sélection persistante : la puce
// ne reste pas allumée, c'est le panier qui matérialise le choix.

import SwiftUI
import NivelCore

struct FoodCatalogView: View {
    let catalog: FoodCatalog
    /// Créneau courant, pour filtrer l'onglet Plats. Sans effet sur les quatre autres.
    var slot: MealSlot?
    /// Verrouille l'onglet, sans sélecteur visible : utilisé par l'écran de détail pour
    /// n'ouvrir que les ingrédients (spec §5.4, « Ajouter un ingrédient »).
    var lockedCategory: FoodItem.Category?
    let onPick: (FoodItem) -> Void

    @State private var category: FoodItem.Category

    init(catalog: FoodCatalog, slot: MealSlot? = nil, lockedCategory: FoodItem.Category? = nil,
         onPick: @escaping (FoodItem) -> Void) {
        self.catalog = catalog
        self.slot = slot
        self.lockedCategory = lockedCategory
        self.onPick = onPick
        _category = State(initialValue: lockedCategory ?? .dish)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if lockedCategory == nil {
                SectionTitle("Catalogue")
                categoryPicker
            }
            grid
        }
    }

    // MARK: Catégorie
    //
    // Rangée de pastilles défilantes : cinq catégories ne tiennent plus dans la
    // largeur d'un iPhone, et le Dynamic Type achève le Picker segmenté. Motif
    // proche des pastilles de créneau de MealLogSheet.slotPicker — à ceci près
    // que le trait `.isSelected` est posé à la main : un Picker segmenté le
    // portait nativement pour VoiceOver, un Button nu ne l'a pas.
    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FoodItem.Category.tabOrder, id: \.self) { candidate in
                    Button {
                        category = candidate
                    } label: {
                        Text(candidate.frLabel)
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .background(category == candidate ? Theme.orange : Theme.card,
                                        in: Capsule())
                            .foregroundStyle(category == candidate ? .white : Theme.text)
                            // 44 pt de cible tactile (règle Apple), la pastille seule
                            // n'atteignant que 36 pt de haut.
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                            .animation(.snappy, value: category)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Catégorie \(candidate.frLabel)")
                    .accessibilityAddTraits(category == candidate ? [.isSelected] : [])
                }
            }
        }
    }

    /// Seul l'onglet Plats tient compte du créneau (spec §5.3).
    private var items: [FoodItem] {
        catalog.items(category: category, slot: category == .dish ? slot : nil)
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())],
                  spacing: 12) {
            ForEach(items) { item in
                foodCard(item)
            }
        }
    }

    private func foodCard(_ item: FoodItem) -> some View {
        Button {
            onPick(item)
        } label: {
            VStack(spacing: 5) {
                Text(item.emoji)
                    .font(.system(size: 34))
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text("~\(defaultKcal(item).frFormatted) kcal")
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .padding(10)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    /// Kcal affichées sur la puce : la composition par défaut si le plat en a une
    /// (plus juste que le seul repli `kcalPer100g × defaultGrams`), sinon ce repli.
    private func defaultKcal(_ item: FoodItem) -> Int {
        MealEstimator.kcal(lines: [catalog.line(for: item)], kcalPer100g: catalog.kcalPer100g)
    }
}

#Preview("Catalogue") {
    let catalog = try! FoodCatalog.load()
    return FoodCatalogView(catalog: catalog) { _ in }
        .fontDesign(.rounded)
        .padding(20)
        .background(Theme.background)
}
