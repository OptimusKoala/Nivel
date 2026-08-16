// App/Views/Home/CalorieRing.swift
// Anneau des calories du jour (spec §4.1) : mangé / objectif, restant mis en avant.
// Anneau intérieur : dépense du jour / cible de dépense (spec v1.14 §5.5).
// Dépassement = accent chaleureux + message neutre — JAMAIS de rouge (spec §2).

import SwiftUI

struct CalorieRingCard: View {
    let eaten: Int
    let target: Int
    /// Dépense estimée du jour — pas + sport non marché (spec v1.14 §5.4). INDICATIVE :
    /// elle n'est jamais créditée au budget alimentaire (règle v1 §2).
    let burned: Int
    let burnTarget: Int
    /// Prénom à mettre en tête du libellé d'accessibilité. `nil` sur l'accueil, où l'anneau
    /// parle de SOI et n'a personne à nommer ; renseigné sur la page du duo (spec 1.15
    /// §3.9), où VoiceOver doit dire « Marion, calories… » et non « Calories… ».
    ///
    /// Un paramètre plutôt qu'une seconde carte : la géométrie de cet anneau est mesurée au
    /// dixième de point et tenue par quatre constantes (lot B). En redessiner une divergerait
    /// au premier ajustement, et c'est justement l'anneau que les deux personnes comparent.
    var accessibilityOwner: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// La légende de dépense s'efface aux tailles d'ACCESSIBILITÉ (au-delà de
    /// `.xxxLarge`). Relevé à `.accessibility4` sur iPhone 17 Pro Max : la légende
    /// passe à trois lignes, le sous-titre entier en occupe cinq, la carte passe de
    /// 584 à 1 100 px de haut (près du DOUBLE, pas le quadruple qu'on lit parfois) et
    /// la ligne de quête finit sous la barre d'onglets.
    ///
    /// Le seuil retenu est celui du système, mais il flatte la réalité : à `.xxxLarge`
    /// la légende passe DÉJÀ à deux lignes, l'emoji seul sur la seconde. Elle n'y tient
    /// pas au large, elle passe tout juste — c'est le fait à regarder le jour où l'on
    /// se demandera s'il faut redescendre le seuil à `.xxLarge`.
    ///
    /// Le compromis, sans l'enjoliver. VoiceOver ne perd rien : l'anneau porte déjà
    /// « Dépensé : environ X sur Y » dans son `.accessibilityLabel` (voir `ring`), et
    /// ce libellé ne dépend pas de la taille de texte. Mais ce chiffre n'est visible
    /// NULLE PART ailleurs dans l'app — l'écran Progrès a trois sections (Poids,
    /// Calories mangées, Pas) et aucune ne montre la dépense en kcal ; `burnKcal` n'a
    /// que deux appelants, celui-ci et l'écriture du DayLog à la clôture, invisible.
    /// Donc quelqu'un qui grossit le texte SANS VoiceOver perd l'information pour de
    /// bon, et c'est précisément l'utilisateur que la forme visible du réglage sert.
    /// On échange ce chiffre contre la lisibilité du reste de l'accueil ; l'anneau
    /// orange, lui, reste tracé.
    static func showsBurnLegend(at size: DynamicTypeSize) -> Bool { !size.isAccessibilitySize }

    /// La même décision, appliquée à la taille courante. La statique existe pour le
    /// test, celle-ci pour la vue.
    private var showsBurnLegend: Bool { Self.showsBurnLegend(at: dynamicTypeSize) }

    /// Plafond de mise à l'échelle du SEUL contenu central de l'anneau (défaut antérieur
    /// à la 1.13, pas de la 1.14). La largeur de l'anneau est PLAFONNÉE à 130 pt — un
    /// `.frame(maxWidth:maxHeight:)`, donc un plafond et non une taille imposée : sous
    /// les 130 pt il rétrécit, au-dessus il ne suit pas. Le texte en son centre n'a donc
    /// aucune place garantie pour croître. Les deux bornes, relevées à l'image :
    /// - dès `.xLarge`, le gros chiffre « ~1 030 » mord déjà le tracé à gauche et à
    ///   droite — c'est CETTE borne qui fixe le plafond, pas la suivante ;
    /// - dès `.xxxLarge`, la seconde ligne « / 1 650 kcal » traverse le tracé en plus et
    ///   se tronque en « / 1 65… ».
    /// `.large` est donc la dernière taille où les DEUX lignes tiennent dans le disque
    /// intérieur — et le rendu y est celui de la taille par défaut.
    ///
    /// Rien n'est perdu pour l'assistance : le `ZStack` de `ring` est
    /// `.accessibilityElement(children: .ignore)` avec son propre libellé, donc VoiceOver
    /// ne lit jamais ces deux `Text`, et le libellé n'est pas mis à l'échelle. Ce plafond
    /// ne touche que le rendu graphique.
    static let centerTypeSizeCap: DynamicTypeSize = .large

    /// Largeur plafond de l'anneau. Déjà appliquée par le `.frame(maxWidth:maxHeight:)`
    /// de `ring` ; nommée ici pour que le test de géométrie puisse la lire. ATTENTION :
    /// c'est la largeur du CADRE, pas celle du `ZStack` — voir `ringOuterPadding`.
    static let ringMaxWidth: CGFloat = 130

    /// Épaisseur du trait de l'anneau extérieur (mangé / objectif).
    static let outerRingLineWidth: CGFloat = 12

    /// Épaisseur du trait de l'anneau intérieur (dépense). Plus fin que l'extérieur :
    /// c'est l'information secondaire de la carte.
    static let innerRingLineWidth: CGFloat = 8

    /// Écart entre les deux anneaux. Il pilote le diamètre du disque blanc central,
    /// donc la place réellement offerte au texte : l'augmenter RÉTRÉCIT le centre.
    static let innerRingPadding: CGFloat = 14

    /// Marge extérieure de l'anneau. Le trait est centré sur le cercle géométrique, il
    /// déborde donc de sa moitié — d'où la dérivation plutôt qu'un 6 recopié : si un
    /// jour le trait change d'épaisseur, la marge suit toute seule.
    ///
    /// Mais elle est posée AVANT le `.frame(maxWidth:)`, donc elle ne s'ajoute pas
    /// autour des 130 pt : elle les RETRANCHE. Le `ZStack` ne reçoit que 118 pt, et
    /// tout ce qui se calcule à l'intérieur (le cercle de dépense, le disque blanc,
    /// la place du texte) part de 118 et non de 130. C'est le piège de ce bloc : la
    /// 1.15 s'est trompée de 12 pt en le lisant, et la 1.14 avant elle.
    static let ringOuterPadding: CGFloat = outerRingLineWidth / 2

    /// Taille du gros chiffre. 26 pt jusqu'à la 1.14 : « ~1 240 » y mordait le tracé.
    /// La borne assumée est QUATRE chiffres (spec 1.15 §4), pas davantage.
    ///
    /// Ce que la descente à 22 achète exactement : à quatre chiffres le texte est de
    /// toute façon RÉDUIT par `centerMinimumScaleFactor` (voir plus bas), et à 26 pt il
    /// tenait déjà. Elle n'évite donc pas la réduction, elle éloigne du PLANCHER de
    /// réduction — 0,88 de facteur requis au lieu de 0,74, contre un plancher à 0,70.
    /// C'est cette réserve qui la justifie, et c'est elle que teste
    /// `CalorieRingCenterTests`, pas la taille elle-même.
    static let centerFontSize: CGFloat = 22

    /// Rembourrage horizontal du bloc central. 14 pt jusqu'à la 1.14, ce qui laissait
    /// 90 pt de large à un texte dont le disque blanc n'en offre que 73,6 à la hauteur
    /// du gros chiffre. C'est LA cause du débordement : le texte avait le droit d'être
    /// plus large que le cercle censé le contenir. Voir CalorieRingCenterTests pour la
    /// géométrie.
    static let centerHorizontalPadding: CGFloat = 24

    /// Plancher de réduction du texte central. À quatre chiffres il travaille pour de
    /// bon (le gros chiffre est rendu autour de 19 pt, pas 22) : ce n'est pas un filet
    /// de secours, c'est le mécanisme qui fait tenir le texte. Descendre plus bas
    /// rendrait le chiffre illisible, donc on garde de la réserve au-dessus.
    static let centerMinimumScaleFactor: CGFloat = 0.7

    private var isOver: Bool { target > 0 && eaten > target }
    private var fraction: Double {
        guard target > 0 else { return 0 }
        return min(1, Double(eaten) / Double(target))
    }

    private var burnFraction: Double {
        guard burnTarget > 0 else { return 0 }
        return min(1, Double(burned) / Double(burnTarget))
    }
    private var burnReached: Bool { burnTarget > 0 && burned >= burnTarget }

    var body: some View {
        VStack(spacing: 10) {
            ring
            subtitle
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .card()
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Theme.track, lineWidth: Self.outerRingLineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(isOver ? Theme.accent : Theme.green,
                        style: StrokeStyle(lineWidth: Self.outerRingLineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            // Anneau de dépense (spec §5.5), rayon de tracé 45 contre 59 à l'extérieur
            // (le padding de 14 sur les 118 pt du ZStack — le plafond de 130 moins
            // `ringOuterPadding` de chaque côté, et non 130). `Theme.orange`
            // et NON `Theme.accent` : l'anneau extérieur passe à `accent` en cas de
            // dépassement calorique, et les deux cercles deviendraient alors
            // indistinguables — précisément les jours où l'on regarde la carte de près.
            // (La façade `Theme` n'expose pas `primary` : c'est `Theme.orange` qui
            // porte `palette.primary`.)
            Circle()
                .stroke(Theme.track, lineWidth: Self.innerRingLineWidth)
                .padding(Self.innerRingPadding)
            Circle()
                .trim(from: 0, to: burnFraction)
                .stroke(Theme.orange,
                        style: StrokeStyle(lineWidth: Self.innerRingLineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(Self.innerRingPadding)
            // Le centre ne change pas : le chiffre qu'on vient chercher reste le mangé,
            // en grand (spec §5.5).
            VStack(spacing: 2) {
                // "~" : le total mangé est une somme d'estimations (spec §13).
                Text("~\(eaten.frFormatted)")
                    .font(.system(size: Self.centerFontSize, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .minimumScaleFactor(Self.centerMinimumScaleFactor)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                // Pas de "~" sur l'objectif : c'est un budget fixé, pas une estimation
                // (cohérent avec le journal Repas et le graphe calories).
                Text("/ \(target.frFormatted) kcal")
                    .font(.caption2)
                    .foregroundStyle(Theme.subtext)
            }
            .padding(.horizontal, Self.centerHorizontalPadding)
            .dynamicTypeSize(...Self.centerTypeSizeCap)
        }
        // Un log/édition de repas anime l'anneau et fait défiler le compteur
        // (contentTransition numérique) au lieu de sauter d'une valeur à l'autre.
        .animation(.snappy, value: eaten)
        // Même raison pour la dépense : les pas arrivent APRÈS le premier rendu
        // (lecture HealthKit asynchrone), l'anneau intérieur se remplit au lieu de
        // sauter d'un coup.
        .animation(.snappy, value: burned)
        .padding(Self.ringOuterPadding) // le trait (12 pt) déborde du cercle géométrique
        .frame(maxWidth: Self.ringMaxWidth, maxHeight: Self.ringMaxWidth)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
    }

    /// Le libellé lu par VoiceOver, préfixé du prénom quand l'anneau parle de quelqu'un
    /// d'autre. La ponctuation change avec : « Marion, calories : … ».
    private var accessibilityLabelText: String {
        let chiffres = "Calories : environ \(eaten) sur \(target). Dépensé : environ \(burned) sur \(burnTarget)"
        guard let accessibilityOwner, !accessibilityOwner.isEmpty else { return chiffres }
        return "\(accessibilityOwner), " + chiffres.prefix(1).lowercased() + chiffres.dropFirst()
    }

    /// Le sous-titre porte les DEUX lignes (reste à manger + dépense) : la légende de
    /// dépense se fond dans le sous-titre existant plutôt que de s'ajouter comme
    /// troisième enfant de la carte (qui aurait coûté 10 pt d'interligne de plus) — la
    /// 1.13 s'est battue pour chaque point de hauteur (spec §5.5).
    @ViewBuilder private var subtitle: some View {
        VStack(spacing: 3) {
            if isOver {
                Text("Objectif dépassé de ~\((eaten - target).frFormatted), ça arrive 😌")
                    .foregroundStyle(Theme.subtext)
            } else {
                HStack(spacing: 4) {
                    Text("Reste ~\(max(0, target - eaten).frFormatted) kcal")
                    CozyIcon(name: "tab_meals", size: 15)
                }
                .foregroundStyle(Theme.green)
            }
            if showsBurnLegend {
                HStack(spacing: 4) {
                    // La pastille rappelle la couleur de l'anneau intérieur : sans elle,
                    // rien ne dit lequel des deux cercles la ligne commente.
                    Circle().fill(Theme.orange).frame(width: 7, height: 7)
                    // Jamais de reproche au-delà de l'objectif : on a bougé plus que prévu,
                    // il n'y a rien à redire (spec §5.5, aucun rouge non plus ici).
                    Text(burnReached
                         ? "Objectif de dépense atteint 🎉"
                         : "Dépensé ~\(burned.frFormatted) / \(burnTarget.frFormatted)")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.subtext)
            }
        }
    }
}

#Preview("Sous l'objectif") {
    CalorieRingCard(eaten: 1240, target: 2000, burned: 180, burnTarget: 400)
        .frame(width: 210, height: 210)
        .padding()
        .background(Theme.background)
}

#Preview("Dépassé (jamais rouge)") {
    // Dépassement des DEUX objectifs : l'anneau extérieur passe à `Theme.accent`,
    // c'est le cas où l'intérieur ne doit surtout pas prendre la même couleur.
    CalorieRingCard(eaten: 2350, target: 2000, burned: 520, burnTarget: 400)
        .frame(width: 210, height: 210)
        .padding()
        .background(Theme.background)
}

#Preview("Pire cas, 4 chiffres") {
    // La BORNE de la spec 1.15 §4, figée pour qu'on la voie au lieu de la supposer :
    // quatre chiffres aux quatre valeurs, soit la combinaison la plus large que le
    // centre puisse avoir à afficher.
    //
    // L'anneau extérieur y reste VERT et non `accent` : `isOver` est `eaten > target`,
    // donc l'égalité n'est pas un dépassement. C'est voulu — le cas `accent` a déjà sa
    // prévisualisation juste au-dessus, et le pousser ici coûterait le cinquième
    // chiffre qu'on refuse justement de promettre.
    CalorieRingCard(eaten: 9_999, target: 9_999, burned: 9_999, burnTarget: 9_999)
        .frame(width: 210, height: 210)
        .padding()
        .background(Theme.background)
}
