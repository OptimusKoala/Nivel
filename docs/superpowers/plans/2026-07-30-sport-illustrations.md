# Illustrations Sport & Séances guidées — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Illustrer chaque sport avec les 20 images Nivelito (assets embarqués + fallback emoji) et transformer la séance du jour en player pas-à-pas avec consignes et rythmes.

**Architecture:** Aucun changement SwiftData ni GameService. NivelCore gagne deux champs de contenu (`Activity.instructions`, `SessionStep.tempo`) et les JSON réécrits ; l'app gagne un composant `SportIllustration` (avec fallback), 20 imagesets dans un namespace `Sport/`, une `ActivityLogSheet` enrichie et un `SessionPlayerSheet` (pager) qui remplace `SessionDetailSheet`. Spec : `docs/superpowers/specs/2026-07-30-sport-illustrations-design.md`.

**Tech Stack:** Swift/SwiftUI, XCTest, XcodeGen (`xcodegen generate` après tout ajout/suppression de fichier sous `App/` ou `scripts/`), `sips` (redimensionnement).

**Branche : créer `feat/sport-illustrations` depuis `main`** (la v1.2 est mergée : `main` porte déjà les conventions « aucun tiret cadratin (—) dans les textes utilisateur » et les styles partagés `PrimaryButtonStyle`/sheets radius 28).

### Task 0 : Branche

- [ ] `cd /Users/mbernard/perso/Nivel && git checkout -b feat/sport-illustrations`

**Commandes de test :**
- NivelCore : `cd NivelCore && swift test`
- App : `xcodebuild -project Nivel.xcodeproj -scheme Nivel -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`

**Pièges connus :**
1. Les textes utilisateur ne doivent contenir AUCUN « — » (convention de la branche). Les tables de la spec §4 en contiennent encore : ce plan fait foi pour les chaînes exactes, et la Task 2 synchronise la spec.
2. `xcodegen generate` requis après création/suppression de fichiers Swift (Tasks 3, 4, 5) — PAS nécessaire pour les assets (`Assets.xcassets` est référencé en dossier).
3. Les imagesets doivent porter EXACTEMENT les ids des catalogues (un test le garantit, Task 1).
4. `SessionDetailSheet` est supprimé en Task 5 : ses deux call sites (`HomeView`, `SportView`) basculent dans le même commit, sinon le build casse.
5. Les sources PNG 1254px (~26 Mo) sont déjà committées dans `design/sport/` (convention `design/`) mais ne doivent JAMAIS être ajoutées au bundle app.

---

## Task 1 : Assets — pipeline d'import + catalogue `Sport/` + test de présence

**Files:**
- Vérifier: `design/sport/*.png` (20 sources, DÉJÀ committées sur main)
- Create: `scripts/import-sport-images.sh`
- Create: `App/Assets.xcassets/Sport/` (généré par le script — 20 imagesets JPEG 750px)
- Test: `NivelTests/SportAssetsTests.swift`

- [ ] **Step 1 : Écrire le test de présence (rouge)**

```swift
// NivelTests/SportAssetsTests.swift
import XCTest
import UIKit
import NivelCore
@testable import Nivel

final class SportAssetsTests: XCTestCase {
    /// Garde anti-typo : chaque entrée de catalogue sport a son illustration embarquée
    /// (spec illustrations §7). Le fallback emoji existe, mais un asset manquant est un
    /// bug de packaging à attraper ici.
    func testEveryCatalogEntryHasAnIllustration() throws {
        let ids = try Catalogs.activities().map(\.id) + Catalogs.sessions().map(\.id)
        XCTAssertEqual(ids.count, 20)
        for id in ids {
            XCTAssertNotNil(UIImage(named: "Sport/\(id)"), "asset manquant : Sport/\(id)")
        }
    }
}
```

- [ ] **Step 2 : Vérifier l'échec**

Run: `xcodegen generate && xcodebuild -project Nivel.xcodeproj -scheme Nivel -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | tail -5`
Expected: FAIL (les 20 assertions `asset manquant`).

- [ ] **Step 3 : Écrire le script d'import**

```bash
#!/bin/bash
# scripts/import-sport-images.sh
# Régénère App/Assets.xcassets/Sport/ depuis design/sport/*.png :
# JPEG 750x750 qualité 80 (~100-150 Ko), un imageset universel single-scale par image.
# Idempotent : relancer après avoir ajouté/retouché une source.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="design/sport"
DST="App/Assets.xcassets/Sport"

rm -rf "$DST"
mkdir -p "$DST"
cat > "$DST/Contents.json" <<'JSON'
{
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "provides-namespace" : true }
}
JSON

for src in "$SRC"/*.png; do
  id=$(basename "$src" .png)
  dir="$DST/$id.imageset"
  mkdir -p "$dir"
  sips -Z 750 -s format jpeg -s formatOptions 80 "$src" --out "$dir/$id.jpg" >/dev/null
  cat > "$dir/Contents.json" <<JSON
{
  "images" : [ { "filename" : "$id.jpg", "idiom" : "universal" } ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
done

echo "OK : $(ls -d "$DST"/*.imageset | wc -l | tr -d ' ') imagesets générés"
```

`chmod +x scripts/import-sport-images.sh` puis le lancer : `./scripts/import-sport-images.sh`
Expected: `OK : 20 imagesets générés`. Vérifier le poids : `du -sh App/Assets.xcassets/Sport` (~2-3 Mo).

- [ ] **Step 4 : Vérifier le vert**

Run: `xcodebuild -project Nivel.xcodeproj -scheme Nivel -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | tail -5`
Expected: TEST SUCCEEDED (35 tests : 34 + le nouveau).
Note : pas de `xcodegen generate` nécessaire pour les assets, mais il a déjà été lancé au Step 2 pour le fichier de test.

- [ ] **Step 5 : Commit**

```bash
git add design/sport scripts/import-sport-images.sh App/Assets.xcassets/Sport NivelTests/SportAssetsTests.swift Nivel.xcodeproj
git commit -m "feat(app): illustrations sport embarquées (20 imagesets, namespace Sport/)"
```

---

## Task 2 : NivelCore — `instructions` + `tempo` + contenus

**Files:**
- Modify: `NivelCore/Sources/NivelCore/ActivityCatalog.swift` (2 champs)
- Modify: `NivelCore/Sources/NivelCore/Resources/activities.json` (réécrit, contenu ci-dessous)
- Modify: `NivelCore/Sources/NivelCore/Resources/sessions.json` (réécrit, contenu ci-dessous)
- Modify: `docs/superpowers/specs/2026-07-30-sport-illustrations-design.md` (sync §4 : retirer les « — » des textes pour coller aux JSON)
- Test: `NivelCore/Tests/NivelCoreTests/ActivityCatalogTests.swift`

- [ ] **Step 1 : Ajouter les tests (rouges)** — dans `ActivityCatalogTests.swift` :

```swift
    func testEveryActivityHasInstructions() throws {
        for activity in try Catalogs.activities() {
            XCTAssertGreaterThanOrEqual(activity.instructions.count, 3, activity.id)
            XCTAssertTrue(activity.instructions.allSatisfy { !$0.isEmpty }, activity.id)
        }
    }

    func testEverySessionStepHasTempo() throws {
        for session in try Catalogs.sessions() {
            for step in session.steps {
                XCTAssertFalse(step.tempo.isEmpty, "\(session.id)/\(step.activityID)")
            }
        }
    }

    func testUserFacingSportTextsHaveNoEmDash() throws {
        // Convention de la branche (commit « remove em dashes ») : aucun — dans les textes.
        for activity in try Catalogs.activities() {
            for line in activity.instructions {
                XCTAssertFalse(line.contains("—"), "\(activity.id): \(line)")
            }
        }
        for session in try Catalogs.sessions() {
            for step in session.steps {
                XCTAssertFalse(step.tempo.contains("—"), "\(session.id)/\(step.activityID)")
            }
        }
    }
```

- [ ] **Step 2 : Vérifier l'échec**

Run: `cd NivelCore && swift test --filter ActivityCatalogTests`
Expected: FAIL (compile error, champs inconnus).

- [ ] **Step 3 : Ajouter les champs**

Dans `ActivityCatalog.swift` :
- `Activity` : ajouter après `durations` →
```swift
    /// Consignes « comment faire » : 3-4 puces courtes (position, mouvement,
    /// repère sécurité/respiration), ton bienveillant (spec illustrations §4.1).
    public let instructions: [String]
```
- `SessionStep` : ajouter après `minutes` (et compléter le `public init`) →
```swift
    /// Rythme suggéré de l'étape, affiché en badge dans le player (spec §4.2).
    /// Jamais un programme rigide : une suggestion, pas un chrono.
    public let tempo: String
```

- [ ] **Step 4 : Réécrire les deux JSON avec le contenu EXACT ci-dessous** (sans tiret cadratin) :

`NivelCore/Sources/NivelCore/Resources/activities.json` — mêmes entrées/valeurs qu'actuellement, chacune gagnant `"instructions"` :

```json
[
  {"id": "walk",            "name": "Marche",               "emoji": "🚶",  "location": "outdoor", "kcalPerMin": 4.0, "durations": [10, 20, 40],
   "instructions": ["Garde le dos droit, les épaules relâchées", "Marche d'un bon pas, les bras balancent naturellement", "Respire régulièrement : la conversation doit rester possible"]},
  {"id": "brisk_walk",      "name": "Marche rapide",        "emoji": "🚶‍♀️", "location": "outdoor", "kcalPerMin": 5.5, "durations": [10, 20, 30],
   "instructions": ["Accélère le pas jusqu'à sentir le souffle monter", "Les bras accompagnent, coudes pliés", "Garde une foulée confortable, vitesse ne veut pas dire course"]},
  {"id": "bike",            "name": "Vélo tranquille",      "emoji": "🚴",  "location": "outdoor", "kcalPerMin": 6.0, "durations": [15, 30, 45],
   "instructions": ["Règle la selle : jambe presque tendue en bas de pédale", "Pédale à un rythme régulier, sans forcer", "Change de vitesse plutôt que de forcer sur les jambes"]},
  {"id": "stairs",          "name": "Montées d'escaliers",  "emoji": "🪜",  "location": "both",    "kcalPerMin": 8.0, "durations": [5, 10, 15],
   "instructions": ["Monte marche par marche, pose tout le pied", "Aide-toi de la rampe si besoin", "Redescends tranquillement, la descente compte aussi", "Fais une pause dès que les jambes brûlent trop"]},
  {"id": "dance",           "name": "Danse libre",          "emoji": "💃",  "location": "home",    "kcalPerMin": 5.5, "durations": [10, 15, 25],
   "instructions": ["Mets ta musique préférée, personne ne regarde", "Bouge tout : bras, hanches, tête", "Un léger essoufflement est bon signe, amuse-toi"]},
  {"id": "stretching",      "name": "Étirements",           "emoji": "🧘",  "location": "home",    "kcalPerMin": 2.5, "durations": [5, 10, 15],
   "instructions": ["Étire-toi lentement, sans à-coups", "Tiens chaque position environ 30 secondes", "La tension doit rester agréable, jamais de douleur", "Respire profondément pendant l'étirement"]},
  {"id": "plank",           "name": "Gainage / planche",    "emoji": "🧎",  "location": "home",    "kcalPerMin": 4.0, "durations": [3, 5, 8],
   "instructions": ["Avant-bras au sol, coudes sous les épaules", "Corps aligné des épaules aux talons", "Serre le ventre, ne creuse pas le dos", "Pose les genoux quand ça tremble trop, c'est normal"]},
  {"id": "squats",          "name": "Squats",               "emoji": "🦵",  "location": "home",    "kcalPerMin": 5.5, "durations": [3, 5, 10],
   "instructions": ["Pieds écartés largeur d'épaules", "Descends comme pour t'asseoir sur une chaise", "Le dos reste droit, les talons au sol", "Remonte en poussant dans les talons"]},
  {"id": "wall_pushups",    "name": "Pompes murales",       "emoji": "🧱",  "location": "home",    "kcalPerMin": 4.0, "durations": [3, 5, 8],
   "instructions": ["Face au mur, mains à plat largeur d'épaules", "Recule d'un pas, corps bien aligné", "Plie les coudes pour approcher le mur, puis repousse", "Plus les pieds sont loin du mur, plus c'est intense"]},
  {"id": "active_cleaning", "name": "Ménage actif",         "emoji": "🧹",  "location": "home",    "kcalPerMin": 3.5, "durations": [15, 30, 45],
   "instructions": ["Mets de la musique et accélère le mouvement", "Alterne les tâches pour faire bouger tout le corps", "Plie les genoux pour ramasser, pas le dos"]},
  {"id": "yoga",            "name": "Yoga doux",            "emoji": "🧘‍♀️", "location": "home",    "kcalPerMin": 3.0, "durations": [10, 20, 30],
   "instructions": ["Installe-toi au calme, sur un tapis si possible", "Enchaîne des postures simples, tenues quelques respirations", "Concentre-toi sur une respiration lente et profonde", "Ne force jamais une posture"]},
  {"id": "digestive_walk",  "name": "Balade digestive",     "emoji": "🌳",  "location": "outdoor", "kcalPerMin": 3.5, "durations": [10, 15, 20],
   "instructions": ["Pars tranquillement, 10 à 20 minutes après le repas", "Rythme doux : c'est une balade, pas une marche sportive", "Profites-en pour prendre l'air et souffler"]}
]
```

`NivelCore/Sources/NivelCore/Resources/sessions.json` — mêmes séances/étapes, chaque étape gagnant `"tempo"` :

```json
[
  {"id": "wake_up",           "title": "Réveil musculaire",   "emoji": "🌅", "steps": [
    {"activityID": "stretching", "minutes": 4, "tempo": "~30 s par position : bras, nuque, dos, jambes"},
    {"activityID": "squats",     "minutes": 4, "tempo": "~10 squats tranquilles × 3, avec des pauses"},
    {"activityID": "plank",      "minutes": 3, "tempo": "3 × ~30 s, repos entre chaque, genoux posés si besoin"}]},
  {"id": "energy_break",      "title": "Pause énergie",       "emoji": "⚡", "steps": [
    {"activityID": "stairs",     "minutes": 5, "tempo": "Monte et descends à ton rythme, pause à mi-parcours"},
    {"activityID": "dance",      "minutes": 5, "tempo": "2-3 morceaux, lâche-toi !"},
    {"activityID": "stretching", "minutes": 3, "tempo": "Jambes et dos, ~30 s par étirement"}]},
  {"id": "evening_wind_down", "title": "Détente du soir",     "emoji": "🌙", "steps": [
    {"activityID": "yoga",       "minutes": 8, "tempo": "3-4 postures douces, tenues 4-5 respirations"},
    {"activityID": "stretching", "minutes": 5, "tempo": "Étirements lents, ~40 s chacun, pour préparer la nuit"}]},
  {"id": "quick_tone",        "title": "Tonus express",       "emoji": "💪", "steps": [
    {"activityID": "squats",       "minutes": 4, "tempo": "~10 squats × 3, la dernière série plus lente"},
    {"activityID": "wall_pushups", "minutes": 4, "tempo": "~8 pompes × 3, coudes près du corps"},
    {"activityID": "plank",        "minutes": 4, "tempo": "4 × ~30 s, souffle régulier"}]},
  {"id": "fresh_air",         "title": "Bol d'air",           "emoji": "🚶", "steps": [
    {"activityID": "walk",       "minutes": 15, "tempo": "Un tour de quartier d'un bon pas, en respirant à fond"}]},
  {"id": "mood_boost",        "title": "Boost bonne humeur",  "emoji": "🎵", "steps": [
    {"activityID": "dance",      "minutes": 10, "tempo": "3-4 morceaux qui font du bien, sans retenue"},
    {"activityID": "stretching", "minutes": 4,  "tempo": "Redescends en douceur, ~30 s par étirement"}]},
  {"id": "zen_core",          "title": "Zen & gainage",       "emoji": "🧘", "steps": [
    {"activityID": "yoga",       "minutes": 6, "tempo": "2-3 postures d'équilibre, 5 respirations chacune"},
    {"activityID": "plank",      "minutes": 4, "tempo": "3 × ~40 s, concentration sur la respiration"},
    {"activityID": "stretching", "minutes": 4, "tempo": "Dos et épaules, lentement"}]},
  {"id": "home_cardio",       "title": "Cardio maison",       "emoji": "🪜", "steps": [
    {"activityID": "stairs",     "minutes": 6, "tempo": "3 allers-retours, pause entre chaque"},
    {"activityID": "squats",     "minutes": 3, "tempo": "~10 squats × 2, bien poussés dans les talons"},
    {"activityID": "stretching", "minutes": 4, "tempo": "Jambes surtout : mollets, cuisses, ~30 s chacun"}]}
]
```

⚠️ `SessionStep` a un `public init` explicite : le compléter (`init(activityID:minutes:tempo:)`). Vérifier que rien d'autre ne construit des `SessionStep` en dur (grep) : seuls les JSON en créent.

- [ ] **Step 5 : Synchroniser la spec** — dans `docs/superpowers/specs/2026-07-30-sport-illustrations-design.md` §4.1/§4.2, remplacer les textes contenant « — » par les versions ci-dessus (les JSON font foi).

- [ ] **Step 6 : Vérifier le vert complet**

Run: `cd NivelCore && swift test`
Expected: PASS, 50 tests (47 + 3 nouveaux). Puis suite app : TEST SUCCEEDED, 35 tests (rien ne consomme encore les nouveaux champs, mais le décodage est exercé partout).

- [ ] **Step 7 : Commit**

```bash
git add NivelCore docs
git commit -m "feat(core): consignes d'activités et rythmes d'étapes (contenus validés)"
```

---

## Task 3 : `SportIllustration` + vignettes partout

**Files:**
- Create: `App/Views/Sport/SportIllustration.swift`
- Modify: `App/Views/Sport/DailySessionCard.swift` (vignette héro 56pt dans `DailySessionCardContent`)
- Modify: `App/Views/Sport/SportView.swift` (lignes catalogue + « Fait aujourd'hui »)

- [ ] **Step 1 : Créer le composant**

```swift
// App/Views/Sport/SportIllustration.swift
// Vignettes et héros des illustrations sport (spec illustrations §3) : affiche
// l'asset "Sport/<name>" ; FALLBACK automatique sur l'emoji en pastille si
// l'asset manque : l'app ne dépend jamais d'une image.

import SwiftUI
import UIKit

/// Vignette carrée (lignes de liste, cartes). `name` = id de catalogue.
struct SportIllustration: View {
    let name: String
    let fallbackEmoji: String
    var size: CGFloat = 52
    var cornerRadius: CGFloat = 12

    var body: some View {
        if UIImage(named: "Sport/\(name)") != nil {
            Image("Sport/\(name)")
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            Text(fallbackEmoji)
                .font(.system(size: size * 0.55))
                .frame(width: size, height: size)
                .background(Theme.accent.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

/// Grand format du player (pleine largeur, carré, hauteur plafonnée ~280pt, spec §5.1).
struct SportHeroIllustration: View {
    let name: String
    let fallbackEmoji: String

    var body: some View {
        if UIImage(named: "Sport/\(name)") != nil {
            Image("Sport/\(name)")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: 20))
        } else {
            Text(fallbackEmoji)
                .font(.system(size: 80))
                .frame(maxWidth: .infinity, minHeight: 180)
                .background(Theme.accent.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 20))
        }
    }
}
```

- [ ] **Step 2 : Remplacer les emoji par des vignettes**

1. `DailySessionCardContent` (DailySessionCard.swift) : remplacer `Text(session.emoji).font(.system(size: 32))` par `SportIllustration(name: session.id, fallbackEmoji: session.emoji, size: 56, cornerRadius: 14)`.
2. `SportView.activitySection` : remplacer `Text(activity.emoji).font(.system(size: 26))` par `SportIllustration(name: activity.id, fallbackEmoji: activity.emoji)`.
3. `SportView.doneRow` : le tuple `(emoji, name)` devient `(refID-based)` : remplacer `Text(emoji).font(.system(size: 26))` par `SportIllustration(name: entry.refID, fallbackEmoji: emoji)` (le refID EST l'id d'asset, pour les deux kinds).

- [ ] **Step 3 : Build + previews**

Run: `xcodegen generate && xcodebuild -project Nivel.xcodeproj -scheme Nivel -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | tail -5`
Expected: TEST SUCCEEDED, 35 tests. Vérifier les previews SportView/HomeView dans Xcode (vignettes visibles, fallback testable en passant un name bidon dans un preview temporaire, ne pas le committer).

- [ ] **Step 4 : Commit**

```bash
git add -A && git commit -m "feat(app): vignettes illustrées (SportIllustration + fallback emoji)"
```

---

## Task 4 : `ActivityLogSheet` enrichie (illustration + « Comment faire »)

**Files:**
- Modify: `App/Views/Sport/ActivityLogSheet.swift`

- [ ] **Step 1 : Ajouter l'illustration et les consignes**

Dans le `VStack` du `ScrollView`, remplacer l'en-tête actuel (emoji 40pt + nom) par :

```swift
                    SportHeroIllustration(name: activity.id, fallbackEmoji: activity.emoji)
                    Text(activity.name)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.text)
```

puis AVANT la section « Durée », insérer :

```swift
                    SectionTitle("Comment faire")   // composant partagé v1.2 (comme SectionTitle("Durée") juste dessous)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(activity.instructions, id: \.self) { line in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•").foregroundStyle(Theme.orange)
                                Text(line)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
```

- [ ] **Step 2 : Build + tests + vérif preview**

Run: `xcodebuild ... test 2>&1 | tail -5` → TEST SUCCEEDED, 35 tests. Preview : l'illustration s'affiche, les puces sont lisibles, le choix de durée et le CTA n'ont pas bougé.

- [ ] **Step 3 : Commit**

```bash
git add -A && git commit -m "feat(app): sheet d'activité illustrée avec consignes Comment faire"
```

---

## Task 5 : `SessionPlayerSheet` (pas-à-pas) + bascule des call sites

**Files:**
- Create: `App/Views/Sport/SessionPlayerSheet.swift`
- Delete: `App/Views/Sport/SessionDetailSheet.swift`
- Modify: `App/Views/Home/HomeView.swift` (call site + en-tête de fichier)
- Modify: `App/Views/Sport/SportView.swift` (call site)
- Test: `NivelTests/SessionPlayerTests.swift`

- [ ] **Step 1 : Écrire le test de la fonction pure (rouge)**

```swift
// NivelTests/SessionPlayerTests.swift
import XCTest
@testable import Nivel

final class SessionPlayerTests: XCTestCase {
    /// Le contrat EXHAUSTIF du bouton (spec illustrations §5.1, 5 lignes).
    func testButtonStateContract() {
        // Page 0 (aperçu)
        XCTAssertEqual(SessionPlayerSheet.buttonState(page: 0, stepCount: 3, done: false), .start)
        XCTAssertEqual(SessionPlayerSheet.buttonState(page: 0, stepCount: 3, done: true), .alreadyDone)
        // Étapes intermédiaires (done indifférent)
        XCTAssertEqual(SessionPlayerSheet.buttonState(page: 1, stepCount: 3, done: false), .next)
        XCTAssertEqual(SessionPlayerSheet.buttonState(page: 2, stepCount: 3, done: true), .next)
        // Dernière étape
        XCTAssertEqual(SessionPlayerSheet.buttonState(page: 3, stepCount: 3, done: false), .validate)
        XCTAssertEqual(SessionPlayerSheet.buttonState(page: 3, stepCount: 3, done: true), .alreadyDone)
        // Séance à une seule étape (fresh_air) : la page 1 est déjà la dernière.
        XCTAssertEqual(SessionPlayerSheet.buttonState(page: 1, stepCount: 1, done: false), .validate)
    }
}
```

- [ ] **Step 2 : Vérifier l'échec**

Run: `xcodegen generate && xcodebuild ... test 2>&1 | tail -5` → BUILD FAILED (`SessionPlayerSheet` inconnu).

- [ ] **Step 3 : Créer le player**

```swift
// App/Views/Sport/SessionPlayerSheet.swift
// Player pas-à-pas de la séance du jour (spec illustrations §5.1) : page 0 aperçu,
// une page par étape (grande illustration, consignes, tempo), navigation LIBRE
// (guide, pas chrono). Validation sur la dernière page uniquement.
// Remplace SessionDetailSheet.

import SwiftUI
import UIKit
import NivelCore

struct SessionPlayerSheet: View {
    @Environment(GameService.self) private var game
    @Environment(\.dismiss) private var dismiss

    let session: ActivitySession
    let done: Bool
    @State private var page = 0
    @State private var isSaving = false

    /// Contrat du bouton bas (spec §5.1) : logique PURE, testée (SessionPlayerTests).
    enum PlayerButton: Equatable { case start, next, validate, alreadyDone }

    static func buttonState(page: Int, stepCount: Int, done: Bool) -> PlayerButton {
        if page == 0 { return done ? .alreadyDone : .start }
        if page < stepCount { return .next }
        return done ? .alreadyDone : .validate
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                dots
                TabView(selection: $page) {
                    overviewPage.tag(0)
                    ForEach(Array(session.steps.enumerated()), id: \.offset) { index, step in
                        stepPage(step, number: index + 1).tag(index + 1)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Progression

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(0...session.steps.count, id: \.self) { index in
                Circle()
                    .fill(index == page ? Theme.orange : Theme.track)
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.top, 14)
        .accessibilityHidden(true)
    }

    // MARK: Page 0 : aperçu

    private var overviewPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SportHeroIllustration(name: session.id, fallbackEmoji: session.emoji)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Séance du jour")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.subtext)
                    Text(session.title)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.text)
                    Text("\(session.totalMinutes) min · ~\(game.sessionKcal(session).frFormatted) kcal")
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtext)
                }
                VStack(spacing: 8) {
                    ForEach(Array(session.steps.enumerated()), id: \.offset) { _, step in
                        summaryRow(step)
                    }
                }
            }
            .padding(20)
        }
    }

    private func summaryRow(_ step: SessionStep) -> some View {
        let activity = game.activitiesByID[step.activityID]
        return HStack(spacing: 10) {
            SportIllustration(name: step.activityID,
                              fallbackEmoji: activity?.emoji ?? "🏃",
                              size: 40, cornerRadius: 10)
            Text(activity?.name ?? step.activityID)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.text)
            Spacer()
            Text("\(step.minutes) min")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.orange)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Pages 1..n : étapes

    private func stepPage(_ step: SessionStep, number: Int) -> some View {
        let activity = game.activitiesByID[step.activityID]
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SportHeroIllustration(name: step.activityID,
                                      fallbackEmoji: activity?.emoji ?? "🏃")
                HStack(alignment: .firstTextBaseline) {
                    Text(activity?.name ?? step.activityID)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Text("Étape \(number)/\(session.steps.count) · \(step.minutes) min")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.subtext)
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(activity?.instructions ?? [], id: \.self) { line in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•").foregroundStyle(Theme.orange)
                            Text(line)
                                .font(.subheadline)
                                .foregroundStyle(Theme.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Text(step.tempo)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.accent.opacity(0.15), in: Capsule())
            }
            .padding(20)
        }
    }

    // MARK: Bouton bas

    private var bottomBar: some View {
        HStack {
            switch Self.buttonState(page: page, stepCount: session.steps.count, done: done) {
            case .start:
                ctaButton("C'est parti !") { withAnimation(.snappy) { page = 1 } }
            case .next:
                ctaButton("Étape suivante →") { withAnimation(.snappy) { page += 1 } }
            case .validate:
                ctaButton("C'est fait ! (+40 XP)", action: validate)
            case .alreadyDone:
                Label("Déjà faite", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.green)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.card.ignoresSafeArea(edges: .bottom))
        .shadow(color: .black.opacity(0.08), radius: 10, y: -4)
    }

    private func ctaButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
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

⚠️ CONVENTIONS v1.2 (obligatoires, le code ci-dessus est un GABARIT à adapter) :
- `ctaButton` → utiliser **`PrimaryButtonStyle`** comme `MealLogSheet`/`ActivityLogSheet` (reproduire leur pattern exact), pas le gradient inline montré ici ;
- ombre de `bottomBar` → **`Theme.floatingShadow`**, pas `.black.opacity(0.08)` ;
- sheet → ajouter **`.presentationCornerRadius(28)`** (convention sheets v1.2) ;
- « Séance du jour » de la page aperçu → composant **`Overline`** (comme l'ancien `SessionDetailSheet`).

- [ ] **Step 4 : Basculer les call sites et supprimer l'ancienne sheet**

1. `HomeView.swift` : `SessionDetailSheet(session:done:)` → `SessionPlayerSheet(session: status.session, done: status.done)` (le `.presentationDragIndicator(.visible)` du call site peut disparaître, le player le porte déjà).
2. `SportView.swift` : idem.
3. `git rm App/Views/Sport/SessionDetailSheet.swift` puis `xcodegen generate`.
4. Ajouter un `#Preview` à `SessionPlayerSheet.swift` (fixture in-memory type SportView, avec et sans `done`).

- [ ] **Step 5 : Vérifier le vert**

Run: `xcodebuild ... test 2>&1 | tail -5`
Expected: TEST SUCCEEDED, 36 tests (35 + SessionPlayerTests). Vérifier au passage : `grep -rn "SessionDetailSheet" App NivelTests` → vide.

- [ ] **Step 6 : Commit**

```bash
git add -A && git commit -m "feat(app): player pas-à-pas de la séance du jour (remplace la sheet de détail)"
```

---

## Task 6 : Vérification finale + docs

**Files:**
- Modify: `README.md` (mention des séances guidées illustrées)

- [ ] **Step 1 : Suites complètes**

Run: `cd NivelCore && swift test && cd .. && xcodebuild -project Nivel.xcodeproj -scheme Nivel -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | tail -5`
Expected: 50 tests NivelCore + 36 tests app, tout vert.

- [ ] **Step 2 : README**

Dans l'intro, enrichir la phrase sport : les activités et la séance du jour sont illustrées (Nivelito en action) et la séance se suit en mode pas-à-pas guidé. Mentionner `scripts/import-sport-images.sh` dans la section Commandes (régénération des assets depuis `design/sport/`).

- [ ] **Step 3 : Vérification visuelle simulateur (recommandée)**

Onglet Sport : vignettes partout, tap séance → player (aperçu → étapes → validation +40 XP → bulle au retour accueil), re-ouverture → « Déjà faite » + feuilletage libre. Tap activité → illustration + « Comment faire » + durées. Thème Nuit douce : vignettes claires OK.

- [ ] **Step 4 : Commit final**

```bash
git add -A && git commit -m "docs: README, séances guidées illustrées"
```

Fin de branche : options merge/PR présentées à Michaël (superpowers:finishing-a-development-branch).
