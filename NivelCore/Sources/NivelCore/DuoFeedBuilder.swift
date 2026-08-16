// NivelCore/Sources/NivelCore/DuoFeedBuilder.swift
// Construction du fil du jour publié vers le partenaire (spec 1.15 §3.4).
//
// Ce fichier ne connaît NI SwiftData NI CloudKit : il prend des valeurs simples, que
// l'app lui fournit en projetant `MealEntry` et `ActivityEntry`. C'est ce qui le rend
// éprouvable en une fraction de seconde, sans simulateur, sans magasin et sans nuage —
// et c'est le même partage des rôles que `BurnCalculator`, qui reçoit des `BurnEntry`
// plutôt que les modèles persistants eux-mêmes.
//
// Il porte la décision centrale du duo : `title` et `subtitle` sont composés ICI, à la
// publication, chez celui qui possède les catalogues. Le partenaire n'a plus qu'à
// afficher. Une entrée de catalogue que sa version de l'app ignore reste donc lisible
// chez lui, au lieu de laisser un trou.

import Foundation

/// Ce que le constructeur a besoin de savoir d'un repas. Volontairement pas
/// `MealEntry` : le paquet ne connaît pas SwiftData.
public struct MealFeedInput: Equatable, Sendable {
    /// Vide pour toute entrée d'avant la 1.15 ; `assignMissingIDs` s'en occupe.
    public let publicID: String
    public let date: Date
    public let slot: MealSlot
    /// Déjà résumé par `MealFormatting.frSummary` : le catalogue d'aliments est
    /// résolu avant d'arriver ici, jamais chez le partenaire.
    public let title: String
    public let kcal: Int
    /// Chiffre saisi à la main plutôt qu'estimé : décide du tilde.
    public let isManual: Bool

    public init(publicID: String, date: Date, slot: MealSlot, title: String,
                kcal: Int, isManual: Bool) {
        self.publicID = publicID
        self.date = date
        self.slot = slot
        self.title = title
        self.kcal = kcal
        self.isManual = isManual
    }
}

/// Ce que le constructeur a besoin de savoir d'une activité validée.
public struct ActivityFeedInput: Equatable, Sendable {
    public let publicID: String
    public let date: Date
    /// Nom de l'activité ou de la séance, déjà résolu depuis le catalogue.
    public let title: String
    public let durationMinutes: Int
    public let xp: Int

    public init(publicID: String, date: Date, title: String,
                durationMinutes: Int, xp: Int) {
        self.publicID = publicID
        self.date = date
        self.title = title
        self.durationMinutes = durationMinutes
        self.xp = xp
    }
}

/// Les identifiants qu'il reste à écrire, par POSITION dans les tableaux passés à
/// `assignMissingIDs`. La position est la seule identité disponible : une entrée dont
/// le `publicID` est vide n'a, par définition, rien d'autre pour la désigner.
///
/// L'appelant applique `meals[i]` à son i-ᵉ repas, `activities[j]` à sa j-ᵉ activité,
/// puis sauvegarde. Une clé absente veut dire « celle-ci a déjà son identifiant, n'y
/// touche pas » — et c'est une distinction qui compte, voir `assignMissingIDs`.
public struct MissingIDAssignment: Equatable, Sendable {
    public let meals: [Int: String]
    public let activities: [Int: String]

    public var isEmpty: Bool { meals.isEmpty && activities.isEmpty }

    public init(meals: [Int: String], activities: [Int: String]) {
        self.meals = meals
        self.activities = activities
    }
}

public enum DuoFeedBuilder {

    /// Le fil du jour, repas et activités entremêlés, du matin au soir.
    public static func build(meals: [MealFeedInput],
                             activities: [ActivityFeedInput]) -> [DuoEvent] {
        let evenements =
            meals.map { repas in
                DuoEvent(id: repas.publicID, kind: .meal, at: repas.date,
                         title: repas.title,
                         subtitle: "\(repas.slot.frLabel), "
                             + MealFormatting.frKcal(repas.kcal, isManual: repas.isManual))
            }
            + activities.map { activite in
                // Une activité qui ne rapporte rien ne l'annonce pas : le sous-titre
                // s'arrête à la durée. `XPEngine.award` plafonne `activityDone` à deux
                // fois par jour, donc la TROISIÈME marche d'une journée vaut réellement
                // 0 XP — le cas n'a rien de théorique. Publier « +0 XP » reviendrait à
                // annoncer à l'autre, sur sa page de profil, que ce qu'il vient de faire
                // n'a rien valu. Le plafond est un garde-fou d'économie de jeu, pas un
                // jugement sur l'effort, et la règle zéro culpabilisation de la v1 pèse
                // ici plus lourd qu'ailleurs puisque le reproche serait lu par quelqu'un
                // d'autre que soi.
                //
                // Pas de tiret cadratin non plus : c'est du texte affiché, et la virgule
                // fait le travail.
                let duree = "\(activite.durationMinutes) min"
                return DuoEvent(id: activite.publicID, kind: .activity, at: activite.date,
                                title: activite.title,
                                subtitle: activite.xp == 0 ? duree
                                    : "\(duree), +\(activite.xp) XP")
            }

        // Tri chronologique croissant : c'est une JOURNÉE qu'on relit du matin au soir,
        // pas un fil d'actualité qui remonterait le plus récent en tête.
        //
        // Le rang sert de départage, et il n'est pas décoratif. `sorted(by:)` n'est PAS
        // garanti stable en Swift : à heure égale — un encas validé dans la même minute
        // qu'une séance, ce qui arrive — l'ordre pourrait changer d'un appel à l'autre
        // pour un contenu identique. `DuoSnapshot ==` compare `events`, donc la
        // publication conclurait « ça a changé » et écrirait dans iCloud à chaque
        // passage, possiblement en alternant sans fin entre deux ordres. Décorer d'un
        // rang rend le tri total et déterministe : les repas d'abord, puis les
        // activités, chacun dans l'ordre reçu.
        return evenements.enumerated()
            .sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }
            .map(\.element)
    }

    /// Attribue un identifiant aux seules entrées qui n'en ont pas encore, et le REND
    /// plutôt que de l'écrire : cette fonction est pure, c'est l'appelant qui persiste.
    ///
    /// Deux règles, opposées et également indispensables :
    ///
    /// - une entrée vide reçoit un identifiant **qui n'est qu'à elle**. `newID` est
    ///   rappelé à chaque fois, jamais hissé hors de la boucle : deux entrées qui
    ///   partageraient une identité partageraient leurs cœurs, et c'est précisément
    ///   l'accident que la sentinelle vide de la 1.15 évitait à la migration ;
    /// - une entrée déjà identifiée n'est **jamais** réattribuée. Un `DuoLike` désigne
    ///   son événement par cet identifiant et rien d'autre : le réécrire détacherait en
    ///   silence tous les cœurs déjà reçus sur ce repas.
    ///
    /// `newID` est injecté pour que les tests soient déterministes, et pour cette seule
    /// raison : en production, le défaut est le bon.
    public static func assignMissingIDs(
        meals: [MealFeedInput],
        activities: [ActivityFeedInput],
        newID: () -> String = { UUID().uuidString }
    ) -> MissingIDAssignment {
        var pourLesRepas: [Int: String] = [:]
        for (rang, repas) in meals.enumerated() where repas.publicID.isEmpty {
            pourLesRepas[rang] = newID()
        }
        var pourLesActivites: [Int: String] = [:]
        for (rang, activite) in activities.enumerated() where activite.publicID.isEmpty {
            pourLesActivites[rang] = newID()
        }
        return MissingIDAssignment(meals: pourLesRepas, activities: pourLesActivites)
    }
}
