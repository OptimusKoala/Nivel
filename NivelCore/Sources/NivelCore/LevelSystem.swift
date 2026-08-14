import Foundation

public enum LevelSystem {

    // MARK: - Courbe vivante (1.14)

    /// XP total requis pour ATTEINDRE le niveau n (niveau 1 = 0 XP).
    /// Seuil = 70 × (n−1)^2,2 (spec v1.14 §5.1).
    ///
    /// L'exposant a été porté de 1,3 à 2,2 et la base décalée d'un niveau : sous
    /// l'ancienne courbe le niveau 30 tombait en un mois d'usage régulier, donc un
    /// niveau ne voulait plus rien dire. Le décalage rend les niveaux 2 et 3 PLUS
    /// rapides qu'avant (70 et 322 au lieu de 246 et 417) : le premier jour
    /// récompense davantage, et le freinage ne commence qu'au niveau 4.
    ///
    /// Le `guard` n'est pas de la politesse : `pow` d'une base négative à un exposant
    /// non entier rend `nan`, et `Int(nan.rounded())` fait trapper. Le retirer serait
    /// un crash, pas un zéro.
    public static func xpRequired(forLevel level: Int) -> Int {
        guard level > 1 else { return 0 }
        return Int((70 * pow(Double(level - 1), 2.2)).rounded())
    }

    /// Boucle ascendante et non inverse fermé (`floor((xp/70)^(1/2,2)) + 1`) : la
    /// boucle ne peut pas être en désaccord avec `xpRequired` sur un seuil, là où la
    /// forme fermée se trompe d'une unité pile sur la valeur limite. À ne pas
    /// « optimiser », même si elle est en O(niveau).
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

    // MARK: - Courbe historique (1.13) — gelée, migration uniquement
    //
    // Ces deux fonctions n'ont qu'un appelant légitime : la migration de
    // `GameService` (spec §5.2), qui lit le niveau atteint sous l'ancien barème pour
    // ne faire descendre personne. Elles sont `public` parce que cet appelant vit
    // dans le module de l'app, pas dans NivelCore.

    /// L'ancienne courbe, 100 × n^1,3 — sur `n` et non `n − 1`, contrairement à la
    /// nouvelle : c'est ce décalage qui rend les niveaux 2 et 3 plus rapides depuis
    /// la 1.14.
    ///
    /// Supprimable seulement le jour où aucune base ne peut plus être en
    /// `levelCurveVersion` 1 — donc jamais : une restauration de sauvegarde 1.13 en
    /// recrée une. La modifier ferait perdre un niveau à quelqu'un, et
    /// `testFormuleAncienneEstPreservee` est là pour que ça devienne rouge et non
    /// silencieux.
    public static func legacyXPRequired(forLevel level: Int) -> Int {
        guard level > 1 else { return 0 }
        return Int((100 * pow(Double(level), 1.3)).rounded())
    }

    /// Niveau atteint sous l'ancienne courbe — même usage unique que ci-dessus.
    public static func legacyLevel(forXP xp: Int) -> Int {
        var level = 1
        while legacyXPRequired(forLevel: level + 1) <= xp { level += 1 }
        return level
    }
}
