# Nivel — Spécification Section Sport (v1.1)

Date : 2026-07-30
Statut : validé avec Michaël (brainstorming du 30/07/2026)
Référence : s'appuie sur la spec v1 (`2026-07-29-nivel-v1-design.md`) — mêmes principes non négociables (zéro culpabilisation, simplicité, tout en local).

## 1. Vision

Ajouter à Nivel une dimension « activité physique douce » : motiver Michaël et Marion à faire quelques exercices simples et efficaces en dépense calorique, sans matériel et peu agressifs pour le corps (marche, étirements, gainage, escaliers…). Deux points d'entrée :

- Un **encart « Activité du jour »** sur l'accueil, sous le bouton « + Logger un repas » : une séance composée toute faite, rapide (~10-15 min), à faire à la maison.
- Un **onglet Sport** : la même séance du jour en tête, plus un catalogue d'activités libres à valider d'un tap.

La gamification existante s'applique : XP à la validation, quêtes hebdo sport, badges sport, messages de Nivelito.

## 2. Décisions validées (brainstorming)

- **Emplacement** : Sport devient un onglet de premier rang.
  ⚠️ Correction post-brainstorming : iPhone affiche au maximum 5 onglets (au-delà, iOS replie dans « Plus »). Pour garder Sport en onglet sans « Plus », **Réglages quitte la tab bar** et devient un bouton ⚙️ dans l'en-tête de l'accueil (pattern iOS courant). Tab bar finale : **Accueil · Repas · Sport · Progrès · Quêtes**.
- **Validation** : tap « C'est fait ! » — système de confiance, zéro friction, comme le log de repas. Pas de timer.
- **Catalogue** : activité + durée au choix (3 durées propres à chaque activité), **plus** des séances composées toutes faites dont une est mise en avant chaque jour (« Activité du jour »).
- **Gamification** : quêtes hebdo sport + badges sport + bulle Nivelito dédiée. Pas de section dans Progrès (v2).
- **Kcal brûlées** : affichage motivant uniquement (« ~90 kcal »). **Jamais** ajoutées au budget calorique ni au DayLog — pas d'effet « j'ai marché, je peux reprendre du dessert ».

## 3. Catalogues (JSON embarqués dans NivelCore)

### 3.1 `activities.json` (~12 activités)

Chaque activité : `id`, `name`, `emoji`, `location` (`home` / `outdoor` / `both`), `kcalPerMin` (Double), `durations` (3 entiers en minutes : courte / moyenne / longue — propres à l'activité, une planche ne se scale pas comme une marche).

| id | Activité | Lieu | Durées (min) | kcal/min |
|---|---|---|---|---|
| walk | 🚶 Marche | Dehors | 10 / 20 / 40 | 4,0 |
| brisk_walk | 🚶‍♀️ Marche rapide | Dehors | 10 / 20 / 30 | 5,5 |
| bike | 🚴 Vélo tranquille | Dehors | 15 / 30 / 45 | 6,0 |
| stairs | 🪜 Montées d'escaliers | Les deux | 5 / 10 / 15 | 8,0 |
| dance | 💃 Danse libre | Maison | 10 / 15 / 25 | 5,5 |
| stretching | 🧘 Étirements | Maison | 5 / 10 / 15 | 2,5 |
| plank | 🧎 Gainage / planche | Maison | 3 / 5 / 8 | 4,0 |
| squats | 🦵 Squats | Maison | 3 / 5 / 10 | 5,5 |
| wall_pushups | 🧱 Pompes murales | Maison | 3 / 5 / 8 | 4,0 |
| active_cleaning | 🧹 Ménage actif | Maison | 15 / 30 / 45 | 3,5 |
| yoga | 🧘‍♀️ Yoga doux | Maison | 10 / 20 / 30 | 3,0 |
| digestive_walk | 🌳 Balade digestive | Dehors | 10 / 15 / 20 | 3,5 |

Estimation kcal d'une validation = `kcalPerMin × minutes`, arrondie à la dizaine, affichée avec « ~ » (honnêteté assumée, comme les repas).

### 3.2 `sessions.json` (8 séances composées)

Chaque séance : `id`, `title`, `emoji`, `steps` (liste ordonnée de `{activityID, minutes}`). Durée totale et kcal estimées sont **dérivées** des steps (pas stockées). Les séances privilégient la maison, 10-15 min.

| id | Séance | Composition (min) |
|---|---|---|
| wake_up | 🌅 Réveil musculaire | étirements 4 + squats 4 + gainage 3 |
| energy_break | ⚡ Pause énergie | escaliers 5 + danse 5 + étirements 3 |
| evening_wind_down | 🌙 Détente du soir | yoga 8 + étirements 5 |
| quick_tone | 💪 Tonus express | squats 4 + pompes murales 4 + gainage 4 |
| fresh_air | 🚶 Bol d'air | marche 15 |
| mood_boost | 🎵 Boost bonne humeur | danse 10 + étirements 4 |
| zen_core | 🧘 Zen & gainage | yoga 6 + gainage 4 + étirements 4 |
| home_cardio | 🪜 Cardio maison | escaliers 6 + squats 3 + étirements 4 |

### 3.3 Séance du jour — rotation déterministe

`indexDuJour = (nombre de jours calendaires écoulés depuis le **1ᵉʳ janvier 2026**, date de référence fixe) % sessions.count`, calculé avec le calendrier canonique de `GameService`. Aucun aléatoire, aucune persistance : **les deux iPhones affichent la même séance le même jour** sans synchronisation (« t'as fait la séance du jour ? »). La logique vit dans NivelCore (testable avec des dates injectées).

## 4. Modèle de données

Nouveau `@Model ActivityEntry` (miroir de `MealEntry`), ajouté au schéma SwiftData — migration légère automatique, aucun modèle existant modifié :

- `date: Date`
- `kindRaw: String` — `activity` (activité libre) ou `dailySession` (séance du jour)
- `refID: String` — `activityID` ou `sessionID` selon le kind
- `durationMinutes: Int`
- `estimatedKcal: Int`
- `xpAwarded: Int`

Le `DayLog` n'est **pas** modifié (kcal brûlées non comptabilisées, §2).

## 5. XP et règles

Deux nouveaux cas dans `XPEngine.XPAction` :

- `.activityDone` : **30 XP**, plafonné à **2 activités récompensées/jour**
- `.dailySessionDone` : **40 XP**, plafonné à **1/jour**

Comme pour les repas, le plafond est dérivé des `ActivityEntry` persistées du jour avec `xpAwarded > 0` (par kind) — robuste aux relances. Au-delà du plafond : l'entrée est quand même enregistrée (compte pour quêtes et badges) mais 0 XP, et pas de bulle de récompense. Jamais de retrait d'XP. Maximum sport : 100 XP/jour (cohérent avec les 80 XP repas).

La séance du jour reste validable même si ce n'est pas « celle du jour » affichée (pas de garde sur l'ID) — mais l'UI ne propose que celle du jour.

## 6. GameService

Extension de la façade existante, mêmes patterns que `logMeal` :

- `logActivity(activity:durationMinutes:date:)` et `logDailySession(session:date:)` : insertion `ActivityEntry`, XP plafonné, `refreshQuestProgress()`, `evaluateBadges()`, `detectLevelUp()`, `saveOrAssert()`.
- `lastActivityXPAwarded: Int?` (miroir de `lastMealXPAwarded`) : consommé par l'accueil pour la bulle `afterActivity`. Si un log de repas et une activité sont en attente, le repas garde la priorité (cas rarissime).
- `deleteActivity(entry:)` : jour même uniquement (swipe), XP conservé, quêtes/badges réévalués — comme `deleteMeal`. Cas assumé (hérité du pattern repas) : supprimer une entrée récompensée fait baisser le compteur du jour, un re-log peut donc être récompensé à nouveau — acceptable pour une app de confiance à deux utilisateurs.
- `dailySession(for date:)` : expose la séance du jour (rotation §3.3) + l'état « déjà faite aujourd'hui » (existence d'une `ActivityEntry` kind `dailySession` du jour).
- `todayActivities()` : entrées du jour pour la liste « Fait aujourd'hui ».

## 7. Gamification branchée

### 7.1 Quêtes (ajout à `quests.json` + 2 métriques dans `QuestEngine`)

Nouvelles métriques : `activitiesDone` (toute `ActivityEntry` de la semaine, libres **et** séances) et `dailySessionsDone` (kind `dailySession` uniquement). `requiresSteps: false` — toujours éligibles au tirage.

| id | Quête | Métrique | Cible |
|---|---|---|---|
| activities_3 | 🏃 Fais 3 activités cette semaine | activitiesDone | 3 |
| activities_5 | 💪 Fais 5 activités cette semaine | activitiesDone | 5 |
| daily_sessions_2 | 📅 Fais 2 séances du jour | dailySessionsDone | 2 |

Elles entrent dans le tirage du lundi automatiquement (les installs en cours de semaine les verront au prochain renouvellement — comportement normal, rien à faire).

### 7.2 Badges (ajout à `badges.json` + `BadgeStats`)

Nouveaux compteurs : `stats.activitiesDone` (all-time, tous kinds), `stats.dailySessionsDone` (all-time).

| id | Badge | Critère |
|---|---|---|
| sport_first | 🥇 Premier pas | 1 activité validée |
| sport_10 | 🏃 En mouvement | 10 activités |
| sport_50 | 🔥 Machine | 50 activités |
| sport_sessions_5 | 🔁 Rituel du jour | 5 séances du jour |

Pas de badge « X jours d'affilée » : contraire au principe « pas de streaks » (spec v1 §7.4).

### 7.3 Nivelito

Nouveau contexte `afterActivity` dans `MessageContext` + ~8 messages dans `messages.json` (dont des « +{value} XP »), ton bienveillant. Consommé par la bulle de l'accueil exactement comme `afterMealLog` (signal consommé une fois, pas de bulle si XP = 0).

## 8. UI

### 8.1 Navigation

Tab bar à 5 onglets : **Accueil · Repas · Sport · Progrès · Quêtes**. L'onglet Sport utilise `figure.walk`. **Réglages** devient un bouton ⚙️ dans l'en-tête de l'accueil (à droite, à côté de la pastille de niveau) qui pousse l'écran Réglages existant (aucun changement de contenu).

### 8.2 Encart « Activité du jour » (accueil)

Carte sous le bouton « + Logger un repas » : emoji + titre de la séance, durée totale, « ~X kcal », et état ✓ « Faite ! » si déjà validée aujourd'hui. Tap → **sheet de détail de séance** (§8.4). Toujours visible (faite ou non) — jamais de disparition punitive.

### 8.3 Onglet Sport

1. **Séance du jour** en tête — même composant que l'encart accueil.
2. **Catalogue** en deux groupes : « 🏠 À la maison » puis « 🌳 Dehors » (les activités `both` apparaissent dans Maison). Carte activité : emoji, nom, fourchette kcal indicative. Tap → sheet choix de durée (§8.4).
3. **« Fait aujourd'hui »** en bas : liste des validations du jour (emoji, nom, durée, ~kcal), swipe pour supprimer (jour même).

### 8.4 Sheets de validation

- **Sheet activité** : nom + emoji, 3 boutons de durée (minutes + ~kcal chacun), bouton « C'est fait ! » → `logActivity`, dismiss, bulle Nivelito au retour sur l'accueil.
- **Sheet séance du jour** : titre, liste des étapes (emoji, nom, minutes), total (durée, ~kcal), bouton « C'est fait ! » → `logDailySession`. Si déjà faite aujourd'hui : le bouton devient un état ✓ inactif (pas de double validation d'une même séance le même jour).

Style : composants et Theme existants (cartes crème, coins arrondis, gradient orange pour les CTA).

## 9. Tests

- **NivelCore** : chargement/décodage des deux catalogues (ids uniques, refs des sessions valides, durées triées), rotation déterministe de la séance du jour (même date → même séance, jours consécutifs → rotation), estimation kcal (activité × durée, somme des steps d'une séance).
- **App (GameService)** : `logActivity`/`logDailySession` (XP, plafonds 2/jour et 1/jour dérivés du store, entrée à 0 XP au-delà), progression des nouvelles métriques de quêtes, nouveaux compteurs de badges, `deleteActivity` (jour même, XP conservé), `dailySession(for:)` (état « déjà faite »).

## 10. Hors périmètre (v2)

- Section Activités dans l'onglet Progrès (histogrammes, historique).
- Timer intégré / séances guidées pas-à-pas.
- Kcal brûlées créditées au budget.
- Notifications de rappel sport.
- HealthKit workouts, Apple Watch.

## 11. Points d'attention

- **Tab bar** : le déplacement de Réglages est le seul changement de navigation — vérifier que l'accès reste évident (⚙️ visible dès l'accueil).
- **Migration SwiftData** : ajout d'un modèle = migration légère automatique ; les stores existants des deux iPhones doivent s'ouvrir sans perte (à vérifier au premier build).
- **Estimations kcal** : approximatives et assumées (« ~ »), comme les repas — jamais utilisées dans un calcul d'objectif.
