import Foundation

public enum LevelSystem {
    /// XP total requis pour ATTEINDRE le niveau n (niveau 1 = 0 XP). Seuil = 100 × n^1.3 arrondi (spec §7.1).
    public static func xpRequired(forLevel level: Int) -> Int {
        guard level > 1 else { return 0 }
        return Int((100 * pow(Double(level), 1.3)).rounded())
    }

    public static func level(forXP xp: Int) -> Int {
        var level = 1
        while xpRequired(forLevel: level + 1) <= xp { level += 1 }
        return level
    }

    /// Progression dans le niveau courant : XP déjà gagné / XP nécessaire jusqu'au prochain niveau.
    public static func progress(forXP xp: Int) -> (current: Int, needed: Int) {
        let level = level(forXP: xp)
        let base = xpRequired(forLevel: level)
        let next = xpRequired(forLevel: level + 1)
        return (xp - base, next - base)
    }
}
