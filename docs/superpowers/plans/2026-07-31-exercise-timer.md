# Timer d'exercice (v1.5) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Timer opt-in en anneau (illustration au centre, graduations de séries, fin en douceur) sur les pages d'étapes du player et la sheet d'activité libre.

**Architecture:** Un modèle d'état pur et testable (`ExerciseTimerModel`, horloge murale, dates injectées), une vue anneau réutilisable (`TimerRingView` + contrôles), branchés sur deux surfaces : `SessionPlayerSheet` (refactor `stepPage` → struct `StepPageView` pour l'état par page) et `ActivityLogSheet`. NivelCore ne change que pour `SessionStep.segments: Int?` + 10 valeurs JSON. Spec : `docs/superpowers/specs/2026-07-31-exercise-timer-design.md` (contrats exhaustifs : pulse §5, graduations §4).

**Tech Stack:** SwiftUI (TimelineView, @Observable), XCTest, AudioToolbox (son système), UIKit (haptique, idleTimer).

**Branche : créer `feat/exercise-timer` depuis `main`.**

### Task 0 : Branche

- [ ] `cd /Users/mbernard/perso/Nivel && git checkout -b feat/exercise-timer`

**Commandes de test :**
- NivelCore : `cd NivelCore && swift test`
- App : `xcodebuild -project Nivel.xcodeproj -scheme Nivel -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`

**Pièges connus :**
1. `xcodegen generate` après chaque création de fichier Swift sous `App/` ou `NivelTests/`.
2. AUCUN texte utilisateur avec tiret cadratin ; formulations neutres.
3. `isIdleTimerDisabled` remis à `false` sur TOUS les chemins de sortie (pause, reset, fin, `onDisappear`, dismiss) — spec §10.
4. Le pulse ne s'applique QUE si la barre basse montre un bouton actionnable (`.next`/`.validate`) — jamais sur `.alreadyDone` (spec §5). Désactivé si Reduce Motion.
5. Les conventions v1.2 s'appliquent (PrimaryButtonStyle/SecondaryButtonStyle, `Theme.*`, pas de gradient inline) : LIRE `ActivityLogSheet.swift` et `Theme.swift` avant d'écrire l'UI.

---

## Task 1 : NivelCore — `SessionStep.segments: Int?` + 10 valeurs JSON

**Files:**
- Modify: `NivelCore/Sources/NivelCore/ActivityCatalog.swift` (champ optionnel + init)
- Modify: `NivelCore/Sources/NivelCore/Resources/sessions.json` (10 étapes gagnent `"segments"`)
- Test: `NivelCore/Tests/NivelCoreTests/ActivityCatalogTests.swift`

- [ ] **Step 1 : Test (rouge)** — ajouter à `ActivityCatalogTests.swift` :

```swift
    func testSegmentsDecodeWhenPresentAndNilOtherwise() throws {
        let sessions = try Catalogs.sessions()
        let wakeUp = try XCTUnwrap(sessions.first { $0.id == "wake_up" })
        XCTAssertEqual(wakeUp.steps.map(\.segments), [2, 3, 3])           // stretching, squats, plank
        let freshAir = try XCTUnwrap(sessions.first { $0.id == "fresh_air" })
        XCTAssertEqual(freshAir.steps.map(\.segments), [nil])             // pas de séries explicites
        // Cohérence : jamais 0 ou 1 (une graduation n'a de sens qu'à partir de 2).
        for session in sessions {
            for step in session.steps {
                if let segments = step.segments { XCTAssertGreaterThanOrEqual(segments, 2, "\(session.id)/\(step.activityID)") }
            }
        }
    }
```

- [ ] **Step 2 : Vérifier l'échec** — `cd NivelCore && swift test --filter ActivityCatalogTests` → FAIL (compile, `segments` inconnu).

- [ ] **Step 3 : Champ** — dans `ActivityCatalog.swift`, `SessionStep` :

```swift
    /// Nombre de séries affiché en graduations sur l'anneau du timer (spec timer §4).
    /// nil = pas de graduations (tempos en fourchette ou sans séries explicites).
    public let segments: Int?
```

et compléter le `public init` (`segments: Int? = nil`).

- [ ] **Step 4 : JSON** — dans `sessions.json`, ajouter `"segments": N` aux 10 étapes EXACTES (spec §4, dérivées des tempos) :
wake_up/stretching 2, wake_up/squats 3, wake_up/plank 3, quick_tone/squats 3, quick_tone/wall_pushups 3, quick_tone/plank 4, zen_core/plank 3, home_cardio/squats 2, legs_day/squats 2, gentle_cardio/high_knees 3. Exemple de forme : `{"activityID": "plank", "minutes": 3, "tempo": "3 × ~30 s, repos entre chaque, genoux posés si besoin", "segments": 3}`. AUCUNE autre étape ne change.

- [ ] **Step 5 : Vert** — `cd NivelCore && swift test` → **51 tests, 0 failures** (50 + 1). Suite app inchangée si lancée (36).

- [ ] **Step 6 : Commit** — `git add NivelCore && git commit -m "feat(core): segments de séries sur les étapes de séances (graduations du timer)"`

---

## Task 2 : App — `ExerciseTimerModel` (logique pure, TDD)

**Files:**
- Create: `App/Views/Sport/ExerciseTimerModel.swift`
- Test (create): `NivelTests/ExerciseTimerModelTests.swift`

- [ ] **Step 1 : Tests (rouges)**

```swift
// NivelTests/ExerciseTimerModelTests.swift
import XCTest
@testable import Nivel

@MainActor
final class ExerciseTimerModelTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func t(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    func testIdleThenRunningCountsDown() {
        let timer = ExerciseTimerModel(durationMinutes: 3)   // 180 s
        XCTAssertEqual(timer.remaining(at: t0), 180)
        XCTAssertEqual(timer.fraction(at: t0), 0)
        timer.start(at: t0)
        XCTAssertEqual(timer.remaining(at: t(60)), 120)
        XCTAssertEqual(timer.fraction(at: t(90)), 0.5, accuracy: 0.001)
    }

    func testPauseFreezesAndResumeContinues() {
        let timer = ExerciseTimerModel(durationMinutes: 3)
        timer.start(at: t0)
        timer.pause(at: t(30))
        XCTAssertEqual(timer.remaining(at: t(999)), 150)     // figé pendant la pause
        timer.resume(at: t(100))
        XCTAssertEqual(timer.remaining(at: t(130)), 120)     // 30 s écoulées + 30 s après reprise
    }

    func testExpiryFlipsToFinishedIncludingWhileAway() {
        let timer = ExerciseTimerModel(durationMinutes: 3)
        timer.start(at: t0)
        // Retour au premier plan APRÈS l'échéance (app en arrière-plan pendant le timer).
        XCTAssertTrue(timer.syncNow(at: t(190)))              // transition → finished (une seule fois)
        XCTAssertTrue(timer.isFinished)
        XCTAssertEqual(timer.remaining(at: t(999)), 0)
        XCTAssertFalse(timer.syncNow(at: t(200)))             // pas de double transition
    }

    func testResetReturnsToIdle() {
        let timer = ExerciseTimerModel(durationMinutes: 3)
        timer.start(at: t0)
        timer.pause(at: t(10))
        timer.reset()
        XCTAssertEqual(timer.remaining(at: t(500)), 180)
        XCTAssertFalse(timer.isRunning)
        XCTAssertFalse(timer.isFinished)
    }

    func testFractionClampsAtOne() {
        let timer = ExerciseTimerModel(durationMinutes: 3)
        timer.start(at: t0)
        XCTAssertEqual(timer.fraction(at: t(9_999)), 1.0)
    }
}
```

- [ ] **Step 2 : Vérifier l'échec** — `xcodegen generate && xcodebuild ... test` → BUILD FAILED (type inconnu).

- [ ] **Step 3 : Implémenter**

```swift
// App/Views/Sport/ExerciseTimerModel.swift
// État du timer d'exercice (spec timer §5) : machine à états sur HORLOGE MURALE
// (robuste au passage en arrière-plan), logique pure interrogeable avec une date
// injectée — les tests ne dorment jamais. Opt-in : ne démarre jamais seul.

import Foundation
import Observation

@Observable @MainActor
final class ExerciseTimerModel {
    enum Phase: Equatable {
        case idle
        case running(since: Date, alreadyElapsed: TimeInterval)
        case paused(elapsed: TimeInterval)
        case finished
    }

    let duration: TimeInterval
    private(set) var phase: Phase = .idle

    init(durationMinutes: Int) {
        self.duration = TimeInterval(durationMinutes) * 60
    }

    // MARK: Lecture (pures, date injectée)

    func elapsed(at now: Date = .now) -> TimeInterval {
        switch phase {
        case .idle: 0
        case .running(let since, let already): min(duration, already + now.timeIntervalSince(since))
        case .paused(let elapsed): elapsed
        case .finished: duration
        }
    }

    func remaining(at now: Date = .now) -> TimeInterval { max(0, duration - elapsed(at: now)) }

    func fraction(at now: Date = .now) -> Double {
        duration > 0 ? min(1, elapsed(at: now) / duration) : 1
    }

    var isRunning: Bool { if case .running = phase { true } else { false } }
    var isPaused: Bool { if case .paused = phase { true } else { false } }
    var isFinished: Bool { phase == .finished }
    var isIdle: Bool { phase == .idle }

    // MARK: Transitions

    func start(at now: Date = .now) { phase = .running(since: now, alreadyElapsed: 0) }

    func pause(at now: Date = .now) {
        guard isRunning else { return }
        phase = .paused(elapsed: elapsed(at: now))
    }

    func resume(at now: Date = .now) {
        guard case .paused(let elapsed) = phase else { return }
        phase = .running(since: now, alreadyElapsed: elapsed)
    }

    func reset() { phase = .idle }

    /// À appeler à chaque tick d'affichage et au retour au premier plan : bascule en
    /// `.finished` si l'échéance est passée. Retourne true UNIQUEMENT à la transition
    /// (pour ne déclencher haptique/son qu'une fois).
    @discardableResult
    func syncNow(at now: Date = .now) -> Bool {
        guard isRunning, remaining(at: now) <= 0 else { return false }
        phase = .finished
        return true
    }
}
```

- [ ] **Step 4 : Vert** — suite app → **41 tests** (36 + 5), TEST SUCCEEDED.

- [ ] **Step 5 : Commit** — `git add -A && git commit -m "feat(app): ExerciseTimerModel, machine à états du timer sur horloge murale"`

---

## Task 3 : App — `TimerRingView` + contrôles (UI réutilisable)

**Files:**
- Create: `App/Views/Sport/TimerRingView.swift`

Pas de TDD (vue) : implémentation + previews + build. LIRE `App/Views/Home/CalorieRing.swift` d'abord (technique d'anneau maison) et suivre les conventions v1.2.

- [ ] **Step 1 : Implémenter** — le fichier contient TOUT l'UI timer réutilisable :

```swift
// App/Views/Sport/TimerRingView.swift
// UI du timer d'exercice (spec timer §3, §5) : anneau de progression autour de
// l'illustration (cousin de CalorieRing), graduations de séries optionnelles,
// temps restant, contrôles. Fin = vert + « Bien joué ! », jamais de rouge.

import SwiftUI

/// Anneau + illustration circulaire. Décoratif pour VoiceOver (le temps est à côté).
struct TimerRingView: View {
    let illustrationName: String
    let fallbackEmoji: String
    let fraction: Double          // 0...1
    let finished: Bool
    var segments: Int? = nil      // ≥ 2 → graduations
    var size: CGFloat = 230

    private var lineWidth: CGFloat { max(10, size * 0.056) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    finished
                        ? AnyShapeStyle(Theme.green)
                        : AnyShapeStyle(LinearGradient(colors: [Theme.accent, Theme.orange],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: fraction)
            if let segments, segments >= 2 {
                ForEach(1..<segments, id: \.self) { index in
                    Capsule()
                        .fill(Theme.background)
                        .frame(width: 4, height: lineWidth + 6)
                        .offset(y: -size / 2)
                        .rotationEffect(.degrees(Double(index) / Double(segments) * 360))
                }
            }
            SportIllustration(name: illustrationName, fallbackEmoji: fallbackEmoji,
                              size: size - lineWidth * 2 - 12,
                              cornerRadius: (size - lineWidth * 2 - 12) / 2)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Temps restant + contrôles Lancer/Pause/Reprendre/Recommencer, pilotés par le modèle.
/// `now` vient du TimelineView de l'appelant (lecture pure, pas de tick interne).
struct TimerControls: View {
    let timer: ExerciseTimerModel
    let now: Date

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if timer.isFinished {
                    Text("Bien joué !")
                        .foregroundStyle(Theme.green)
                } else {
                    Text(Self.format(timer.remaining(at: now)))
                        .foregroundStyle(Theme.text)
                        .contentTransition(.numericText())
                }
            }
            .font(.system(.largeTitle, design: .rounded).weight(.heavy))   // scale en Dynamic Type (spec §7)
            .minimumScaleFactor(0.7)
            .monospacedDigit()
            .accessibilityLabel(timer.isFinished ? "Terminé, bien joué" : Self.spokenRemaining(timer.remaining(at: now)))

            if timer.isPaused {
                Text("En pause, prends ton temps 🧡")
                    .font(.footnote)
                    .foregroundStyle(Theme.subtext)
            }

            HStack(spacing: 10) {
                if timer.isIdle {
                    Button("Lancer le timer") { timer.start() }
                        .buttonStyle(PrimaryButtonStyle(size: .compact))
                } else if timer.isRunning {
                    Button("Pause") { timer.pause() }
                        .buttonStyle(SecondaryButtonStyle())
                } else if timer.isPaused {
                    Button("Reprendre") { timer.resume() }
                        .buttonStyle(PrimaryButtonStyle(size: .compact))
                }
                if !timer.isIdle {
                    Button("Recommencer") { timer.reset() }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }

    /// "2:41" (minutes:secondes, arrondi à la seconde supérieure pour ne jamais afficher 0:00 en cours).
    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }

    static func spokenRemaining(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let minutes = total / 60, secs = total % 60
        if minutes > 0 { return "\(minutes) minutes \(secs) secondes restantes" }
        return "\(secs) secondes restantes"
    }
}
```

⚠️ Les signatures `PrimaryButtonStyle(size: .compact)` / `SecondaryButtonStyle()` sont vérifiées contre `Theme.swift` (elles compilent telles quelles). Le `LinearGradient` inline de l'ANNEAU est VOULU (même gradient que la famille d'anneaux/CTA maison — le piège #5 vise les boutons, pas les strokes d'anneau). Si un helper de format de temps existe déjà, le réutiliser.

- [ ] **Step 2 : Previews** — dans le même fichier : anneau idle (fraction 0), en cours (0.6 avec segments 3), finished (1, vert), + un preview TimerControls par état (modèle piloté avec `start(at:)`/dates fixes).

- [ ] **Step 3 : Build** — `xcodegen generate && xcodebuild ... build` → BUILD SUCCEEDED, puis `... test` → 41 tests.

- [ ] **Step 4 : Commit** — `git add -A && git commit -m "feat(app): TimerRingView et contrôles du timer (anneau, graduations, états)"`

---

## Task 4 : Player — `StepPageView` + timer intégré

**Files:**
- Modify: `App/Views/Sport/SessionPlayerSheet.swift`

- [ ] **Step 1 : Extraire `StepPageView`** — transformer la fonction privée `stepPage(_:number:)` en struct privée `StepPageView` (dans le même fichier) : propriétés `step: SessionStep`, `number: Int`, `stepCount: Int`, `activity: Activity?`, **`isCurrent: Bool`** (le parent passe `page == index + 1`) et **closure `onTimerFinished: () -> Void`** (forme retenue — pas de Binding). Le `ForEach` l'instancie : `StepPageView(..., isCurrent: page == index + 1, onTimerFinished: { ... }).tag(index + 1)`. Aucun changement visuel à cette étape hors timer.

- [ ] **Step 2 : Intégrer le timer dans `StepPageView`**

- `@State private var timer: ExerciseTimerModel` initialisé avec `step.minutes` (dans `init`, `_timer = State(initialValue: ExerciseTimerModel(durationMinutes: step.minutes))`).
- Remplacer le `SportHeroIllustration` de la page par :
```swift
                TimerRingView(illustrationName: step.activityID,
                              fallbackEmoji: activity?.emoji ?? "🏃",
                              fraction: timer.fraction(at: now),
                              finished: timer.isFinished,
                              segments: step.segments)
                    .frame(maxWidth: .infinity)
```
- Envelopper le contenu de la page dans `TimelineView(.periodic(from: .now, by: 1)) { context in ... }` (le `now = context.date` alimente ring + contrôles). ⚠️ Ne PAS muter le modèle dans le body : la détection de fin passe par `.onChange(of: context.date)` (ou un `.task` par seconde) qui appelle `timer.syncNow()` ; quand il retourne `true` → haptique `.success` + `AudioServicesPlaySystemSound(1103)` (import AudioToolbox ; le son respecte le mode silencieux) + notifier le parent (voir pulse).
- `TimerControls(timer: timer, now: context.date)` sous le badge tempo.
- **Écran allumé** : `.onChange(of: timer.isRunning) { UIApplication.shared.isIdleTimerDisabled = $0 }` ET `.onDisappear { UIApplication.shared.isIdleTimerDisabled = false }`.
- ⚠️ **`TabView(.page)` garde les pages adjacentes VIVANTES : `onDisappear` ne se déclenche PAS au swipe.** D'où `isCurrent` : `.onChange(of: isCurrent) { _, current in if !current { timer.reset(); UIApplication.shared.isIdleTimerDisabled = false } }` — quitter la page abandonne le timer (spec §3.1) et relâche l'écran (piège #3). Sans ça : timer fantôme qui sonne depuis une page invisible + batterie vidée.
- **Son/haptique honnêtes** : AVANT d'appeler `syncNow()`, lire `let overrun = timer.overrun(at: context.date)` (API du modèle, testée) ; si `syncNow()` retourne `true`, ne jouer haptique+son QUE si `isCurrent` ET `overrun ?? .infinity < 2` — un timer expiré pendant que l'app était en arrière-plan affiche l'état fini sans sonner (spec §5).
- Garder l'ordre visuel : ring → nom/« Étape i/n » → puces → tempo → contrôles (ajuster l'espacement pour rester lisible ; le ScrollView absorbe le reste).

- [ ] **Step 3 : Pulse du CTA (spec §5, contrat exact)**

- `SessionPlayerSheet` gagne `@State private var pulsingCTA = false`, mis à `true` par la closure `onTimerFinished: { pulsingCTA = true }` (la page ne notifie que si `isCurrent`, pas de garde supplémentaire côté parent), remis à `false` à chaque changement de page (`.onChange(of: page)`).
- Appliquer sur les boutons `.next` et `.validate` UNIQUEMENT (jamais `.alreadyDone`) un modifier léger :
```swift
    .scaleEffect(pulse ? 1.03 : 1)
    .animation(reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)
```
avec `@Environment(\.accessibilityReduceMotion) private var reduceMotion`.

- [ ] **Step 4 : Build + tests + previews** — suite complète → 41 tests. Vérifier les previews « Étape » (le timer idle s'affiche), « Séance faite » (timer utilisable, pas de pulse possible).

- [ ] **Step 5 : Commit** — `git add -A && git commit -m "feat(app): timer d'étape dans le player (StepPageView, pulse du CTA, écran allumé)"`

---

## Task 5 : `ActivityLogSheet` — timer sur les activités libres

**Files:**
- Modify: `App/Views/Sport/ActivityLogSheet.swift`

- [ ] **Step 1 : Intégrer**

- `@State private var timer: ExerciseTimerModel?` (nil tant qu'aucune durée n'est choisie).
- Au changement de `selectedMinutes` (`.onChange`) : `timer = minutes.map { ExerciseTimerModel(durationMinutes: $0) }` (reset implicite) et `UIApplication.shared.isIdleTimerDisabled = false`.
- Quand `timer != nil` : remplacer la vignette 140pt d'en-tête par `TimerRingView(..., size: 180)` (fraction/finished du modèle, segments nil) + `TimerControls` juste en dessous, le tout dans le même `TimelineView` pattern que Task 4 (sync, haptique+son, idleTimer, onDisappear). Quand `timer == nil` (aucune durée choisie) : vignette 140pt actuelle inchangée.
- Pulse du CTA « C'est fait ! » quand `timer?.isFinished == true` (même modifier que Task 4, Reduce Motion respecté). La validation reste possible à tout moment.

- [ ] **Step 2 : Build + tests** — suite complète → 41 tests, TEST SUCCEEDED.

- [ ] **Step 3 : Commit** — `git add -A && git commit -m "feat(app): timer sur les activités libres (ActivityLogSheet)"`

---

## Task 6 : Version 1.5 + vérification finale

**Files:**
- Modify: `project.yml` (1.4/5 → 1.5/6)

- [ ] **Step 1 : Bump** — `CFBundleShortVersionString: "1.5"`, `CFBundleVersion: "6"`, puis `xcodegen generate`.
- [ ] **Step 2 : Suites complètes** — NivelCore **51** + app **46**, tout vert (comptes finaux après les fixes de reviews).
- [ ] **Step 3 : Vérification simulateur (recommandée)** — player wake_up : étape gainage (graduations ×3 visibles), Lancer → l'anneau progresse, Pause/Reprendre, fin → vert + « Bien joué ! » + pulse d'« Étape suivante » ; séance déjà faite → timer utilisable, pas de pulse ; ActivityLogSheet planche 4 min → anneau 180pt après choix de durée. Vérifier que l'écran ne se verrouille pas timer lancé, et se reverrouille après.
- [ ] **Step 4 : Commit** — `git add -A && git commit -m "chore: version 1.5 (build 6)"`

Fin de branche : options merge/PR présentées à Michaël (superpowers:finishing-a-development-branch).
