# Section Sport & Activité du jour — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ajouter à Nivel un onglet Sport (catalogue d'activités + séance du jour validables d'un tap, XP/quêtes/badges branchés) et un encart « Activité du jour » sur l'accueil.

**Architecture:** Miroir strict du pattern « repas » existant : catalogues JSON dans NivelCore (logique pure testée par `swift test`), un `@Model ActivityEntry` persisté, une extension `GameService+Sport` qui orchestre (XP plafonné dérivé du store, quêtes, badges, level-up), et des vues SwiftUI qui réutilisent Theme/card/sheets. Spec de référence : `docs/superpowers/specs/2026-07-30-sport-section-design.md`.

**Tech Stack:** Swift 5.9+, SwiftUI, SwiftData, XCTest, XcodeGen (projet généré — lancer `xcodegen generate` après tout ajout de fichier sous `App/`).

**Commandes de test :**
- NivelCore : `cd NivelCore && swift test`
- App : `xcodebuild -project Nivel.xcodeproj -scheme Nivel -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`

**Pièges connus (ne pas les découvrir en cours de route) :**
1. `QuestEngineTests.testWeeklyDrawIsPinnedForKnownWeek` **va casser** quand on ajoute des quêtes au pool (le tirage seedé change avec le pool). C'est attendu : re-pinner les ids observés (Task 5).
2. `MessageBankTests.testBankHasAllContextsWithEnoughVariety` exige **≥ 12 messages par contexte** : le nouveau contexte `afterActivity` doit avoir 12 messages minimum (la spec disait ~8 — on en met 12).
3. `CatalogsTests` pinne les comptes exacts : quêtes 15 → **18**, badges 20 → **24**.
4. Tout nouveau fichier sous `App/` n'entre dans le build qu'après `xcodegen generate`.
5. Chaque `Schema([...])` / `ModelContainer(for:)` du projet doit lister `ActivityEntry.self` (app, previews, tests) — un oubli = crash au runtime du preview/test concerné.

---

## Task 0 : Branche de travail

**Files:** aucun.

- [ ] **Step 1 : Créer la branche**

```bash
cd /Users/mbernard/perso/Nivel && git checkout -b feat/sport
```

---

## Task 1 : NivelCore — modèles Activity/ActivitySession + catalogues JSON

**Files:**
- Create: `NivelCore/Sources/NivelCore/ActivityCatalog.swift`
- Create: `NivelCore/Sources/NivelCore/Resources/activities.json`
- Create: `NivelCore/Sources/NivelCore/Resources/sessions.json`
- Modify: `NivelCore/Sources/NivelCore/Catalogs.swift` (2 méthodes de chargement)
- Test: `NivelCore/Tests/NivelCoreTests/ActivityCatalogTests.swift`

- [ ] **Step 1 : Écrire les tests (rouges)**

```swift
// NivelCore/Tests/NivelCoreTests/ActivityCatalogTests.swift
import XCTest
@testable import NivelCore

final class ActivityCatalogTests: XCTestCase {
    func testActivitiesLoadAndIdsAreUnique() throws {
        let activities = try Catalogs.activities()
        XCTAssertEqual(activities.count, 12)
        XCTAssertEqual(Set(activities.map(\.id)).count, activities.count)
        XCTAssertTrue(activities.contains { $0.id == "walk" && $0.location == .outdoor })
    }

    func testActivityDurationsAreThreeAscending() throws {
        for activity in try Catalogs.activities() {
            XCTAssertEqual(activity.durations.count, 3, "\(activity.id)")
            XCTAssertEqual(activity.durations, activity.durations.sorted(), "\(activity.id)")
            XCTAssertEqual(Set(activity.durations).count, 3, "\(activity.id) : durées dupliquées")
        }
    }

    func testSessionsLoadAndStepsResolve() throws {
        let sessions = try Catalogs.sessions()
        let activityIDs = Set(try Catalogs.activities().map(\.id))
        XCTAssertEqual(sessions.count, 8)
        XCTAssertEqual(Set(sessions.map(\.id)).count, sessions.count)
        for session in sessions {
            XCTAssertFalse(session.steps.isEmpty, "\(session.id)")
            for step in session.steps {
                XCTAssertTrue(activityIDs.contains(step.activityID),
                              "\(session.id) référence '\(step.activityID)' inconnu")
                XCTAssertGreaterThan(step.minutes, 0)
            }
        }
    }

    func testEstimatedKcalRoundsToTens() throws {
        let activities = try Catalogs.activities()
        let walk = try XCTUnwrap(activities.first { $0.id == "walk" })       // 4,0 kcal/min
        XCTAssertEqual(walk.estimatedKcal(minutes: 20), 80)
        let plank = try XCTUnwrap(activities.first { $0.id == "plank" })     // 4,0 kcal/min
        XCTAssertEqual(plank.estimatedKcal(minutes: 5), 20)

        // wake_up = étirements 4×2,5 + squats 4×5,5 + gainage 3×4,0 = 44 → 40.
        let sessions = try Catalogs.sessions()
        let wakeUp = try XCTUnwrap(sessions.first { $0.id == "wake_up" })
        let byID = Dictionary(uniqueKeysWithValues: activities.map { ($0.id, $0) })
        XCTAssertEqual(wakeUp.totalMinutes, 11)
        XCTAssertEqual(wakeUp.estimatedKcal(activitiesByID: byID), 40)
    }
}
```

- [ ] **Step 2 : Vérifier l'échec**

Run: `cd NivelCore && swift test --filter ActivityCatalogTests`
Expected: FAIL (compile error — `Catalogs.activities()` n'existe pas).

- [ ] **Step 3 : Implémenter les modèles**

```swift
// NivelCore/Sources/NivelCore/ActivityCatalog.swift
import Foundation

/// Activité physique du catalogue sport (spec sport §3.1) — douce, sans matériel.
public struct Activity: Codable, Identifiable, Hashable, Sendable {
    public enum Location: String, Codable, Sendable { case home, outdoor, both }

    public let id: String
    public let name: String
    public let emoji: String
    public let location: Location
    public let kcalPerMin: Double
    /// Les 3 durées proposées (minutes), croissantes — propres à l'activité
    /// (une planche ne se scale pas comme une marche).
    public let durations: [Int]

    /// Estimation "~ kcal" arrondie à la dizaine — indicative, jamais créditée au budget.
    public func estimatedKcal(minutes: Int) -> Int {
        Int((kcalPerMin * Double(minutes) / 10).rounded()) * 10
    }
}

public struct SessionStep: Codable, Hashable, Sendable {
    public let activityID: String
    public let minutes: Int
    public init(activityID: String, minutes: Int) {
        self.activityID = activityID; self.minutes = minutes
    }
}

/// Séance composée toute faite — la « séance du jour » (spec sport §3.2).
public struct ActivitySession: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let emoji: String
    public let steps: [SessionStep]

    public var totalMinutes: Int { steps.reduce(0) { $0 + $1.minutes } }

    /// Somme des kcal des étapes, arrondie à la dizaine.
    public func estimatedKcal(activitiesByID: [String: Activity]) -> Int {
        let raw = steps.reduce(0.0) {
            $0 + (activitiesByID[$1.activityID]?.kcalPerMin ?? 0) * Double($1.minutes)
        }
        return Int((raw / 10).rounded()) * 10
    }
}

/// Nature d'une validation sport — persistée côté app dans `ActivityEntry.kindRaw`.
public enum ActivityKind: String, Codable, Sendable {
    case activity, dailySession
}
```

Dans `Catalogs.swift`, ajouter après `badges()` :

```swift
    public static func activities() throws -> [Activity] { try load("activities") }
    public static func sessions() throws -> [ActivitySession] { try load("sessions") }
```

- [ ] **Step 4 : Écrire les catalogues JSON**

```json
// NivelCore/Sources/NivelCore/Resources/activities.json
[
  {"id": "walk",            "name": "Marche",               "emoji": "🚶",  "location": "outdoor", "kcalPerMin": 4.0, "durations": [10, 20, 40]},
  {"id": "brisk_walk",      "name": "Marche rapide",        "emoji": "🚶‍♀️", "location": "outdoor", "kcalPerMin": 5.5, "durations": [10, 20, 30]},
  {"id": "bike",            "name": "Vélo tranquille",      "emoji": "🚴",  "location": "outdoor", "kcalPerMin": 6.0, "durations": [15, 30, 45]},
  {"id": "stairs",          "name": "Montées d'escaliers",  "emoji": "🪜",  "location": "both",    "kcalPerMin": 8.0, "durations": [5, 10, 15]},
  {"id": "dance",           "name": "Danse libre",          "emoji": "💃",  "location": "home",    "kcalPerMin": 5.5, "durations": [10, 15, 25]},
  {"id": "stretching",      "name": "Étirements",           "emoji": "🧘",  "location": "home",    "kcalPerMin": 2.5, "durations": [5, 10, 15]},
  {"id": "plank",           "name": "Gainage / planche",    "emoji": "🧎",  "location": "home",    "kcalPerMin": 4.0, "durations": [3, 5, 8]},
  {"id": "squats",          "name": "Squats",               "emoji": "🦵",  "location": "home",    "kcalPerMin": 5.5, "durations": [3, 5, 10]},
  {"id": "wall_pushups",    "name": "Pompes murales",       "emoji": "🧱",  "location": "home",    "kcalPerMin": 4.0, "durations": [3, 5, 8]},
  {"id": "active_cleaning", "name": "Ménage actif",         "emoji": "🧹",  "location": "home",    "kcalPerMin": 3.5, "durations": [15, 30, 45]},
  {"id": "yoga",            "name": "Yoga doux",            "emoji": "🧘‍♀️", "location": "home",    "kcalPerMin": 3.0, "durations": [10, 20, 30]},
  {"id": "digestive_walk",  "name": "Balade digestive",     "emoji": "🌳",  "location": "outdoor", "kcalPerMin": 3.5, "durations": [10, 15, 20]}
]
```

```json
// NivelCore/Sources/NivelCore/Resources/sessions.json
[
  {"id": "wake_up",           "title": "Réveil musculaire",   "emoji": "🌅", "steps": [{"activityID": "stretching", "minutes": 4}, {"activityID": "squats", "minutes": 4}, {"activityID": "plank", "minutes": 3}]},
  {"id": "energy_break",      "title": "Pause énergie",       "emoji": "⚡", "steps": [{"activityID": "stairs", "minutes": 5}, {"activityID": "dance", "minutes": 5}, {"activityID": "stretching", "minutes": 3}]},
  {"id": "evening_wind_down", "title": "Détente du soir",     "emoji": "🌙", "steps": [{"activityID": "yoga", "minutes": 8}, {"activityID": "stretching", "minutes": 5}]},
  {"id": "quick_tone",        "title": "Tonus express",       "emoji": "💪", "steps": [{"activityID": "squats", "minutes": 4}, {"activityID": "wall_pushups", "minutes": 4}, {"activityID": "plank", "minutes": 4}]},
  {"id": "fresh_air",         "title": "Bol d'air",           "emoji": "🚶", "steps": [{"activityID": "walk", "minutes": 15}]},
  {"id": "mood_boost",        "title": "Boost bonne humeur",  "emoji": "🎵", "steps": [{"activityID": "dance", "minutes": 10}, {"activityID": "stretching", "minutes": 4}]},
  {"id": "zen_core",          "title": "Zen & gainage",       "emoji": "🧘", "steps": [{"activityID": "yoga", "minutes": 6}, {"activityID": "plank", "minutes": 4}, {"activityID": "stretching", "minutes": 4}]},
  {"id": "home_cardio",       "title": "Cardio maison",       "emoji": "🪜", "steps": [{"activityID": "stairs", "minutes": 6}, {"activityID": "squats", "minutes": 3}, {"activityID": "stretching", "minutes": 4}]}
]
```

Note : les Resources du package sont déjà déclarées par dossier dans `NivelCore/Package.swift` (vérifier — si les fichiers sont listés un à un, ajouter les deux nouveaux).

- [ ] **Step 5 : Vérifier le vert**

Run: `cd NivelCore && swift test --filter ActivityCatalogTests`
Expected: PASS (4 tests).

- [ ] **Step 6 : Commit**

```bash
git add NivelCore && git commit -m "feat(core): catalogues activités et séances sport"
```

---

## Task 2 : NivelCore — rotation déterministe de la séance du jour

**Files:**
- Create: `NivelCore/Sources/NivelCore/DailySessionPicker.swift`
- Test: `NivelCore/Tests/NivelCoreTests/DailySessionPickerTests.swift`

- [ ] **Step 1 : Écrire les tests (rouges)**

```swift
// NivelCore/Tests/NivelCoreTests/DailySessionPickerTests.swift
import XCTest
@testable import NivelCore

final class DailySessionPickerTests: XCTestCase {
    /// Calendrier identique à GameService.calendar (ISO, lundi premier jour).
    private var calendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    func testIndexIsPinnedToReferenceDate() {
        // 01/01/2026 = jour 0 → index 0 ; 8 jours plus tard (count 8) → 0 à nouveau.
        XCTAssertEqual(DailySessionPicker.index(for: date(2026, 1, 1), count: 8, calendar: calendar), 0)
        XCTAssertEqual(DailySessionPicker.index(for: date(2026, 1, 9), count: 8, calendar: calendar), 0)
        // 30/07/2026 = 210 jours après la référence → 210 % 8 = 2.
        XCTAssertEqual(DailySessionPicker.index(for: date(2026, 7, 30), count: 8, calendar: calendar), 2)
    }

    func testConsecutiveDaysRotate() {
        let today = DailySessionPicker.index(for: date(2026, 7, 30), count: 8, calendar: calendar)
        let tomorrow = DailySessionPicker.index(for: date(2026, 7, 31), count: 8, calendar: calendar)
        XCTAssertEqual(tomorrow, (today + 1) % 8)
    }

    func testSameDayDifferentHoursSameIndex() {
        XCTAssertEqual(
            DailySessionPicker.index(for: date(2026, 7, 30, hour: 0), count: 8, calendar: calendar),
            DailySessionPicker.index(for: date(2026, 7, 30, hour: 23), count: 8, calendar: calendar)
        )
    }

    func testDatesBeforeReferenceStayInRange() {
        let index = DailySessionPicker.index(for: date(2025, 12, 31), count: 8, calendar: calendar)
        XCTAssertEqual(index, 7) // jour -1 → modulo positif
    }

    func testSessionForDate() throws {
        let sessions = try Catalogs.sessions()
        let session = DailySessionPicker.session(for: date(2026, 1, 1), sessions: sessions, calendar: calendar)
        XCTAssertEqual(session?.id, sessions[0].id)
        XCTAssertNil(DailySessionPicker.session(for: .now, sessions: [], calendar: calendar))
    }
}
```

- [ ] **Step 2 : Vérifier l'échec**

Run: `cd NivelCore && swift test --filter DailySessionPickerTests`
Expected: FAIL (compile error).

- [ ] **Step 3 : Implémenter**

```swift
// NivelCore/Sources/NivelCore/DailySessionPicker.swift
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
```

- [ ] **Step 4 : Vérifier le vert**

Run: `cd NivelCore && swift test --filter DailySessionPickerTests`
Expected: PASS (5 tests).

- [ ] **Step 5 : Commit**

```bash
git add NivelCore && git commit -m "feat(core): rotation déterministe de la séance du jour"
```

---

## Task 3 : NivelCore — XP sport (XPEngine)

**Files:**
- Modify: `NivelCore/Sources/NivelCore/XPEngine.swift`
- Test: `NivelCore/Tests/NivelCoreTests/XPEngineTests.swift`

- [ ] **Step 1 : Ajouter le test (rouge)**

Dans `XPEngineTests.swift`, ajouter :

```swift
    func testActivityXPCappedAtTwoPerDay() {
        XCTAssertEqual(XPEngine.award(.activityDone, todayCount: 0), 30)
        XCTAssertEqual(XPEngine.award(.activityDone, todayCount: 1), 30)
        XCTAssertEqual(XPEngine.award(.activityDone, todayCount: 2), 0)
    }

    func testDailySessionXPCappedAtOnePerDay() {
        XCTAssertEqual(XPEngine.award(.dailySessionDone, todayCount: 0), 40)
        XCTAssertEqual(XPEngine.award(.dailySessionDone, todayCount: 1), 0)
    }
```

- [ ] **Step 2 : Vérifier l'échec**

Run: `cd NivelCore && swift test --filter XPEngineTests`
Expected: FAIL (compile error — cases inconnus).

- [ ] **Step 3 : Implémenter**

Dans `XPEngine.swift` : ajouter `activityDone, dailySessionDone` à l'enum `XPAction`, et dans `award` :

```swift
        case .activityDone:    todayCount < 2 ? 30 : 0
        case .dailySessionDone: todayCount < 1 ? 40 : 0
```

- [ ] **Step 4 : Vérifier le vert**

Run: `cd NivelCore && swift test --filter XPEngineTests`
Expected: PASS.

- [ ] **Step 5 : Commit**

```bash
git add NivelCore && git commit -m "feat(core): XP activité (30, max 2/j) et séance du jour (40, max 1/j)"
```

---

## Task 4 : NivelCore — contexte Nivelito `afterActivity` + 12 messages

**Files:**
- Modify: `NivelCore/Sources/NivelCore/MessageBank.swift` (enum + doc du contrat {value})
- Modify: `NivelCore/Sources/NivelCore/Resources/messages.json`
- Test: `NivelCore/Tests/NivelCoreTests/MessageBankTests.swift`

- [ ] **Step 1 : Ajouter le test (rouge)**

Dans `MessageBankTests.swift`, ajouter :

```swift
    func testAfterActivityMessagesSubstituteValue() throws {
        let bank = try MessageBank.load()
        for _ in 0..<20 {
            let msg = bank.pick(context: .afterActivity, excluding: nil, name: "Marion", value: 30)
            XCTAssertFalse(msg.text.contains("{name}"))
            XCTAssertFalse(msg.text.contains("{value}"))
        }
    }
```

Note : `testBankHasAllContextsWithEnoughVariety` (existant) couvrira automatiquement le nouveau contexte via `MessageContext.allCases` — il exige **≥ 12 messages**.

- [ ] **Step 2 : Vérifier l'échec**

Run: `cd NivelCore && swift test --filter MessageBankTests`
Expected: FAIL (compile error — `.afterActivity` inconnu).

- [ ] **Step 3 : Implémenter**

Dans `MessageBank.swift` : ajouter `afterActivity` à `MessageContext` (l'enum est `CaseIterable`), et compléter le doc-comment de `pick` : les contextes à `{value}` sont `afterMealLog`, `afterActivity`, `levelUp`, `questCompleted`.

Dans `messages.json`, ajouter la clé `"afterActivity"` (12 messages, ton bienveillant, `{value}` = XP gagné — toujours appelé avec `value` non nil) :

```json
  "afterActivity": [
    {"id": "act1",  "text": "Et hop, +{value} XP ! Ton corps te dit merci 🧡"},
    {"id": "act2",  "text": "Bien bougé, {name} ! +{value} XP au compteur."},
    {"id": "act3",  "text": "Chaque mouvement compte. +{value} XP !"},
    {"id": "act4",  "text": "Moi je fais la sieste, toi tu bouges — chacun son talent. +{value} XP !"},
    {"id": "act5",  "text": "Tu l'as fait ! +{value} XP bien mérités."},
    {"id": "act6",  "text": "Ni vu ni connu, +{value} XP dans la poche."},
    {"id": "act7",  "text": "Ton cœur bat un peu plus fort, moi je suis un peu plus fier. +{value} XP !"},
    {"id": "act8",  "text": "Une activité de plus ! +{value} XP, bravo {name}."},
    {"id": "act9",  "text": "Le canapé attendra — bien joué ! +{value} XP"},
    {"id": "act10", "text": "Petit exercice, grand effet. +{value} XP 🧡"},
    {"id": "act11", "text": "Même un panda applaudirait… si ses pattes suivaient. +{value} XP !"},
    {"id": "act12", "text": "Bouger comme ça, ça mérite bien +{value} XP."}
  ]
```

- [ ] **Step 4 : Vérifier le vert**

Run: `cd NivelCore && swift test --filter MessageBankTests`
Expected: PASS (4 tests, dont la variété ≥ 12 pour tous les contextes).

- [ ] **Step 5 : Commit**

```bash
git add NivelCore && git commit -m "feat(core): contexte Nivelito afterActivity (12 messages)"
```

---

## Task 5 : NivelCore — métriques de quêtes sport + quests.json

**Files:**
- Modify: `NivelCore/Sources/NivelCore/QuestEngine.swift` (enum Metric)
- Modify: `NivelCore/Sources/NivelCore/Resources/quests.json` (3 entrées)
- Test: `NivelCore/Tests/NivelCoreTests/CatalogsTests.swift`, `NivelCore/Tests/NivelCoreTests/QuestEngineTests.swift`

- [ ] **Step 1 : Mettre à jour les tests (rouges)**

Dans `CatalogsTests.testQuestsLoadAndIdsAreUnique` : remplacer les deux `15` par `18`, et ajouter :

```swift
        XCTAssertTrue(quests.contains { $0.id == "activities_3" && $0.metric == .activitiesDone })
        XCTAssertTrue(quests.contains { $0.id == "daily_sessions_2" && $0.metric == .dailySessionsDone })
```

- [ ] **Step 2 : Vérifier l'échec**

Run: `cd NivelCore && swift test --filter CatalogsTests`
Expected: FAIL (compile error — metrics inconnues).

- [ ] **Step 3 : Implémenter**

Dans `QuestEngine.swift`, enum `Quest.Metric` : ajouter `activitiesDone, dailySessionsDone` à la liste des cases.

Dans `quests.json`, ajouter :

```json
  {"id": "activities_3",     "title": "Fais 3 activités cette semaine",          "emoji": "🏃", "metric": "activitiesDone",   "target": 3,     "requiresSteps": false},
  {"id": "activities_5",     "title": "Fais 5 activités cette semaine",          "emoji": "💪", "metric": "activitiesDone",   "target": 5,     "requiresSteps": false},
  {"id": "daily_sessions_2", "title": "Fais 2 séances du jour",                  "emoji": "📅", "metric": "dailySessionsDone","target": 2,     "requiresSteps": false}
```

(`slot` omis = décodé nil, comme les entrées existantes sans slot.)

- [ ] **Step 4 : Lancer TOUTE la suite et re-pinner le tirage**

Run: `cd NivelCore && swift test`
Expected: `testWeeklyDrawIsPinnedForKnownWeek` **FAIL** — le pool a changé, le tirage seedé de `2026-W31` aussi. C'est le comportement attendu du test de régression.

Copier les 3 ids réellement tirés (affichés dans le message d'échec) dans l'assertion du test, et mettre à jour le commentaire « pool de 15 » de `testDrawIsDeterministicForSameWeek` en « pool de 18 ».

⚠️ Conséquence produit assumée : les quêtes de la semaine COURANTE re-tirées après mise à jour de l'app changeront une fois (le tirage dépend du pool). Les progressions/récompenses déjà acquises sont conservées (`completedThisWeekQuestIDs` garde la re-récompense). Pas de code à écrire — juste ne pas s'étonner.

- [ ] **Step 5 : Vérifier le vert complet**

Run: `cd NivelCore && swift test`
Expected: PASS (toute la suite NivelCore).

- [ ] **Step 6 : Commit**

```bash
git add NivelCore && git commit -m "feat(core): quêtes sport (activitiesDone, dailySessionsDone)"
```

---

## Task 6 : NivelCore — badges sport + badges.json

**Files:**
- Modify: `NivelCore/Sources/NivelCore/BadgeEngine.swift` (Metric + BadgeStats)
- Modify: `NivelCore/Sources/NivelCore/Resources/badges.json` (4 entrées)
- Test: `NivelCore/Tests/NivelCoreTests/CatalogsTests.swift`, `NivelCore/Tests/NivelCoreTests/BadgeEngineTests.swift`

- [ ] **Step 1 : Mettre à jour les tests (rouges)**

`CatalogsTests.testBadgesLoadAndIdsAreUnique` : remplacer les deux `20` par `24`.
Dans `BadgeEngineTests.swift`, ajouter :

```swift
    func testSportBadgesUnlockOnActivityCounters() throws {
        let badges = try Catalogs.badges()
        var stats = BadgeStats()
        stats.activitiesDone = 10
        stats.dailySessionsDone = 5
        let unlocked = BadgeEngine.newlyUnlocked(badges: badges, stats: stats, alreadyUnlocked: [])
        let ids = Set(unlocked.map(\.id))
        XCTAssertTrue(ids.isSuperset(of: ["sport_first", "sport_10", "sport_sessions_5"]))
        XCTAssertFalse(ids.contains("sport_50"))
    }
```

- [ ] **Step 2 : Vérifier l'échec**

Run: `cd NivelCore && swift test --filter "CatalogsTests|BadgeEngineTests"`
Expected: FAIL (compile error — `activitiesDone` inconnu sur BadgeStats).

- [ ] **Step 3 : Implémenter**

Dans `BadgeEngine.swift` :
- `Badge.Metric` : ajouter `activitiesDone, dailySessionsDone`.
- `BadgeStats` : ajouter `activitiesDone = 0, dailySessionsDone = 0` aux propriétés, et les deux cases dans `value(for:)`.

Dans `badges.json`, ajouter :

```json
  {"id": "sport_first",      "title": "Premier pas",           "emoji": "🥇", "hint": "Valide ta première activité",          "metric": "activitiesDone",    "threshold": 1},
  {"id": "sport_10",         "title": "En mouvement",          "emoji": "🏃", "hint": "Valide 10 activités",                  "metric": "activitiesDone",    "threshold": 10},
  {"id": "sport_50",         "title": "Machine",               "emoji": "🔥", "hint": "Valide 50 activités",                  "metric": "activitiesDone",    "threshold": 50},
  {"id": "sport_sessions_5", "title": "Rituel du jour",        "emoji": "📅", "hint": "Fais 5 séances du jour",               "metric": "dailySessionsDone", "threshold": 5}
]
```

- [ ] **Step 4 : Vérifier le vert**

Run: `cd NivelCore && swift test`
Expected: PASS (toute la suite).

- [ ] **Step 5 : Commit**

```bash
git add NivelCore && git commit -m "feat(core): badges sport (compteurs activités et séances)"
```

---

## Task 7 : App — @Model ActivityEntry + enregistrement dans tous les schémas

**Files:**
- Modify: `App/Models/PersistentModels.swift`
- Modify: `App/NivelApp.swift` (ModelContainer)
- Modify: **tous** les sites `Schema([...])` — les trouver avec `grep -rn "GamificationState.self" App NivelTests`
- Test: `NivelTests/AppSmokeTests.swift`

- [ ] **Step 1 : Ajouter le test (rouge)**

Dans `AppSmokeTests.swift`, ajouter `import NivelCore` (pour `ActivityKind`), puis dans `testInMemoryContainerInsertsAndFetchesModels` ajouter `ActivityEntry.self` au `Schema([...])` et, après le bloc repas :

```swift
        let activity = ActivityEntry(kind: .activity, refID: "walk",
                                     durationMinutes: 20, estimatedKcal: 80, xpAwarded: 30)
        context.insert(activity)
```

et après les assertions repas :

```swift
        let fetchedActivities = try context.fetch(FetchDescriptor<ActivityEntry>())
        XCTAssertEqual(fetchedActivities.count, 1)
        XCTAssertEqual(fetchedActivities.first?.kind, .activity)
        XCTAssertEqual(fetchedActivities.first?.refID, "walk")
```

- [ ] **Step 2 : Vérifier l'échec (compile)**

Run: `xcodebuild -project Nivel.xcodeproj -scheme Nivel -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | tail -20`
Expected: BUILD FAILED (`ActivityEntry` inconnu).

- [ ] **Step 3 : Implémenter le modèle**

Dans `PersistentModels.swift`, après `MealEntry` :

```swift
@Model
final class ActivityEntry {
    var date: Date
    var kindRaw: String                  // ActivityKind (activité libre / séance du jour)
    var refID: String                    // activityID ou sessionID selon kind
    var durationMinutes: Int
    var estimatedKcal: Int               // indicatif — jamais crédité au budget (spec sport §2)
    var xpAwarded: Int

    init(
        date: Date = .now,
        kind: ActivityKind,
        refID: String,
        durationMinutes: Int,
        estimatedKcal: Int,
        xpAwarded: Int = 0
    ) {
        self.date = date
        self.kindRaw = kind.rawValue
        self.refID = refID
        self.durationMinutes = durationMinutes
        self.estimatedKcal = estimatedKcal
        self.xpAwarded = xpAwarded
    }

    var kind: ActivityKind {
        get { ActivityKind(rawValue: kindRaw) ?? .activity }
        set { kindRaw = newValue.rawValue }
    }
}
```

- [ ] **Step 4 : Enregistrer ActivityEntry PARTOUT**

`grep -rn "GamificationState.self" App NivelTests` puis ajouter `ActivityEntry.self` à chaque liste (`NivelApp.init`, previews de `RootView`/`HomeView`/`MealLogSheet`/etc., fixtures de tests). Aucun site ne doit rester sans lui.

- [ ] **Step 5 : Vérifier le vert**

Run: `xcodegen generate && xcodebuild -project Nivel.xcodeproj -scheme Nivel -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | tail -5`
Expected: TEST SUCCEEDED.

- [ ] **Step 6 : Commit**

```bash
git add -A && git commit -m "feat(app): modèle ActivityEntry (SwiftData)"
```

---

## Task 8 : App — GameService+Sport (log, plafonds, quêtes, badges, suppression)

**Files:**
- Modify: `App/Services/GameService.swift` (catalogues + signal + questValue + badgeStats + visibilité `dayBounds`)
- Create: `App/Services/GameService+Sport.swift`
- Test (create): `NivelTests/SportServiceTests.swift`

- [ ] **Step 1 : Écrire les tests (rouges)**

```swift
// NivelTests/SportServiceTests.swift
import XCTest
import SwiftData
import NivelCore
@testable import Nivel

@MainActor
final class SportServiceTests: XCTestCase {
    private var context: ModelContext!
    private var service: GameService!
    private var walk: Activity!
    private var session: ActivitySession!

    override func setUp() async throws {
        let schema = Schema([
            UserProfile.self, MealEntry.self, WeightEntry.self,
            DayLog.self, GamificationState.self, ActivityEntry.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
        context.insert(UserProfile(
            name: "Michaël", sex: .male, birthDate: Date(timeIntervalSince1970: 0),
            heightCm: 180, initialWeightKg: 90, activity: .moderate, dailyCalorieTarget: 2000
        ))
        context.insert(GamificationState())
        try context.save()

        service = GameService(modelContext: context, stepsService: FakeStepsService(authorized: false))
        walk = try XCTUnwrap(service.activityCatalog.first { $0.id == "walk" })
        session = try XCTUnwrap(service.sessionCatalog.first { $0.id == "wake_up" })
    }

    func testLogActivityAwardsCappedXPAndSurvivesRestart() async throws {
        var awarded: [Int] = []
        for _ in 1...3 {
            let entry = await service.logActivity(activity: walk, durationMinutes: 20)
            awarded.append(entry.xpAwarded)
        }
        XCTAssertEqual(awarded, [30, 30, 0])
        XCTAssertEqual(service.lastActivityXPAwarded, 0)

        // Le plafond est dérivé des ActivityEntry persistées → tient à la "relance".
        let restarted = GameService(modelContext: context, stepsService: FakeStepsService(authorized: false))
        let fourth = await restarted.logActivity(activity: walk, durationMinutes: 10)
        XCTAssertEqual(fourth.xpAwarded, 0)

        // kcal estimées : 20 min × 4,0 = 80 ; PAS de DayLog créé (jamais crédité au budget).
        let first = try XCTUnwrap(try context.fetch(FetchDescriptor<ActivityEntry>(
            sortBy: [SortDescriptor(\.date)])).first)
        XCTAssertEqual(first.estimatedKcal, 80)
        XCTAssertTrue(try context.fetch(FetchDescriptor<DayLog>()).isEmpty)
    }

    func testDailySessionXPCappedAtOnePerDayIndependentlyOfActivities() async throws {
        _ = await service.logActivity(activity: walk, durationMinutes: 10)     // n'entame pas le plafond séance
        let first = await service.logDailySession(session: session)
        let second = await service.logDailySession(session: session)
        XCTAssertEqual(first.xpAwarded, 40)
        XCTAssertEqual(first.estimatedKcal, 40)   // 4×2,5 + 4×5,5 + 3×4,0 = 44 → 40
        XCTAssertEqual(first.durationMinutes, session.totalMinutes)
        XCTAssertEqual(second.xpAwarded, 0)
    }

    func testSportQuestsProgressAndComplete() async throws {
        let state = try XCTUnwrap(try context.fetch(FetchDescriptor<GamificationState>()).first)
        state.questWeekID = QuestEngine.weekID(for: .now, calendar: GameService.calendar)
        state.activeQuestIDs = ["activities_3", "daily_sessions_2"]
        try context.save()

        _ = await service.logActivity(activity: walk, durationMinutes: 10)
        _ = await service.logActivity(activity: walk, durationMinutes: 10)
        XCTAssertEqual(state.questProgress["activities_3"], 2)

        // La séance du jour compte pour LES DEUX métriques (c'est une activité aussi).
        _ = await service.logDailySession(session: session)
        XCTAssertEqual(state.questProgress["activities_3"], 3)
        XCTAssertEqual(state.questProgress["daily_sessions_2"], 1)
        XCTAssertTrue(state.completedThisWeekQuestIDs.contains("activities_3"))
        XCTAssertTrue(service.pendingCelebrations.contains { $0.id == "quest-activities_3" })
    }

    func testFirstActivityUnlocksSportBadge() async throws {
        _ = await service.logActivity(activity: walk, durationMinutes: 10)
        let state = try XCTUnwrap(try context.fetch(FetchDescriptor<GamificationState>()).first)
        XCTAssertNotNil(state.badgeUnlocks["sport_first"])
        XCTAssertTrue(service.pendingCelebrations.contains {
            if case .badge(let badge) = $0 { badge.id == "sport_first" } else { false }
        })
    }

    func testDeleteActivityKeepsXPAndRemovesEntry() async throws {
        let entry = await service.logActivity(activity: walk, durationMinutes: 10)
        let state = try XCTUnwrap(try context.fetch(FetchDescriptor<GamificationState>()).first)
        let xpBefore = state.totalXP
        await service.deleteActivity(entry: entry)
        XCTAssertEqual(state.totalXP, xpBefore)   // jamais de retrait d'XP
        XCTAssertTrue(try context.fetch(FetchDescriptor<ActivityEntry>()).isEmpty)
    }

    func testDailySessionStatusFlipsToDone() async throws {
        let before = try XCTUnwrap(service.dailySessionStatus())
        XCTAssertFalse(before.done)
        _ = await service.logDailySession(session: before.session)
        let after = try XCTUnwrap(service.dailySessionStatus())
        XCTAssertEqual(after.session.id, before.session.id)
        XCTAssertTrue(after.done)
    }
}
```

- [ ] **Step 2 : Vérifier l'échec (compile)**

Run: `xcodebuild -project Nivel.xcodeproj -scheme Nivel -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | tail -20`
Expected: BUILD FAILED (`activityCatalog`, `logActivity`… inconnus).

- [ ] **Step 3 : Modifier GameService.swift**

1. Propriétés (à côté de `questCatalog`) :

```swift
    let activityCatalog: [Activity]
    let sessionCatalog: [ActivitySession]
    /// Index id → Activity (kcal des séances, libellés des vues).
    let activitiesByID: [String: Activity]
```

2. Signal pour la bulle (à côté de `lastMealXPAwarded`, même contrat : nil sinon, 0 = plafonné → pas de bulle) :

```swift
    /// XP attribué à l'activité qui VIENT d'être validée — consommé par l'accueil
    /// pour la bulle `afterActivity` (miroir de `lastMealXPAwarded`).
    var lastActivityXPAwarded: Int?
```

3. Dans `init`, après le chargement des catalogues existants :

```swift
        self.activityCatalog = Self.loadOrAssert({ try Catalogs.activities() }, fallback: [])
        self.sessionCatalog = Self.loadOrAssert({ try Catalogs.sessions() }, fallback: [])
        self.activitiesByID = Dictionary(uniqueKeysWithValues: activityCatalog.map { ($0.id, $0) })
```

4. Dans `questValue(for:week:mealsByDay:stepsByDay:)`, ajouter les cases :

```swift
        case .activitiesDone:
            return activityCount(from: week.start, to: week.end)
        case .dailySessionsDone:
            return activityCount(from: week.start, to: week.end, kind: .dailySession)
```

5. Dans `badgeStats()`, avant `return stats` :

```swift
        let activities = (try? modelContext.fetch(FetchDescriptor<ActivityEntry>())) ?? []
        stats.activitiesDone = activities.count
        stats.dailySessionsDone = activities.count { $0.kind == .dailySession }
```

6. Visibilité pour l'extension (même type, autre fichier — `private` n'y est PAS visible, contrairement à DayCloser qui ne touche jamais le store directement) :
   - `private let modelContext` → `let modelContext` (internal), en adaptant son commentaire ;
   - `private func dayBounds` → `func dayBounds` (internal).

- [ ] **Step 4 : Créer GameService+Sport.swift**

```swift
// App/Services/GameService+Sport.swift
// Section Sport (spec sport §5-6) : validation d'activités et de séances du jour.
// Miroir de logMeal — XP plafonné dérivé du store, quêtes, badges, level-up.
// AUCUNE écriture dans DayLog : les kcal brûlées sont indicatives, jamais créditées.

import Foundation
import SwiftData
import NivelCore

extension GameService {
    // MARK: - Validation

    /// Valide une activité libre : +30 XP (max 2 activités récompensées/jour).
    @discardableResult
    func logActivity(activity: Activity, durationMinutes: Int, date: Date = .now) async -> ActivityEntry {
        await logSport(kind: .activity, refID: activity.id, minutes: durationMinutes,
                       kcal: activity.estimatedKcal(minutes: durationMinutes), date: date)
    }

    /// Valide la séance du jour : +40 XP (max 1/jour, indépendant du plafond activités).
    @discardableResult
    func logDailySession(session: ActivitySession, date: Date = .now) async -> ActivityEntry {
        await logSport(kind: .dailySession, refID: session.id, minutes: session.totalMinutes,
                       kcal: session.estimatedKcal(activitiesByID: activitiesByID), date: date)
    }

    private func logSport(kind: ActivityKind, refID: String, minutes: Int,
                          kcal: Int, date: Date) async -> ActivityEntry {
        let state = fetchOrCreateState()
        let levelBefore = LevelSystem.level(forXP: state.totalXP)

        // Plafond robuste aux relances : dérivé des ActivityEntry persistées (par kind).
        let action: XPAction = kind == .dailySession ? .dailySessionDone : .activityDone
        let xp = XPEngine.award(action, todayCount: sportAwardedCount(kind: kind, on: date))

        let entry = ActivityEntry(date: date, kind: kind, refID: refID,
                                  durationMinutes: minutes, estimatedKcal: kcal, xpAwarded: xp)
        modelContext.insert(entry)
        state.totalXP += xp
        lastActivityXPAwarded = xp

        await refreshQuestProgress()
        evaluateBadges(state: state)
        detectLevelUp(state: state, levelBefore: levelBefore)
        saveOrAssert()
        return entry
    }

    /// Supprime une validation (jour même). L'XP est CONSERVÉ (spec v1 §7.1) — cas
    /// assumé : un re-log après suppression peut être récompensé à nouveau.
    func deleteActivity(entry: ActivityEntry) async {
        assert(Self.calendar.isDateInToday(entry.date), "suppression réservée au jour même")
        let state = fetchOrCreateState()
        let levelBefore = LevelSystem.level(forXP: state.totalXP)
        modelContext.delete(entry)
        await refreshQuestProgress()
        evaluateBadges(state: state)
        detectLevelUp(state: state, levelBefore: levelBefore)
        saveOrAssert()
    }

    // MARK: - Exposition pour les vues

    /// Séance du jour (rotation déterministe, spec sport §3.3) + état « déjà faite ».
    func dailySessionStatus(now: Date = .now) -> (session: ActivitySession, done: Bool)? {
        guard let session = DailySessionPicker.session(for: now, sessions: sessionCatalog,
                                                       calendar: Self.calendar) else { return nil }
        return (session, sportCount(kind: .dailySession, on: now) > 0)
    }

    /// Kcal estimées d'une séance (catalogue chargé une fois à l'init).
    func sessionKcal(_ session: ActivitySession) -> Int {
        session.estimatedKcal(activitiesByID: activitiesByID)
    }

    /// Validations du jour, chronologiques — liste « Fait aujourd'hui ».
    func todayActivities(now: Date = .now) -> [ActivityEntry] {
        guard let (start, end) = dayBounds(for: now) else { return [] }
        let descriptor = FetchDescriptor<ActivityEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Compteurs

    /// Validations sur [start, end[, optionnellement filtrées par kind (quêtes hebdo).
    func activityCount(from start: Date, to end: Date, kind: ActivityKind? = nil) -> Int {
        let predicate: Predicate<ActivityEntry>
        if let kind {
            let kindRaw = kind.rawValue
            predicate = #Predicate { $0.date >= start && $0.date < end && $0.kindRaw == kindRaw }
        } else {
            predicate = #Predicate { $0.date >= start && $0.date < end }
        }
        return (try? modelContext.fetchCount(FetchDescriptor(predicate: predicate))) ?? 0
    }

    /// Validations du kind ce jour-là (peu importe l'XP).
    private func sportCount(kind: ActivityKind, on date: Date) -> Int {
        guard let (start, end) = dayBounds(for: date) else { return 0 }
        return activityCount(from: start, to: end, kind: kind)
    }

    /// Validations DÉJÀ récompensées en XP ce jour-là, par kind (plafond persistant).
    private func sportAwardedCount(kind: ActivityKind, on date: Date) -> Int {
        guard let (start, end) = dayBounds(for: date) else { return 0 }
        let kindRaw = kind.rawValue
        let predicate = #Predicate<ActivityEntry> {
            $0.date >= start && $0.date < end && $0.kindRaw == kindRaw && $0.xpAwarded > 0
        }
        return (try? modelContext.fetchCount(FetchDescriptor(predicate: predicate))) ?? 0
    }
}
```

- [ ] **Step 5 : Vérifier le vert**

Run: `xcodegen generate && xcodebuild -project Nivel.xcodeproj -scheme Nivel -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | tail -5`
Expected: TEST SUCCEEDED (dont les 6 nouveaux SportServiceTests).

- [ ] **Step 6 : Commit**

```bash
git add -A && git commit -m "feat(app): GameService sport — validation, plafonds XP, quêtes, badges"
```

---

## Task 9 : App — vues Sport (carte séance, sheets, onglet)

**Files:**
- Create: `App/Views/Sport/DailySessionCard.swift`
- Create: `App/Views/Sport/SessionDetailSheet.swift`
- Create: `App/Views/Sport/ActivityLogSheet.swift`
- Create: `App/Views/Sport/SportView.swift`

Pas de TDD sur les vues (comme le reste du projet) : implémentation + build + previews. Style : Theme existant, `.card()`, gradient `Theme.accent → Theme.orange` pour les CTA, JAMAIS de rouge.

- [ ] **Step 1 : DailySessionCard (composant partagé accueil/onglet)**

```swift
// App/Views/Sport/DailySessionCard.swift
// Carte « Séance du jour » (spec sport §8.2) — partagée entre l'accueil et l'onglet
// Sport. Toujours visible, l'état ✓ n'est jamais punitif.

import SwiftUI
import NivelCore

/// Version « carte » (avec `.card()`) pour l'accueil ; l'onglet Sport utilise
/// directement `DailySessionCardContent` dans une List (le row a déjà son fond).
struct DailySessionCard: View {
    let session: ActivitySession
    let kcal: Int
    let done: Bool

    var body: some View {
        DailySessionCardContent(session: session, kcal: kcal, done: done)
            .card()
    }
}

struct DailySessionCardContent: View {
    let session: ActivitySession
    let kcal: Int
    let done: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(session.emoji)
                .font(.system(size: 32))
            VStack(alignment: .leading, spacing: 3) {
                Text("SÉANCE DU JOUR")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(0.5)
                    .foregroundStyle(Theme.subtext)
                Text(session.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text("\(session.totalMinutes) min · ~\(kcal.frFormatted) kcal")
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
            }
            Spacer()
            if done {
                Label("Faite !", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.green)
            } else {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

- [ ] **Step 2 : SessionDetailSheet**

```swift
// App/Views/Sport/SessionDetailSheet.swift
// Détail de la séance du jour (spec sport §8.4) : étapes + « C'est fait ! ».
// Déjà faite aujourd'hui → état ✓ inactif (pas de double validation).

import SwiftUI
import UIKit
import NivelCore

struct SessionDetailSheet: View {
    @Environment(GameService.self) private var game
    @Environment(\.dismiss) private var dismiss

    let session: ActivitySession
    let done: Bool
    @State private var isSaving = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 10) {
                        Text(session.emoji).font(.system(size: 40))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Séance du jour")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.subtext)
                            Text(session.title)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.text)
                        }
                    }
                    VStack(spacing: 10) {
                        ForEach(Array(session.steps.enumerated()), id: \.offset) { _, step in
                            stepRow(step)
                        }
                    }
                }
                .padding(20)
            }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .presentationDetents([.medium, .large])
    }

    private func stepRow(_ step: SessionStep) -> some View {
        let activity = game.activitiesByID[step.activityID]
        return HStack(spacing: 12) {
            Text(activity?.emoji ?? "🏃").font(.system(size: 26))
            Text(activity?.name ?? step.activityID)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.text)
            Spacer()
            Text("\(step.minutes) min")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.orange)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Total")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.subtext)
                Text("\(session.totalMinutes) min · ~\(game.sessionKcal(session).frFormatted) kcal")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
            }
            Spacer()
            if done {
                Label("Déjà faite aujourd'hui", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.green)
            } else {
                Button(action: validate) {
                    Text("C'est fait ! (+40 XP)")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(colors: [Theme.accent, Theme.orange],
                                           startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: Theme.buttonRadius)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.card.ignoresSafeArea(edges: .bottom))
        .shadow(color: .black.opacity(0.08), radius: 10, y: -4)
    }

    private func validate() {
        guard !isSaving else { return }
        isSaving = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            await game.logDailySession(session: session)
            dismiss()
        }
    }
}
```

- [ ] **Step 3 : ActivityLogSheet**

```swift
// App/Views/Sport/ActivityLogSheet.swift
// Validation d'une activité libre (spec sport §8.4) : 3 durées → « C'est fait ! ».

import SwiftUI
import UIKit
import NivelCore

struct ActivityLogSheet: View {
    @Environment(GameService.self) private var game
    @Environment(\.dismiss) private var dismiss

    let activity: Activity
    @State private var selectedMinutes: Int?
    @State private var isSaving = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 10) {
                    Text(activity.emoji).font(.system(size: 40))
                    Text(activity.name)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.text)
                }
                Text("Durée")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                HStack(spacing: 8) {
                    ForEach(activity.durations, id: \.self) { minutes in
                        durationButton(minutes)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .presentationDetents([.medium])
    }

    private func durationButton(_ minutes: Int) -> some View {
        let isSelected = selectedMinutes == minutes
        return Button {
            selectedMinutes = minutes
        } label: {
            VStack(spacing: 3) {
                Text("\(minutes) min")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isSelected ? .white : Theme.text)
                Text("~\(activity.estimatedKcal(minutes: minutes).frFormatted) kcal")
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .white.opacity(0.85) : Theme.subtext)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? Theme.orange : Theme.card,
                        in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
        Button(action: validate) {
            Text("C'est fait ! (+30 XP)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(colors: [Theme.accent, Theme.orange],
                                   startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: Theme.buttonRadius)
                )
                .opacity(selectedMinutes == nil ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(selectedMinutes == nil || isSaving)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.card.ignoresSafeArea(edges: .bottom))
        .shadow(color: .black.opacity(0.08), radius: 10, y: -4)
    }

    private func validate() {
        guard let minutes = selectedMinutes, !isSaving else { return }
        isSaving = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            await game.logActivity(activity: activity, durationMinutes: minutes)
            dismiss()
        }
    }
}
```

- [ ] **Step 4 : SportView (onglet)**

Structure en `List` (comme le journal Repas : `.insetGrouped`, fond masqué, `listRowBackground(Theme.card)`) pour avoir les `swipeActions` de suppression. Rechargement : `@State` + `reload()` dans `.task` et à la fermeture des sheets (le parent applique `.id(dayKey)` — Task 10 — donc « aujourd'hui » suit le changement de jour).

```swift
// App/Views/Sport/SportView.swift
// Onglet Sport (spec sport §8.3) : séance du jour, catalogue Maison/Dehors,
// « Fait aujourd'hui » (swipe = supprimer, jour même par construction).

import SwiftUI
import SwiftData
import NivelCore

struct SportView: View {
    @Environment(GameService.self) private var game

    @State private var sessionStatus: (session: ActivitySession, done: Bool)?
    @State private var todayEntries: [ActivityEntry] = []
    @State private var selectedActivity: Activity?
    @State private var showSessionDetail = false

    private var homeActivities: [Activity] {
        game.activityCatalog.filter { $0.location != .outdoor }
    }
    private var outdoorActivities: [Activity] {
        game.activityCatalog.filter { $0.location == .outdoor }
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            List {
                Section {
                    if let status = sessionStatus {
                        Button { showSessionDetail = true } label: {
                            DailySessionCardContent(session: status.session,
                                                    kcal: game.sessionKcal(status.session),
                                                    done: status.done)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Theme.card)
                    }
                } header: { header }

                activitySection("🏠 À la maison", activities: homeActivities)
                activitySection("🌳 Dehors", activities: outdoorActivities)

                if !todayEntries.isEmpty {
                    Section {
                        ForEach(todayEntries) { entry in
                            doneRow(entry)
                        }
                    } header: {
                        Text("Fait aujourd'hui")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Theme.subtext)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .task { reload() }
        .sheet(isPresented: $showSessionDetail, onDismiss: reload) {
            if let status = sessionStatus {
                SessionDetailSheet(session: status.session, done: status.done)
            }
        }
        .sheet(item: $selectedActivity, onDismiss: reload) { activity in
            ActivityLogSheet(activity: activity)
        }
    }

    private func reload() {
        sessionStatus = game.dailySessionStatus()
        todayEntries = game.todayActivities()
    }

    private var header: some View {
        Text("Sport")
            .font(.system(size: 26, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.text)
            .textCase(nil)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 10, trailing: 0))
    }

    private func activitySection(_ title: String, activities: [Activity]) -> some View {
        Section {
            ForEach(activities) { activity in
                Button { selectedActivity = activity } label: {
                    HStack(spacing: 12) {
                        Text(activity.emoji).font(.system(size: 26))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activity.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.text)
                            // Fourchette kcal indicative (spec sport §8.3) sur les durées min/max.
                            Text(activity.durations.map(String.init).joined(separator: " / ")
                                 + " min · ~\(activity.estimatedKcal(minutes: activity.durations.first ?? 0))"
                                 + " à \(activity.estimatedKcal(minutes: activity.durations.last ?? 0)) kcal")
                                .font(.caption)
                                .foregroundStyle(Theme.subtext)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.subtext)
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(Theme.card)
            }
        } header: {
            Text(title)
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.subtext)
        }
    }

    private func doneRow(_ entry: ActivityEntry) -> some View {
        let (emoji, name): (String, String) = {
            switch entry.kind {
            case .activity:
                let activity = game.activitiesByID[entry.refID]
                return (activity?.emoji ?? "🏃", activity?.name ?? entry.refID)
            case .dailySession:
                let session = game.sessionCatalog.first { $0.id == entry.refID }
                return (session?.emoji ?? "📅", session?.title ?? entry.refID)
            }
        }()
        return HStack(spacing: 12) {
            Text(emoji).font(.system(size: 26))
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text("\(entry.durationMinutes) min")
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
            }
            Spacer()
            Text("~\(entry.estimatedKcal.frFormatted) kcal")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.orange)
        }
        .listRowBackground(Theme.card)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                Task {
                    await game.deleteActivity(entry: entry)
                    reload()
                }
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
            .tint(Theme.accent)   // accent, pas rouge (spec v1 §7.4)
        }
    }
}
```

`Activity` doit être `Identifiable` pour `.sheet(item:)` — c'est déjà le cas (Task 1).

- [ ] **Step 5 : Build + previews**

Ajouter un `#Preview` à `SportView.swift` sur le modèle de `HomeView` (container in-memory + `GameService` + `FakeStepsService()`, schéma AVEC `ActivityEntry.self`).

Run: `xcodegen generate && xcodebuild -project Nivel.xcodeproj -scheme Nivel -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -3`
Expected: BUILD SUCCEEDED.

- [ ] **Step 6 : Commit**

```bash
git add -A && git commit -m "feat(app): vues Sport — séance du jour, catalogue, fait aujourd'hui"
```

---

## Task 10 : App — navigation : onglet Sport, Réglages → ⚙️ accueil

**Files:**
- Modify: `App/RootView.swift` (MainTabView)
- Modify: `App/Views/Home/HomeView.swift` (bouton ⚙️ dans l'en-tête)

- [ ] **Step 1 : MainTabView — remplacer l'onglet Réglages par Sport**

Dans l'enum `Tab` : `case home, meals, sport, progress, quests` (supprimer `settings`).
Ordre des onglets : Accueil · Repas · **Sport** · Progrès · Quêtes. Insérer après `MealsJournalView` :

```swift
            // .id(dayKey) : la séance du jour et « Fait aujourd'hui » repartent
            // sur le bon jour au retour au premier plan après minuit.
            SportView()
                .id(dayKey)
                .tabItem { Label("Sport", systemImage: "figure.walk") }
                .tag(Tab.sport)
```

Supprimer le bloc `SettingsView()` + son `.tabItem`.

- [ ] **Step 2 : HomeView — bouton ⚙️ dans l'en-tête**

Dans `header` (HStack), après `levelPill` :

```swift
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.subtext)
                    .frame(width: 40, height: 40)
                    .background(Theme.card, in: Circle())
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
```

Avec `@State private var showSettings = false` et, sur le ZStack racine :

```swift
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
```

- [ ] **Step 3 : Build + vérification manuelle des previews**

Run: `xcodebuild -project Nivel.xcodeproj -scheme Nivel -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -3`
Expected: BUILD SUCCEEDED. Vérifier dans Xcode que le preview Accueil montre le ⚙️ et que les 5 onglets sont Accueil/Repas/Sport/Progrès/Quêtes.

- [ ] **Step 4 : Commit**

```bash
git add -A && git commit -m "feat(app): onglet Sport, Réglages déplacé derrière ⚙️ sur l'accueil"
```

---

## Task 11 : App — encart « Activité du jour » sur l'accueil + bulle afterActivity

**Files:**
- Modify: `App/Views/Home/HomeView.swift`

- [ ] **Step 1 : Encart sous le bouton « + Logger un repas »**

États : `@State private var sessionStatus: (session: ActivitySession, done: Bool)?` et `@State private var showSessionDetail = false`. Dans le VStack du body, après `logMealButton` :

```swift
                    if let status = sessionStatus {
                        Button { showSessionDetail = true } label: {
                            DailySessionCard(session: status.session,
                                             kcal: game.sessionKcal(status.session),
                                             done: status.done)
                        }
                        .buttonStyle(.plain)
                    }
```

Rafraîchissement : `sessionStatus = game.dailySessionStatus()` dans `refresh()` ET dans `updateBubble()` n'y touche pas — ajouter l'appel dans `onAppear` et dans le `onDismiss` de la sheet :

```swift
        .sheet(isPresented: $showSessionDetail, onDismiss: {
            sessionStatus = game.dailySessionStatus()
            updateBubble()
        }) {
            if let status = sessionStatus {
                SessionDetailSheet(session: status.session, done: status.done)
            }
        }
```

et dans `.onAppear` : remplacer `.onAppear(perform: updateBubble)` par

```swift
        .onAppear {
            sessionStatus = game.dailySessionStatus()
            updateBubble()
        }
```

(`import NivelCore` est déjà présent.)

- [ ] **Step 2 : Bulle Nivelito après activité**

Dans `updateBubble()`, après le bloc `lastMealXPAwarded` (le repas garde la priorité, spec sport §6) :

```swift
        if let activityXP = game.lastActivityXPAwarded {
            game.lastActivityXPAwarded = nil
            if activityXP > 0 {
                lastBubbleContext = .afterActivity
                bubbleText = game.nivelitoSays(context: .afterActivity, value: activityXP)
                return
            }
        }
```

- [ ] **Step 3 : Build + tests complets**

Run: `xcodebuild -project Nivel.xcodeproj -scheme Nivel -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | tail -5`
Expected: TEST SUCCEEDED.

- [ ] **Step 4 : Commit**

```bash
git add -A && git commit -m "feat(app): encart activité du jour sur l'accueil, bulle afterActivity"
```

---

## Task 12 : Vérification finale + documentation

**Files:**
- Modify: `README.md`

- [ ] **Step 1 : Suites complètes**

Run: `cd NivelCore && swift test && cd .. && xcodebuild -project Nivel.xcodeproj -scheme Nivel -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | tail -5`
Expected: tout PASS (NivelCore ≥ 40 tests, app ≥ 26 tests).

- [ ] **Step 2 : README**

Mettre à jour la description des onglets (Sport remplace Réglages dans la tab bar, Réglages accessible via ⚙️ sur l'accueil) et mentionner les nouveaux catalogues (`activities.json`, `sessions.json`) dans la section structure.

- [ ] **Step 3 : Vérification visuelle sur simulateur (optionnelle mais recommandée)**

Lancer l'app sur le simulateur, vérifier : encart séance du jour sur l'accueil (tap → sheet → valider → bulle Nivelito au retour), onglet Sport complet (valider une activité, la voir dans « Fait aujourd'hui », swipe supprimer), ⚙️ → Réglages.

- [ ] **Step 4 : Commit final**

```bash
git add -A && git commit -m "docs: README — onglet Sport, Réglages via l'accueil"
```

La branche `feat/sport` est prête pour la review finale et le merge dans `main` (fast-forward, comme la v1).
