# Programme posture (v1.11) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Donner à Marion un programme posture court, varié et choisi à sa place, avec un rappel à 21 h et une quête hebdomadaire, sans rien changer sur l'autre téléphone ni introduire de streak.

**Architecture:** Les exercices et séances posture vivent dans deux catalogues séparés, avec leur propre rotation, afin de ne pas toucher à celle de la séance du jour. Le ciblage est un interrupteur par appareil dans `UserDefaults`, sur le modèle de `SoundSettings`. La rigueur passe par les mécaniques existantes : une quête filtrée par drapeau comme les quêtes de pas, une action d'XP plafonnée indépendante, un rappel du catalogue v1.9.

**Tech Stack:** Swift 5.9, SwiftUI, SwiftData, XcodeGen, XCTest.

**Spec:** `docs/superpowers/specs/2026-08-03-programme-posture-design.md`. Contenus et libellés : la spec est la source, ce plan ne les recopie pas.

---

## Déjà fait, ne pas refaire

Trois choses ont atterri avant ce plan, dans le commit `cd33b74` :

- `NivelCore/Sources/NivelCore/Resources/posture-activities.json` (9 exercices) et `posture-sessions.json` (5 séances), contenus conformes à la spec §4, §4.1 et §5.
- Les **14 illustrations** générées par Michaël, importées en 750 px dans `App/Assets.xcassets/Sport/`.
- `scripts/import-sport-images.sh` étendu aux deux catalogues posture.

Elles ont dû précéder le plan parce que le script d'import refuse une image dont l'id ne figure dans aucun catalogue qu'il lit. Aucune fenêtre rouge n'a été créée : `SportAssetsTests` ne parcourt encore que les catalogues globaux, et c'est la Task 2 qui l'étend.

## Commandes de référence

```sh
cd NivelCore && swift test
xcodegen generate
xcodebuild -project Nivel.xcodeproj -scheme Nivel \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Point de départ : **143 tests NivelCore + 76 tests app** au vert sur `main`, version 1.10 (build 11).

## Structure des fichiers

**Créés dans NivelCore**

| Fichier | Responsabilité |
|---|---|
| `Sources/NivelCore/PostureCatalog.swift` | Chargement des deux catalogues posture et rotation du soir |
| `Tests/NivelCoreTests/PostureCatalogTests.swift` | Cloisonnement, intégrité, rotation |

**Créés dans l'app**

| Fichier | Responsabilité |
|---|---|
| `App/Services/PosturePlanSettings.swift` | L'interrupteur, par appareil |
| `App/Views/Sport/PostureSection.swift` | La section en tête de l'onglet Sport |
| `NivelTests/PosturePlanTests.swift` | Interrupteur, rappel, comptage en jours distincts |

**Modifiés**

| Fichier | Changement |
|---|---|
| `NivelCore/Sources/NivelCore/Catalogs.swift` | +`postureActivities()`, +`postureSessions()` |
| `NivelCore/Sources/NivelCore/QuestEngine.swift` | +`requiresPosture`, +métrique `postureSessionsDone` |
| `NivelCore/Sources/NivelCore/XPEngine.swift` | +`postureSessionDone` |
| `NivelCore/Sources/NivelCore/ActivityCatalog.swift` | +`ActivityKind.posture` |
| `NivelCore/Sources/NivelCore/Reminders.swift` | +5ᵉ entrée du catalogue |
| `NivelCore/Sources/NivelCore/MessageBank.swift` | +contexte `postureReminder` |
| `NivelCore/Sources/NivelCore/Resources/quests.json` | +3 quêtes posture |
| `NivelCore/Sources/NivelCore/Resources/messages.json` | +8 messages |
| `NivelTests/SportAssetsTests.swift` | Étendu aux catalogues posture |
| `App/Services/GameService+Sport.swift` | `logPostureSession`, compteurs |
| `App/Services/GameService.swift` | Table d'ids fusionnée, métrique de quête |
| `App/Views/Sport/SportView.swift` | Section Posture en tête |
| `App/Views/Settings/SettingsView+DevicePreferences.swift` | L'interrupteur |
| `project.yml`, `README.md` | Version 1.11 (build 12) |

---

### Task 1 : Le catalogue posture et sa rotation

**Files:**
- Create: `NivelCore/Sources/NivelCore/PostureCatalog.swift`
- Modify: `NivelCore/Sources/NivelCore/Catalogs.swift`
- Test: `NivelCore/Tests/NivelCoreTests/PostureCatalogTests.swift`

- [ ] **Step 1: Écrire les tests qui échouent**

Le premier test est le plus important du lot : c'est lui qui protège la rotation de la séance du jour, que la spec sport interdit de modifier.

```swift
// NivelCore/Tests/NivelCoreTests/PostureCatalogTests.swift
import XCTest
@testable import NivelCore

final class PostureCatalogTests: XCTestCase {
    private var catalog: PostureCatalog!
    private var calendar: Calendar!

    override func setUpWithError() throws {
        catalog = try PostureCatalog.load()
        calendar = Calendar(identifier: .iso8601)
    }

    /// LE test du lot. Verser les entrées posture dans les catalogues globaux les
    /// afficherait sur les deux téléphones ET ferait passer la rotation de la séance
    /// du jour de 11 à 16 entrées, donc changerait la séance vue chaque jour par tout
    /// le monde. La spec sport interdit de toucher à cette rotation.
    func testLesCataloguesSontCloisonnes() throws {
        let globalActivities = Set(try Catalogs.activities().map(\.id))
        let globalSessions = Set(try Catalogs.sessions().map(\.id))
        let postureActivities = Set(catalog.activities.map(\.id))
        let postureSessions = Set(catalog.sessions.map(\.id))

        XCTAssertTrue(globalActivities.isDisjoint(with: postureActivities))
        XCTAssertTrue(globalSessions.isDisjoint(with: postureSessions))
        XCTAssertEqual(globalSessions.count, 11, "la rotation de la séance du jour a bougé")
        XCTAssertEqual(globalActivities.count, 20)
    }

    func testTailleDesCatalogues() {
        XCTAssertEqual(catalog.activities.count, 9)
        XCTAssertEqual(catalog.sessions.count, 5)
    }

    func testChaqueEtapeReferenceUnExerciceExistant() {
        let ids = Set(catalog.activities.map(\.id))
        for session in catalog.sessions {
            XCTAssertFalse(session.steps.isEmpty, session.id)
            for step in session.steps {
                XCTAssertTrue(ids.contains(step.activityID),
                              "\(session.id) cite un exercice inconnu : \(step.activityID)")
                XCTAssertGreaterThan(step.minutes, 0)
                XCTAssertFalse(step.tempo.isEmpty, "\(session.id)/\(step.activityID) sans tempo")
            }
        }
    }

    func testIntegriteDesExercices() {
        for activity in catalog.activities {
            XCTAssertEqual(activity.durations, activity.durations.sorted(), activity.id)
            XCTAssertEqual(activity.durations.count, 3, activity.id)
            XCTAssertGreaterThan(activity.kcalPerMin, 0, activity.id)
            XCTAssertTrue((3...4).contains(activity.instructions.count),
                          "\(activity.id) : 3 ou 4 consignes attendues")
            XCTAssertEqual(activity.location, .home, activity.id)
        }
    }

    /// Cinq séances : cinq soirs consécutifs en donnent cinq différentes, le sixième
    /// revient à la première. Rotation partagée avec la séance du jour, donc même
    /// référence fixe du 1ᵉʳ janvier 2026.
    func testRotationSurCinqJours() throws {
        let start = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 3))
        )
        let five = (0..<5).compactMap { offset -> String? in
            let day = calendar.date(byAdding: .day, value: offset, to: start)!
            return catalog.session(for: day, calendar: calendar)?.id
        }
        XCTAssertEqual(Set(five).count, 5, "deux soirs de suite donnent la même séance")

        let sixth = calendar.date(byAdding: .day, value: 5, to: start)!
        XCTAssertEqual(catalog.session(for: sixth, calendar: calendar)?.id, five.first)
    }

    /// Une séance douce doit exister : un programme à un seul niveau d'effort se fait
    /// abandonner le premier soir de fatigue (spec §5).
    func testUneSeanceDouceExiste() {
        let gentle = catalog.sessions.first { $0.id == "posture_gentle" }
        XCTAssertNotNil(gentle)
        XCTAssertLessThanOrEqual(gentle?.totalMinutes ?? 99, 6)
    }
}
```

- [ ] **Step 2: Lancer, vérifier l'échec**

Run: `cd NivelCore && swift test --filter PostureCatalogTests`
Expected: « cannot find 'PostureCatalog' in scope ».

- [ ] **Step 3: Écrire l'implémentation**

Dans `Catalogs.swift` :

```swift
    public static func postureActivities() throws -> [Activity] { try load("posture-activities") }
    public static func postureSessions() throws -> [ActivitySession] { try load("posture-sessions") }
```

```swift
// NivelCore/Sources/NivelCore/PostureCatalog.swift
// Programme posture (spec v1.11 §4 à §6) : catalogues SÉPARÉS des catalogues sport
// globaux, avec leur propre rotation.
//
// Le cloisonnement n'est pas une préférence de rangement : verser ces entrées dans
// activities.json et sessions.json les afficherait sur les deux téléphones, et surtout
// ferait passer la rotation de la séance du jour de 11 à 16 entrées, donc changerait
// la séance vue chaque jour par tout le monde. La spec sport l'interdit.

import Foundation

public struct PostureCatalog: Sendable {
    public let activities: [Activity]
    public let sessions: [ActivitySession]
    public let byID: [String: Activity]

    public static func load() throws -> PostureCatalog {
        let activities = try Catalogs.postureActivities()
        return PostureCatalog(
            activities: activities,
            sessions: try Catalogs.postureSessions(),
            byID: Dictionary(activities.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        )
    }

    /// Catalogue vide, pour le repli sans crash du service quand un JSON est corrompu.
    public static let empty = PostureCatalog(activities: [], sessions: [], byID: [:])

    /// Séance du soir. Réutilise la rotation générique de la séance du jour, appliquée
    /// au pool posture : même référence fixe, modulo 5.
    public func session(for date: Date, calendar: Calendar) -> ActivitySession? {
        DailySessionPicker.session(for: date, sessions: sessions, calendar: calendar)
    }

    public func kcal(_ session: ActivitySession) -> Int {
        session.estimatedKcal(activitiesByID: byID)
    }
}
```

- [ ] **Step 4: Vérifier**

Run: `cd NivelCore && swift test`
Expected: 143 pré-existants + les nouveaux, tous verts.

- [ ] **Step 5: Commit**

```bash
git add NivelCore/
git commit -m "feat(core): catalogue posture cloisonné et rotation du soir"
```

---

### Task 2 : Étendre la garde des illustrations

**Files:**
- Modify: `NivelTests/SportAssetsTests.swift`

- [ ] **Step 1: Étendre le test**

Il ne parcourt aujourd'hui que `Catalogs.activities()` et `Catalogs.sessions()`. Les 14 images posture sont déjà importées ; il doit maintenant les couvrir, sinon rien ne protège leur présence.

Ajouter les ids posture à la liste parcourue, en gardant la vérification de largeur 750 qui attrape une source déposée à la main sans passer par le script.

- [ ] **Step 2: Vérifier que le test détecte réellement une image manquante**

Renommer temporairement `App/Assets.xcassets/Sport/chin_tucks.imageset` en `chin_tucks.imageset.off`, lancer le test, **constater l'échec**, puis remettre le nom. Sans cette vérification, on ne sait pas si le test couvre vraiment les nouveaux ids ou s'il les ignore en silence.

Run: `xcodebuild -project Nivel.xcodeproj -scheme Nivel -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:NivelTests/SportAssetsTests`

- [ ] **Step 3: Commit**

```bash
git add NivelTests/SportAssetsTests.swift
git commit -m "test: la garde des illustrations couvre les 14 assets posture"
```

---

### Task 3 : L'XP, la métrique et la quête

**Files:**
- Modify: `NivelCore/Sources/NivelCore/XPEngine.swift`
- Modify: `NivelCore/Sources/NivelCore/ActivityCatalog.swift`
- Modify: `NivelCore/Sources/NivelCore/QuestEngine.swift`
- Modify: `NivelCore/Sources/NivelCore/Resources/quests.json`
- Test: les fichiers de tests correspondants

- [ ] **Step 1: Écrire les tests qui échouent**

Deux d'entre eux encodent des pièges précis. Le premier : réutiliser l'action de la séance du jour ferait que faire les deux le même soir n'en paierait qu'une, ce qui punirait le comportement qu'on veut installer. Le second : `requiresPosture` doit être optionnel au décodage, sinon **tout** le catalogue de quêtes échoue et les quêtes disparaissent chez les deux personnes.

```swift
// dans XPEngineTests
    /// Plafonds INDÉPENDANTS : faire la séance du jour et la séance posture le même
    /// soir doit payer les deux, sinon on punit exactement ce qu'on veut encourager.
    func testPostureEtSeanceDuJourSontIndependantes() {
        XCTAssertEqual(XPEngine.award(.postureSessionDone, todayCount: 0), 40)
        XCTAssertEqual(XPEngine.award(.postureSessionDone, todayCount: 1), 0)
        // Le compteur de l'une n'affecte pas l'autre : les deux sont interrogées à 0.
        XCTAssertEqual(XPEngine.award(.dailySessionDone, todayCount: 0), 40)
    }
```

```swift
// dans QuestEngineTests
    /// Le drapeau doit filtrer, sinon la quête posture tomberait chez quelqu'un qui
    /// n'a pas le programme et resterait à zéro toute la semaine.
    func testQuetePostureNestTireeQueSiLeProgrammeEstActif() throws {
        let pool = try Catalogs.quests()
        XCTAssertTrue(pool.contains { $0.requiresPosture }, "aucune quête posture au catalogue")

        for week in ["2026-W32", "2026-W33", "2026-W34", "2026-W35"] {
            let sans = QuestEngine.weeklyDraw(pool: pool, weekID: week,
                                              stepsAvailable: true, postureAvailable: false)
            XCTAssertFalse(sans.contains { $0.requiresPosture }, week)
        }
        // Et elle doit pouvoir sortir quand le programme est actif, sur au moins une
        // semaine parmi plusieurs : sinon le test ne prouverait que la moitié du contrat.
        let semaines = (30...45).map { "2026-W\($0)" }
        XCTAssertTrue(semaines.contains { week in
            QuestEngine.weeklyDraw(pool: pool, weekID: week,
                                   stepsAvailable: true, postureAvailable: true)
                .contains { $0.requiresPosture }
        })
    }

    /// Les entrées existantes de quests.json ne portent pas le champ : un Bool non
    /// optionnel ferait échouer le décodage de TOUT le catalogue.
    func testLesQuetesExistantesSeDecodentSansLeChamp() throws {
        let pool = try Catalogs.quests()
        XCTAssertGreaterThan(pool.count, 3)
        XCTAssertFalse(pool.first { $0.id == "log_meals_10" }?.requiresPosture ?? true)
    }
```

- [ ] **Step 2: Lancer, vérifier l'échec**

- [ ] **Step 3: Implémenter**

- `XPAction` gagne `postureSessionDone`, 40 XP, `todayCount < 1`.
- `ActivityKind` gagne `posture`.
- `Quest` gagne `requiresPosture: Bool`, **décodé avec `decodeIfPresent` et un défaut à faux**, avec un `init(from:)` explicite, comme `SessionStep.segments` en v1.5.
- `Quest.Metric` gagne `postureSessionsDone`.
- `QuestEngine.weeklyDraw` gagne un paramètre `postureAvailable: Bool` et filtre comme il le fait déjà pour `stepsAvailable`. Mettre à jour les appelants.
- `quests.json` gagne trois quêtes `requiresPosture: true`, cibles 3, 4 et 5, métrique `postureSessionsDone`, icônes existantes.

**Deux conséquences du tirage à documenter dans le code, pas à découvrir plus tard.**

Le tirage est déterministe et seedé par la semaine, sur le pool ÉLIGIBLE. Donc :

- Programme éteint, le pool éligible est identique à celui de la v1.10 : **le tirage de Michaël ne change pas d'une quête**. C'est la promesse « rien ne bouge chez toi », et le test ci-dessus la vérifie en exigeant qu'aucune quête posture ne sorte sur quatre semaines consécutives.
- Programme allumé, le pool grandit de trois entrées, donc **le tirage de Marion change** pour une semaine donnée par rapport à ce qu'il aurait été. Ce n'est pas un bug : le tirage n'a jamais été une promesse stable dans le temps, il l'est seulement à pool constant. À écrire en commentaire au-dessus du filtre.

**Le cas de l'extinction en cours de semaine.** Si Marion éteint le programme après le tirage du lundi, une quête posture peut être active et devenir inatteignable. On ne fait rien : elle reste à sa progression, ne se complète pas, et le lundi suivant en tire une autre. C'est exactement le comportement d'une quête non finie dans cette app, et la retirer de force serait la seule fois où l'app reprendrait quelque chose. À documenter dans le code, avec un test qui vérifie qu'éteindre ne purge pas `activeQuestIDs`.

- [ ] **Step 4: Vérifier et committer**

```bash
git add NivelCore/
git commit -m "feat(core): XP, métrique et quêtes du programme posture"
```

---

### Task 4 : Le rappel de 21 h et ses messages

**Files:**
- Modify: `NivelCore/Sources/NivelCore/Reminders.swift`
- Modify: `NivelCore/Sources/NivelCore/MessageBank.swift`
- Modify: `NivelCore/Sources/NivelCore/Resources/messages.json`
- Modify: `NivelCore/Tests/NivelCoreTests/RemindersTests.swift`

- [ ] **Step 1: Tests**

Épingler la cinquième entrée (id `posture`, 21 h 00, tous les jours, jour non modifiable, contexte `.postureReminder`) et son libellé « tous les jours à 21 h ». Vérifier aussi que les quatre défauts existants n'ont pas bougé : le test qui les épingle depuis la v1.9 doit rester vert sans modification.

Côté banque : les huit messages du nouveau contexte se chargent, aucun ne contient de tiret cadratin, aucun n'est une injonction.

- [ ] **Step 2: Implémenter**

Cinquième `ReminderDefinition`. Nouveau cas `postureReminder` dans `MessageContext`, plus huit textes dans `messages.json`.

Ton : jamais d'injonction, jamais de reproche, comme le reste de la banque. Par exemple « Cinq minutes pour ta nuque, ça se fait bien avant le canapé 🧡 ». Jamais « tu n'as pas fait ta séance ».

**Attention** : `MessageBank.load` fait un `assertionFailure` sur une clé de contexte inconnue. Ajouter le cas de l'enum sans ajouter la clé au JSON ne casse rien en release mais fait tomber les tests en debug, et réciproquement.

- [ ] **Step 3: Vérifier et committer**

```bash
git add NivelCore/
git commit -m "feat(core): rappel posture de 21 h et ses huit messages"
```

---

### Task 5 : L'interrupteur et le rappel qu'il allume

**Files:**
- Create: `App/Services/PosturePlanSettings.swift`
- Modify: `App/Views/Settings/SettingsView+DevicePreferences.swift`
- Test: `NivelTests/PosturePlanTests.swift`

- [ ] **Step 1: Tests**

Sur le modèle de `SoundSettingsTests` : suite `UserDefaults` dédiée, jamais les vrais réglages. Défaut **faux**. Persistance. Et le cas qui compte : `false` persisté ne doit pas être confondu avec l'absence de clé, donc `object(forKey:)` et non `bool(forKey:)`.

Puis, avec un profil en mémoire : allumer l'interrupteur pose `remindersEnabled["posture"] = true`, l'éteindre le remet à faux. Ce test doit échouer si l'on oublie de poser la clé, ce qui est précisément le piège documenté en v1.9 : une clé absente vaut désactivé, donc le rappel naîtrait éteint et Marion ne le trouverait jamais.

- [ ] **Step 2: Implémenter**

`PosturePlanSettings`, copie conforme de `SoundSettings` avec la clé `nivel.posturePlan` et un défaut faux.

Dans les Réglages, une carte « Programme posture » dans `SettingsView+DevicePreferences.swift`, aux côtés du thème et du son, avec un `@Bindable` local comme le son du timer. Sous-titre honnête, du registre de la spec §1.1 : décrire la zone, ne rien promettre.

Le geste qui allume doit, dans le même bloc, poser la clé du rappel sur le profil (réassignation complète du dictionnaire, règle SwiftData) puis appeler `NotificationService.reschedule(for:)`.

- [ ] **Step 3: Vérifier et committer**

Ajouter aussi le test du cas d'extinction en cours de semaine : éteindre l'interrupteur ne doit pas modifier `activeQuestIDs` ni `questProgress`.

---

### Task 6 : Enregistrer une séance posture et la compter

**Files:**
- Modify: `App/Services/GameService+Sport.swift`
- Modify: `App/Services/GameService.swift`
- Modify: `NivelTests/PosturePlanTests.swift`

- [ ] **Step 1: Tests**

- `logPostureSession` attribue 40 XP, une fois par jour, **et** n'empêche pas la séance du jour de payer les siennes le même jour. C'est le test qui garde l'indépendance des plafonds au niveau du service, pas seulement de `XPEngine`.
- `postureSessionDayCount(from:to:)` compte des **jours distincts** : deux séances le même soir valent une. Miroir exact de `dailySessionDayCount`.
- Le compteur mensuel sur un mois à zéro, à une, et à plusieurs séances réparties sur des jours différents.
- Une entrée posture apparaît dans « Fait aujourd'hui » **avec son nom**, ce qui vérifie la table d'ids fusionnée.

- [ ] **Step 2: Implémenter**

- `GameService` charge un `PostureCatalog` au constructeur, avec le même repli sans crash que les autres catalogues.
- **La table d'ids est fusionnée** : `activitiesByID` doit contenir les exercices posture, sinon une entrée posture dans « Fait aujourd'hui » ou dans un récapitulatif perd son nom. Les listes affichées et les deux rotations, elles, restent cloisonnées.
- `logPostureSession(session:date:)` sur le modèle de `logDailySession`, avec `kind: .posture` et l'action `postureSessionDone`. Garder le contrat anti-double-tap : insertion avant le premier `await`.
- `postureSessionDayCount(from:to:)` et le compteur du mois courant.
- La métrique de quête `postureSessionsDone` branchée sur le compteur en jours distincts.
- L'appel à `weeklyDraw` passe `postureAvailable: PosturePlanSettings.shared.isEnabled`.

- [ ] **Step 3: Vérifier et committer**

---

### Task 7 : La section Posture dans l'onglet Sport

**Files:**
- Create: `App/Views/Sport/PostureSection.swift`
- Modify: `App/Views/Sport/SportView.swift`

- [ ] **Step 1: Implémenter**

`PostureSection` rend, quand `PosturePlanSettings.shared.isEnabled` :

- l'overline « Posture » ;
- la carte de la séance du soir, même forme que `DailySessionCardContent`, avec le compteur mensuel en sous-titre (« 12 soirs ce mois-ci », **jours distincts**, cohérent avec la quête) ;
- les neuf exercices en lignes, même forme que les sections existantes.

Dans `SportView`, la section passe **en tête**, avant la séance du jour. Le titre « Sport » reste tout en haut : c'est l'en-tête de la première `Section` de la `List`, il suit donc la section Posture qui devient première.

Le player et la feuille d'activité sont réutilisés tels quels : `SessionPlayerSheet` pour la séance, `ActivityLogSheet` pour un exercice. Vérifier que le timer, les consignes et les chimes de la v1.9 fonctionnent sur ces nouvelles entrées sans adaptation.

- [ ] **Step 2: Vérifier à l'œil et mesurer**

Dans le simulateur, interrupteur allumé : la section est en tête, la carte du soir affiche la bonne séance, les neuf exercices ouvrent leur feuille avec leur illustration et leurs consignes. Interrupteur éteint : l'onglet est identique à la v1.10.

**Mesurer la largeur**, comme en v1.9 : la carte du soir et une ligne d'exercice au harnais de rendu à 375 pt, pas à l'œil sur un iPhone 17 Pro. Le nom « Rétractions d'omoplates » est le plus long du catalogue sport et c'est là que ça cassera si ça casse.

- [ ] **Step 3: Commit**

---

### Task 8 : Version et documentation

**Files:**
- Modify: `project.yml`, `README.md`

- [ ] **Step 1: Version 1.11 (build 12)** sur les **deux** cibles. La version atterrit dans `App/Info.plist` et `Widgets/Info.plist`, pas dans le `pbxproj`.

- [ ] **Step 2: README** : badges de version et de tests aux comptes réels. **Vérifier la chaîne remplacée**, un remplacement qui ne matche pas est passé inaperçu en v1.10.

- [ ] **Step 3: Vérifications transverses**

```sh
grep -rn '"[^"]*—[^"]*"' App/Views NivelCore/Sources
grep -rni "bison" App NivelCore Widgets
```
Expected : rien dans les deux cas. Le second est la garde de la règle de langage de la spec §1.1.

- [ ] **Step 4: Les deux suites**, comptes reportés dans le README.

- [ ] **Step 5: Commit**

---

## Vérification sur les téléphones (par Michaël, après merge)

Reprise du §15 de la spec.

- [ ] Sur ton téléphone, interrupteur laissé éteint : **rien n'a changé**, aucun rappel de plus.
- [ ] Chez Marion, interrupteur allumé : section Posture en tête, et le rappel de 21 h actif dans les Réglages sans autre geste.
- [ ] Le rappel arrive bien à 21 h.
- [ ] Cinq soirs de suite donnent cinq séances différentes.
- [ ] Faire la séance posture ET la séance du jour le même soir paie les deux XP.
- [ ] La quête posture apparaît au tirage du lundi suivant, pas avant.
- [ ] Le rendu de la section en tête sur le plus petit des deux iPhones.
