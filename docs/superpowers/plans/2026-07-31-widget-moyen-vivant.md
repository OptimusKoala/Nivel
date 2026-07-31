# Widget moyen vivant (v1.7/v1.8) — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Une phrase de Nivelito différente à chaque heure dans le widget, et Nivelito à 72 pt dans le widget moyen.

**Architecture:** Le planner pur (`WidgetTimelinePlanner`, NivelCore) passe de 6 bornes à une entrée par heure pleine (énumération en heures MURALES, dédupliquées pour le changement d'heure) et le seed des messages devient l'heure absolue depuis la référence fixe (`dayIndex × 24 + heure` : +1 par heure, aucune collision possible entre heures consécutives). Côté vue, seul `MediumWidgetView` change (Nivelito 48 → 72 pt, `minimumScaleFactor` 0,8 → 0,75). Spec : `docs/superpowers/specs/2026-07-31-widget-moyen-vivant-design.md`.

**Tech Stack:** Swift/SwiftUI, WidgetKit (inchangé), NivelCore (SPM pur), XcodeGen.

**Conventions bloquantes :** pas de tiret cadratin ni point médian dans les textes utilisateur ; pas de gardes défensives pour des invariants testés à la source ; ne pas éditer le `.xcodeproj` (XcodeGen) ; TDD.

**Commandes :**
- NivelCore : `cd NivelCore && swift test`
- App : `xcodebuild -project Nivel.xcodeproj -scheme Nivel -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`

**État de départ (main, post-v1.6)** : `WidgetTimelinePlanner.swift` a `boundaryHours = [7, 12, 18, 22]`, `messageIndex(dayIndex:slot:count:)` (seed `jour×31 + créneau×7`), `Slot: Int` ; `WidgetTimelinePlannerTests.swift` a 17 tests ; `MediumWidgetView` passe `size: 48` à WidgetNivelito, la bulle a `.lineLimit(4)` + `.minimumScaleFactor(0.8)`. Suites au départ (mesurées) : NivelCore 70, app 55 — des sessions parallèles peuvent les faire bouger : re-mesurer et raisonner en deltas.

---

## Carte des fichiers

| Fichier | Changement |
|---|---|
| `NivelCore/Sources/NivelCore/WidgetTimelinePlanner.swift` | entrées horaires + seed heure absolue |
| `NivelCore/Tests/NivelCoreTests/WidgetTimelinePlannerTests.swift` | tests adaptés (jamais affaiblis) |
| `Widgets/Views/SystemWidgetViews.swift` | MediumWidgetView : 72 pt + scale 0,75 |
| `project.yml` | version au merge (dernière task) |

---

### Task 0 : Worktree

- [ ] **Step 0.1**

Le worktree `.worktrees/feat-widget-vivant` (branche `feat/widget-vivant`) existe déjà, projet généré. Vérifier : `git -C /Users/mbernard/perso/Nivel/.worktrees/feat-widget-vivant status --short` (propre) — sinon le créer : `git worktree add .worktrees/feat-widget-vivant -b feat/widget-vivant && xcodegen generate`.

- [ ] **Step 0.2 : Baseline** — `cd NivelCore && swift test` puis la suite app : noter les comptes (attendus ~70 / ~55), tout doit être vert avant de commencer.

---

### Task 1 : Planner — une entrée par heure pleine

**Files:**
- Modify: `NivelCore/Sources/NivelCore/WidgetTimelinePlanner.swift`
- Test: `NivelCore/Tests/NivelCoreTests/WidgetTimelinePlannerTests.swift`

Dans cette task, SEULES les dates d'entrées changent (le seed des messages reste celui par créneau : Task 2).

- [ ] **Step 1.1 : Adapter/ajouter les tests de bornes (qui échouent)**

Remplacer `testEntriesFromMorningCoverAllRemainingBoundaries` et `testEntriesLateEveningSkipPastBoundaries` par :

```swift
    /// from 9 h : toutes les heures pleines jusqu'à 7 h du lendemain inclus
    /// (spec vivant §3) : 9 h (from), 10 h … 23 h, minuit, 1 h … 7 h = 23 entrées.
    func testEntriesCoverEveryHourUntilNextMorning() {
        let from = date(hour: 9)
        let entries = WidgetTimelinePlanner.entries(snapshot: snapshot(), from: from,
                                                    bank: bank, calendar: calendar)
        var expected: [Date] = [from]
        expected += (10...23).map { date(hour: $0) }
        expected.append(calendar.startOfDay(for: date(hour: 0, day: 32)))
        expected += (1...7).map { date(hour: $0, day: 32) }
        XCTAssertEqual(entries.map(\.date), expected)
        XCTAssertEqual(entries.count, 23)
    }

    /// from 23 h : plus d'heure restante le jour même, la nuit du lendemain suit.
    func testEntriesLateEveningRollIntoNextDay() {
        let from = date(hour: 23)
        let entries = WidgetTimelinePlanner.entries(snapshot: snapshot(), from: from,
                                                    bank: bank, calendar: calendar)
        var expected: [Date] = [from]
        expected.append(calendar.startOfDay(for: date(hour: 0, day: 32)))
        expected += (1...7).map { date(hour: $0, day: 32) }
        XCTAssertEqual(entries.map(\.date), expected)
    }

    /// Pire cas pré-aube (spec §3) : from entre 0 h et 1 h = 32 entrées.
    func testPreDawnWorstCaseIsThirtyTwoEntries() {
        let from = date(hour: 0, minute: 30)
        let entries = WidgetTimelinePlanner.entries(snapshot: snapshot(), from: from,
                                                    bank: bank, calendar: calendar)
        XCTAssertEqual(entries.count, 32)
    }
```

`testPreDawnGetsSameDaySevenAMBoundary`, `testMidnightRolloverResetsKcalKeepsXP`, `testStaleSnapshotFromYesterdayShowsZeroKcalToday`, `testEntryAtTenPMIsSleepy`, le test DST et le test d'indépendance du calendrier restent TELS QUELS (ils doivent passer avec les entrées horaires). Supprimer `testBoundaryHoursMatchEveryChangeOfSlotOrExpression` (l'invariant devient « une entrée à chaque heure », couvert par les tests ci-dessus — tout changement de créneau ou d'expression tombe sur une heure pleine par construction).

- [ ] **Step 1.2 : Vérifier l'échec**

Run: `cd NivelCore && swift test --filter WidgetTimelinePlannerTests`
Expected: FAIL (les nouvelles listes de dates ne correspondent pas aux 6 bornes actuelles)

- [ ] **Step 1.3 : Implémenter**

Dans `WidgetTimelinePlanner.swift`, supprimer `boundaryHours` et remplacer `entries` par :

```swift
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
        // Tri + déduplication : WidgetKit exige des dates strictement croissantes
        // (pinné par testTimelineStaysOrderedAcrossDSTTransitions).
        var unique: [Date] = []
        for d in dates.sorted() where d != unique.last {
            unique.append(d)
        }
        return unique.map { entry(at: $0, snapshot: snapshot, bank: bank, calendar: calendar) }
    }
```

Mettre à jour le doc comment de l'enum (« créneaux de messages (7 h, 12 h, 18 h) » → une entrée par heure pleine, phrase différente chaque heure à partir de la Task 2).

- [ ] **Step 1.4 : Vérifier le vert (suite NivelCore complète)**

Run: `cd NivelCore && swift test`
Expected: PASS (compte inchangé, 70 : 3 tests remplacent 2, le test de couplage est supprimé)

- [ ] **Step 1.5 : Commit**

```bash
git add NivelCore && git commit -m "feat(core): timeline du widget, une entrée par heure pleine"
```

---

### Task 2 : Planner — seed horaire absolu (phrase différente chaque heure)

**Files:**
- Modify: `NivelCore/Sources/NivelCore/WidgetTimelinePlanner.swift`
- Test: `NivelCore/Tests/NivelCoreTests/WidgetTimelinePlannerTests.swift`

- [ ] **Step 2.1 : Adapter/ajouter les tests (qui échouent)**

Remplacer `testMessageIndexDeterministicAndBounded`, `testMessageIndexRotatesAcrossDays` et `testMessageIndexWithNonPositiveCountReturnsZero` par :

```swift
    /// L'index est stable et borné pour la même heure absolue.
    func testMessageIndexDeterministicAndBounded() {
        for hours in [-25, 0, 1, 24, 1_000] {
            let a = WidgetTimelinePlanner.messageIndex(hoursSinceReference: hours, count: 7)
            let b = WidgetTimelinePlanner.messageIndex(hoursSinceReference: hours, count: 7)
            XCTAssertEqual(a, b)
            XCTAssertTrue((0..<7).contains(a))
        }
    }

    /// Le seed avance de 1 par heure : deux heures consécutives ne coïncident
    /// JAMAIS, quel que soit le pool (>= 2) — y compris 23 h vers 0 h, la
    /// collision systématique qu'un seed (jour, créneau) multiplié aurait créée
    /// (spec vivant §3).
    func testConsecutiveHoursNeverCollide() {
        for count in [2, 25, 26] {
            for hours in [0, 23, 47, 500] {
                XCTAssertNotEqual(
                    WidgetTimelinePlanner.messageIndex(hoursSinceReference: hours, count: count),
                    WidgetTimelinePlanner.messageIndex(hoursSinceReference: hours + 1, count: count),
                    "count \(count), heure \(hours)")
            }
        }
    }

    /// La même heure d'un jour à l'autre change aussi (delta 24, non multiple
    /// des tailles de pools actuelles 25/26). Si un futur pool devient multiple
    /// de 24, ce test le signalera : c'est voulu (spec vivant §7).
    func testSameHourNextDayDiffers() {
        for context in [MessageContext.morning, .midday, .evening] {
            let count = bank.messages(for: context).count + bank.messages(for: .fun).count
            XCTAssertNotEqual(24 % count, 0, "pool \(context) de taille \(count)")
        }
    }

    /// Parité avec DailySessionPickerTests : count non positif renvoie 0 (pas de crash).
    func testMessageIndexWithNonPositiveCountReturnsZero() {
        XCTAssertEqual(WidgetTimelinePlanner.messageIndex(hoursSinceReference: 5, count: 0), 0)
        XCTAssertEqual(WidgetTimelinePlanner.messageIndex(hoursSinceReference: 5, count: -1), 0)
    }

    /// Pinne explicitement la non-collision de minuit sur une VRAIE timeline :
    /// l'entrée de 23 h et celle de minuit portent des messages différents.
    func testMidnightEntryDiffersFromElevenPM() {
        let entries = WidgetTimelinePlanner.entries(snapshot: snapshot(), from: date(hour: 21),
                                                    bank: bank, calendar: calendar)
        let elevenPM = entries.first { $0.date == date(hour: 23) }!
        let midnight = entries.first {
            $0.date == calendar.startOfDay(for: date(hour: 0, day: 32))
        }!
        XCTAssertNotEqual(elevenPM.message, midnight.message)
    }

    /// Deux heures consécutives d'une vraie timeline (même pool du matin)
    /// portent des messages différents.
    func testHourlyEntriesRotateWithinASlot() {
        let entries = WidgetTimelinePlanner.entries(snapshot: snapshot(), from: date(hour: 8),
                                                    bank: bank, calendar: calendar)
        let nine = entries.first { $0.date == date(hour: 9) }!
        let ten = entries.first { $0.date == date(hour: 10) }!
        XCTAssertNotEqual(nine.message, ten.message)
    }
```

Adapter `testSameDaySameSlotSameMessage` : renommer en `testSameDaySameHourSameMessage` (le corps reste : l'entrée de 12 h générée depuis 9 h et depuis 10 h porte le même message — c'est maintenant « même heure », pas « même créneau »).

- [ ] **Step 2.2 : Vérifier l'échec**

Run: `cd NivelCore && swift test --filter WidgetTimelinePlannerTests`
Expected: FAIL (compilation : `messageIndex(hoursSinceReference:count:)` introuvable)

- [ ] **Step 2.3 : Implémenter**

Dans `WidgetTimelinePlanner.swift` :

1. Remplacer `messageIndex(dayIndex:slot:count:)` par :

```swift
    /// Index déterministe dans le pool, seedé sur l'heure ABSOLUE (heures écoulées
    /// depuis la référence fixe partagée avec DailySessionPicker). Le seed avance
    /// de 1 par heure : deux heures consécutives d'un même pool ne coïncident
    /// jamais, y compris 23 h vers 0 h (spec vivant §3). Modulo positif.
    static func messageIndex(hoursSinceReference: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((hoursSinceReference % count) + count) % count
    }
```

2. Dans `message(at:snapshot:bank:calendar:)`, remplacer le calcul d'index :

```swift
        // Heure absolue depuis la référence fixe (01/01/2026) : une phrase
        // différente à chaque heure, la même sur les deux iPhones.
        let hoursSinceReference = DailySessionPicker.dayIndex(for: date, calendar: calendar) &* 24
            &+ calendar.component(.hour, from: date)
        let chosen = pool[messageIndex(hoursSinceReference: hoursSinceReference, count: pool.count)]
```

3. `Slot` ne sert plus au seed : retirer `Int` (`enum Slot: Equatable { case morning, midday, evening }`) et remplacer son doc comment (il ne choisit plus que le POOL) :

```swift
    /// Créneau de messages d'une entrée (choix du POOL uniquement : le seed est
    /// l'heure absolue) — nuit (< 7 h) : pool du soir.
```

- [ ] **Step 2.4 : Vérifier le vert (suite complète)**

Run: `cd NivelCore && swift test`
Expected: PASS (73 tests : 6 remplacent 3, +3 nets ; suite planner 17 vers 20)

- [ ] **Step 2.5 : Commit**

```bash
git add NivelCore && git commit -m "feat(core): phrase de Nivelito differente a chaque heure (seed horaire absolu)"
```

---

### Task 3 : Vue — Nivelito 72 pt dans le widget moyen

**Files:**
- Modify: `Widgets/Views/SystemWidgetViews.swift` (MediumWidgetView + previews)

- [ ] **Step 3.1 : Implémenter**

Dans `MediumWidgetView` (vérifier les valeurs de départ avant d'éditer : `WidgetNivelito(... size: 48)` et `.minimumScaleFactor(0.8)`) :
- `size: 48` → `size: 72` ;
- `.minimumScaleFactor(0.8)` → `.minimumScaleFactor(0.75)` avec un commentaire : la bulle perd ~24 pt au profit de Nivelito (spec vivant §4), le scale compense pour les messages longs.

Vérifier dans les `#Preview` du fichier que la variante medium avec message long existe toujours (elle sert de contrôle visuel) ; ne pas la modifier sauf si elle passait une taille explicite à corriger.

- [ ] **Step 3.2 : Builder + suite app complète**

```bash
xcodebuild -project Nivel.xcodeproj -scheme Nivel -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | tail -3
```
Expected: TEST SUCCEEDED (même compte qu'à la baseline).

- [ ] **Step 3.3 : Commit**

```bash
git add Widgets && git commit -m "feat(widgets): Nivelito 72pt dans le widget moyen (maquette A)"
```

- [ ] **Step 3.4 (review qualité — critère d'acceptation, spec §4)** : re-mesurer au harnais de rendu ad hoc (macOS SwiftUI + ImageRenderer sur les vraies vues, comme en v1.6) que les 77 messages des pools widget passent sans troncature à 364/338/329/321 pt avec Nivelito 72 pt et scale 0,75. Si échec à 321 pt : passer `lineLimit(5)` ou scale 0,7 et re-mesurer. (« 77 messages » = somme des pools 26+25+26, soit 51 textes distincts, fun compté trois fois.)

---

### Task 4 : Version au merge + vérification finale

**Files:**
- Modify: `project.yml` (2 targets)

- [ ] **Step 4.1 : Déterminer le numéro** — au moment du merge, lire la version courante sur `main` (`grep CFBundleShortVersionString project.yml`). Si les icônes cozy ont déjà pris 1.7 (build 8), prendre **1.8 (build 9)** ; sinon **1.7 (build 8)**. Mettre à jour les DEUX targets (Nivel et NivelWidgets), puis `xcodegen generate`.

- [ ] **Step 4.2 : Vérification complète**

```bash
cd NivelCore && swift test && cd .. && xcodebuild -project Nivel.xcodeproj -scheme Nivel -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | tail -3
```
Expected: tout PASS.

- [ ] **Step 4.3 : Commit**

```bash
git add -A && git commit -m "chore: version X.Y (build N) pour le widget vivant"
```

---

## Après le plan

- Review finale holistique de la branche, puis superpowers:finishing-a-development-branch (merge dans main, attention aux sessions parallèles : re-merger main dans la branche d'abord si divergence, comme pour la v1.6).
- Passe device : vérifier sur iPhone que la phrase change bien d'heure en heure et que les messages longs tiennent avec Nivelito 72 pt. Comportement CONNU et accepté : aux frontières de pools (11 h vers 12 h, 17 h vers 18 h), un même message fun peut sortir deux heures de suite (~3 fois sur 40 jours) — pas un bug.
- Mettre à jour la mémoire projet.
