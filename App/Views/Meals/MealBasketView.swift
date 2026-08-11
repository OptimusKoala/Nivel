// App/Views/Meals/MealBasketView.swift
// Le panier « Ton repas » (spec v1.10 §5.2) : une ligne par élément ajouté, avec
// son sous-titre de quantité et ses kcal. Chevron = pousse le détail, swipe = retire.

import SwiftUI
import NivelCore

struct MealBasketView: View {
    @Binding var lines: [MealLine]
    let catalog: FoodCatalog
    let onOpen: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Ton repas")
            if lines.isEmpty {
                Text("Tape un plat, une boisson, ce que tu veux")
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtext)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        SwipeToDeleteRow(resetToken: lines.count, onDelete: { removeLine(at: index) }) {
                            basketRow(line, index: index)
                        }
                    }
                }
            }
        }
    }

    private func basketRow(_ line: MealLine, index: Int) -> some View {
        let item = catalog.byID[line.itemID]
        return Button {
            onOpen(index)
        } label: {
            HStack(spacing: 12) {
                Text(item?.emoji ?? "🥘")
                    .font(.system(size: 28))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item?.name ?? "Repas")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text(subtitle(for: line))
                        .font(.caption)
                        .foregroundStyle(Theme.subtext)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text("~\(kcal(for: line).frFormatted) kcal")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.orange)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.subtext)
            }
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func kcal(for line: MealLine) -> Int {
        MealEstimator.kcal(lines: [line], kcalPer100g: catalog.kcalPer100g)
    }

    /// « normal · 6 ingrédients », « ajusté · 6 ingrédients » quand les grammes
    /// courants ne retombent sur aucun des trois crans, ou « 1 verre »/« 50 g » pour
    /// une ligne simple. La portion n'est jamais persistée : déduite à l'affichage
    /// en comparant les grammes courants à la composition par défaut (spec §5.2).
    private func subtitle(for line: MealLine) -> String {
        switch line {
        case .simple(let component):
            guard let item = catalog.byID[component.itemID] else { return "\(component.grams) g" }
            return item.frQuantity(grams: component.grams)
        case .composed(let itemID, let components):
            let count = components.count
            let suffix = count == 1 ? "1 ingrédient" : "\(count) ingrédients"
            let defaults = catalog.compositions[itemID] ?? []
            guard !defaults.isEmpty else { return suffix }
            let label = MealPortion.matching(components: components, defaults: defaults)?.frLabel.lowercased()
                ?? "ajusté"
            return "\(label) · \(suffix)"
        }
    }

    private func removeLine(at index: Int) {
        guard lines.indices.contains(index) else { return }
        lines.remove(at: index)
    }
}

// MARK: - Swipe de suppression hors `List`

/// Le panier vit dans un `VStack` au sein de la `ScrollView` de la feuille (pas un
/// `List`) : `.swipeActions` n'existe que dans un `List`. Ce petit wrapper glissant
/// reproduit le geste (seuil à mi-largeur, retour élastique) sans dépendre d'une
/// `List` imbriquée dans une `ScrollView`, source de conflits de défilement.
/// Réutilisé par `MealLineDetailView` pour retirer un composant.
///
/// v1.13 — le geste ne fonctionnait PAS depuis son introduction en v1.10 : il était
/// attaché avec `.gesture(...)`, donc en priorité NORMALE, et en SwiftUI les gestes
/// d'une sous-vue l'emportent alors sur ceux du parent. Le contenu passé par
/// `MealBasketView` étant un `Button` (le chevron ouvre le détail de la ligne), le
/// bouton gagnait et le `DragGesture` ne recevait jamais rien : un glissement vers la
/// gauche POUSSAIT la page de détail. Voir `highPriorityGesture` plus bas.
struct SwipeToDeleteRow<Content: View>: View {
    /// Change à chaque ajout ou retrait dans la liste parente. Les `ForEach` de cet
    /// écran identifient leurs lignes par INDEX : après une suppression, l'état de
    /// swipe d'une ligne resterait collé à son ancien rang et se retrouverait sur la
    /// ligne voisine, qui afficherait une corbeille que personne n'a fait glisser.
    /// Refermer tout le monde au moindre changement règle le cas sans avoir à donner
    /// une identité stable à des lignes qui peuvent légitimement être identiques
    /// (deux demis de bière, par exemple).
    let resetToken: Int
    let onDelete: () -> Void
    @ViewBuilder let content: Content

    @State private var offset: CGFloat = 0
    private let deleteWidth: CGFloat = 84

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: deleteWidth)
                    .frame(maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16))
            // Sans libellé explicite, VoiceOver (et le test d'interface) annoncent le
            // nom du symbole SF, « trash ».
            .accessibilityLabel("Retirer")

            content
                .offset(x: offset)
                // `highPriorityGesture` et non `gesture` : c'est LA correction de la
                // v1.13. Le parent doit l'emporter sur le `Button` du contenu, sinon
                // le drag ne reçoit rien.
                //
                // `minimumDistance: 12` est ce qui rend l'inversion de priorité sans
                // danger : un tap sans mouvement n'active jamais le drag et atteint
                // donc toujours le bouton — ouvrir le détail d'une ligne continue de
                // marcher. Les deux comportements sont couverts par
                // NivelUITests/BasketSwipeTests.
                .highPriorityGesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            offset = min(0, max(-deleteWidth, value.translation.width))
                        }
                        .onEnded { value in
                            withAnimation(.snappy) {
                                offset = value.translation.width < -deleteWidth / 2 ? -deleteWidth : 0
                            }
                        }
                )
        }
        .onChange(of: resetToken) { _, _ in offset = 0 }
    }
}
