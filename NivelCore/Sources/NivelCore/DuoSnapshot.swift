// NivelCore/Sources/NivelCore/DuoSnapshot.swift
// Les formes publiées par un membre du duo (spec 1.15 §3.3 et §3.4).
//
// AUCUN `import CloudKit` ici, et c'est délibéré : ces types décrivent CE QUI est
// publié, jamais COMMENT. Le contrat reste donc éprouvable sans nuage, sans compte
// iCloud et sans réseau — comme `WidgetSnapshot` décrit ce que l'app dépose dans
// l'App Group sans rien savoir de WidgetKit. Le transport (zone partagée, `CKShare`,
// `CKModifyRecordsOperation`) vit côté app, et lui seul.
//
// Le magasin SwiftData local reste la seule source de vérité : on ne miroite rien,
// on publie à côté un instantané reconstruit en entier à chaque changement.

import Foundation

/// La quête la plus avancée non terminée, telle qu'elle apparaît chez le partenaire.
/// Pas de `Quest` ni de `QuestProgress` ici : ces types portent des métriques et des
/// prérequis (`requiresPosture`, `requiresMuscu`…) qui ne regardent que l'app qui les
/// évalue, et le partenaire n'a besoin que d'un intitulé et d'une fraction.
public struct DuoQuestLine: Codable, Equatable, Sendable {
    public let title: String
    public let done: Int
    public let total: Int

    public init(title: String, done: Int, total: Int) {
        self.title = title
        self.done = done
        self.total = total
    }
}

/// Un événement du fil du jour : un repas ou une activité, tel qu'il s'affiche chez
/// le partenaire et tel qu'un cœur le désigne.
public struct DuoEvent: Codable, Equatable, Identifiable, Sendable {
    /// `String` brut, et pas un enum nu : le genre voyage en clair (« meal »,
    /// « activity ») et non en indice. Un enum sans type brut se coderait en 0 / 1,
    /// et l'insertion d'un cas entre les deux dans une version future transformerait
    /// tous les repas déjà publiés en activités chez qui lit.
    public enum Kind: String, Codable, Sendable {
        case meal, activity

        /// Second volet de la compatibilité ascendante (spec §3.4), et le plus important
        /// des deux. La règle « tout champ ajouté sera optionnel » ne couvre PAS les cas
        /// d'énumération, et le défaut qu'elle laisse est bien pire : mesuré, un seul
        /// `kind` inconnu fait échouer le décodage du TABLEAU ENTIER, pas du seul
        /// événement fautif. Une 1.16 qui publierait `kind: "weight"` viderait
        /// entièrement le fil chez un partenaire resté en 1.15, sans le moindre message.
        ///
        /// Le repli coûte presque rien, et c'est une conséquence heureuse d'une décision
        /// prise plus haut : `title` et `subtitle` étant calculés à la publication, un
        /// événement de genre inconnu reste parfaitement lisible et aimable — seule son
        /// icône est indéterminée, et l'affichage en prend une neutre. Le laisser tomber
        /// en silence serait strictement pire que le montrer sans son icône.
        ///
        /// Ce cas ne s'obtient qu'au DÉCODAGE : rien ne le publie jamais, puisque le fil
        /// est construit depuis les entrées locales, qui sont un repas ou une activité et
        /// rien d'autre. La règle vaut pour toute énumération qui voyagera entre les deux
        /// appareils.
        case unknown

        public init(from decoder: any Decoder) throws {
            let brut = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: brut) ?? .unknown
        }
    }

    /// Le `publicID` de l'entrée locale (spec §3.4). C'est LA cible d'un cœur : le
    /// `recordName` d'un `DuoLike` vaut `like-<giverID>-<eventID>`, donc cet
    /// identifiant doit rester stable quand le repas est modifié. Il l'est : seule
    /// la suppression de l'entrée le fait disparaître.
    public let id: String
    public let kind: Kind
    public let at: Date
    /// « Salade de lentilles », « Vélo tranquille ».
    ///
    /// `title` et `subtitle` sont calculés à la PUBLICATION, jamais à l'affichage, et
    /// c'est le point de conception de ce type. Le partenaire n'a aucune raison de
    /// posséder les mêmes catalogues : il peut tourner sur une version antérieure de
    /// l'app, où l'aliment ou l'activité en question n'existe pas encore. Publier un
    /// `refID` à résoudre chez lui afficherait un trou à chaque entrée récente ;
    /// publier le texte déjà composé l'affiche correctement, toujours.
    public let title: String
    /// « déjeuner, ~420 kcal », « 20 min, +30 XP ». Même règle que `title`.
    public let subtitle: String

    public init(id: String, kind: Kind, at: Date, title: String, subtitle: String) {
        self.id = id
        self.kind = kind
        self.at = at
        self.title = title
        self.subtitle = subtitle
    }
}

/// L'instantané complet d'un membre : ce que l'autre voit de sa journée, et rien de
/// plus. Le poids, la courbe de poids et les badges n'y sont pas, par décision de
/// conception (spec §3.1) — ils ne sont pas omis par oubli, ils sont exclus.
///
/// Les champs sont des `var` : un instantané est une valeur qu'on assemble puis qu'on
/// retouche par copie, et il ne protège aucun invariant.
public struct DuoSnapshot: Codable, Sendable {
    /// Les pas sont indisponibles tant que HealthKit n'a pas répondu, et indisponibles
    /// pour toujours s'il est refusé. Cette sentinelle porte les deux cas, en miroir de
    /// `DailySteps.unavailable` côté app : un `0` publié ferait afficher « 0 pas » à
    /// quelqu'un qui a marché toute la journée. Un `Int?` ferait l'affaire côté Swift,
    /// mais le champ est aussi un `Int(64)` d'enregistrement CloudKit (§3.3), et une
    /// valeur convenue traverse les deux représentations sans cas particulier.
    public static let stepsUnavailable = -1

    /// Identifiant stable de la personne ; c'est aussi le `recordName` de son
    /// enregistrement `DuoMember`.
    public var memberID: String
    public var name: String
    /// Choisit l'illustration `boy` ou `girl` chez le partenaire. Brut plutôt que typé :
    /// une valeur inconnue d'une version future doit arriver telle quelle et se replier
    /// à l'affichage, pas faire échouer le décodage de tout l'instantané.
    public var sexRaw: String

    /// Niveau et progression DÉJÀ CALCULÉS, jamais le seul `totalXP` à interpréter.
    /// Les deux téléphones peuvent tourner sur des versions différentes de l'app, donc
    /// sur deux courbes de niveaux différentes : la 1.14 en a fait l'expérience, et
    /// `levelCurveVersion` ne doit jamais être remise en cause. Publier le résultat
    /// plutôt que l'ingrédient met le duo à l'abri de cette divergence — le partenaire
    /// affiche « niveau 11, 140/220 » sans jamais rejouer le calcul avec SA courbe.
    /// `totalXP` reste publié, mais pour être montré tel quel, pas pour être converti.
    public var level: Int
    public var totalXP: Int
    public var xpIntoLevel: Int
    public var xpForNextLevel: Int

    /// Le jour de l'instantané, en `AAAA-MM-JJ`. Une chaîne et non une `Date` : c'est
    /// une étiquette de journée locale, et deux fuseaux ne doivent pas pouvoir la faire
    /// glisser d'un jour. Elle sert aussi à savoir si ce qu'on affiche est bien
    /// d'aujourd'hui — le fil ne couvre que le jour courant et se vide à minuit.
    public var dayKey: String

    /// Anneau extérieur (mangé / objectif) et anneau intérieur (dépensé / cible).
    public var kcalEaten: Int
    public var kcalTarget: Int
    public var burned: Int
    public var burnTarget: Int
    /// `stepsUnavailable` si les pas ne sont pas connus. Voir ci-dessus.
    public var steps: Int

    /// La quête la plus avancée non terminée, absente s'il n'y en a pas.
    public var quest: DuoQuestLine?
    /// Le fil du jour, de minuit à minuit, dans l'ordre où l'app le compose.
    public var events: [DuoEvent]

    /// Horodatage de publication, qui alimente la ligne « mis à jour il y a… ».
    /// EXCLU de l'égalité, voir `==`.
    public var generatedAt: Date

    public init(memberID: String, name: String, sexRaw: String,
                level: Int, totalXP: Int, xpIntoLevel: Int, xpForNextLevel: Int,
                dayKey: String,
                kcalEaten: Int, kcalTarget: Int, burned: Int, burnTarget: Int, steps: Int,
                quest: DuoQuestLine?, events: [DuoEvent], generatedAt: Date) {
        self.memberID = memberID
        self.name = name
        self.sexRaw = sexRaw
        self.level = level
        self.totalXP = totalXP
        self.xpIntoLevel = xpIntoLevel
        self.xpForNextLevel = xpForNextLevel
        self.dayKey = dayKey
        self.kcalEaten = kcalEaten
        self.kcalTarget = kcalTarget
        self.burned = burned
        self.burnTarget = burnTarget
        self.steps = steps
        self.quest = quest
        self.events = events
        self.generatedAt = generatedAt
    }
}

extension DuoSnapshot: Equatable {
    /// Égalité écrite à la main pour une seule raison : **`generatedAt` n'en fait pas
    /// partie**. C'est cette égalité que `DuoPublisher` interroge pour décider d'écrire
    /// dans iCloud (spec §3.5). Comparer l'horodatage rendrait chaque instantané
    /// différent du précédent par construction, et l'app écrirait à chaque retour au
    /// premier plan, à chaque validation, à chaque bascule de minuit — sans qu'aucun
    /// chiffre montré au partenaire ait bougé.
    ///
    /// Le revers : cette liste est à tenir à jour. Un champ ajouté et oublié ici serait
    /// publié une première fois puis jamais remis à jour, en silence. C'est exactement
    /// ce que `testChaqueChampCompteDansLEgaliteSaufLHorodatage` empêche, en confrontant
    /// les champs comparés à ceux que `Mirror` lit sur le type.
    public static func == (gauche: DuoSnapshot, droite: DuoSnapshot) -> Bool {
        gauche.memberID == droite.memberID
            && gauche.name == droite.name
            && gauche.sexRaw == droite.sexRaw
            && gauche.level == droite.level
            && gauche.totalXP == droite.totalXP
            && gauche.xpIntoLevel == droite.xpIntoLevel
            && gauche.xpForNextLevel == droite.xpForNextLevel
            && gauche.dayKey == droite.dayKey
            && gauche.kcalEaten == droite.kcalEaten
            && gauche.kcalTarget == droite.kcalTarget
            && gauche.burned == droite.burned
            && gauche.burnTarget == droite.burnTarget
            && gauche.steps == droite.steps
            && gauche.quest == droite.quest
            && gauche.events == droite.events
        // generatedAt : volontairement absent.
    }
}
