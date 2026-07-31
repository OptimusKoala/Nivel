# Extension du catalogue Sport (v1.4) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ajouter 8 activités et 3 séances composées au catalogue sport (avec leurs 11 images Nivelito déjà déposées dans `design/sport/`), sans aucun changement Swift hors comptes de tests.

**Architecture:** Extension de contenu pure sur les rails v1.3 : entrées ajoutées EN FIN des deux JSON de NivelCore, assets régénérés par `scripts/import-sport-images.sh` (son garde-fou de synchronisation impose que JSON, sources et assets atterrissent ensemble), comptes pinnés des tests mis à jour. Spec : `docs/superpowers/specs/2026-07-31-sport-catalogue-expansion-design.md`.

**Tech Stack:** JSON, bash (script existant), XCTest. Pas de xcodegen (aucun fichier Swift créé/supprimé).

**Branche : créer `feat/sport-expansion` depuis `main`.**

### Task 0 : Branche

- [ ] `cd /Users/mbernard/perso/Nivel && git checkout -b feat/sport-expansion`

**Commandes de test :**
- NivelCore : `cd NivelCore && swift test`
- App : `xcodebuild -project Nivel.xcodeproj -scheme Nivel -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`

**Pièges connus :**
1. Le script d'import REFUSE de tourner si `design/sport/*.png` et les ids des catalogues sont désynchronisés — c'est voulu. Ordre obligatoire : JSON d'abord, PUIS `./scripts/import-sport-images.sh`, tout dans le MÊME commit.
2. Aucun tiret cadratin (—) dans les textes (gardé par `testNoBundleResourceContainsEmDash`).
3. Les 3 séances s'ajoutent EN FIN de `sessions.json` (la rotation par modulo dépend de l'ordre).
4. Ne pas toucher aux 12 activités / 8 séances existantes : ajouts strictement additifs.

---

## Task 1 : Contenu + assets + tests (une seule task, un seul commit — atomicité imposée par le garde-fou)

**Files:**
- Vérifier : `design/sport/` contient les 11 nouvelles sources (31 PNG au total, déjà déposées par Michaël, untracked)
- Modify: `NivelCore/Sources/NivelCore/Resources/activities.json` (+8 entrées en fin)
- Modify: `NivelCore/Sources/NivelCore/Resources/sessions.json` (+3 entrées en fin)
- Modify: `NivelCore/Tests/NivelCoreTests/ActivityCatalogTests.swift` (comptes 12→20, 8→11, + pins nouveaux)
- Régénérer : `App/Assets.xcassets/Sport/` (via le script — 31 imagesets)

- [ ] **Step 1 : Mettre à jour les tests (rouges)**

Dans `ActivityCatalogTests.swift` :
- `testActivitiesLoadAndIdsAreUnique` : `XCTAssertEqual(activities.count, 12)` → `20`, et ajouter :
```swift
        XCTAssertTrue(activities.contains { $0.id == "wall_sit" && $0.location == .home })
        XCTAssertTrue(activities.contains { $0.id == "hike" && $0.location == .outdoor })
```
- `testSessionsLoadAndStepsResolve` : `XCTAssertEqual(sessions.count, 8)` → `11`.
- Dans `testEstimatedKcalRoundsToTens`, ajouter (pin du calcul sur une nouvelle séance — recommandation de la review de spec) :
```swift
        // legs_day = squats 3×5,5 + fentes 3×5,5 + chaise murale 2×4,5 + étirements 3×2,5 = 49,5 → 50.
        let legsDay = try XCTUnwrap(sessions.first { $0.id == "legs_day" })
        XCTAssertEqual(legsDay.totalMinutes, 11)
        XCTAssertEqual(legsDay.estimatedKcal(activitiesByID: byID), 50)
```

- [ ] **Step 2 : Vérifier l'échec**

Run: `cd NivelCore && swift test --filter ActivityCatalogTests`
Expected: FAIL (`20 != 12`, `11 != 8`, `legs_day` introuvable).

- [ ] **Step 3 : Ajouter les 8 activités en FIN de `activities.json`** (après `digestive_walk`, virgule sur la ligne précédente) :

```json
  {"id": "lunges",          "name": "Fentes",               "emoji": "🤺",  "location": "home",    "kcalPerMin": 5.5, "durations": [3, 5, 10],
   "instructions": ["Un grand pas en avant, le buste reste droit", "Descends le genou arrière vers le sol, sans le toucher", "Pousse sur la jambe avant pour revenir, puis change de côté", "Tiens-toi à un mur ou une chaise si l'équilibre manque"]},
  {"id": "wall_sit",        "name": "Chaise contre le mur", "emoji": "🪑",  "location": "home",    "kcalPerMin": 4.5, "durations": [2, 4, 6],
   "instructions": ["Dos plaqué contre le mur, pieds avancés", "Glisse jusqu'à avoir les genoux pliés, comme sur une chaise invisible", "Les genoux restent au-dessus des chevilles, pas au-delà", "Souffle régulier, remonte dès que les cuisses brûlent trop"]},
  {"id": "high_knees",      "name": "Montées de genoux",    "emoji": "🏃",  "location": "home",    "kcalPerMin": 6.5, "durations": [3, 5, 8],
   "instructions": ["Sur place, monte un genou après l'autre vers les hanches", "Pas besoin de sauter : un pied reste toujours au sol", "Les bras accompagnent comme en course", "Ralentis quand le souffle monte trop"]},
  {"id": "march_in_place",  "name": "Marche sur place",     "emoji": "🧍",  "location": "home",    "kcalPerMin": 4.0, "durations": [5, 10, 15],
   "instructions": ["Marche sur place d'un pas régulier, les bras balancent", "Devant la télé ou une fenêtre, comme tu préfères", "Monte un peu plus les genoux pour intensifier"]},
  {"id": "shadow_boxing",   "name": "Boxe dans le vide",    "emoji": "🥊",  "location": "home",    "kcalPerMin": 6.0, "durations": [3, 5, 8],
   "instructions": ["Poings devant le visage, genoux légèrement fléchis", "Enchaîne des coups légers dans le vide, sans verrouiller les coudes", "Garde des appuis légers, bouge un peu", "C'est aussi fait pour évacuer : lâche-toi"]},
  {"id": "mobility",        "name": "Réveil articulaire",   "emoji": "🌀",  "location": "home",    "kcalPerMin": 2.5, "durations": [5, 8, 12],
   "instructions": ["Des cercles lents : nuque, épaules, poignets, hanches, chevilles", "Amplitude confortable, jamais forcée", "Quelques respirations profondes entre chaque zone"]},
  {"id": "gardening",       "name": "Jardinage",            "emoji": "🌻",  "location": "outdoor", "kcalPerMin": 4.0, "durations": [15, 30, 45],
   "instructions": ["Plie les genoux pour jardiner au sol, pas le dos", "Alterne les tâches pour varier les postures", "L'arrosoir et la brouette comptent comme de la muscu douce"]},
  {"id": "hike",            "name": "Randonnée légère",     "emoji": "🥾",  "location": "outdoor", "kcalPerMin": 5.5, "durations": [30, 45, 60],
   "instructions": ["Choisis un sentier facile et de bonnes chaussures", "Petit rythme régulier, surtout en montée", "Emporte de l'eau et profite du paysage"]}
```

- [ ] **Step 4 : Ajouter les 3 séances en FIN de `sessions.json`** (ordre EXACT — la rotation en dépend) :

```json
  {"id": "legs_day",         "title": "Spécial jambes",       "emoji": "🦵", "steps": [
    {"activityID": "squats",         "minutes": 3, "tempo": "~10 squats × 2, tranquilles"},
    {"activityID": "lunges",         "minutes": 3, "tempo": "~8 fentes par jambe, en alternant"},
    {"activityID": "wall_sit",       "minutes": 2, "tempo": "2-3 tenues de ~30 s, repos entre chaque"},
    {"activityID": "stretching",     "minutes": 3, "tempo": "Cuisses et mollets, ~30 s chacun"}]},
  {"id": "gentle_cardio",    "title": "Cardio tout doux",     "emoji": "💓", "steps": [
    {"activityID": "march_in_place", "minutes": 4, "tempo": "Rythme régulier, accélère sur la fin si ça va"},
    {"activityID": "shadow_boxing",  "minutes": 3, "tempo": "Séries de ~20 coups, pause quand tu veux"},
    {"activityID": "high_knees",     "minutes": 3, "tempo": "3 × ~40 s, repos entre les séries"},
    {"activityID": "stretching",     "minutes": 3, "tempo": "Épaules et jambes, ~30 s par étirement"}]},
  {"id": "morning_mobility", "title": "Souplesse & mobilité", "emoji": "🌀", "steps": [
    {"activityID": "mobility",       "minutes": 5, "tempo": "Chaque articulation y passe : ~30 s par zone"},
    {"activityID": "yoga",           "minutes": 5, "tempo": "2-3 postures douces, 4-5 respirations chacune"},
    {"activityID": "stretching",     "minutes": 4, "tempo": "Termine par le dos et la nuque, lentement"}]}
```

- [ ] **Step 5 : Régénérer les assets**

Run: `./scripts/import-sport-images.sh`
Expected: `OK : 31 imagesets générés` (le garde-fou valide la synchro JSON ↔ sources au passage). Vérifier `du -sh App/Assets.xcassets/Sport` (~3 Mo).

- [ ] **Step 6 : Vérifier le vert complet**

Run: `cd NivelCore && swift test` → Expected: **50 tests, 0 failures**.
Run: `xcodebuild ... test` → Expected: **TEST SUCCEEDED, 36 tests** (SportAssetsTests couvre automatiquement les 31 ids ; les invariants durées/instructions/tempo/em-dash couvrent les nouveautés).

- [ ] **Step 7 : Commit (UN SEUL, atomique)**

```bash
git add design/sport NivelCore App/Assets.xcassets/Sport
git commit -m "feat: 8 activités et 3 séances de plus au catalogue sport (v1.4)"
```

---

## Task 2 : Version + vérification finale

**Files:**
- Modify: `project.yml` (version 1.3 → 1.4, build 4 → 5)

- [ ] **Step 1 : Bump version**

Dans `project.yml` : `CFBundleShortVersionString: "1.4"`, `CFBundleVersion: "5"`. Puis `xcodegen generate` (régénère `App/Info.plist` + pbxproj).

- [ ] **Step 2 : Suites complètes**

Run: `cd NivelCore && swift test && cd .. && xcodebuild ... test` → 50 + 36, tout vert.

- [ ] **Step 3 : Vérification visuelle simulateur (recommandée)**

Onglet Sport : les 8 nouvelles activités visibles avec leurs vignettes (Maison : 6 nouvelles ; Dehors : jardinage + rando), tap Fentes → illustration + « Comment faire » + durées. La séance du jour tourne désormais sur 11 (rappel : re-builder les DEUX iPhones ensemble).

- [ ] **Step 4 : Commit**

```bash
git add -A && git commit -m "chore: version 1.4 (build 5)"
```

Fin de branche : options merge/PR présentées à Michaël (superpowers:finishing-a-development-branch).
