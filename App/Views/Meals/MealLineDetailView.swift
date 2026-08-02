// App/Views/Meals/MealLineDetailView.swift
// Écran de détail d'une ligne (spec v1.10 §5.4), poussé par le chevron du panier
// (NavigationStack, pas une sheet par-dessus la sheet). Ligne composée : puces de
// portion + composants réglables + ajout/retrait d'ingrédient. Ligne simple : juste
// la quantité, sans les deux premières sections.
//
// Note de créé par avance (Task 5, pas Task 6) : le sample code de la Task 5 pousse
// déjà vers cet écran dans son `navigationDestination`, alors que le plan range sa
// création en Task 6 — mais l'arbre doit compiler à la fin de la Task 5. Le contenu
// suit donc directement la spec §5.4 ; la Task 6 n'aura plus qu'à retirer Dish/Extra.

import SwiftUI
import NivelCore

struct MealLineDetailView: View {
    @Binding var line: MealLine
    let catalog: FoodCatalog

    @State private var showAddIngredient = false

    private var item: FoodItem? { catalog.byID[line.itemID] }
    /// Composition PAR DÉFAUT du plat, jamais les grammes courants : les puces de
    /// portion s'appliquent toujours à cette référence fixe, sinon "copieux" tapé
    /// deux fois dériverait (×1,3 puis ×1,3 = ×1,69) au lieu de rester sur ×1,3.
    private var defaults: [MealComponent] { catalog.compositions[line.itemID] ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if line.isComposed {
                    portionPicker
                }
                componentsSection
                if line.isComposed {
                    addIngredientButton
                }
            }
            .padding(20)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(item?.name ?? "Repas")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddIngredient) {
            NavigationStack {
                ScrollView {
                    FoodCatalogView(catalog: catalog, lockedCategory: .side) { picked in
                        addComponent(itemID: picked.id, grams: picked.defaultGrams)
                        showAddIngredient = false
                    }
                    .padding(20)
                }
                .background(Theme.background.ignoresSafeArea())
                .navigationTitle("Ajouter un ingrédient")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(28)
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: En-tête

    private var header: some View {
        HStack(spacing: 10) {
            Text(item?.emoji ?? "🥘")
                .font(.system(size: 34))
            Text(item?.name ?? "Repas")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.text)
        }
    }

    // MARK: Portion (ligne composée uniquement)

    private var currentPortion: MealPortion? {
        MealPortion.matching(components: line.components, defaults: defaults)
    }

    private var portionPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Portion")
            HStack(spacing: 8) {
                ForEach(MealPortion.allCases, id: \.self) { candidate in
                    Button {
                        applyPortion(candidate)
                    } label: {
                        Text(candidate.frLabel)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(currentPortion == candidate ? Theme.orange : Theme.card,
                                        in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(currentPortion == candidate ? .white : Theme.text)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Réécrit TOUS les composants d'un coup depuis la composition par défaut
    /// (spec §2) : aucun multiplicateur ne s'applique après coup sur un ajustement
    /// à la main, donc composants ajoutés/retirés perdent leur trace en tapant une
    /// puce — c'est le compromis assumé de l'emplacement (spec §5.4).
    private func applyPortion(_ portion: MealPortion) {
        guard !defaults.isEmpty else { return }
        line = .composed(itemID: line.itemID, components: portion.applied(to: defaults))
    }

    // MARK: Composants

    private var componentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(line.isComposed ? "Ingrédients" : "Quantité")
            VStack(spacing: 8) {
                ForEach(Array(line.components.enumerated()), id: \.offset) { index, component in
                    componentRow(component, index: index)
                }
            }
        }
    }

    @ViewBuilder
    private func componentRow(_ component: MealComponent, index: Int) -> some View {
        // Une ligne simple a un seul composant, non supprimable (spec §5.4) : rien
        // à décomposer davantage. Une ligne composée garde au moins un composant.
        if line.isComposed && line.components.count > 1 {
            SwipeToDeleteRow(onDelete: { removeComponent(at: index) }) {
                componentContent(component)
            }
        } else {
            componentContent(component)
        }
    }

    private func componentContent(_ component: MealComponent) -> some View {
        let componentItem = catalog.byID[component.itemID]
        return HStack(spacing: 10) {
            Text(componentItem?.emoji ?? "🥘")
                .font(.title3)
            Text(componentItem?.name ?? component.itemID)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            quantityControl(for: component, item: componentItem)
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    /// Stepper dans l'unité naturelle si l'item en a une, champ en grammes toujours
    /// accessible en plus (spec §5.4) : les grammes restent la vérité stockée.
    private func quantityControl(for component: MealComponent, item: FoodItem?) -> some View {
        HStack(spacing: 10) {
            if let item, item.hasUnit {
                unitStepper(component: component, item: item)
            }
            gramsField(component: component)
        }
    }

    private func unitStepper(component: MealComponent, item: FoodItem) -> some View {
        let unitGrams = max(1, item.unitGrams ?? 1)
        let count = Double(component.grams) / Double(unitGrams)
        return HStack(spacing: 8) {
            Button {
                setGrams(itemID: component.itemID,
                        grams: Int(((count - 0.5) * Double(unitGrams)).rounded()))
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(Theme.orange)
            }
            .buttonStyle(.plain)

            Text(item.frQuantity(grams: component.grams))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.text)
                .frame(minWidth: 64)
                .lineLimit(1)

            Button {
                setGrams(itemID: component.itemID,
                        grams: Int(((count + 0.5) * Double(unitGrams)).rounded()))
            } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Theme.orange)
            }
            .buttonStyle(.plain)
        }
    }

    private func gramsField(component: MealComponent) -> some View {
        HStack(spacing: 4) {
            TextField("g", text: gramsTextBinding(itemID: component.itemID))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.subheadline.monospacedDigit())
                .frame(width: 40)
            Text("g")
                .font(.caption)
                .foregroundStyle(Theme.subtext)
        }
    }

    /// Proxy texte ↔ grammes : la vérité reste `line`, jamais un état local qui
    /// pourrait diverger (spec §3.2 : toujours des grammes, jamais autre chose).
    private func gramsTextBinding(itemID: String) -> Binding<String> {
        Binding<String>(
            get: {
                let grams = line.components.first { $0.itemID == itemID }?.grams ?? 0
                return "\(grams)"
            },
            set: { newValue in
                guard let grams = Int(newValue), grams > 0 else { return }
                setGrams(itemID: itemID, grams: grams)
            }
        )
    }

    /// Réassignation complète des composants (une ligne composée n'a pas de poids
    /// propre à recalculer, spec §3.2) : jamais de mutation en place.
    private func setGrams(itemID: String, grams: Int) {
        let bounded = max(1, grams)
        var components = line.components
        guard let index = components.firstIndex(where: { $0.itemID == itemID }) else { return }
        components[index] = MealComponent(itemID: itemID, grams: bounded)
        rewrite(components: components)
    }

    private func removeComponent(at index: Int) {
        guard case .composed(let itemID, var components) = line, components.count > 1 else { return }
        guard components.indices.contains(index) else { return }
        components.remove(at: index)
        line = .composed(itemID: itemID, components: components)
    }

    private func rewrite(components: [MealComponent]) {
        switch line {
        case .simple:
            if let first = components.first { line = .simple(first) }
        case .composed(let itemID, _):
            line = .composed(itemID: itemID, components: components)
        }
    }

    // MARK: Ajout d'ingrédient (ligne composée uniquement)

    private var addIngredientButton: some View {
        Button {
            showAddIngredient = true
        } label: {
            Label("Ajouter un ingrédient", systemImage: "plus")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(SecondaryButtonStyle())
    }

    private func addComponent(itemID: String, grams: Int) {
        guard case .composed(let lineItemID, var components) = line else { return }
        if let existingIndex = components.firstIndex(where: { $0.itemID == itemID }) {
            components[existingIndex] = MealComponent(
                itemID: itemID, grams: components[existingIndex].grams + grams)
        } else {
            components.append(MealComponent(itemID: itemID, grams: grams))
        }
        line = .composed(itemID: lineItemID, components: components)
    }
}
