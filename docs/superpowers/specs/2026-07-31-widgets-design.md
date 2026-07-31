# Nivel — Spécification Widgets iOS (v1.4)

Date : 2026-07-31
Statut : validé avec Michaël (brainstorming du 31/07/2026)
Référence : s'appuie sur la v1 (`2026-07-29-nivel-v1-design.md`) et ses principes non négociables (zéro culpabilisation, tout en local, deux téléphones indépendants).

## 1. Vision

Nivel s'invite sur l'écran d'accueil et l'écran verrouillé : d'un coup d'œil, on voit où on en est de sa journée (anneau calories, niveau), Nivelito glisse un mot bienveillant qui change au fil de la journée, et un tap suffit pour logger un repas. Le widget est une vitrine douce de l'app, jamais un tableau de bord culpabilisant.

## 2. Décisions validées (brainstorming)

- **Rôle** : mix « journée d'un coup d'œil » + « raccourci pour logger » + « motivation Nivelito ».
- **Formats** : petit (2×2), moyen (4×2), écran verrouillé (accessoires circulaire + rectangulaire). Pas de grand widget en v1.4.
- **Pas de compteur de pas dans les widgets** : un widget ne peut pas lire HealthKit, il afficherait les pas de la dernière ouverture de l'app — un chiffre visiblement périmé contredit l'esprit soigné de l'app. Le widget se limite aux données produites par l'app elle-même (kcal, XP, thème).
- **Architecture « snapshot léger »** : l'app écrit un petit résumé JSON dans l'App Group après chaque action ; le widget ne fait que lire. La base SwiftData ne bouge pas (aucune migration de store — décision explicite face à l'option « base partagée », jugée risquée pour les deux iPhones existants).
- **Version** : 1.4 (build 5) dans `project.yml`.

## 3. Architecture

### 3.1 Nouvelle target `NivelWidgets`

- Extension WidgetKit (`type: app-extension` XcodeGen, `NSExtensionPointIdentifier: com.apple.widgetkit-extension`), bundle `fr.mbernard.Nivel.Widgets`, embarquée par l'app, `DEVELOPMENT_TEAM` identique.
- Sources : nouveau dossier `Widgets/` (bundle `@main WidgetBundle`, provider, vues) + dossier partagé `Shared/` + package NivelCore.

### 3.2 App Group

- Identifiant `group.fr.mbernard.nivel`, déclaré dans les entitlements des DEUX targets (`com.apple.security.application-groups`). Compatible compte Apple gratuit (personal team).
- Support : `UserDefaults(suiteName: "group.fr.mbernard.nivel")`, clé `nivel.widget.snapshot` (Data JSON).

### 3.3 Code partagé app ↔ widget (`Shared/`)

- **`ThemePalette`** : la struct existe déjà dans `App/Theme.swift` (couleurs en dur, aucun asset) — elle est déplacée telle quelle dans `Shared/ThemePalette.swift` avec le helper `Color(hex:)`. La façade `Theme.*` et `ThemeStore` restent dans l'app, inchangées. Le widget résout sa palette depuis le `themeID` du snapshot (fallback Crème si id inconnu).
- **`NivelitoShapes`** (+ ses dépendances minimales, ex. l'enum d'expression) : déplacé de `App/Nivelito/` vers `Shared/` pour dessiner Nivelito en vectoriel dans le widget moyen. `NivelitoView` (micro-gestes d'idle, animations) reste dans l'app — le widget affiche un Nivelito statique.
- Règle : `Shared/` ne contient QUE du code compilable sans SwiftData ni services.

## 4. NivelCore — snapshot et planner (logique pure, testée `swift test`)

### 4.1 `WidgetSnapshot` (Codable, Sendable)

| Champ | Rôle |
|---|---|
| `dayKey: Date` | minuit local du jour auquel appartiennent les kcal |
| `kcalEaten: Int` | somme estimée du jour (affichée avec « ~ ») |
| `kcalTarget: Int` | objectif du profil |
| `totalXP: Int` | niveau et progression recalculés via `LevelSystem` |
| `userName: String` | substitution du placeholder `{name}` des messages |
| `themeID: String` | palette à appliquer |
| `generatedAt: Date` | debug / fraîcheur |

### 4.2 `WidgetTimelinePlanner`

Fonction pure `entries(snapshot:from:calendar:) -> [WidgetEntry]` — `WidgetEntry` est une struct pure (date, kcalEaten, kcalTarget, totalXP, texte du message, themeID, userName). Règles :

- **Créneaux de messages** alignés sur `GameService.homeMessageContext` : matin < 12 h, midi < 18 h, soir ≥ 18 h. Entrées générées à `from`, puis à chaque borne restante (12 h, 18 h) et à **minuit**.
- **Bascule de minuit** : les entrées dont la date dépasse le jour de `dayKey` affichent `kcalEaten = 0` (nouveau jour), XP/niveau conservés. L'anneau ne montre jamais les kcal d'hier.
- **Choix du message** : pool = `messages(context du créneau)` + `messages(.fun)` de la `MessageBank` existante ; index déterministe seedé sur (jour, créneau) — même principe que `DailySessionPicker` : stable, pas de `Date.now`, pas d'aléatoire. `{name}` substitué par `userName`.
- La timeline se termine sur l'entrée de minuit ; politique de rechargement « after » le prochain matin (7 h) pour reprendre la rotation même app fermée.

## 5. Synchronisation côté app — `WidgetSync`

Petit service de l'app (pas de protocole, pas d'abstraction) : construit le `WidgetSnapshot` depuis l'état courant (repas du jour, profil, `GamificationState`, `ThemeStore`), l'écrit dans les UserDefaults partagés, puis appelle `WidgetCenter.reloadTimelines(ofKind:)`. Appelé à quatre moments :

1. **après chaque mutation persistée de `GameService`** — un crochet unique au point de sauvegarde (`saveOrAssert`), pas un appel dispersé dans chaque méthode ;
2. **à la clôture de journée** (`DayCloser`) ;
3. **au changement de thème** (Réglages) ;
4. **au retour au premier plan** de l'app — rattrape tout le reste (minuit passé app fermée, quêtes du lundi…).

Fire and forget : si l'écriture échoue, le widget garde le snapshot précédent — jamais d'erreur visible.

## 6. Les widgets (UI)

Tous suivent la palette du snapshot et la règle **zéro rouge** : en dépassement, l'anneau passe à `accent` (chaleureux) avec le même « ~X / Y kcal », exactement comme `CalorieRingCard`. Textes sans tiret cadratin ni point médian (conventions v1.1/v1.2).

- **Petit (`systemSmall`)** : anneau calories (~mangé / objectif) + pastille « Niv. N ». Tap → app (accueil).
- **Moyen (`systemMedium`)** : gauche = anneau + niveau et progression XP ; droite = Nivelito statique (expression `sleepy` de 22 h à 7 h, sinon `happy` — même règle que l'accueil) + bulle courte (message du créneau) ; zone « + Repas » (`Link`) → `nivel://log-meal`.
- **Écran verrouillé** : `accessoryCircular` = `Gauge` kcal (rendu monochrome système) ; `accessoryRectangular` = « ~850 / 1 800 kcal » + « Niv. 3 ». Kcal visibles sur l'écran verrouillé : choix assumé (comme les anneaux Activité d'Apple), c'est l'utilisateur qui décide d'ajouter le widget là.

## 7. Deep link `nivel://log-meal`

- Schéma URL `nivel` déclaré dans l'Info.plist de l'app (`CFBundleURLTypes` via `project.yml`).
- `RootView` gère `.onOpenURL` : si l'onboarding est terminé, ouvrir la sheet « Logger un repas » (onglet Accueil) ; sinon ignorer silencieusement.
- La décision de routage est une fonction pure testable (même pattern que `HomeView.bubbleDecision`).
- Le tap ailleurs sur un widget ouvre simplement l'app (comportement par défaut).

## 8. Ce qui ne change PAS

- La base SwiftData reste dans le conteneur de l'app — aucune migration de store.
- `ThemeStore` reste sur `UserDefaults.standard` (le `themeID` voyage dans le snapshot).
- Aucun changement de modèle persisté, aucun nouveau champ SwiftData.
- L'app fonctionne à l'identique si le widget n'est jamais ajouté.

## 9. Cas limites

- **Pas de snapshot** (widget ajouté avant le premier lancement ou onboarding non terminé) : état d'accueil doux — Nivelito + « Ouvre Nivel pour commencer », aucun chiffre. C'est aussi le placeholder de la galerie de widgets.
- **App pas ouverte depuis hier** : bascule de minuit du planner → « 0 / objectif », XP conservés.
- **App expirée** (compte gratuit, 7 jours) : le widget affiche la dernière timeline puis se fige ; le re-build hebdo le réveille. À mentionner dans le README.
- **`kcalTarget = 0`** (jamais en pratique) : anneau vide, pas de division par zéro (même garde que `CalorieRingCard.fraction`).

## 10. Tests

- **NivelCore** : round-trip Codable du snapshot ; planner — bascule de minuit (kcal remises à 0, XP conservés), bornes des créneaux (11 h 59 / 12 h, 17 h 59 / 18 h), rotation déterministe (même jour + même créneau = même message, jours différents = rotation), substitution `{name}` ; garde : aucun message des pools widget (morning, midday, evening, fun) ne contient `{value}`.
- **NivelTests** (simulateur) : `WidgetSync` écrit un snapshot cohérent après un `logMeal` (UserDefaults de suite de test injectés) ; fonction pure de routage du deep link.
- Pas de tests UI des vues du widget (comme le reste de l'app).

## 11. Hors périmètre (v1.4)

- Grand widget (4×4), widget StandBy dédié, contrôles interactifs (boutons AppIntent) : un repas ne se logge pas sans choisir un plat, le deep link est le bon geste.
- Rafraîchissement des pas en arrière-plan (HealthKit background delivery).
- Widgets de quêtes ou de séance du jour.

## 12. Points d'attention

- **XcodeGen** : première target multiple avec embed — vérifier après `xcodegen generate` que l'extension est bien embarquée et signée (personal team) sur les deux iPhones.
- **Nouveau bundle ID** : le compte gratuit plafonne à 10 App IDs par semaine — deux ne posent aucun problème, mais le premier build sur chaque téléphone créera le provisioning de l'extension.
- **Leçon v1.3 rappelée** : pas de gardes défensives pour des invariants testés à la source (ex. ne pas re-vérifier `{value}` au runtime, le test NivelCore s'en charge).
