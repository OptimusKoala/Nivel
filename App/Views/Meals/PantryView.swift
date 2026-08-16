// App/Views/Meals/PantryView.swift
// Le frigo (spec v1.14 §6.3) : les 65 ingrédients du catalogue en cases à cocher,
// une recherche, un bouton « Vider ». Ce que l'utilisateur coche ici ne sert qu'à
// CLASSER les idées de repas — d'où le sous-titre, imposé au mot près par la spec :
// c'est le seul écran de Nivel qui ressemble à un formulaire, il doit dire tout de
// suite que rien ne part nulle part.
//
// FEUILLE, pas écran poussé (la spec §6.3 dit « poussé », mais l'onglet Repas n'a
// aucune pile de navigation : MealsJournalView est un ZStack et MainTabView
// n'enveloppe aucun onglet ; en ajouter une autour de l'onglet toucherait
// themedTabBar() et le budget de hauteur gagné en 1.13). La pile est donc INTERNE
// à la feuille, comme MealLogSheet, et ne porte que le titre et la fermeture.

import SwiftUI
import SwiftData
import NivelCore

struct PantryView: View {
    @Query private var profiles: [UserProfile]

    var body: some View {
        Group {
            if let profile = profiles.first {
                PantryContent(profile: profile)
            } else {
                ZStack { Theme.background.ignoresSafeArea() }
            }
        }
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
    }
}

struct PantryContent: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var search = ""
    /// Confirmation de « Vider » — voir `clearDialog`.
    @State private var showClearDialog = false

    private let catalog: FoodCatalog

    init(profile: UserProfile) {
        self.profile = profile
        catalog = (try? FoodCatalog.load()) ?? .empty
    }

    // MARK: Données dérivées

    /// Les ingrédients, dans l'ordre du catalogue. Statique et non calculée sur la vue :
    /// c'est la moitié du contrat que `RecipeCatalogTests.testChaqueIngredientDeRecetteEnEstUn`
    /// tient déjà de l'autre côté — les recettes ne citent que des `.side` PARCE QUE le
    /// frigo ne liste que ceux-là. Un `.dish` glissé ici casserait le classement de la
    /// bande d'idées sans qu'aucun test de NivelCore bronche ; celui de `PantryTests` s'en
    /// charge, ce qu'une propriété privée ne permettait pas.
    ///
    /// Passe par `items(category:slot:)` plutôt que par un filtre à la main sur `items` :
    /// c'est le même accesseur que le catalogue de saisie, et il écarte déjà les recettes
    /// (aucune n'est en `.side` aujourd'hui — autant que ça reste vrai si un jour l'une
    /// d'elles l'est).
    static func ingredients(in catalog: FoodCatalog) -> [FoodItem] {
        catalog.items(category: .side, slot: nil)
    }

    private var ingredients: [FoodItem] { Self.ingredients(in: catalog) }

    /// Recherche insensible à la casse ET aux accents — la règle vit dans NivelCore
    /// (`FoodSearch`), où elle s'éprouve sans écran et où la bande d'idées la reprendra.
    private var filtered: [FoodItem] {
        FoodSearch.filter(ingredients, query: search)
    }

    /// Les ids cochés QUI EXISTENT ENCORE dans le catalogue. Un id retiré ou renommé
    /// dans `foods.json` est inoffensif pour le classement (il ne matche rien), mais il
    /// mentirait ici : « 3 ingrédients cochés » sans la moindre coche à l'écran, et un
    /// « Vider » actif qui ne vide rien de visible.
    ///
    /// Catalogue illisible (repli `.empty`) : on rend la liste telle quelle plutôt que
    /// de déclarer tout le frigo fantôme.
    static func knownIDs(_ ids: [String], in ingredients: [FoodItem]) -> [String] {
        guard !ingredients.isEmpty else { return ids }
        let known = Set(ingredients.map(\.id))
        return ids.filter { known.contains($0) }
    }

    private var checkedCount: Int {
        Self.knownIDs(profile.pantryItemIDs, in: ingredients).count
    }

    // MARK: Corps

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 14) {
                    heading
                    searchField
                    list
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Même bouton nu que MealLogSheet : le chrome de barre d'outils
                    // dessine déjà une cible au-delà de 44 pt, lui imposer un cadre
                    // transformerait le cercle en capsule.
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .tint(Theme.subtext)
                        .accessibilityLabel("Fermer")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Vider") { showClearDialog = true }
                        .tint(Theme.orange)
                        // Rien à vider = rien à proposer. Le bouton reste VISIBLE et
                        // estompé plutôt que masqué : un bouton qui apparaît et
                        // disparaît au fil des coches est plus difficile à viser
                        // qu'un bouton toujours au même endroit.
                        .disabled(checkedCount == 0)
                        .accessibilityLabel("Vider le frigo")
                }
            }
            .confirmationDialog("Vider le frigo ?", isPresented: $showClearDialog,
                                titleVisibility: .visible) {
                // PAS de `role: .destructive` : le système le peindrait en rouge et
                // refuserait de le teinter (même raison qu'au dialogue d'abandon de
                // MealLogSheet) — « jamais de rouge », règle v1 §7.4.
                Button("Vider") { clear() }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text(checkedCount == 1
                     ? "Ta coche sera décochée."
                     : "Tes \(checkedCount) coches seront décochées.")
            }
        }
        .foregroundStyle(Theme.text)
        .tint(Theme.orange)
        // Nettoyage des ids disparus du catalogue, une fois par ouverture.
        .task { pruneUnknownIDs() }
    }

    // MARK: Titre

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mon frigo")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.text)
            // Formulation IMPOSÉE par la spec §6.3, au mot près.
            Text("Sert à classer les idées de repas. Rien n'est envoyé nulle part.")
                .font(.footnote)
                .foregroundStyle(Theme.subtext)
                .fixedSize(horizontal: false, vertical: true)
            Text(countLabel)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(checkedCount == 0 ? Theme.subtext : Theme.orange)
        }
    }

    private var countLabel: String { Self.countLabel(checkedCount) }

    /// Trois branches, dont un singulier : statique pour que la suite les épingle
    /// toutes les trois (« 1 ingrédients cochés » est le genre de faute qu'aucun test
    /// de vue n'attrape et que tout le monde voit).
    static func countLabel(_ count: Int) -> String {
        switch count {
        case 0: "Rien de coché pour l'instant."
        case 1: "1 ingrédient coché."
        default: "\(count) ingrédients cochés."
        }
    }

    // MARK: Recherche

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.subtext)
            TextField("Rechercher un ingrédient", text: $search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(Theme.text)
                .submitLabel(.done)
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.subtext)
                }
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Effacer la recherche")
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        // Hauteur portée par le cadre, pas par un padding vertical : le bouton
        // d'effacement porte déjà ses 44 pt et gonflerait la capsule dès qu'il paraît.
        .frame(minHeight: 48)
        .background(Theme.card, in: Capsule())
        .shadow(color: Theme.shadow, radius: 8, y: 4)
    }

    // MARK: Liste

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                // DEUX situations, deux textes. Confondues, un catalogue illisible
                // (repli `.empty`) affichait « Aucun ingrédient ne correspond à «  ». » :
                // des guillemets vides, sur un écran qui n'a jamais rien filtré.
                if ingredients.isEmpty {
                    emptyMessage("La liste des ingrédients n'a pas pu être chargée. Ferme et rouvre le frigo 🙏")
                } else if filtered.isEmpty {
                    VStack(spacing: 12) {
                        emptyMessage("Aucun ingrédient ne correspond à « \(search) ».")
                        // Le × du champ est en haut, à l'autre bout de l'écran : la
                        // sortie est offerte là où l'utilisateur regarde.
                        Button("Effacer la recherche") { search = "" }
                            .buttonStyle(SecondaryButtonStyle())
                            .frame(minHeight: 44)
                    }
                } else {
                    ForEach(filtered) { item in
                        row(item)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func emptyMessage(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Theme.subtext)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
    }

    private func row(_ item: FoodItem) -> some View {
        let isChecked = profile.pantryItemIDs.contains(item.id)
        return Button {
            toggle(item)
        } label: {
            HStack(spacing: 12) {
                Text(item.emoji)
                    .font(.system(size: 24))
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    // PAS d'`opacity` sur la case vide : mesuré en Crème, un
                    // `Theme.subtext` à 50 % tombe à 1,56:1 sur `Theme.card`, très
                    // en dessous des 3:1 que WCAG 1.4.11 demande à un composant qui
                    // porte un état. À plein, 2,68:1 — court encore, d'où la bordure
                    // ci-dessous — et rien n'est perdu au passage : coché et décoché
                    // se distinguent déjà par la forme et par la couleur.
                    .foregroundStyle(isChecked ? Theme.green : Theme.subtext)
            }
            .padding(.horizontal, 14)
            // 44 pt de cible tactile (règle Apple, comme les pastilles du catalogue).
            .frame(minHeight: 44)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
            // Marque au niveau de la LIGNE, comme les cartes d'activité de
            // l'onboarding (OnboardingFlow, `strokeBorder` 1,5 pt sur la carte
            // choisie). Repérer trente coches parmi cinquante-huit ligne à ligne
            // ne peut pas reposer sur un seul glyphe de 20 pt : le contour se lit
            // du coin de l'œil, et il se lit encore si la couleur ne se lit pas.
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(isChecked ? Theme.green : Color.clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: isChecked)
        .accessibilityLabel(item.name)
        // Une ligne cochée est un état, pas un libellé : VoiceOver l'annonce lui-même.
        .accessibilityAddTraits(isChecked ? [.isSelected] : [])
    }

    // MARK: Mutations

    private func toggle(_ item: FoodItem) {
        Pantry.toggle(item.id, on: profile)
        save()
    }

    private func clear() {
        Pantry.clear(on: profile)
        save()
    }

    /// Jette du frigo les ids que le catalogue ne connaît plus (aliment retiré ou
    /// renommé dans `foods.json`). Le tour se paie une fois par ouverture, pas à chaque
    /// coche. Ne fait rien si le catalogue n'a pas pu être lu — sans ce garde, un JSON
    /// illisible viderait le frigo pour de bon, et cette fois sans dialogue.
    private func pruneUnknownIDs() {
        let kept = Self.knownIDs(profile.pantryItemIDs, in: ingredients)
        guard kept.count != profile.pantryItemIDs.count else { return }
        profile.pantryItemIDs = kept
        save()
    }

    /// Sauvegarde explicite à chaque coche, comme les Réglages : ce chemin ne passe pas
    /// par GameService. Pas de `syncWidget()` — le frigo n'est dans aucun snapshot.
    private func save() {
        do {
            try modelContext.save()
        } catch {
            assertionFailure("SwiftData save failed in PantryView: \(error)")
        }
    }
}

// MARK: - Preview

#Preview("Frigo") {
    let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                         DayLog.self, GamificationState.self, ActivityEntry.self])
    let container = try! ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
    )
    let profile = UserProfile(name: "Marion", sex: .female,
                              birthDate: Date(timeIntervalSince1970: 0),
                              heightCm: 165, initialWeightKg: 70, activity: .light,
                              dailyCalorieTarget: 1700)
    profile.pantryItemIDs = ["tomato", "egg"]
    container.mainContext.insert(profile)
    return PantryView()
        .fontDesign(.rounded)
        .modelContainer(container)
}
