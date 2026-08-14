// Reminders.swift
// Catalogue et formatage des rappels (spec v1.9 §4). Remplace les quatre cas en dur
// de NotificationService : le programme posture (v1.11) puis le programme muscu
// (v1.14 §4.4) y ont ajouté une entrée chacun, et rien d'autre.
//
// Catalogue en dur (Swift), contrairement à `dishes`/`activities`/`sessions`/`quests`/
// `badges` qui viennent de JSON via `Catalogs` : un `MessageContext` en JSON troquerait
// une erreur de compilation contre un identifiant en chaîne qui échoue silencieusement
// en release, et ces valeurs sont épinglées par design, pas du contenu éditorial
// à ajuster sans recompiler.

import Foundation

/// Les programmes optionnels, chacun derrière son interrupteur par téléphone :
/// `posture` (v1.11) et `muscu` (v1.14 §4.4). Un cas ici n'est pas un rappel de plus,
/// c'est un programme de plus dont un rappel peut dépendre.
///
/// `CaseIterable` n'est pas décoratif : les tests s'en servent pour dire "tout allumé"
/// sans coder la liste en dur, sans quoi un troisième programme laisserait toute la
/// batterie du planificateur tourner avec lui éteint, sans qu'aucun test ne bronche.
public enum ReminderPlan: String, Codable, CaseIterable, Sendable { case posture, muscu }

public struct ReminderDefinition: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let defaultHour: Int
    public let defaultMinute: Int
    /// Convention `Calendar` : 1 = dimanche … 7 = samedi. nil = tous les jours.
    public let defaultWeekday: Int?
    /// Seuls les rappels hebdomadaires laissent choisir leur jour.
    ///
    /// Le drapeau va donc TOUJOURS avec un `defaultWeekday` concret. Le porter sur un
    /// rappel quotidien (`defaultWeekday: nil`) casserait l'écran de réglage : le
    /// planificateur notifierait tous les jours, mais `weekdayBinding` retombe sur 1
    /// faute de valeur et les Réglages annonceraient "dim." ; et le `Picker`, qui itère
    /// `weekdayRange` sans option "tous les jours", rendrait le rappel réellement
    /// hebdomadaire au premier tap de quelqu'un venu regarder.
    public let isWeekdayEditable: Bool
    public let context: MessageContext
    /// Programme dont un rappel dépend (spec v1.11 §3, v1.14 §4.4). `nil` = rappel
    /// ordinaire, toujours visible.
    ///
    /// Généralisé depuis le booléen `requiresPosturePlan` de la v1.11 : la 1.14
    /// apporte un second programme, et deux booléens auraient dédoublé chaque
    /// signature. La règle, elle, ne change pas d'un iota : un rappel de programme
    /// ne doit jamais apparaître dans les Réglages tant que son programme est
    /// éteint, sinon (a) une ligne visible en plus casse la promesse "rien ne
    /// change chez toi", et (b) n'importe qui peut l'allumer sans avoir jamais vu
    /// le programme, et le laisser sonner en silence.
    public let requiresPlan: ReminderPlan?

    public init(id: String, title: String, defaultHour: Int, defaultMinute: Int,
                defaultWeekday: Int?, isWeekdayEditable: Bool, context: MessageContext,
                requiresPlan: ReminderPlan?) {
        self.id = id
        self.title = title
        self.defaultHour = defaultHour
        self.defaultMinute = defaultMinute
        self.defaultWeekday = defaultWeekday
        self.isWeekdayEditable = isWeekdayEditable
        self.context = context
        self.requiresPlan = requiresPlan
    }

    public var defaultMinutesFromMidnight: Int { defaultHour * 60 + defaultMinute }

    /// Un rappel ordinaire est toujours disponible ; un rappel de programme l'est
    /// seulement quand SON programme est allumé sur ce téléphone.
    ///
    /// Extrait plutôt que recopié dans `ReminderCatalog.visibleReminders` et
    /// `ReminderPlanner.planned`, pour la raison que ce fichier a déjà tranchée au sujet
    /// de `resolvedMinutes`/`resolvedWeekday` : une seule règle, jamais deux qui
    /// pourraient diverger. L'enjeu est même plus lourd ici qu'un affichage — les deux
    /// portes forment ENSEMBLE la garantie qu'un rappel ne sonne pas pour un programme
    /// invisible, et n'en corriger qu'une un jour la romprait en silence.
    public func isAvailable(with enabledPlans: Set<ReminderPlan>) -> Bool {
        requiresPlan.map(enabledPlans.contains) ?? true
    }
}

public enum ReminderCatalog {
    public static let all: [ReminderDefinition] = [
        ReminderDefinition(id: "lunch", title: "Déjeuner", defaultHour: 12, defaultMinute: 30,
                           defaultWeekday: nil, isWeekdayEditable: false, context: .midday,
                           requiresPlan: nil),
        ReminderDefinition(id: "dinner", title: "Dîner", defaultHour: 20, defaultMinute: 0,
                           defaultWeekday: nil, isWeekdayEditable: false, context: .evening,
                           requiresPlan: nil),
        ReminderDefinition(id: "weigh", title: "Pesée", defaultHour: 9, defaultMinute: 0,
                           defaultWeekday: 7, isWeekdayEditable: true, context: .weighReminder,
                           requiresPlan: nil),
        ReminderDefinition(id: "steps", title: "Pas", defaultHour: 18, defaultMinute: 0,
                           defaultWeekday: nil, isWeekdayEditable: false, context: .stepsEncouragement,
                           requiresPlan: nil),
        // Programme posture (spec v1.11 §10) : 21 h et non 20 h 30, pour ne pas se coller
        // au rappel "Dîner" (20 h) — deux notifications collées se font ignorer toutes les
        // deux. Quotidien, jour non modifiable, comme "Pas". Naît éteint (clé absente de
        // `remindersEnabled`) tant que l'interrupteur du programme ne l'allume pas
        // explicitement. `requiresPlan: .posture` : sans lui la ligne apparaîtrait
        // dans les Réglages des DEUX téléphones, y compris celui où le programme est
        // resté éteint (voir `visibleReminders`).
        ReminderDefinition(id: "posture", title: "Posture", defaultHour: 21, defaultMinute: 0,
                           defaultWeekday: nil, isWeekdayEditable: false, context: .postureReminder,
                           requiresPlan: .posture),
        // Programme muscu maison (spec v1.14 §4.4) : 19 h, avant le rappel "Dîner" de
        // 20 h et bien après celui des "Pas" de 18 h, donc collé à aucun des deux.
        // Quotidien, jour non modifiable, exactement comme la posture : le programme est
        // une rotation de cinq séances PAR JOUR, qu'un rappel hebdomadaire contredirait.
        // Naît éteint (clé absente de `remindersEnabled`) tant que l'interrupteur du
        // programme ne l'allume pas explicitement.
        ReminderDefinition(id: "muscu", title: "Muscu", defaultHour: 19, defaultMinute: 0,
                           defaultWeekday: nil, isWeekdayEditable: false, context: .muscuReminder,
                           requiresPlan: .muscu),
    ]

    public static func definition(id: String) -> ReminderDefinition? {
        all.first { $0.id == id }
    }

    /// Rappels à AFFICHER dans les Réglages (spec v1.11 §3, §10 ; v1.14 §4.4), filtrés
    /// du catalogue complet : un rappel de programme ne doit apparaître QUE si SON
    /// programme est allumé, exactement comme `QuestEngine.weeklyDraw` filtre les
    /// quêtes `requiresPosture` sur `postureAvailable`. Les deux programmes sont
    /// indépendants : allumer la muscu ne fait pas apparaître la ligne posture. Pur et
    /// testable sans vue : la garde vit ici, pas dans `SettingsView+Reminders`.
    public static func visibleReminders(enabledPlans: Set<ReminderPlan>) -> [ReminderDefinition] {
        all.filter { $0.isAvailable(with: enabledPlans) }
    }
}

public enum ReminderSchedule {
    public static let minutesRange = 0...1439
    public static let weekdayRange = 1...7

    /// Inverse de `ReminderDefinition.defaultMinutesFromMidnight`. Arithmétique pure
    /// (aucun `Calendar`) : le lot D (réglage utilisateur) y range ses minutes stockées,
    /// le lot E (écran de réglage) en tire l'heure et la minute à afficher.
    ///
    /// Écrêtage sur `minutesRange` avant division : `ReminderPlanner` filtre déjà les
    /// valeurs hors plage en amont, mais cette fonction est publique et un futur appelant
    /// moins prudent ne doit jamais obtenir une paire incohérente (heure 24, minute
    /// négative...). Sans écrêtage, -30 donnerait (0, -30) et 1440 donnerait (24, 0) :
    /// ni l'un ni l'autre n'est une heure valide.
    public static func hourMinute(fromMinutesFromMidnight minutes: Int) -> (hour: Int, minute: Int) {
        let clamped = min(max(minutes, minutesRange.lowerBound), minutesRange.upperBound)
        return (hour: clamped / 60, minute: clamped % 60)
    }

    private static let longNames = ["dimanche", "lundi", "mardi", "mercredi",
                                    "jeudi", "vendredi", "samedi"]
    private static let shortNames = ["dim.", "lun.", "mar.", "mer.",
                                     "jeu.", "ven.", "sam."]

    /// « tous les jours à 12 h 30 », « le samedi à 9 h ». Minutes omises à zéro,
    /// sur deux chiffres sinon. Aucun tiret cadratin (règle v1.2).
    public static func frLabel(hour: Int, minute: Int, weekday: Int?) -> String {
        let time = minute == 0 ? "\(hour) h" : String(format: "%d h %02d", hour, minute)
        guard let weekday, weekdayRange.contains(weekday) else {
            return "tous les jours à \(time)"
        }
        return "le \(longNames[weekday - 1]) à \(time)"
    }

    /// Fréquence seule, pour le sous-titre de la ligne de réglage.
    public static func frFrequency(weekday: Int?) -> String {
        weekday == nil ? "tous les jours" : "chaque semaine"
    }

    /// Libellé court du menu de sélection du jour.
    public static func frShortWeekday(_ weekday: Int) -> String {
        guard weekdayRange.contains(weekday) else { return "" }
        return shortNames[weekday - 1]
    }

    // MARK: Résolution surcharge / défaut
    //
    // Règle UNIQUE (spec v1.9 §4.3) utilisée à la fois par `ReminderPlanner.planned`
    // (ce qui sera réellement notifié) et par l'écran de réglage (ce qui est affiché).
    // Avant, les deux la réimplémentaient chacun de leur côté ; un divergence entre
    // les deux aurait affiché une heure et sonné à une autre.

    /// Surcharge du profil si elle est dans les bornes, défaut du catalogue sinon.
    /// Une surcharge hors bornes est ÉCARTÉE, pas conservée : un réglage corrompu ne
    /// doit jamais faire disparaître un rappel actif ni afficher une heure absurde.
    public static func resolvedMinutes(_ stored: Int?, for definition: ReminderDefinition) -> Int {
        stored.flatMap { minutesRange.contains($0) ? $0 : nil }
            ?? definition.defaultMinutesFromMidnight
    }

    /// Court-circuit sur `isWeekdayEditable` : un rappel quotidien ne consulte JAMAIS
    /// la surcharge de jour, même si une clé traîne dans le dictionnaire (résidu d'un
    /// ancien réglage, bug amont...). Sans ce court-circuit une clé périmée pourrait
    /// rendre hebdomadaire un rappel qui doit rester quotidien.
    public static func resolvedWeekday(_ stored: Int?, for definition: ReminderDefinition) -> Int? {
        guard definition.isWeekdayEditable else { return definition.defaultWeekday }
        return stored.flatMap { weekdayRange.contains($0) ? $0 : nil }
            ?? definition.defaultWeekday
    }
}

/// Ce qu'il faut réellement planifier, une fois les réglages du profil appliqués.
public struct PlannedReminder: Equatable, Sendable {
    public let id: String
    public let hour: Int
    public let minute: Int
    public let weekday: Int?
    public let context: MessageContext

    // Init public explicite, comme les autres structs publiques du module : sans lui
    // le memberwise init reste internal et la cible app ne peut pas en construire un
    // (fixture de test, preview).
    public init(id: String, hour: Int, minute: Int, weekday: Int?, context: MessageContext) {
        self.id = id
        self.hour = hour
        self.minute = minute
        self.weekday = weekday
        self.context = context
    }
}

public enum ReminderPlanner {
    /// Itère sur le CATALOGUE, pas sur les dictionnaires : les identifiants inconnus
    /// y sont donc naturellement ignorés. Toute valeur aberrante retombe sur le défaut
    /// du catalogue, jamais sur une disparition du rappel. La résolution surcharge /
    /// défaut vit dans `ReminderSchedule.resolvedMinutes`/`resolvedWeekday`, partagée
    /// avec l'écran de réglage : une seule règle, jamais deux qui pourraient diverger.
    /// - Parameter enabledPlans: les programmes allumés sur CE téléphone. Un rappel qui
    ///   exige un programme absent de l'ensemble n'est JAMAIS planifié, quoi que dise
    ///   `enabled`. Ceinture et bretelles voulues : masquer la ligne dans les Réglages
    ///   suffit aujourd'hui, mais cela ferait dépendre d'un écran la garantie qu'un
    ///   rappel ne sonne pas pour un programme invisible. Une clé restée à true, ou une
    ///   future surface de réglage qui écrirait le dictionnaire, ne doit pas pouvoir
    ///   réveiller ce rappel.
    public static func planned(enabled: [String: Bool],
                               times: [String: Int],
                               weekdays: [String: Int],
                               enabledPlans: Set<ReminderPlan>) -> [PlannedReminder] {
        ReminderCatalog.all.compactMap { definition -> PlannedReminder? in
            guard enabled[definition.id] == true else { return nil }
            guard definition.isAvailable(with: enabledPlans) else { return nil }

            let minutes = ReminderSchedule.resolvedMinutes(times[definition.id], for: definition)
            let weekday = ReminderSchedule.resolvedWeekday(weekdays[definition.id], for: definition)

            let time = ReminderSchedule.hourMinute(fromMinutesFromMidnight: minutes)
            return PlannedReminder(id: definition.id,
                                   hour: time.hour, minute: time.minute,
                                   weekday: weekday, context: definition.context)
        }
    }
}
