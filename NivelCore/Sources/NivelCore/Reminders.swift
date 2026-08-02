// Reminders.swift
// Catalogue et formatage des rappels (spec v1.9 §4). Remplace les quatre cas en dur
// de NotificationService : le lot C (programme de Marion) ajoutera une entrée ici,
// et rien d'autre.

import Foundation

public struct ReminderDefinition: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let defaultHour: Int
    public let defaultMinute: Int
    /// Convention `Calendar` : 1 = dimanche … 7 = samedi. nil = tous les jours.
    public let defaultWeekday: Int?
    /// Seuls les rappels hebdomadaires laissent choisir leur jour.
    public let isWeekdayEditable: Bool
    public let context: MessageContext

    public init(id: String, title: String, defaultHour: Int, defaultMinute: Int,
                defaultWeekday: Int?, isWeekdayEditable: Bool, context: MessageContext) {
        self.id = id
        self.title = title
        self.defaultHour = defaultHour
        self.defaultMinute = defaultMinute
        self.defaultWeekday = defaultWeekday
        self.isWeekdayEditable = isWeekdayEditable
        self.context = context
    }

    public var defaultMinutesFromMidnight: Int { defaultHour * 60 + defaultMinute }
}

public enum ReminderCatalog {
    public static let all: [ReminderDefinition] = [
        ReminderDefinition(id: "lunch", title: "Déjeuner", defaultHour: 12, defaultMinute: 30,
                           defaultWeekday: nil, isWeekdayEditable: false, context: .midday),
        ReminderDefinition(id: "dinner", title: "Dîner", defaultHour: 20, defaultMinute: 0,
                           defaultWeekday: nil, isWeekdayEditable: false, context: .evening),
        ReminderDefinition(id: "weigh", title: "Pesée", defaultHour: 9, defaultMinute: 0,
                           defaultWeekday: 7, isWeekdayEditable: true, context: .weighReminder),
        ReminderDefinition(id: "steps", title: "Pas", defaultHour: 18, defaultMinute: 0,
                           defaultWeekday: nil, isWeekdayEditable: false, context: .stepsEncouragement),
    ]

    public static func definition(id: String) -> ReminderDefinition? {
        all.first { $0.id == id }
    }
}

public enum ReminderSchedule {
    public static let minutesRange = 0...1439
    public static let weekdayRange = 1...7

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
}
