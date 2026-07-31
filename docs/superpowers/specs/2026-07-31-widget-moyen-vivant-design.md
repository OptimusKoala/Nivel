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
- **Version** : 1.7 (build 8).

## 3. Planner — entrées horaires

`WidgetTimelinePlanner.entries(snapshot:from:bank:calendar:)` (API inchangée, provider intact) :

- **Bornes** : `from`, puis **chaque heure pleine** jusqu'à 7 h du lendemain inclus (~24-30 entrées ; la politique de rechargement `.after(dernière entrée)` reste valable).
- **Message par (jour, heure)** : seed `jour × 31 + heure × 7` (au lieu du rang de créneau), pool inchangé (contexte du créneau + `fun`). Déterministe : même phrase à la même heure sur les 2 iPhones, phrase différente d'une heure à l'autre (des collisions ponctuelles de modulo restent possibles et acceptées).
- **Inchangé** : créneaux de pools (matin < 12 h, midi < 18 h, soir ≥ 18 h, nuit < 7 h = pool du soir), expression sleepy 22 h-7 h, bascule de minuit (kcal 0, XP conservés), substitution `{name}`.
- Les heures pleines contiennent par construction les anciens points de bascule (7/12/18/22/minuit) : le test de couplage bornes/créneau/expression est reformulé (tout changement de créneau ou d'expression tombe sur une heure pleine, donc sur une entrée).

## 4. Vue — Nivelito 72 pt

Dans `MediumWidgetView` uniquement :

- `WidgetNivelito` passe de 48 à **72 pt** (même position, à gauche de la bulle).
- La bulle perd ~35 pt de largeur : `minimumScaleFactor` passe de 0,8 à **0,75**, `lineLimit(4)` conservé.
- **Critère d'acceptation** : les 77 messages des pools widget passent sans troncature sur toutes les largeurs d'iPhone (364/338/329/321 pt), re-mesurés au harnais de rendu pendant la review qualité. Si un message échoue à 321 pt : ajuster (lineLimit 5 ou scale 0,7) avant merge.

## 5. Ce qui ne change PAS

Petit widget, accessoires écran verrouillé, état d'accueil, snapshot (`WidgetSnapshot` intact), synchronisation (`syncWidget`), deep link, provider (forme de l'API planner conservée).

## 6. Tests

- Planner : nombre et dates des entrées horaires (from 9 h → 9 h, 10 h, … 7 h lendemain) ; rotation horaire (deux heures consécutives du même créneau donnent des index différents dans le pool) ; déterminisme conservé (même jour + même heure = même message) ; bascule de minuit et expressions inchangées (tests existants adaptés, pas affaiblis) ; couplage reformulé (§3).
- Vue : pas de test UI ; l'acceptation §4 passe par le harnais de rendu en review.

## 7. Points d'attention

- Ne pas toucher au seed des créneaux ailleurs : la « séance du jour » (`DailySessionPicker`) garde sa rotation propre.
- Le nombre d'entrées reste borné (< 32) : aucun risque côté WidgetKit, mais ne pas descendre sous l'heure (pas de minutes).
