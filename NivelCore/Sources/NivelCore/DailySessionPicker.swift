import Foundation

/// Sélection de la « séance du jour » (spec sport §3.3) : rotation déterministe sur la
/// date — AUCUN aléatoire, AUCUNE persistance — pour que les deux iPhones affichent la
/// même séance le même jour sans synchronisation.
public enum DailySessionPicker {
    /// 1ᵉʳ janvier 2026 — date de référence FIXE de la rotation : ne JAMAIS la changer
    /// (elle est pinnée par les tests et partagée par les deux installations).
    static func referenceDay(calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
    }

    /// Index du jour dans [0, count) — modulo positif (les dates antérieures à la
    /// référence restent valides).
    public static func index(for date: Date, count: Int, calendar: Calendar) -> Int {
        guard count > 0 else { return 0 }
        let days = calendar.dateComponents(
            [.day],
            from: referenceDay(calendar: calendar),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
        return ((days % count) + count) % count
    }

    public static func session(for date: Date, sessions: [ActivitySession],
                               calendar: Calendar) -> ActivitySession? {
        guard !sessions.isEmpty else { return nil }
        return sessions[index(for: date, count: sessions.count, calendar: calendar)]
    }
}
