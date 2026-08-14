// App/Views/Meals/RecipeStrip.swift
// La bande d'idées de saison (spec v1.14 §6.4 et §6.5) : trois cartes défilant
// horizontalement entre la carte du total et le journal, chacune avec son emoji,
// son titre, ses kcal et l'état du frigo la concernant. Plus une carte finale
// « Dis-moi ce que tu as 🧺 » tant que le frigo est vide.
//
// La vue ne CLASSE rien (c'est `RecipeSuggester`, dans NivelCore) et ne décide de
// rien qui ne soit STATIQUE ET PUR, donc éprouvable sans écran : s'afficher ou non
// et pour quel créneau (`framing`), le titre, la phrase d'état du frigo, le libellé
// d'accessibilité d'une carte. Ce qui reste dans `body` est de la pose.

import SwiftUI
import NivelCore

struct RecipeStrip: View {
    /// Déjà classées par `RecipeSuggester` — la bande les affiche dans l'ordre reçu.
    let suggestions: [RecipeSuggestion]
    /// Créneau et mois, décidés par `framing(at:isToday:calendar:)` — la vue ne les
    /// recalcule pas et ne peut donc pas en afficher deux versions.
    let framing: Framing
    let foods: FoodCatalog
    /// Frigo vide : la carte d'invitation finale, et les cartes qui se taisent sur ce
    /// qu'il manque. C'est le cas du premier lancement, pas un cas dégradé.
    let pantryIsEmpty: Bool
    let onPick: (RecipeSuggestion) -> Void
    /// Présente la feuille du frigo. La bande ne la présente PAS elle-même : l'onglet
    /// Repas en porte déjà une (`showPantry`), et deux `.sheet` sur le même contenu
    /// ne s'ouvriraient pas plus vite mais mèneraient deux vies séparées.
    let onOpenPantry: () -> Void

    // MARK: Décisions pures

    /// Ce que la bande doit montrer, ou `nil` si elle ne doit pas s'afficher du tout.
    ///
    /// Tout ce qui se décidait encore dans `MealsJournalView` est descendu ici, pour la
    /// raison suivante : aucun test unitaire ne rend une vue, donc rien là-bas ne peut
    /// vérifier qu'un `if` de `body` est correctement écrit. Rassembler les trois
    /// décisions (afficher ou non, quel créneau, quel mois) dans une fonction pure les
    /// met à portée de `RecipeStripTests` et ne laisse à découvert qu'une seule chose :
    /// que la vue appelle bien celle-ci — ce que tient `NivelUITests/IdeasJourneyTests`,
    /// sur la vraie app. Voir l'en-tête des deux suites.
    struct Framing: Equatable {
        let slot: MealSlot
        let month: Int
    }

    /// `isToday` vient de l'appelant plutôt que d'une comparaison faite ici : le
    /// journal a déjà ce prédicat (il en dépend depuis la v1 pour le tap, le glissement
    /// et le bandeau bas), et en refaire une seconde version serait s'offrir la
    /// possibilité qu'elles divergent.
    static func framing(at date: Date, isToday: Bool, calendar: Calendar) -> Framing? {
        // Les jours passés sont en lecture seule depuis la v1 (§4.2) : une idée de
        // dîner pour mardi dernier serait un mensonge — même raisonnement que le
        // bandeau « Noter un repas » de la 1.13.
        guard isToday else { return nil }
        return Framing(slot: targetSlot(forHour: calendar.component(.hour, from: date)),
                       month: calendar.component(.month, from: date))
    }

    /// Créneau des idées : déjeuner jusqu'à 15 h, dîner ensuite (spec §6.4 règle 2).
    ///
    /// ⚠️ Volontairement DISTINCT de `MealSlot.suggested(forHour:)`, et il faut que ça
    /// le reste. Les deux fonctions répondent à deux questions différentes : celle-là
    /// dit quel repas l'utilisateur est en train de NOTER (d'où son `.breakfast` le
    /// matin et son `.snack` de 16 à 17 h), celle-ci pour quel repas on lui donne des
    /// IDÉES. Aucune recette ne porte le créneau `.snack` ni `.breakfast` : mutualiser
    /// les deux viderait la bande tous les jours en milieu d'après-midi, et toute la
    /// matinée. Tenu par `RecipeStripTests`, sur les deux bords et sur les catalogues
    /// réels.
    static func targetSlot(forHour hour: Int) -> MealSlot {
        hour < 15 ? .lunch : .dinner
    }

    /// « Idées pour ce soir · août ». Deux moments seulement, parce que `targetSlot`
    /// n'en produit que deux — un `switch` exhaustif ici promettrait des idées de
    /// petit-déjeuner que le catalogue n'a pas.
    static func title(slot: MealSlot, month: Int) -> String {
        let moment = slot == .dinner ? "ce soir" : "ce midi"
        // Mois hors bornes (l'appelant le tient de `Calendar`, donc jamais — mais une
        // indexation de tableau ne se garde pas « jamais ») : le titre perd son mois
        // plutôt que son point médian, qui resterait orphelin en fin de ligne.
        guard let name = frMonth(month) else { return "Idées pour \(moment)" }
        return "Idées pour \(moment) · \(name)"
    }

    /// Noms de mois en français, en minuscules — ceux du système, pas une liste
    /// recopiée. Statique : un `DateFormatter` coûte cher à construire et le titre est
    /// recalculé à chaque passe de rendu.
    private static let monthNames: [String] = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter.standaloneMonthSymbols ?? []
    }()

    static func frMonth(_ month: Int) -> String? {
        guard month >= 1, month <= monthNames.count else { return nil }
        return monthNames[month - 1]
    }

    /// L'état du frigo pour une recette. Un CONSTAT, jamais un reproche (règle v1
    /// §7.4) : on ne dit pas ce qu'il faut aller acheter, on dit ce qu'on voit.
    ///
    /// `nil` quand le frigo est vide, et c'est la seule des trois branches qui ait
    /// demandé une décision : « il manque 4 » compterait alors ce qu'on IGNORE, pas ce
    /// qui manque — chaque ingrédient est réputé absent faute d'avoir été coché. La
    /// carte se tait donc, et la carte d'invitation 🧺 en bout de bande dit ce qu'il
    /// y a à faire. C'est aussi ce que la fiche recette fait déjà de son côté.
    static func frPantryState(missingCount: Int, pantryIsEmpty: Bool) -> String? {
        guard !pantryIsEmpty else { return nil }
        return missingCount == 0 ? "Tu as tout ✓" : "Il manque \(missingCount)"
    }

    /// Ce que VoiceOver lit d'une carte. L'emoji est décoratif, et il n'y a pas de
    /// préfixe (« Idée : … ») : la bande est titrée juste au-dessus, et un préfixe de
    /// plus est ce qui a cassé deux tests d'interface au lot A.
    static func frCardLabel(name: String, kcal: Int, missingCount: Int,
                            pantryIsEmpty: Bool) -> String {
        let head = "\(name), environ \(kcal) kcal"
        guard let state = frPantryState(missingCount: missingCount,
                                        pantryIsEmpty: pantryIsEmpty) else { return head }
        return "\(head), \(state)"
    }

    /// Lignes accordées au titre d'une carte. DEUX aux tailles ordinaires (« Soupe
    /// poireaux-pommes de terre » y tient), QUATRE aux tailles d'accessibilité : la
    /// carte y est deux fois plus large mais les mots y sont trois fois plus gros, et
    /// deux lignes rendaient « Gaspa-cho e… ».
    ///
    /// Statique et pure pour la même raison que `CalorieRing.showsBurnLegend(at:)` du
    /// lot C : c'est une décision, pas de la pose, et elle s'éprouve sans écran.
    static func titleLineLimit(at size: DynamicTypeSize) -> Int {
        size.isAccessibilitySize ? 4 : 2
    }

    // MARK: Gabarit des cartes

    /// La taille de texte courante décide de la LARGEUR d'une carte et du nombre de
    /// lignes de son titre. Voir `cardWidth` et `titleLineLimit(at:)`.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// 148 pt à la taille par défaut, mis à l'échelle du corps de texte : c'est la
    /// moitié du remède au débordement (l'autre moitié est la hauteur, plus bas). Une
    /// largeur figée à 148 pt tronquait le titre dès `accessibility-medium`, quelle
    /// que soit la hauteur qu'on lui laisse — un mot de dix lettres ne rentre pas dans
    /// 124 pt de contenu à 40 pt de corps.
    @ScaledMetric(relativeTo: .subheadline) private var scaledCardWidth: CGFloat = 148

    /// La largeur mise à l'échelle, PLAFONNÉE : au-delà, une carte ne tiendrait plus
    /// entière sur un iPhone (la bande en montre trois, il faut au moins en voir deux
    /// pour comprendre qu'elle défile) et le titre gagnerait en largeur ce qu'il
    /// perdrait en nombre d'idées visibles.
    private var cardWidth: CGFloat { min(scaledCardWidth, 240) }

    /// Hauteur PLANCHER, jamais plafond — c'est le correctif du débordement.
    ///
    /// Une hauteur imposée (`.frame(height: 132)`) ne rogne pas : le `VStack` prend sa
    /// hauteur idéale et DESSINE PAR-DESSUS le fond. Relevé au simulateur, frigo garni
    /// (donc avec la troisième ligne « Il manque N ») : dès `accessibility-medium`
    /// l'état du frigo disparaissait, dès `accessibility-large` les kcal étaient
    /// tracées à cheval sur le bord de la carte, et à `accessibility-XXL` il ne restait
    /// que l'emoji et un titre coupé. Or les kcal et l'état du frigo sont tout ce que
    /// la carte apporte de plus qu'un emoji, et VoiceOver ne perd rien de tout ça
    /// (`frCardLabel`) : le seul lésé était le gros texte SANS VoiceOver.
    ///
    /// Même remède que `StepsCard` (`maxHeight: .infinity` et aucune hauteur imposée) :
    /// les cartes gardent leur alignement entre elles parce que le `HStack` leur
    /// propose à toutes la hauteur de la plus haute.
    private static let cardMinHeight: CGFloat = 132

    /// Le châssis commun aux deux cartes — même largeur, même plancher de hauteur,
    /// même fond, même coin. Partagé et non recopié : le correctif de débordement
    /// ci-dessus est ainsi écrit UNE fois, et la carte d'invitation ne peut pas se
    /// mettre à déborder toute seule le jour où l'autre est réparée.
    private func cardShell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6, content: content)
            .frame(width: cardWidth, alignment: .topLeading)
            .frame(minHeight: Self.cardMinHeight, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
            .contentShape(Rectangle())
    }

    // MARK: Corps

    var body: some View {
        // Catalogue de recettes illisible, ou aucune candidate : la bande DISPARAÎT,
        // en entier, titre compris (spec §6.2). Un titre au-dessus d'un vide serait
        // pire que rien, et la carte d'invitation seule promettrait des idées qui ne
        // viendraient pas.
        //
        // Et elle disparaît JUSQUE DANS L'ESPACEMENT du journal, sans que celui-ci ait
        // à s'en occuper : un enfant de `VStack` dont le `body` ne rend rien ne
        // consomme pas non plus l'espacement de la pile. Vérifié à l'image, catalogue
        // de recettes vidé — le rendu est identique au pixel près à celui d'un journal
        // qui ne construirait pas la bande du tout.
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(Self.title(slot: framing.slot, month: framing.month))
                    .padding(.horizontal, 20)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(suggestions) { suggestion in
                            card(suggestion)
                        }
                        if pantryIsEmpty {
                            pantryCard
                        }
                    }
                    .padding(.horizontal, 20)
                    // Les cartes portent une ombre : sans cette marge, elle serait
                    // rognée par le bord du ScrollView.
                    .padding(.vertical, 4)
                }
                // Un ScrollView prend TOUTE la hauteur qu'on lui laisse, même
                // horizontal : sans cette ligne, la bande mangeait la moitié de
                // l'écran du journal et les cartes s'étiraient sur 400 pt (constaté au
                // simulateur). `fixedSize` la ramène à la hauteur de son contenu.
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Cartes

    private func card(_ suggestion: RecipeSuggestion) -> some View {
        let item = foods.byID[suggestion.recipe.itemID]
        return Button {
            onPick(suggestion)
        } label: {
            cardShell {
                Text(item?.emoji ?? "🥘")
                    .font(.system(size: 30))
                Text(item?.name ?? "Idée de repas")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.leading)
                    // Plus de lignes RÉSERVÉES (`reservesSpace:`) depuis que la hauteur
                    // est un plancher : les cartes se calent déjà sur la plus haute de
                    // la bande, et les kcal sont poussées en bas par le `Spacer`
                    // ci-dessous. Réserver en plus creusait un trou de deux lignes
                    // vides sous « Gaspacho » aux tailles d'accessibilité.
                    .lineLimit(Self.titleLineLimit(at: dynamicTypeSize))
                // Pousse kcal et état du frigo en bas de carte : elles s'alignent donc
                // d'une carte à l'autre, quel que soit le nombre de lignes du titre.
                Spacer(minLength: 0)
                Text("~\(suggestion.kcal.frFormatted) kcal")
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
                // Rien du tout quand le frigo est vide : la carte ne compte pas ce
                // qu'elle ignore. La carte ne rétrécit pas pour autant, sa hauteur a
                // un plancher (voir `cardMinHeight`).
                if let state = Self.frPantryState(missingCount: suggestion.missingCount,
                                                  pantryIsEmpty: pantryIsEmpty) {
                    Text(state)
                        .font(.caption2.weight(.semibold))
                        // Vert quand tout est là, sinon la couleur du texte secondaire :
                        // « il manque 2 » n'est pas un avertissement, et surtout jamais
                        // du rouge (règle v1 §7.4).
                        .foregroundStyle(suggestion.hasEverything ? Theme.green : Theme.subtext)
                }
            }
            .shadow(color: Theme.shadow, radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.frCardLabel(
            name: item?.name ?? "Idée de repas", kcal: suggestion.kcal,
            missingCount: suggestion.missingCount, pantryIsEmpty: pantryIsEmpty))
    }

    /// Carte finale tant que le frigo est vide (spec §6.5). Elle vient APRÈS les
    /// idées, pas avant : la bande doit marcher sans frigo, et le premier écran ne se
    /// paie pas d'un formulaire.
    private var pantryCard: some View {
        Button {
            onOpenPantry()
        } label: {
            cardShell {
                Text("🧺")
                    .font(.system(size: 30))
                Text("Dis-moi ce que tu as")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.leading)
                    .lineLimit(Self.titleLineLimit(at: dynamicTypeSize))
                Spacer(minLength: 0)
                Text("Les idées se classeront selon ton frigo.")
                    .font(.caption2)
                    .foregroundStyle(Theme.subtext)
                    .multilineTextAlignment(.leading)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Theme.orange.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dis-moi ce que tu as. Les idées se classeront selon ton frigo.")
    }
}

// MARK: - Preview

#Preview("Bande d'idées") {
    let foods = try! FoodCatalog.load()
    let recipes = try! RecipeCatalog.load()
    let calendar = Calendar(identifier: .gregorian)
    let suggestions = RecipeSuggester.suggestions(
        date: .now, slot: .dinner, pantry: ["potato", "egg", "tomato"],
        recipes: recipes, foods: foods, calendar: calendar
    )
    return VStack(alignment: .leading, spacing: 20) {
        RecipeStrip(suggestions: suggestions,
                    framing: RecipeStrip.Framing(slot: .dinner, month: 8),
                    foods: foods, pantryIsEmpty: false,
                    onPick: { _ in }, onOpenPantry: {})
        // Frigo vide : les cartes se taisent sur ce qui manque, et la carte
        // d'invitation ferme la bande.
        RecipeStrip(suggestions: suggestions,
                    framing: RecipeStrip.Framing(slot: .lunch, month: 1),
                    foods: foods, pantryIsEmpty: true,
                    onPick: { _ in }, onOpenPantry: {})
    }
    .fontDesign(.rounded)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.background)
}
