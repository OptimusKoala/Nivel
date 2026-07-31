# Nivel — Spécification Widget moyen vivant (v1.7)

Date : 2026-07-31
Statut : validé avec Michaël (brainstorming du 31/07/2026, maquettes visual companion — option A retenue)
Référence : itération sur `2026-07-31-widgets-design.md` (v1.6). Tout ce qui n'est pas mentionné ici est inchangé.

## 1. Vision

Le widget moyen devient plus vivant sans tricher avec la plateforme : Nivelito plus présent, une phrase différente à chaque heure. Toujours déterministe, toujours pré-calculé, zéro coût batterie.

## 2. Décisions validées (brainstorming)

- **Pas d'animation du visage** : WidgetKit rend chaque entrée en image figée — l'animation en direct est impossible (limite plateforme, expliquée et acceptée). Les alternatives « stop-motion » proposées ont été déclinées : le visage garde **happy/sleepy tels quels**.
- **Phrases : une par heure** (au lieu d'une par créneau). Choix « Toutes les heures » retenu face à « toutes les 2-3 h » et « comme maintenant ».
- **Nivelito 72 pt** dans le widget moyen (maquette A : structure actuelle conservée, aujourd'hui 48 pt). Options B (bulle au-dessus, 80 pt) et C (héros 110 pt) déclinées.
- **Version** : prochain numéro libre AU MOMENT DU MERGE — la spec « icônes cozy » du même jour vise aussi la 1.7 : le premier jalon mergé prend 1.7 (build 8), le suivant 1.8 (build 9) (précédent : v1.5 timer / v1.6 widgets, résolu au merge).

## 3. Planner — entrées horaires

`WidgetTimelinePlanner.entries(snapshot:from:bank:calendar:)` (API inchangée, provider intact) :

- **Bornes** : `from`, puis **chaque heure pleine** jusqu'à 7 h du lendemain inclus (≤ 32 entrées, maximum atteint pour un `from` entre 0 h et 1 h ; la politique de rechargement `.after(dernière entrée)` reste valable).
- **Message par heure absolue** : seed = **heures écoulées depuis la référence fixe** (`dayIndex × 24 + heure`), pool inchangé (contexte du créneau + `fun`). Le seed avance de 1 à chaque heure : deux heures consécutives du même pool ne donnent JAMAIS le même index (y compris 23 h → 0 h — un seed `jour × 31 + heure × 7` aurait recollé la même phrase chaque nuit, delta 130 ≡ 0 mod 26), et la même heure d'un jour à l'autre change aussi (24 n'est multiple d'aucune taille de pool actuelle, 25/26). Déterministe : même phrase à la même heure sur les 2 iPhones.
- **Inchangé** : créneaux de pools (matin < 12 h, midi < 18 h, soir ≥ 18 h, nuit < 7 h = pool du soir), expression sleepy 22 h-7 h, bascule de minuit (kcal 0, XP conservés), substitution `{name}`.
- Les heures pleines contiennent par construction les anciens points de bascule (7/12/18/22/minuit) : le test de couplage bornes/créneau/expression est reformulé (tout changement de créneau ou d'expression tombe sur une heure pleine, donc sur une entrée).

## 4. Vue — Nivelito 72 pt

Dans `MediumWidgetView` uniquement :

- `WidgetNivelito` passe de 48 à **72 pt** (même position, à gauche de la bulle).
- La bulle perd ~24 pt de largeur : `minimumScaleFactor` passe de 0,8 à **0,75**, et `lineLimit` passe de 4 à **5** (clause de repli du critère ci-dessous, déclenchée : 4 messages fun débordaient à 321 pt avec 4 lignes ; le scale 0,7 seul ne suffisait pas, mesuré).
- **Critère d'acceptation** : les 77 messages des pools widget passent sans troncature sur toutes les largeurs d'iPhone (364/338/329/321 pt). Mesure : harnais de rendu **ad hoc reconstruit par le reviewer qualité** (macOS SwiftUI + ImageRenderer compilant les vraies vues, comme pour la v1.6 — outil jetable, non committé). Si un message échoue à 321 pt : ajuster (lineLimit 5 ou scale 0,7) avant merge.

## 5. Ce qui ne change PAS

Petit widget, accessoires écran verrouillé, état d'accueil, snapshot (`WidgetSnapshot` intact), synchronisation (`syncWidget`), deep link, provider (forme de l'API planner conservée).

## 6. Tests

- Planner : nombre et dates des entrées horaires (from 9 h → 9 h, 10 h, … 7 h lendemain, soit 23 entrées ; ≤ 32 dans le pire cas pré-aube) ; rotation horaire SANS collision de minuit (l'index de 23 h diffère de celui de 0 h, pinné explicitement) ; déterminisme conservé (même jour + même heure = même message) ; variété jour à jour (même heure, jour suivant : message différent avec les pools actuels) ; bascule de minuit et expressions inchangées (tests existants adaptés, pas affaiblis) ; couplage reformulé (§3).
- Vue : pas de test UI ; l'acceptation §4 passe par le harnais de rendu en review.

## 7. Points d'attention

- Ne pas toucher au seed des créneaux ailleurs : la « séance du jour » (`DailySessionPicker`) garde sa rotation propre.
- Le nombre d'entrées reste borné (≤ 32) : aucun risque côté WidgetKit, mais ne pas descendre sous l'heure (pas de minutes).
- Si les tailles de pools changent un jour (ajout de messages), la propriété « même heure, jour suivant = différent » peut casser pour un pool multiple de 24 : le test §6 le signalera, c'est voulu.
- Avec le seed ×24, une heure murale donnée ne parcourt que la moitié d'un pool de 26 (gcd(24,26) = 2, cycle de 13 jours) : accepté, la variété promise (§3 : d'heure en heure et de jour en jour) n'est pas affectée.
