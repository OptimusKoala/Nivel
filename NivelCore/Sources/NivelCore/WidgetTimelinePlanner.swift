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
            message: "",
            expression: expression(hour: hour),
            themeID: snapshot.themeID,
            userName: snapshot.userName
        )
    }

    /// Même règle que l'accueil (`HomeView.nivelitoExpression`) : nuit de 22 h à 7 h.
    static func expression(hour: Int) -> WidgetEntry.Expression {
        (hour >= 22 || hour < 7) ? .sleepy : .happy
    }
}
