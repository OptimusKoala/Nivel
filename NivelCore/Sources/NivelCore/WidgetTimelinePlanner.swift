import Foundation

/// Une entrée de timeline pré-calculée, consommée telle quelle par l'extension
/// widget (spec widgets §4.2) — struct PURE, aucune dépendance UI.
public struct WidgetEntry: Equatable, Sendable {
    public enum Expression: Equatable, Sendable { case happy, sleepy }

    public let date: Date
    public let kcalEaten: Int
    public let kcalTarget: Int
    public let totalXP: Int
    /// Message de Nivelito, `{name}` déjà substitué.
    public let message: String
    public let expression: Expression
    public let themeID: String
    public let userName: String

    public init(date: Date, kcalEaten: Int, kcalTarget: Int, totalXP: Int,
                message: String, expression: Expression, themeID: String, userName: String) {
        self.date = date
        self.kcalEaten = kcalEaten
        self.kcalTarget = kcalTarget
        self.totalXP = totalXP
        self.message = message
        self.expression = expression
        self.themeID = themeID
        self.userName = userName
    }
}

/// Planification PURE des entrées de la journée : créneaux de messages (7 h, 12 h,
/// 18 h), passage en sleepy (22 h), bascule de minuit (kcal remises à 0) et réveil
/// (7 h du lendemain). Une entrée WidgetKit est rendue à l'avance : chaque moment
/// où l'apparence doit changer exige sa propre entrée.
public enum WidgetTimelinePlanner {
    /// Heures (jour de `from`) où l'apparence change : réveil, midi, soir, nuit.
    static let boundaryHours = [7, 12, 18, 22]

    public static func entries(snapshot: WidgetSnapshot, from: Date,
                               bank: MessageBank, calendar: Calendar) -> [WidgetEntry] {
        var dates: [Date] = [from]
        for hour in boundaryHours {
            if let d = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: from),
               d > from {
                dates.append(d)
            }
        }
        let startOfDay = calendar.startOfDay(for: from)
        if let midnight = calendar.date(byAdding: .day, value: 1, to: startOfDay) {
            dates.append(midnight)
            if let wakeUp = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: midnight) {
                dates.append(wakeUp)
            }
        }
        return dates.map { entry(at: $0, snapshot: snapshot, bank: bank, calendar: calendar) }
    }

    static func entry(at date: Date, snapshot: WidgetSnapshot,
                      bank: MessageBank, calendar: Calendar) -> WidgetEntry {
        let hour = calendar.component(.hour, from: date)
        // Entrée d'un jour POSTÉRIEUR au snapshot (minuit passé, ou snapshot
        // d'hier) : l'anneau ne montre jamais les kcal d'hier.
        let isNewDay = calendar.startOfDay(for: date) > snapshot.dayKey
        return WidgetEntry(
            date: date,
            kcalEaten: isNewDay ? 0 : snapshot.kcalEaten,
            kcalTarget: snapshot.kcalTarget,
            totalXP: snapshot.totalXP,
            message: message(at: date, snapshot: snapshot, bank: bank, calendar: calendar),
            expression: expression(hour: hour),
            themeID: snapshot.themeID,
            userName: snapshot.userName
        )
    }

    /// Même règle que l'accueil (`HomeView.nivelitoExpression`) : nuit de 22 h à 7 h.
    static func expression(hour: Int) -> WidgetEntry.Expression {
        (hour >= 22 || hour < 7) ? .sleepy : .happy
    }

    /// Créneau de messages d'une entrée — nuit (< 7 h) : pool du soir. `rawValue`
    /// Int STABLE utilisé comme composante du seed de `messageIndex` : ne PAS le
    /// coupler à l'ordre de déclaration de `MessageContext`, qu'un réordonnancement
    /// de ce dernier remélangerait silencieusement.
    enum Slot: Int, Equatable { case morning = 0, midday = 1, evening = 2 }

    /// Avant 7 h, le pool du soir peut évoquer le dîner : fenêtre étroite et
    /// assumée, l'entrée affichée la nuit est normalement celle de minuit (le
    /// message a déjà tourné) et Nivelito y est de toute façon sleepy.
    static func slot(hour: Int) -> Slot {
        if hour < 7 { return .evening }
        if hour < 12 { return .morning }
        if hour < 18 { return .midday }
        return .evening
    }

    /// Index déterministe dans le pool, seedé sur (jour, créneau) — même principe
    /// que DailySessionPicker : stable, aucun aléatoire, modulo positif.
    static func messageIndex(dayIndex: Int, slot: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let seed = dayIndex &* 31 &+ slot &* 7
        return ((seed % count) + count) % count
    }

    static func message(at date: Date, snapshot: WidgetSnapshot,
                        bank: MessageBank, calendar: Calendar) -> String {
        let slot = slot(hour: calendar.component(.hour, from: date))
        let context: MessageContext = switch slot {
        case .morning: .morning
        case .midday: .midday
        case .evening: .evening
        }
        let pool = bank.messages(for: context) + bank.messages(for: .fun)
        // Pré-condition : pool non vide — garanti par le catalogue
        // (MessageBankTests.testBankHasAllContextsWithEnoughVariety, >= 12 par contexte).
        // Même référence fixe que la séance du jour (01/01/2026, partagée via DailySessionPicker).
        let dayIndex = DailySessionPicker.dayIndex(for: date, calendar: calendar)
        let chosen = pool[messageIndex(dayIndex: dayIndex, slot: slot.rawValue, count: pool.count)]
        return chosen.text.replacingOccurrences(of: "{name}", with: snapshot.userName)
    }
}
