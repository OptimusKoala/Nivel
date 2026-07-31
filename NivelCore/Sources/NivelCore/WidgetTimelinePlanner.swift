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

/// Planification PURE des entrées de la journée : une entrée par heure pleine,
/// phrase différente à chaque heure (seed horaire absolu, spec vivant §3),
/// passage en sleepy (22 h), bascule de minuit (kcal remises à 0) et réveil
/// (7 h du lendemain). Une entrée WidgetKit est rendue à l'avance : chaque
/// moment où l'apparence doit changer exige sa propre entrée.
public enum WidgetTimelinePlanner {
    public static func entries(snapshot: WidgetSnapshot, from: Date,
                               bank: MessageBank, calendar: Calendar) -> [WidgetEntry] {
        var dates: [Date] = [from]
        // Heures MURALES du jour de `from` (spec vivant §3/§7) : le jour du
        // passage à l'heure d'été, 2 h n'existe pas et bySettingHour renvoie
        // une date déjà présente — dédupliquée plus bas.
        for hour in 0...23 {
            if let d = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: from),
               d > from {
                dates.append(d)
            }
        }
        let startOfDay = calendar.startOfDay(for: from)
        if let midnight = calendar.date(byAdding: .day, value: 1, to: startOfDay) {
            dates.append(midnight)
            // La rotation continue toute la nuit jusqu'au réveil (7 h inclus).
            for hour in 1...7 {
                if let d = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: midnight) {
                    dates.append(d)
                }
            }
        }
        // Déduplication (pinnée par testTimelineStaysOrderedAcrossDSTTransitions :
        // le 29/03, bySettingHour(2) renvoie 3 h, déjà présente). Le tri est une
        // assurance contre la politique de résolution de Foundation, pas un
        // invariant testé : les dates sortent déjà croissantes.
        var unique: [Date] = []
        for d in dates.sorted() where d != unique.last {
            unique.append(d)
        }
        return unique.map { entry(at: $0, snapshot: snapshot, bank: bank, calendar: calendar) }
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

    /// Créneau de messages d'une entrée (choix du POOL uniquement : le seed est
    /// l'heure absolue) — nuit (< 7 h) : pool du soir.
    enum Slot: Equatable { case morning, midday, evening }

    /// Les 7 entrées de nuit (0 h-6 h) tirent du pool du soir : une phrase de
    /// dîner peut sortir à 4 h du matin — assumé (Nivelito y est sleepy et
    /// l'écran est rarement regardé la nuit ; spec vivant §3, pool inchangé).
    static func slot(hour: Int) -> Slot {
        if hour < 7 { return .evening }
        if hour < 12 { return .morning }
        if hour < 18 { return .midday }
        return .evening
    }

    /// Index déterministe dans le pool, seedé sur `absoluteHour` : le rang de
    /// l'heure MURALE depuis la référence (dayIndex × 24 + heure), pas des
    /// heures physiques : au changement d'heure le rang saute (printemps) ou
    /// stagne (automne), sans collision avec les pools actuels. Modulo positif.
    static func messageIndex(absoluteHour: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((absoluteHour % count) + count) % count
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
        // Heure absolue depuis la référence fixe (01/01/2026) : une phrase
        // différente à chaque heure, la même sur les deux iPhones.
        let absoluteHour = DailySessionPicker.dayIndex(for: date, calendar: calendar) &* 24
            &+ calendar.component(.hour, from: date)
        let chosen = pool[messageIndex(absoluteHour: absoluteHour, count: pool.count)]
        return chosen.text.replacingOccurrences(of: "{name}", with: snapshot.userName)
    }
}
