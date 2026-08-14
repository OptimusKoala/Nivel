// App/Services/GameService+LevelMigration.swift
// Recharge d'XP unique au passage à la courbe durcie de la 1.14 (spec §5.2).
// Migration ponctuelle et GELÉE : une fois la 1.14 diffusée, ce fichier ne doit plus
// changer — le modifier reviendrait à recalculer le niveau de joueurs déjà migrés.
//
// ─── LE DISPOSITIF TIENT EN TROIS PIÈCES, DANS DEUX FICHIERS ────────────────────
//
//  1. `GamificationState.levelCurveVersion`, défaut **1** sur la DÉCLARATION
//     (`App/Models/PersistentModels.swift`) : c'est la valeur que SwiftData donne à
//     la colonne absente des stores d'avant la 1.14. Elle les rend candidats à la
//     recharge. Ce 1 n'est protégé par aucun test — voir l'avertissement sur place.
//
//  2. Le même paramètre, défaut **2** dans l'`init` du même type : un état créé PAR
//     le code de la 1.14 (onboarding, previews, mode captures) naît sur la nouvelle
//     courbe et n'est jamais candidat. Sans cette asymétrie, une installation neuve
//     se ferait « recharger » au lancement suivant une XP déjà gagnée sous la
//     nouvelle courbe : 3 000 XP deviendraient 16 569, sept niveaux offerts.
//
//  3. `migrateLevelCurveIfNeeded()`, ci-dessous, appelée depuis l'init de
//     `GameService` — donc avant tout affichage.
//
// Les deux défauts ont des valeurs DIFFÉRENTES exprès. Ce n'est pas une coquille :
// les « harmoniser » rouvre le trou décrit en 2, et la cible resterait verte.
//
// ─── FENÊTRE CONNUE, ASSUMÉE : LE WIDGET AVANT LE PREMIER LANCEMENT ─────────────
//
// Entre la mise à jour et le premier lancement de l'app, le widget lit le snapshot
// d'AVANT migration (l'XP ancienne) et l'affiche avec la NOUVELLE courbe : « Niv. 6 »
// au lieu de « Niv. 13 » sur l'écran verrouillé, sans que l'app ait été ouverte. La
// timeline se re-rend d'elle-même à 7 h, et le premier lancement corrige tout.
// C'est de l'affichage seul : rien n'est perdu. Corrigé proprement, il faudrait
// toucher NivelCore ET l'extension widget pour une fenêtre qui se referme seule —
// décision prise en revue de la 1.14 : on ne corrige pas, on l'écrit ici.

import Foundation
import NivelCore

extension GameService {

    /// Recharge d'XP unique au passage à la courbe durcie (spec §5.2).
    ///
    /// La nouvelle courbe exige ~4 fois plus d'XP au niveau 10 : appliquée brute, elle
    /// ferait DESCENDRE tous les joueurs existants — la seule régression que l'app se
    /// serait jamais autorisée, contre sa règle « zéro pression, jamais de score
    /// négatif ». On porte donc l'XP au seuil que le niveau déjà atteint exige sous la
    /// nouvelle courbe : personne ne descend, et le niveau suivant se mérite au
    /// nouveau rythme. Le total affiché fait un bond visible ; c'est le prix, et il
    /// vaut mieux qu'un plateau de plusieurs semaines.
    ///
    /// Sa justesse repose sur les deux défauts asymétriques de `levelCurveVersion`
    /// décrits en tête de fichier : les lire avant de toucher à quoi que ce soit ici.
    ///
    /// `max` et non affectation sèche : aux niveaux 2 et 3 la nouvelle courbe est plus
    /// GÉNÉREUSE, et une affectation retirerait de l'XP.
    ///
    /// `fetchState()` et JAMAIS `fetchOrCreateState()` : le second insère un état s'il
    /// n'en trouve pas, et l'init du service tourne aussi en preview, en
    /// `ScreenshotMode` et dans toutes les suites de tests. Une installation neuve n'a
    /// pas encore d'état (l'onboarding le crée) : la migration ne fait alors rien.
    ///
    /// Le garde est `< 2` et non `== 1` : une colonne absente remplie avec 0 plutôt
    /// qu'avec le défaut déclaré doit encore être migrée, pas sautée en silence.
    ///
    /// Une XP négative (store corrompu) donne le niveau 1, seuil 0, donc `max` la
    /// remonte à 0 : voulu, l'app n'affiche jamais de score négatif.
    ///
    /// Ne touche ni `badgeUnlocks` (un journal, jamais recalculé : les badges
    /// Niveau 5/10/20 déjà obtenus le restent), ni l'historique `DayLog.xpEarned`, ni
    /// les quêtes en cours.
    func migrateLevelCurveIfNeeded() {
        guard let state = fetchState(), state.levelCurveVersion < 2 else { return }
        // `min(…, 1000)` n'est pas de la politesse : au-delà du niveau ~6 × 10⁷,
        // `xpRequired` déborde de `Int` et TRAPPE. Comme cet appel vient de l'init de
        // `GameService`, lui-même appelé depuis `NivelApp.init`, un store corrompu à
        // ~1,3 × 10¹² XP donnerait une boucle de crash au démarrage, réparable par la
        // seule réinstallation — c'est-à-dire par la perte des données que cette
        // fonction existe pour protéger. Le niveau 1 000 demande déjà plus d'XP
        // qu'une vie de jeu : le plafond ne peut léser personne de réel.
        let reachedLevel = min(LevelSystem.legacyLevel(forXP: state.totalXP), 1000)
        state.totalXP = max(state.totalXP, LevelSystem.xpRequired(forLevel: reachedLevel))
        state.levelCurveVersion = 2
        try? modelContext.save()
    }
}
