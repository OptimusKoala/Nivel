# Timing & rappels (v1.9) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rendre la fin du timer audible et lisible (deux chimes distincts), rendre les horaires de rappel modifiables, et permettre une durée sport libre ainsi que l'enregistrement du temps réellement écoulé.

**Architecture:** Toute la logique décidable part dans NivelCore en fonctions pures et testées (`TimerChime.decide`, `ReminderCatalog`/`ReminderSchedule`/`ReminderPlanner`, `DurationSelection`/`LoggedDuration`) ; l'app garde les effets de bord (AVFoundation, UNUserNotificationCenter, SwiftUI). Les deux chimes sont des assets générés par un script committé, sur le modèle de `scripts/gen-icons.swift`. Le bloc tick → son aujourd'hui dupliqué entre les deux surfaces sport devient un unique point d'appel.

**Tech Stack:** Swift 5.9, SwiftUI, SwiftData, AVFoundation, UserNotifications, XcodeGen, XCTest.

**Spec:** `docs/superpowers/specs/2026-08-02-timing-rappels-design.md`

---

## Commandes de référence

```sh
# Logique pure (macOS, rapide)
cd NivelCore && swift test

# Un seul test de la logique pure
cd NivelCore && swift test --filter LoggedDurationTests

# Tests d'app (simulateur)
xcodegen generate
xcodebuild -project Nivel.xcodeproj -scheme Nivel \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# Régénérer les chimes
swift scripts/gen-sounds.swift
```

Point de départ attendu : **74 tests NivelCore + 56 tests app** au vert sur `main`.

## Structure des fichiers

**Créés dans NivelCore** (aucun import UIKit, la cible compile sur macOS)

| Fichier | Responsabilité |
|---|---|
| `NivelCore/Sources/NivelCore/TimerFeedback.swift` | `TimerChime`, `TimerChime.Feedback`, `decide`, `forStep` |
| `NivelCore/Sources/NivelCore/Reminders.swift` | `ReminderDefinition`, `ReminderCatalog`, `ReminderSchedule`, `PlannedReminder`, `ReminderPlanner` |
| `NivelCore/Sources/NivelCore/SportDuration.swift` | `DurationSelection`, `CustomDuration`, `LoggedDuration` |
| `NivelCore/Tests/NivelCoreTests/TimerFeedbackTests.swift` | |
| `NivelCore/Tests/NivelCoreTests/RemindersTests.swift` | |
| `NivelCore/Tests/NivelCoreTests/SportDurationTests.swift` | |

**Créés dans l'app**

| Fichier | Responsabilité |
|---|---|
| `scripts/gen-sounds.swift` | Source unique des deux chimes |
| `App/Resources/Sounds/timer_step.caf` | Généré, committé |
| `App/Resources/Sounds/timer_done.caf` | Généré, committé |
| `App/Services/SoundPlayer.swift` | Session audio + lecture |
| `App/Services/SoundSettings.swift` | Préférence par appareil (`UserDefaults`) |
| `App/Views/Sport/TimerChime+App.swift` | Unique site d'appel du tick de fin |
| `NivelTests/SoundAssetsTests.swift` | Présence et durée des `.caf` |
| `NivelTests/SoundSettingsTests.swift` | Défaut et persistance |
| `NivelTests/ReminderSettingsTests.swift` | Migration du profil + écriture des horaires |

**Modifiés**

| Fichier | Changement |
|---|---|
| `App/Models/PersistentModels.swift` | +2 propriétés sur `UserProfile` |
| `App/Services/NotificationService.swift` | Branché sur `ReminderPlanner`, catalogue en dur supprimé |
| `App/Views/Settings/SettingsView.swift` | Carte « Son », lignes de rappel réglables |
| `App/Views/Sport/ActivityLogSheet.swift` | Puce « Autre », roue, ligne « noté », durée résolue |
| `App/Views/Sport/SessionPlayerSheet.swift` | Appel au tick partagé, chime selon l'étape |
| `project.yml` | Version 1.9 / build 10 sur les deux cibles |
| `README.md` | Commande `gen-sounds`, badges |

---

### Task 1 : `TimerChime.decide`, la décision pure

**Files:**
- Create: `NivelCore/Sources/NivelCore/TimerFeedback.swift`
- Test: `NivelCore/Tests/NivelCoreTests/TimerFeedbackTests.swift`

- [ ] **Step 1: Écrire les tests qui échouent**

Ces tests figent les deux règles d'honnêteté déjà en vigueur en v1.5 (dépassement, page courante) plus la nouvelle (réglage de son). Noter le cas `overrun: nil` : c'est un timer en pause dont l'échéance est passée, et il ne doit rien déclencher.

```swift
// NivelCore/Tests/NivelCoreTests/TimerFeedbackTests.swift
import XCTest
@testable import NivelCore

final class TimerFeedbackTests: XCTestCase {
    private func decide(overrun: TimeInterval? = 0.1, transitioned: Bool = true,
                        isCurrent: Bool = true, soundEnabled: Bool = true,
                        chime: TimerChime = .done) -> TimerChime.Feedback? {
        TimerChime.decide(overrun: overrun, transitioned: transitioned,
                          isCurrent: isCurrent, soundEnabled: soundEnabled, chime: chime)
    }

    func testFinDirecteJoueLeChime() {
        XCTAssertEqual(decide()?.chime, .done)
        XCTAssertEqual(decide(chime: .step)?.chime, .step)
    }

    func testSansTransitionRienNeSePasse() {
        XCTAssertNil(decide(transitioned: false))
    }

    func testPageNonCouranteRestteMuette() {
        XCTAssertNil(decide(isCurrent: false))
    }

    /// Fin vécue en différé (app en arrière-plan) : on ne célèbre pas après coup.
    func testDepassementAuDelaDeLaToleranceResteMuet() {
        XCTAssertNil(decide(overrun: 2))
        XCTAssertNil(decide(overrun: 30))
        XCTAssertNotNil(decide(overrun: 1.99))
    }

    /// Timer en pause dont l'échéance est passée : le modèle renvoie nil pour overrun.
    func testOverrunInconnuResteMuet() {
        XCTAssertNil(decide(overrun: nil))
    }

    /// Son coupé dans les Réglages : l'haptique reste, le chime disparaît.
    func testSonCoupeGardeLHaptique() {
        let feedback = decide(soundEnabled: false)
        XCTAssertNotNil(feedback)
        XCTAssertNil(feedback?.chime)
    }

    func testChimeDeLEtape() {
        XCTAssertEqual(TimerChime.forStep(number: 1, stepCount: 3), .step)
        XCTAssertEqual(TimerChime.forStep(number: 2, stepCount: 3), .step)
        XCTAssertEqual(TimerChime.forStep(number: 3, stepCount: 3), .done)
        XCTAssertEqual(TimerChime.forStep(number: 1, stepCount: 1), .done)
    }
}
```

- [ ] **Step 2: Lancer les tests, vérifier l'échec**

Run: `cd NivelCore && swift test --filter TimerFeedbackTests`
Expected: échec de compilation, « cannot find 'TimerChime' in scope ».

- [ ] **Step 3: Écrire l'implémentation minimale**

```swift
// NivelCore/Sources/NivelCore/TimerFeedback.swift
// Décision du retour de fin de timer (spec v1.9 §3.4) : PURE, sans UIKit ni
// AVFoundation, pour que les tests n'aient ni son à jouer ni réglage à écrire.

import Foundation

/// Signal sonore de fin d'un timer d'exercice.
public enum TimerChime: String, CaseIterable, Hashable, Sendable {
    /// Étape intermédiaire finie : passe à la suite.
    case step
    /// Dernière étape, ou activité libre : c'est terminé.
    case done
}

extension TimerChime {
    /// Ce qu'il faut jouer quand un timer vient de basculer sur `finished`.
    /// `chime` à nil = haptique seule (son coupé dans les Réglages).
    public struct Feedback: Equatable, Sendable {
        public let chime: TimerChime?
        public init(chime: TimerChime?) { self.chime = chime }
    }

    /// Seuil du « son honnête » (v1.5) : au delà, la fin a été vécue en différé,
    /// app en arrière-plan, et célébrer après coup serait faux.
    public static let overrunTolerance: TimeInterval = 2

    /// - Parameters:
    ///   - overrun: dépassement lu AVANT `syncNow` (nil si le timer ne tournait pas).
    ///   - transitioned: `syncNow` vient de basculer sur `finished`.
    ///   - isCurrent: la surface est bien affichée (pages voisines vivantes du TabView).
    public static func decide(overrun: TimeInterval?, transitioned: Bool,
                              isCurrent: Bool, soundEnabled: Bool,
                              chime: TimerChime) -> Feedback? {
        guard transitioned, isCurrent else { return nil }
        guard (overrun ?? .infinity) < overrunTolerance else { return nil }
        return Feedback(chime: soundEnabled ? chime : nil)
    }

    /// `done` seulement sur la dernière étape d'une séance.
    public static func forStep(number: Int, stepCount: Int) -> TimerChime {
        number >= stepCount ? .done : .step
    }
}
```

- [ ] **Step 4: Lancer les tests, vérifier le succès**

Run: `cd NivelCore && swift test --filter TimerFeedbackTests`
Expected: 7 tests au vert.

- [ ] **Step 5: Commit**

```bash
git add NivelCore/Sources/NivelCore/TimerFeedback.swift NivelCore/Tests/NivelCoreTests/TimerFeedbackTests.swift
git commit -m "feat(core): TimerChime.decide, décision pure du retour de fin de timer"
```

---

### Task 2 : Les deux chimes et leur script de génération

**Files:**
- Create: `scripts/gen-sounds.swift`
- Create: `App/Resources/Sounds/timer_step.caf` (généré)
- Create: `App/Resources/Sounds/timer_done.caf` (généré)
- Test: `NivelTests/SoundAssetsTests.swift`

- [ ] **Step 1: Écrire le script de génération**

```swift
// scripts/gen-sounds.swift
// Source UNIQUE des chimes du timer (spec v1.9 §3.1). Exécution : swift scripts/gen-sounds.swift
// Émet : App/Resources/Sounds/timer_step.caf (une note, ~0,36 s)
//        App/Resources/Sounds/timer_done.caf (do mi sol montant, ~0,90 s)
// Mono, 44,1 kHz, PCM 16 bits. Attaque de 12 ms et extinction complète : aucun clic.
// Idempotent : réécrit les deux fichiers à l'identique à chaque exécution.

import Foundation
import AVFoundation

let sampleRate = 44_100.0

struct Note {
    let frequency: Double   // Hz
    let start: Double       // s, depuis le début du fichier
    let duration: Double    // s
}

/// Timbre de petite cloche : fondamentale + octave discrète, enveloppe percussive.
/// L'attaque de 12 ms évite le clic de début, l'extinction exponentielle évite
/// celui de fin (le signal atteint zéro avant la fin du buffer).
func render(_ notes: [Note], totalDuration: Double) -> [Float] {
    var samples = [Float](repeating: 0, count: Int(totalDuration * sampleRate))
    for note in notes {
        let startIndex = Int(note.start * sampleRate)
        let count = Int(note.duration * sampleRate)
        for i in 0..<count {
            let index = startIndex + i
            guard index < samples.count else { break }
            let t = Double(i) / sampleRate
            let attack = min(1, t / 0.012)
            let decay = exp(-3.5 * t / note.duration)
            let wave = sin(2 * .pi * note.frequency * t)
                     + 0.28 * sin(4 * .pi * note.frequency * t)
            samples[index] += Float(attack * decay * wave * 0.34)
        }
    }
    // Les notes du chime « done » se recouvrent : garde-fou anti-saturation.
    let peak = samples.map { abs($0) }.max() ?? 0
    if peak > 0.92 {
        let gain = Float(0.92) / peak
        samples = samples.map { $0 * gain }
    }
    return samples
}

func write(_ samples: [Float], to url: URL) throws {
    try? FileManager.default.removeItem(at: url)   // AVAudioFile n'écrase pas proprement
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
    ]
    let file = try AVAudioFile(forWriting: url, settings: settings,
                               commonFormat: .pcmFormatFloat32, interleaved: false)
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                               channels: 1, interleaved: false)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                  frameCapacity: AVAudioFrameCount(samples.count))!
    buffer.frameLength = AVAudioFrameCount(samples.count)
    samples.withUnsafeBufferPointer { source in
        buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
    }
    try file.write(from: buffer)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outputDir = root.appendingPathComponent("App/Resources/Sounds")
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

// « Étape suivante » : une note claire et brève (la 5).
let step = render([Note(frequency: 880, start: 0, duration: 0.35)], totalDuration: 0.36)
try write(step, to: outputDir.appendingPathComponent("timer_step.caf"))

// « Terminé » : do mi sol montant, notes qui se recouvrent en accord.
let done = render([
    Note(frequency: 523.25, start: 0.00, duration: 0.55),
    Note(frequency: 659.25, start: 0.16, duration: 0.55),
    Note(frequency: 783.99, start: 0.32, duration: 0.55),
], totalDuration: 0.90)
try write(done, to: outputDir.appendingPathComponent("timer_done.caf"))

print("OK : timer_step.caf (0,36 s) et timer_done.caf (0,90 s) écrits dans App/Resources/Sounds")
```

- [ ] **Step 2: Générer les fichiers et les écouter**

Run: `swift scripts/gen-sounds.swift && ls -l App/Resources/Sounds/`
Expected: deux `.caf` non vides (environ 32 Ko et 80 Ko).

Run: `afplay App/Resources/Sounds/timer_step.caf; afplay App/Resources/Sounds/timer_done.caf`
Expected: une note brève, puis trois notes montantes. Aucun clic au début ni à la fin.

**Point de validation humaine :** ces deux sons se distinguent-ils à l'oreille ? Si non, ajuster les fréquences dans le script et régénérer avant de continuer.

- [ ] **Step 3: Régénérer le projet Xcode et écrire le test d'asset**

Run: `xcodegen generate`

Le test ne dépend volontairement d'aucun symbole de la Task 3 : il vérifie le **packaging**, pas le lecteur, et doit donc pouvoir tourner dès maintenant. C'est aussi lui qui attrapera un `.caf` qu'XcodeGen n'aurait pas mis dans la phase de copie des ressources.

```swift
// NivelTests/SoundAssetsTests.swift
import XCTest
import AVFoundation
@testable import Nivel

final class SoundAssetsTests: XCTestCase {
    /// Garde de packaging (même esprit que SportAssetsTests) : les deux chimes sont
    /// bien embarqués, non vides, et leur durée est épinglée pour attraper une
    /// régénération partie de travers.
    func testLesDeuxChimesSontEmbarques() throws {
        let expected: [String: Double] = ["timer_step": 0.36, "timer_done": 0.90]
        for (name, duration) in expected {
            let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "caf"),
                                    "asset manquant : \(name).caf")
            let file = try AVAudioFile(forReading: url)
            let actual = Double(file.length) / file.fileFormat.sampleRate
            XCTAssertEqual(actual, duration, accuracy: 0.02, "\(name).caf : durée inattendue")
            XCTAssertEqual(file.fileFormat.sampleRate, 44_100)
            XCTAssertEqual(file.fileFormat.channelCount, 1)
        }
    }
}
```

- [ ] **Step 4: Lancer le test, vérifier le succès**

Run: `xcodebuild -project Nivel.xcodeproj -scheme Nivel -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:NivelTests/SoundAssetsTests`
Expected: PASS.

Si l'assertion `XCTUnwrap` échoue, `.caf` n'est pas dans la phase de copie des ressources : ouvrir `Nivel.xcodeproj`, cible Nivel, Build Phases, Copy Bundle Resources, et déclarer le dossier dans `project.yml` avec `sources: [App, Shared, {path: App/Resources, buildPhase: resources}]` avant de relancer `xcodegen generate`.

- [ ] **Step 5: Commit**

```bash
git add scripts/gen-sounds.swift App/Resources/Sounds NivelTests/SoundAssetsTests.swift
git commit -m "feat: script de génération des chimes du timer + les deux .caf"
```

---

### Task 3 : `SoundSettings` et `SoundPlayer`

**Files:**
- Create: `App/Services/SoundSettings.swift`
- Create: `App/Services/SoundPlayer.swift`
- Test: `NivelTests/SoundSettingsTests.swift`

- [ ] **Step 1: Écrire le test qui échoue**

Calqué sur `ThemeStoreTests` : suite `UserDefaults` dédiée, jamais les vrais réglages.

```swift
// NivelTests/SoundSettingsTests.swift
import XCTest
@testable import Nivel

final class SoundSettingsTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "nivel.tests.sound.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// Le son est actif par défaut : c'est tout l'intérêt de la fonctionnalité.
    func testActifParDefaut() {
        XCTAssertTrue(SoundSettings(defaults: defaults).timerSoundEnabled)
    }

    func testLeChoixEstPersiste() {
        SoundSettings(defaults: defaults).timerSoundEnabled = false
        XCTAssertFalse(SoundSettings(defaults: defaults).timerSoundEnabled)
    }

    /// `false` persisté doit survivre : un `bool(forKey:)` naïf le confondrait
    /// avec l'absence de clé, mais ici les deux donnent des résultats différents.
    func testFauxPersisteNEstPasConfonduAvecLAbsence() {
        defaults.set(false, forKey: SoundSettings.defaultsKey)
        XCTAssertFalse(SoundSettings(defaults: defaults).timerSoundEnabled)
        defaults.removeObject(forKey: SoundSettings.defaultsKey)
        XCTAssertTrue(SoundSettings(defaults: defaults).timerSoundEnabled)
    }
}
```

- [ ] **Step 2: Lancer le test, vérifier l'échec**

Run: `xcodebuild -project Nivel.xcodeproj -scheme Nivel -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:NivelTests/SoundSettingsTests`
Expected: échec de compilation, « cannot find 'SoundSettings' in scope ».

- [ ] **Step 3: Écrire les deux services**

```swift
// App/Services/SoundSettings.swift
// Préférence de son du timer, PAR APPAREIL (spec v1.9 §3.5) : UserDefaults comme le
// thème, pas SwiftData. Aucune migration, aucun impact sur l'instantané du widget.

import Foundation
import Observation

@Observable
final class SoundSettings {
    static let shared = SoundSettings()
    static let defaultsKey = "nivel.timerSound"

    var timerSoundEnabled: Bool {
        didSet { defaults.set(timerSoundEnabled, forKey: Self.defaultsKey) }
    }

    private let defaults: UserDefaults

    /// `defaults` injectable pour les tests (suite dédiée, pas de pollution des vrais
    /// réglages). `object(forKey:)` et non `bool(forKey:)` : il faut distinguer
    /// « jamais réglé » (donc actif) de « réglé à false ».
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.timerSoundEnabled = defaults.object(forKey: Self.defaultsKey) as? Bool ?? true
    }
}
```

```swift
// App/Services/SoundPlayer.swift
// Lecture des chimes du timer (spec v1.9 §3.2).
// Catégorie `.playback` : le son passe MALGRÉ l'interrupteur silencieux, ce qui est
// tout l'intérêt d'un timer qu'on pose par terre. `.mixWithOthers` : la musique en
// cours n'est ni coupée ni baissée. La session est activée une fois et jamais
// désactivée (désactiver à chaque son produit des micro-coupures chez les autres apps).

import Foundation
import AVFoundation
import NivelCore

@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()

    private var players: [TimerChime: AVAudioPlayer] = [:]
    private var sessionConfigured = false

    static func fileName(for chime: TimerChime) -> String {
        switch chime {
        case .step: "timer_step"
        case .done: "timer_done"
        }
    }

    func play(_ chime: TimerChime) {
        configureSessionIfNeeded()
        guard let player = player(for: chime) else { return }
        player.currentTime = 0
        player.play()
    }

    private func configureSessionIfNeeded() {
        guard !sessionConfigured else { return }
        sessionConfigured = true
        // Erreurs avalées : un son qui ne part pas ne casse jamais une séance.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    /// Construit à la demande puis conservé : `prepareToPlay` supprime la latence
    /// du premier déclenchement, qui tomberait pile sur la fin du timer.
    private func player(for chime: TimerChime) -> AVAudioPlayer? {
        if let existing = players[chime] { return existing }
        guard let url = Bundle.main.url(forResource: Self.fileName(for: chime),
                                        withExtension: "caf"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.prepareToPlay()
        players[chime] = player
        return player
    }
}
```

- [ ] **Step 4: Lancer les tests, vérifier le succès**

Run: `xcodebuild -project Nivel.xcodeproj -scheme Nivel -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`
Expected: toute la suite d'app au vert, les 3 nouveaux tests de réglages compris.

- [ ] **Step 5: Commit**

```bash
git add App/Services/SoundSettings.swift App/Services/SoundPlayer.swift NivelTests/SoundSettingsTests.swift
git commit -m "feat: SoundSettings (par appareil) et SoundPlayer (playback + mixWithOthers)"
```

---

### Task 4 : Un seul site d'appel du tick, et les deux chimes branchés

Cette task paie la dette notée en v1.5 : le bloc tick → son était dupliqué à l'identique dans les deux surfaces.

**Files:**
- Create: `App/Views/Sport/TimerChime+App.swift`
- Modify: `App/Views/Sport/ActivityLogSheet.swift:102-110`
- Modify: `App/Views/Sport/SessionPlayerSheet.swift:265-277`

- [ ] **Step 1: Écrire le helper**

```swift
// App/Views/Sport/TimerChime+App.swift
// Unique site d'appel du tick de fin de timer (spec v1.9 §3.4). Avant la v1.9 ce bloc
// était copié dans ActivityLogSheet et dans StepPageView, avec l'ordre « overrun avant
// syncNow » à retenir des deux côtés.

import Foundation
import UIKit
import NivelCore

extension TimerChime {
    /// Fait avancer le timer d'un tick et joue le retour de fin s'il y a lieu.
    /// L'ordre est imposé par le modèle : lire `overrun` AVANT `syncNow`, car une
    /// fois `.finished` il retourne toujours nil.
    /// - Returns: true si le timer vient de basculer sur `finished`.
    @MainActor
    @discardableResult
    static func onTick(timer: ExerciseTimerModel, at date: Date,
                       isCurrent: Bool, chime: TimerChime) {
        let overrun = timer.overrun(at: date)
        guard timer.syncNow(at: date) else { return false }
        guard let feedback = decide(overrun: overrun, transitioned: true,
                                    isCurrent: isCurrent,
                                    soundEnabled: SoundSettings.shared.timerSoundEnabled,
                                    chime: chime) else { return true }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if let chime = feedback.chime { SoundPlayer.shared.play(chime) }
        return true
    }
}
```

- [ ] **Step 2: Brancher l'activité libre**

Dans `App/Views/Sport/ActivityLogSheet.swift`, remplacer le bloc `.onChange(of: context.date)` (lignes 102-110) par :

```swift
                .onChange(of: context.date) { _, date in
                    // Activité libre : pas de notion de page courante, et le timer va
                    // toujours jusqu'au bout de l'activité, donc chime « terminé ».
                    TimerChime.onTick(timer: timer, at: date, isCurrent: true, chime: .done)
                }
```

Supprimer l'import `AudioToolbox` devenu inutile en tête de fichier.

- [ ] **Step 3: Brancher le player**

Dans `App/Views/Sport/SessionPlayerSheet.swift`, remplacer le bloc `.onChange(of: context.date)` de `StepPageView` (lignes 265-277) par :

```swift
            .onChange(of: context.date) { _, date in
                TimerChime.onTick(timer: timer, at: date, isCurrent: isCurrent,
                                  chime: .forStep(number: number, stepCount: stepCount))
            }
```

Supprimer l'import `AudioToolbox` en tête de fichier.

- [ ] **Step 4: Compiler et lancer toute la suite d'app**

Run: `xcodebuild -project Nivel.xcodeproj -scheme Nivel -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`
Expected: tout au vert, aucune régression sur `SessionPlayerTests` ni `ExerciseTimerModelTests`.

Run: `grep -rn "AudioServicesPlaySystemSound" App/`
Expected: aucun résultat. L'ancien son système a disparu des deux surfaces.

- [ ] **Step 5: Commit**

```bash
git add App/Views/Sport/
git commit -m "refactor(sport): un seul site d'appel du tick de fin, deux chimes distincts"
```

---

### Task 5 : La carte « Son » dans les Réglages

**Files:**
- Modify: `App/Views/Settings/SettingsView.swift`

- [ ] **Step 1: Ajouter la section**

Dans le `VStack` du corps, insérer `soundSection` **entre `goalsSection` et `remindersSection`** :

```swift
                    profileSection
                    goalsSection
                    soundSection
                    remindersSection
```

Puis, après `goalsSection` dans le fichier :

```swift
    // MARK: - Son

    /// Préférence PAR APPAREIL (comme le thème) : elle vit dans UserDefaults, pas
    /// dans SwiftData, donc aucun `save()` ici.
    private var soundSection: some View {
        section("Son") {
            Toggle(isOn: Binding(
                get: { SoundSettings.shared.timerSoundEnabled },
                set: { SoundSettings.shared.timerSoundEnabled = $0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Son du timer").font(.subheadline.weight(.semibold))
                    Text("sonne même en mode silencieux")
                        .font(.caption).foregroundStyle(Theme.subtext)
                }
            }
        }
    }
```

- [ ] **Step 2: Vérifier à l'œil dans la preview Xcode**

Ouvrir la preview de `SettingsView`, vérifier que la carte « Son » apparaît entre Objectifs et Rappels, que le sous-titre tient sur une ligne, et basculer l'interrupteur.

- [ ] **Step 3: Lancer la suite d'app**

Run: `xcodebuild -project Nivel.xcodeproj -scheme Nivel -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`
Expected: tout au vert.

- [ ] **Step 4: Commit**

```bash
git add App/Views/Settings/SettingsView.swift
git commit -m "feat(réglages): interrupteur « Son du timer »"
```

---

### Task 6 : Le catalogue de rappels et le formatage français

**Files:**
- Create: `NivelCore/Sources/NivelCore/Reminders.swift`
- Test: `NivelCore/Tests/NivelCoreTests/RemindersTests.swift`

- [ ] **Step 1: Écrire les tests qui échouent**

Le premier test est le plus important du lot : il garantit qu'aucun téléphone déjà installé ne voit ses horaires bouger.

```swift
// NivelCore/Tests/NivelCoreTests/RemindersTests.swift
import XCTest
@testable import NivelCore

final class RemindersTests: XCTestCase {

    /// Valeurs ÉPINGLÉES sur celles de la v1 : une modification ici déplacerait les
    /// rappels des installations existantes sans que personne ne l'ait demandé.
    func testLesQuatreDefautsSontCeuxDeLaV1() {
        let byID = Dictionary(uniqueKeysWithValues: ReminderCatalog.all.map { ($0.id, $0) })
        XCTAssertEqual(ReminderCatalog.all.count, 4)

        XCTAssertEqual(byID["lunch"]?.defaultHour, 12)
        XCTAssertEqual(byID["lunch"]?.defaultMinute, 30)
        XCTAssertNil(byID["lunch"]?.defaultWeekday)
        XCTAssertEqual(byID["lunch"]?.context, .midday)

        XCTAssertEqual(byID["dinner"]?.defaultHour, 20)
        XCTAssertEqual(byID["dinner"]?.defaultMinute, 0)
        XCTAssertEqual(byID["dinner"]?.context, .evening)

        XCTAssertEqual(byID["weigh"]?.defaultHour, 9)
        XCTAssertEqual(byID["weigh"]?.defaultWeekday, 7)   // samedi
        XCTAssertEqual(byID["weigh"]?.context, .weighReminder)

        XCTAssertEqual(byID["steps"]?.defaultHour, 18)
        XCTAssertEqual(byID["steps"]?.context, .stepsEncouragement)
    }

    /// La pesée est le seul rappel hebdomadaire, donc le seul dont le jour se choisit.
    func testSeuleLaPeseeALeJourModifiable() {
        for definition in ReminderCatalog.all {
            XCTAssertEqual(definition.isWeekdayEditable, definition.id == "weigh",
                           "jour modifiable inattendu sur \(definition.id)")
        }
    }

    func testLibelleFrancais() {
        XCTAssertEqual(ReminderSchedule.frLabel(hour: 12, minute: 30, weekday: nil),
                       "tous les jours à 12 h 30")
        XCTAssertEqual(ReminderSchedule.frLabel(hour: 20, minute: 0, weekday: nil),
                       "tous les jours à 20 h")
        XCTAssertEqual(ReminderSchedule.frLabel(hour: 8, minute: 5, weekday: nil),
                       "tous les jours à 8 h 05")
        XCTAssertEqual(ReminderSchedule.frLabel(hour: 0, minute: 0, weekday: nil),
                       "tous les jours à 0 h")
        XCTAssertEqual(ReminderSchedule.frLabel(hour: 9, minute: 0, weekday: 7),
                       "le samedi à 9 h")
        XCTAssertEqual(ReminderSchedule.frLabel(hour: 9, minute: 0, weekday: 1),
                       "le dimanche à 9 h")
    }

    func testLesSeptJours() {
        let expected = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]
        for (index, name) in expected.enumerated() {
            XCTAssertEqual(ReminderSchedule.frLabel(hour: 7, minute: 0, weekday: index + 1),
                           "le \(name) à 7 h")
            XCTAssertFalse(ReminderSchedule.frShortWeekday(index + 1).isEmpty)
        }
    }

    func testFrequence() {
        XCTAssertEqual(ReminderSchedule.frFrequency(weekday: nil), "tous les jours")
        XCTAssertEqual(ReminderSchedule.frFrequency(weekday: 7), "chaque semaine")
    }

    /// Aucun tiret cadratin dans les textes destinés à l'écran (règle v1.2).
    func testAucunTiretCadratin() {
        for definition in ReminderCatalog.all {
            XCTAssertFalse(definition.title.contains("—"))
        }
        XCTAssertFalse(ReminderSchedule.frLabel(hour: 9, minute: 0, weekday: 7).contains("—"))
    }
}
```

- [ ] **Step 2: Lancer les tests, vérifier l'échec**

Run: `cd NivelCore && swift test --filter RemindersTests`
Expected: échec de compilation, « cannot find 'ReminderCatalog' in scope ».

- [ ] **Step 3: Écrire l'implémentation**

```swift
// NivelCore/Sources/NivelCore/Reminders.swift
// Catalogue et formatage des rappels (spec v1.9 §4). Remplace les quatre cas en dur
// de NotificationService : le lot C (programme de Marion) ajoutera une entrée ici,
// et rien d'autre.

import Foundation

public struct ReminderDefinition: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let defaultHour: Int
    public let defaultMinute: Int
    /// Convention `Calendar` : 1 = dimanche … 7 = samedi. nil = tous les jours.
    public let defaultWeekday: Int?
    /// Seuls les rappels hebdomadaires laissent choisir leur jour.
    public let isWeekdayEditable: Bool
    public let context: MessageContext

    public init(id: String, title: String, defaultHour: Int, defaultMinute: Int,
                defaultWeekday: Int?, isWeekdayEditable: Bool, context: MessageContext) {
        self.id = id
        self.title = title
        self.defaultHour = defaultHour
        self.defaultMinute = defaultMinute
        self.defaultWeekday = defaultWeekday
        self.isWeekdayEditable = isWeekdayEditable
        self.context = context
    }

    public var defaultMinutesFromMidnight: Int { defaultHour * 60 + defaultMinute }
}

public enum ReminderCatalog {
    public static let all: [ReminderDefinition] = [
        ReminderDefinition(id: "lunch", title: "Déjeuner", defaultHour: 12, defaultMinute: 30,
                           defaultWeekday: nil, isWeekdayEditable: false, context: .midday),
        ReminderDefinition(id: "dinner", title: "Dîner", defaultHour: 20, defaultMinute: 0,
                           defaultWeekday: nil, isWeekdayEditable: false, context: .evening),
        ReminderDefinition(id: "weigh", title: "Pesée", defaultHour: 9, defaultMinute: 0,
                           defaultWeekday: 7, isWeekdayEditable: true, context: .weighReminder),
        ReminderDefinition(id: "steps", title: "Pas", defaultHour: 18, defaultMinute: 0,
                           defaultWeekday: nil, isWeekdayEditable: false, context: .stepsEncouragement),
    ]

    public static func definition(id: String) -> ReminderDefinition? {
        all.first { $0.id == id }
    }
}

public enum ReminderSchedule {
    public static let minutesRange = 0...1439
    public static let weekdayRange = 1...7

    private static let longNames = ["dimanche", "lundi", "mardi", "mercredi",
                                    "jeudi", "vendredi", "samedi"]
    private static let shortNames = ["dim.", "lun.", "mar.", "mer.",
                                     "jeu.", "ven.", "sam."]

    /// « tous les jours à 12 h 30 », « le samedi à 9 h ». Minutes omises à zéro,
    /// sur deux chiffres sinon. Aucun tiret cadratin (règle v1.2).
    public static func frLabel(hour: Int, minute: Int, weekday: Int?) -> String {
        let time = minute == 0 ? "\(hour) h" : String(format: "%d h %02d", hour, minute)
        guard let weekday, weekdayRange.contains(weekday) else {
            return "tous les jours à \(time)"
        }
        return "le \(longNames[weekday - 1]) à \(time)"
    }

    /// Fréquence seule, pour le sous-titre de la ligne de réglage.
    public static func frFrequency(weekday: Int?) -> String {
        weekday == nil ? "tous les jours" : "chaque semaine"
    }

    /// Libellé court du menu de sélection du jour.
    public static func frShortWeekday(_ weekday: Int) -> String {
        guard weekdayRange.contains(weekday) else { return "" }
        return shortNames[weekday - 1]
    }
}
```

- [ ] **Step 4: Lancer les tests, vérifier le succès**

Run: `cd NivelCore && swift test --filter RemindersTests`
Expected: 6 tests au vert.

- [ ] **Step 5: Commit**

```bash
git add NivelCore/Sources/NivelCore/Reminders.swift NivelCore/Tests/NivelCoreTests/RemindersTests.swift
git commit -m "feat(core): catalogue de rappels et formatage français des horaires"
```

---

### Task 7 : `ReminderPlanner`

**Files:**
- Modify: `NivelCore/Sources/NivelCore/Reminders.swift`
- Modify: `NivelCore/Tests/NivelCoreTests/RemindersTests.swift`

- [ ] **Step 1: Écrire les tests qui échouent**

Ajouter dans `RemindersTests` :

```swift
    // MARK: - Planificateur

    private let allOn = ["lunch": true, "dinner": true, "weigh": true, "steps": true]

    private func planned(_ enabled: [String: Bool], times: [String: Int] = [:],
                         weekdays: [String: Int] = [:]) -> [PlannedReminder] {
        ReminderPlanner.planned(enabled: enabled, times: times, weekdays: weekdays)
    }

    func testSansSurchargeOnRetrouveLesDefauts() {
        let result = planned(allOn)
        XCTAssertEqual(result.count, 4)
        let lunch = result.first { $0.id == "lunch" }
        XCTAssertEqual(lunch?.hour, 12)
        XCTAssertEqual(lunch?.minute, 30)
        XCTAssertNil(lunch?.weekday)
        XCTAssertEqual(result.first { $0.id == "weigh" }?.weekday, 7)
    }

    func testRappelEteintAbsentDuResultat() {
        let result = planned(["lunch": true, "dinner": false, "weigh": true])
        XCTAssertEqual(Set(result.map(\.id)), ["lunch", "weigh"])
    }

    func testSurchargeAppliquee() {
        let result = planned(allOn, times: ["lunch": 13 * 60 + 15], weekdays: ["weigh": 1])
        XCTAssertEqual(result.first { $0.id == "lunch" }?.hour, 13)
        XCTAssertEqual(result.first { $0.id == "lunch" }?.minute, 15)
        XCTAssertEqual(result.first { $0.id == "weigh" }?.weekday, 1)
    }

    /// Un réglage corrompu ne doit JAMAIS faire disparaître un rappel actif :
    /// on retombe sur le défaut du catalogue, on ne saute pas l'entrée.
    func testValeursAberrantesRetombentSurLeDefaut() {
        for badMinutes in [-1, 1440, 99_999] {
            let result = planned(allOn, times: ["lunch": badMinutes])
            XCTAssertEqual(result.first { $0.id == "lunch" }?.hour, 12)
            XCTAssertEqual(result.first { $0.id == "lunch" }?.minute, 30)
        }
        for badWeekday in [0, 8, -3] {
            let result = planned(allOn, weekdays: ["weigh": badWeekday])
            XCTAssertEqual(result.first { $0.id == "weigh" }?.weekday, 7)
        }
    }

    /// Poser un jour sur un rappel quotidien ne doit pas le rendre hebdomadaire.
    func testJourIgnoreSurUnRappelNonModifiable() {
        let result = planned(allOn, weekdays: ["lunch": 3])
        XCTAssertNil(result.first { $0.id == "lunch" }?.weekday)
    }

    /// Résidu d'une version antérieure ou d'un lot futur non installé.
    func testIdentifiantInconnuIgnore() {
        let result = planned(allOn.merging(["ghost": true]) { a, _ in a },
                             times: ["ghost": 60])
        XCTAssertEqual(result.count, 4)
        XCTAssertNil(result.first { $0.id == "ghost" })
    }

    func testMinuitEtDerniereMinuteSontValides() {
        XCTAssertEqual(planned(allOn, times: ["lunch": 0]).first { $0.id == "lunch" }?.hour, 0)
        let last = planned(allOn, times: ["lunch": 1439]).first { $0.id == "lunch" }
        XCTAssertEqual(last?.hour, 23)
        XCTAssertEqual(last?.minute, 59)
    }
```

- [ ] **Step 2: Lancer les tests, vérifier l'échec**

Run: `cd NivelCore && swift test --filter RemindersTests`
Expected: échec de compilation, « cannot find 'ReminderPlanner' in scope ».

- [ ] **Step 3: Écrire l'implémentation**

Ajouter à la fin de `Reminders.swift` :

```swift
/// Ce qu'il faut réellement planifier, une fois les réglages du profil appliqués.
public struct PlannedReminder: Equatable, Sendable {
    public let id: String
    public let hour: Int
    public let minute: Int
    public let weekday: Int?
    public let context: MessageContext
}

public enum ReminderPlanner {
    /// Itère sur le CATALOGUE, pas sur les dictionnaires : les identifiants inconnus
    /// y sont donc naturellement ignorés. Toute valeur aberrante retombe sur le défaut
    /// du catalogue, jamais sur une disparition du rappel.
    public static func planned(enabled: [String: Bool],
                               times: [String: Int],
                               weekdays: [String: Int]) -> [PlannedReminder] {
        ReminderCatalog.all.compactMap { definition in
            guard enabled[definition.id] == true else { return nil }

            let minutes = times[definition.id]
                .flatMap { ReminderSchedule.minutesRange.contains($0) ? $0 : nil }
                ?? definition.defaultMinutesFromMidnight

            let weekday = (definition.isWeekdayEditable ? weekdays[definition.id] : nil)
                .flatMap { ReminderSchedule.weekdayRange.contains($0) ? $0 : nil }
                ?? definition.defaultWeekday

            return PlannedReminder(id: definition.id,
                                   hour: minutes / 60, minute: minutes % 60,
                                   weekday: weekday, context: definition.context)
        }
    }
}
```

- [ ] **Step 4: Lancer les tests, vérifier le succès**

Run: `cd NivelCore && swift test`
Expected: toute la suite NivelCore au vert (74 tests d'origine + ceux des Tasks 1, 6 et 7).

- [ ] **Step 5: Commit**

```bash
git add NivelCore/
git commit -m "feat(core): ReminderPlanner, calcul pur de ce qu'il faut planifier"
```

---

### Task 8 : Les horaires dans le profil, et `NotificationService` branché dessus

**Files:**
- Modify: `App/Models/PersistentModels.swift:7-55`
- Modify: `App/Services/NotificationService.swift`
- Test: `NivelTests/ReminderSettingsTests.swift`

- [ ] **Step 1: Écrire le test qui échoue**

```swift
// NivelTests/ReminderSettingsTests.swift
import XCTest
import SwiftData
import NivelCore
@testable import Nivel

@MainActor
final class ReminderSettingsTests: XCTestCase {

    private func makeProfile() throws -> (ModelContainer, UserProfile) {
        let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                             DayLog.self, GamificationState.self, ActivityEntry.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let profile = UserProfile(
            name: "Marion", sex: .female,
            birthDate: Date(timeIntervalSince1970: 0),
            heightCm: 165, initialWeightKg: 70, activity: .light,
            dailyCalorieTarget: 1700,
            remindersEnabled: ["lunch": true, "dinner": true, "weigh": true, "steps": true]
        )
        container.mainContext.insert(profile)
        return (container, profile)
    }

    /// Un profil créé sans horaires (donc tout profil déjà installé) doit produire
    /// exactement la planification de la v1.
    func testProfilSansHorairesGardeLesDefauts() throws {
        let (_, profile) = try makeProfile()
        XCTAssertTrue(profile.reminderTimes.isEmpty)
        XCTAssertTrue(profile.reminderWeekdays.isEmpty)

        let planned = ReminderPlanner.planned(enabled: profile.remindersEnabled,
                                              times: profile.reminderTimes,
                                              weekdays: profile.reminderWeekdays)
        let lunch = planned.first { $0.id == "lunch" }
        XCTAssertEqual(lunch?.hour, 12)
        XCTAssertEqual(lunch?.minute, 30)
        XCTAssertEqual(planned.first { $0.id == "weigh" }?.weekday, 7)
    }

    func testHoraireModifiePersisteEtEstPlanifie() throws {
        let (container, profile) = try makeProfile()
        profile.reminderTimes = ["dinner": 19 * 60 + 45]
        profile.reminderWeekdays = ["weigh": 1]
        try container.mainContext.save()

        let reloaded = try XCTUnwrap(
            try container.mainContext.fetch(FetchDescriptor<UserProfile>()).first
        )
        let planned = ReminderPlanner.planned(enabled: reloaded.remindersEnabled,
                                              times: reloaded.reminderTimes,
                                              weekdays: reloaded.reminderWeekdays)
        let dinner = planned.first { $0.id == "dinner" }
        XCTAssertEqual(dinner?.hour, 19)
        XCTAssertEqual(dinner?.minute, 45)
        XCTAssertEqual(planned.first { $0.id == "weigh" }?.weekday, 1)
    }

    /// Le sous-titre affiché doit suivre l'horaire réel, pas un texte figé.
    func testSousTitreSuitLHoraire() throws {
        let (_, profile) = try makeProfile()
        profile.reminderTimes = ["dinner": 19 * 60 + 45]
        let planned = ReminderPlanner.planned(enabled: profile.remindersEnabled,
                                              times: profile.reminderTimes,
                                              weekdays: profile.reminderWeekdays)
        let dinner = try XCTUnwrap(planned.first { $0.id == "dinner" })
        XCTAssertEqual(
            ReminderSchedule.frLabel(hour: dinner.hour, minute: dinner.minute,
                                     weekday: dinner.weekday),
            "tous les jours à 19 h 45"
        )
    }
}
```

- [ ] **Step 2: Lancer le test, vérifier l'échec**

Run: `xcodebuild -project Nivel.xcodeproj -scheme Nivel -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:NivelTests/ReminderSettingsTests`
Expected: échec de compilation, « value of type 'UserProfile' has no member 'reminderTimes' ».

- [ ] **Step 3: Ajouter les deux propriétés au modèle**

Dans `App/Models/PersistentModels.swift`, après `remindersEnabled` :

```swift
    var remindersEnabled: [String: Bool] // id de rappel → actif
    // Défauts au niveau de la DÉCLARATION : requis pour la migration légère SwiftData
    // des stores existants (le défaut de l'init ne suffit pas — leçon de
    // completedThisWeekQuestIDs en v1). Clé absente = valeur du ReminderCatalog.
    var reminderTimes: [String: Int] = [:]      // id → minutes depuis minuit (0...1439)
    var reminderWeekdays: [String: Int] = [:]   // id → jour (1 = dimanche … 7 = samedi)
```

Et dans l'`init`, ajouter les deux paramètres après `remindersEnabled` :

```swift
        remindersEnabled: [String: Bool] = [:],
        reminderTimes: [String: Int] = [:],
        reminderWeekdays: [String: Int] = [:],
```

avec les affectations correspondantes :

```swift
        self.reminderTimes = reminderTimes
        self.reminderWeekdays = reminderWeekdays
```

- [ ] **Step 4: Brancher `NotificationService` sur le planificateur**

Remplacer intégralement le contenu de `App/Services/NotificationService.swift` par :

```swift
// App/Services/NotificationService.swift
// Rappels locaux bienveillants (spec v1 §10, horaires réglables spec v1.9 §4.3) :
// le CALCUL de ce qu'il faut planifier vit dans NivelCore (ReminderPlanner, pur et
// testé) ; ce fichier ne garde que le dialogue avec UNUserNotificationCenter.
// Re-planifié à chaque passage au premier plan pour renouveler les textes.

import Foundation
import UserNotifications
import NivelCore

@MainActor
enum NotificationService {
    /// Sérialisation des re-planifications : chaque appel incrémente la génération ;
    /// une invocation devenue obsolète après son await (roue d'heure que l'on fait
    /// tourner, retour au premier plan et toggle quasi simultanés) est abandonnée.
    /// C'est ce qui absorbe la rafale de changements d'un DatePicker.
    private static var generation = 0

    /// Supprime toutes les demandes en attente puis re-planifie chaque rappel ACTIF
    /// avec un texte frais de la banque (tirage aléatoire, varie à chaque appel).
    /// Si les notifications sont refusées : ne fait rien (jamais de crash).
    ///
    /// L'instantané des champs du profil (@Model non-Sendable) est capturé ICI,
    /// avant tout passage asynchrone, et le profil n'est plus jamais relu ensuite.
    static func reschedule(for profile: UserProfile) {
        let name = profile.name
        let planned = ReminderPlanner.planned(enabled: profile.remindersEnabled,
                                              times: profile.reminderTimes,
                                              weekdays: profile.reminderWeekdays)
        generation += 1
        let gen = generation
        Task { await perform(name: name, planned: planned, generation: gen) }
    }

    private static func perform(name: String, planned: [PlannedReminder],
                                generation gen: Int) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        // Un appel plus récent est passé pendant l'await → cet instantané est périmé.
        guard gen == generation else { return }
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }

        // Banque chargée une fois par re-planification (un tirage par rappel).
        let bank = try? MessageBank.load()

        // removeAll + adds SYNCHRONES (aucun await entre les deux) : le bloc est
        // atomique du point de vue du main actor, aucun entrelacement possible.
        center.removeAllPendingNotificationRequests()
        for reminder in planned {
            let content = UNMutableNotificationContent()
            content.title = "Nivelito 🧡"
            content.body = bank?.pick(
                context: reminder.context,
                excluding: nil,
                name: name,
                value: nil
            ).text ?? "Petit coucou de Nivelito 🧡"
            content.sound = .default

            var components = DateComponents()
            components.hour = reminder.hour
            components.minute = reminder.minute
            components.weekday = reminder.weekday

            let request = UNNotificationRequest(
                identifier: reminder.id,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            )
            // Variante à completion (et non l'overload async) : l'ajout reste
            // synchrone → pas de point de suspension dans le bloc removeAll + adds.
            center.add(request, withCompletionHandler: nil)
        }
    }
}
```

- [ ] **Step 5: Chercher les usages devenus caducs**

Run: `grep -rn "NotificationService" App NivelTests`
Expected: seuls `App/RootView.swift:148` et `App/Views/Onboarding/OnboardingFlow.swift:177` appellent `reschedule(for:)`, dont la signature n'a pas changé. Aucune référence à l'ancien `NotificationService.reminders`.

- [ ] **Step 6: Lancer toute la suite d'app**

Run: `xcodebuild -project Nivel.xcodeproj -scheme Nivel -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`
Expected: tout au vert, y compris les 3 nouveaux tests.

- [ ] **Step 7: Commit**

```bash
git add App/Models/PersistentModels.swift App/Services/NotificationService.swift NivelTests/ReminderSettingsTests.swift
git commit -m "feat: horaires de rappel dans le profil, NotificationService sur ReminderPlanner"
```

---

### Task 8 bis : Scinder `SettingsView` avant qu'il ne grossisse

Ajoutée après la revue qualité de la Task 5. `SettingsView.swift` fait 481 lignes et porte sept sections ; la Task 9 remplace 37 lignes de rappels par environ 130. Scinder maintenant fait atterrir ce gros diff dans un fichier dédié au lieu d'empiler dans un fichier déjà large.

**Files:**
- Modify: `App/Views/Settings/SettingsView.swift`
- Create: `App/Views/Settings/SettingsView+Reminders.swift`
- Create: `App/Views/Settings/SettingsView+DevicePreferences.swift`

- [ ] **Step 1: Déplacer, sans rien réécrire**

Vers `SettingsView+Reminders.swift` : `remindersSection`, `reminderToggle`, `reminderBinding`. C'est exactement ce que la Task 9 réécrit.

Vers `SettingsView+DevicePreferences.swift` : `themeSection`, `soundSection` et la struct `ThemeSwatchCard`. Ces deux sections partagent la même nature (UserDefaults, par appareil, pas de `save()`), et `ThemeSwatchCard` ne dépend déjà de rien d'interne à `SettingsContent`.

Restent dans `SettingsView.swift` : `SettingsView`, l'état de `SettingsContent`, `profileSection`, `goalsSection`, `healthSection`, `aboutSection`, les briques `section`/`row`/`divider`, les actions kcal, `save()`, la preview.

- [ ] **Step 2: Ouvrir la visibilité, au minimum nécessaire**

`private struct SettingsContent` et ses membres partagés (`profile`, `modelContext`, `game`, `section`, `row`, `divider`, `save()`) doivent perdre leur `private` : en Swift, `private` au niveau d'un fichier est visible dans ce seul fichier, et les extensions vivent désormais ailleurs. Passer en `internal` implicite, sans plus. Ne PAS rendre `public` : la cible est une app, pas une bibliothèque.

- [ ] **Step 3: Vérifier que rien n'a changé**

C'est un déplacement pur. Aucune ligne de logique ne doit être modifiée au passage.

Run: `xcodegen generate && xcodebuild -project Nivel.xcodeproj -scheme Nivel -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`
Expected: 61 tests au vert, inchangés.

Vérifier aussi que la preview de `SettingsView` s'ouvre toujours et affiche les sept sections dans le même ordre.

- [ ] **Step 4: Commit**

```bash
git add App/Views/Settings/ Nivel.xcodeproj/project.pbxproj
git commit -m "refactor(réglages): scinder SettingsView en rappels et préférences d'appareil"
```

---

### Task 9 : Les lignes de rappel réglables dans les Réglages

**Files:**
- Modify: `App/Views/Settings/SettingsView.swift:210-246`

- [ ] **Step 1: Remplacer la section Rappels**

Remplacer `remindersSection`, `reminderToggle` et `reminderBinding` par :

```swift
    // MARK: - Rappels

    /// Jour de référence pour les bindings d'heure : le 1er janvier 2000, qui n'a
    /// aucun changement d'heure. Construire la date par composantes (et non en
    /// ajoutant des secondes à minuit) évite le décalage des jours de bascule.
    private static let referenceDayComponents = DateComponents(year: 2000, month: 1, day: 1)

    private var remindersSection: some View {
        section("Rappels") {
            ForEach(Array(ReminderCatalog.all.enumerated()), id: \.element.id) { index, definition in
                if index > 0 { divider }
                reminderRow(definition)
            }
        }
    }

    private func reminderRow(_ definition: ReminderDefinition) -> some View {
        let isOn = profile.remindersEnabled[definition.id] ?? false
        let minutes = resolvedMinutes(definition)
        let weekday = resolvedWeekday(definition)
        let phrase = ReminderSchedule.frLabel(hour: minutes / 60, minute: minutes % 60,
                                              weekday: weekday)

        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(definition.title).font(.subheadline.weight(.semibold))
                Text(ReminderSchedule.frFrequency(weekday: weekday))
                    .font(.caption).foregroundStyle(Theme.subtext)
            }
            // Le bloc de texte est combiné et porte la phrase entière ; les contrôles
            // gardent chacun leur libellé et restent actionnables séparément.
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(definition.title), \(phrase)")
            // Mesuré (harnais hébergeant SettingsContent réel, 320 à 402 pt) : sans ça
            // le sous-titre de fréquence se coupe en deux lignes dès 375 pt. Voir la
            // note sur le menu de jour ci-dessous : les deux .fixedSize() vont ensemble.
            .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 4)

            if definition.isWeekdayEditable {
                Picker("", selection: weekdayBinding(definition)) {
                    ForEach(Array(ReminderSchedule.weekdayRange), id: \.self) { day in
                        Text(ReminderSchedule.frShortWeekday(day)).tag(day)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                // Sans .fixedSize() le libellé du menu ("sam.") se coupe en "sam" / "."
                // de 320 à 402 pt. Les deux .fixedSize() de la ligne (celui-ci et celui
                // du bloc de texte ci-dessus) doivent être posés ENSEMBLE : poser un
                // seul des deux ne fait que déplacer la coupure sur l'autre élément.
                // À 320 pt la ligne déborde alors de la carte au lieu de rentrer ; aucun
                // iPhone livré ne fait 320 pt, et d'autres lignes de cet écran cassent
                // déjà seules à cette largeur, indépendamment de ce correctif.
                .fixedSize()
                .disabled(!isOn)
                .accessibilityLabel("Jour du rappel \(definition.title)")
            }

            DatePicker("", selection: timeBinding(definition),
                       displayedComponents: .hourAndMinute)
                .datePickerStyle(.compact)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "fr_FR"))
                // Rappel éteint : iOS grise le contrôle de lui-même, l'heure n'a donc
                // plus l'air active.
                .disabled(!isOn)
                .accessibilityLabel("Heure du rappel \(definition.title)")

            Toggle("", isOn: enabledBinding(definition.id))
                .labelsHidden()
                .accessibilityLabel("Rappel \(definition.title)")
        }
    }

    // MARK: Valeurs résolues (surcharge du profil, sinon défaut du catalogue)
    //
    // Simples relais vers ReminderSchedule (NivelCore) : la règle « surcharge valide
    // sinon défaut du catalogue » vit là-bas en un seul endroit, partagée avec
    // ReminderPlanner.planned. Ne PAS la réimplémenter ici : deux copies de la même
    // règle finissent tôt ou tard par diverger, et l'écran afficherait alors une heure
    // différente de celle réellement planifiée.

    private func resolvedMinutes(_ definition: ReminderDefinition) -> Int {
        ReminderSchedule.resolvedMinutes(profile.reminderTimes[definition.id], for: definition)
    }

    private func resolvedWeekday(_ definition: ReminderDefinition) -> Int? {
        ReminderSchedule.resolvedWeekday(profile.reminderWeekdays[definition.id], for: definition)
    }

    // MARK: Bindings
    //
    // Règle SwiftData commune aux trois : réassignation COMPLÈTE du dictionnaire,
    // jamais de mutation en place d'une collection d'un @Model.

    private func enabledBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { profile.remindersEnabled[id] ?? false },
            set: { newValue in
                var enabled = profile.remindersEnabled
                enabled[id] = newValue
                profile.remindersEnabled = enabled
                persistReminders()
            }
        )
    }

    /// Calendrier grégorien FIXE, pas Calendar.current : arithmétique heure/minute
    /// pure sur un jour de référence arbitraire, aucune sémantique calendaire réelle
    /// nécessaire. Calendar.current suivrait le réglage Région de l'appareil ; sous un
    /// calendrier non grégorien, date(from:) peut renvoyer nil et faire retomber le
    /// getter sur .now, affichant l'heure courante au lieu de l'heure enregistrée.
    private static let gregorian = Calendar(identifier: .gregorian)

    private func timeBinding(_ definition: ReminderDefinition) -> Binding<Date> {
        Binding(
            get: {
                let minutes = resolvedMinutes(definition)
                var components = Self.referenceDayComponents
                components.hour = minutes / 60
                components.minute = minutes % 60
                return Self.gregorian.date(from: components) ?? .now
            },
            set: { newValue in
                let parts = Self.gregorian.dateComponents([.hour, .minute], from: newValue)
                var times = profile.reminderTimes
                times[definition.id] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                profile.reminderTimes = times
                persistReminders()
            }
        )
    }

    private func weekdayBinding(_ definition: ReminderDefinition) -> Binding<Int> {
        Binding(
            get: { resolvedWeekday(definition) ?? 1 },
            set: { newValue in
                var weekdays = profile.reminderWeekdays
                weekdays[definition.id] = newValue
                profile.reminderWeekdays = weekdays
                persistReminders()
            }
        )
    }

    /// Faire tourner la roue d'heure appelle ceci des dizaines de fois : le compteur
    /// de génération de NotificationService absorbe la rafale, aucun anti-rebond ici.
    private func persistReminders() {
        save()
        NotificationService.reschedule(for: profile)
    }
```

- [ ] **Step 2: Enrichir la preview**

Dans le `#Preview` en bas du fichier, ajouter au profil de démonstration des horaires personnalisés pour voir la ligne dans son état non trivial :

```swift
        remindersEnabled: ["lunch": true, "dinner": true, "weigh": true, "steps": false],
        reminderTimes: ["dinner": 19 * 60 + 45],
        reminderWeekdays: ["weigh": 1]
```

- [ ] **Step 3: Vérifier à l'œil**

Ouvrir la preview de `SettingsView`. Vérifier :
- les quatre lignes tiennent en largeur, la ligne « Pesée » comprise (menu du jour + heure + interrupteur) ;
- la ligne « Pas » est éteinte et son sélecteur d'heure apparaît grisé ;
- le sous-titre du dîner dit « tous les jours » et son heure affiche 19:45.

- [ ] **Step 4: Lancer toute la suite d'app**

Run: `xcodebuild -project Nivel.xcodeproj -scheme Nivel -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`
Expected: tout au vert.

- [ ] **Step 5: Commit**

```bash
git add App/Views/Settings/SettingsView.swift
git commit -m "feat(réglages): heure modifiable sur les 4 rappels, jour pour la pesée"
```

---

### Task 10 : `DurationSelection` et `LoggedDuration`

**Files:**
- Create: `NivelCore/Sources/NivelCore/SportDuration.swift`
- Test: `NivelCore/Tests/NivelCoreTests/SportDurationTests.swift`

- [ ] **Step 1: Écrire les tests qui échouent**

```swift
// NivelCore/Tests/NivelCoreTests/SportDurationTests.swift
import XCTest
@testable import NivelCore

final class SportDurationTests: XCTestCase {

    // MARK: Valeur d'ouverture de la roue

    func testOuvreSurLaDureeDejaChoisie() {
        XCTAssertEqual(CustomDuration.openingValue(current: 25, durations: [10, 20, 40]), 25)
    }

    func testSansSelectionOuvreSurLaMediane() {
        XCTAssertEqual(CustomDuration.openingValue(current: nil, durations: [10, 20, 40]), 20)
        XCTAssertEqual(CustomDuration.openingValue(current: nil, durations: [5, 10]), 10)
    }

    func testCatalogueVideOuValeurAberranteDonneVingt() {
        XCTAssertEqual(CustomDuration.openingValue(current: nil, durations: []), 20)
        XCTAssertEqual(CustomDuration.openingValue(current: 0, durations: []), 20)
        XCTAssertEqual(CustomDuration.openingValue(current: 999, durations: []), 20)
    }

    func testBornesDeLaRoue() {
        XCTAssertEqual(CustomDuration.range.lowerBound, 1)
        XCTAssertEqual(CustomDuration.range.upperBound, 240)
    }

    func testSelectionExposeSesMinutes() {
        XCTAssertEqual(DurationSelection.preset(20).minutes, 20)
        XCTAssertEqual(DurationSelection.custom(25).minutes, 25)
        XCTAssertFalse(DurationSelection.preset(20).isCustom)
        XCTAssertTrue(DurationSelection.custom(25).isCustom)
    }

    // MARK: Durée réellement enregistrée

    func testTimerJamaisLanceEnregistreLaDureeChoisie() {
        XCTAssertEqual(LoggedDuration.resolve(chosenMinutes: 20, elapsedSeconds: 0,
                                              timerUsed: false), 20)
    }

    func testTimerAlleAuBoutEnregistreLaDureeChoisie() {
        XCTAssertEqual(LoggedDuration.resolve(chosenMinutes: 20, elapsedSeconds: 1200,
                                              timerUsed: true), 20)
    }

    func testArretAnticipeEnregistreLEcoule() {
        XCTAssertEqual(LoggedDuration.resolve(chosenMinutes: 20, elapsedSeconds: 840,
                                              timerUsed: true), 14)
    }

    func testArrondiALaMinuteLaPlusProche() {
        // 13 min 40 s → 14 min ; 13 min 20 s → 13 min.
        XCTAssertEqual(LoggedDuration.resolve(chosenMinutes: 20, elapsedSeconds: 820,
                                              timerUsed: true), 14)
        XCTAssertEqual(LoggedDuration.resolve(chosenMinutes: 20, elapsedSeconds: 800,
                                              timerUsed: true), 13)
    }

    /// Une validation quasi immédiate ne doit pas enregistrer zéro minute.
    func testPlancherAUneMinute() {
        XCTAssertEqual(LoggedDuration.resolve(chosenMinutes: 20, elapsedSeconds: 0,
                                              timerUsed: true), 1)
        XCTAssertEqual(LoggedDuration.resolve(chosenMinutes: 20, elapsedSeconds: 29,
                                              timerUsed: true), 1)
    }

    /// L'écoulé du modèle est déjà plafonné, mais on ne dépend pas de ça.
    func testJamaisPlusQueLaDureeChoisie() {
        XCTAssertEqual(LoggedDuration.resolve(chosenMinutes: 20, elapsedSeconds: 9_999,
                                              timerUsed: true), 20)
    }

    func testDureeLibreMaximale() {
        XCTAssertEqual(LoggedDuration.resolve(chosenMinutes: 240, elapsedSeconds: 14_400,
                                              timerUsed: true), 240)
    }
}
```

- [ ] **Step 2: Lancer les tests, vérifier l'échec**

Run: `cd NivelCore && swift test --filter SportDurationTests`
Expected: échec de compilation, « cannot find 'CustomDuration' in scope ».

- [ ] **Step 3: Écrire l'implémentation**

```swift
// NivelCore/Sources/NivelCore/SportDuration.swift
// Choix et enregistrement de la durée d'une activité libre (spec v1.9 §5).

import Foundation

/// Ce que l'utilisateur a choisi dans la section « Durée ».
public enum DurationSelection: Equatable, Hashable, Sendable {
    /// Une des durées du catalogue de l'activité.
    case preset(Int)
    /// Une durée saisie à la roue.
    case custom(Int)

    public var minutes: Int {
        switch self {
        case .preset(let minutes), .custom(let minutes): minutes
        }
    }

    public var isCustom: Bool {
        if case .custom = self { true } else { false }
    }
}

public enum CustomDuration {
    /// Bornes de la roue. 4 h couvre la plus longue randonnée plausible.
    public static let range = 1...240

    /// Valeur d'ouverture de la roue : la durée déjà choisie si elle est plausible,
    /// sinon la médiane du catalogue de l'activité, sinon 20 minutes. On ne part
    /// jamais de 1 minute, qui obligerait à faire défiler toute la roue.
    public static func openingValue(current: Int?, durations: [Int]) -> Int {
        if let current, range.contains(current) { return current }
        let sorted = durations.sorted()
        if !sorted.isEmpty {
            let median = sorted[sorted.count / 2]
            if range.contains(median) { return median }
        }
        return 20
    }
}

/// Durée réellement enregistrée à la validation.
public enum LoggedDuration {
    /// - Parameters:
    ///   - elapsedSeconds: écoulé du modèle de timer. Il est DÉJÀ plafonné à la durée
    ///     choisie côté modèle ; le plafond est répété ici pour que la fonction soit
    ///     juste indépendamment de son appelant.
    ///   - timerUsed: le timer a été lancé au moins une fois.
    public static func resolve(chosenMinutes: Int, elapsedSeconds: TimeInterval,
                               timerUsed: Bool) -> Int {
        guard timerUsed else { return chosenMinutes }
        let rounded = Int((elapsedSeconds / 60).rounded())
        return min(chosenMinutes, max(1, rounded))
    }
}
```

- [ ] **Step 4: Lancer les tests, vérifier le succès**

Run: `cd NivelCore && swift test`
Expected: toute la suite NivelCore au vert.

- [ ] **Step 5: Commit**

```bash
git add NivelCore/Sources/NivelCore/SportDuration.swift NivelCore/Tests/NivelCoreTests/SportDurationTests.swift
git commit -m "feat(core): durée libre et durée réellement enregistrée"
```

---

### Task 11 : La puce « Autre » et la roue dans la feuille d'activité

**Files:**
- Modify: `App/Views/Sport/ActivityLogSheet.swift`

- [ ] **Step 1: Remplacer l'état et l'init**

```swift
    /// Durée choisie : une puce du catalogue ou la valeur de la roue (spec v1.9 §5.1).
    @State private var selection: DurationSelection?
    /// Valeur courante de la roue, indépendante du fait qu'elle soit sélectionnée.
    @State private var customMinutes: Int

    init(activity: Activity, initialMinutes: Int? = nil) {
        self.activity = activity
        _selection = State(initialValue: initialMinutes.map { DurationSelection.preset($0) })
        _timer = State(initialValue: initialMinutes.map { ExerciseTimerModel(durationMinutes: $0) })
        _customMinutes = State(initialValue: CustomDuration.openingValue(
            current: initialMinutes, durations: activity.durations))
    }
```

- [ ] **Step 2: Remplacer la section Durée**

```swift
                    SectionTitle("Durée")
                    HStack(spacing: 8) {
                        ForEach(activity.durations, id: \.self) { minutes in
                            durationButton(minutes)
                        }
                        customButton
                    }
                    if selection?.isCustom == true {
                        customWheel
                    }
```

```swift
    /// Quatrième puce : sous-titre vide tant qu'elle n'a pas servi, valeur courante
    /// ensuite (les trois autres affichent leurs kcal, elle affiche ses minutes).
    private var customButton: some View {
        let isSelected = selection?.isCustom == true
        return Button {
            selection = .custom(customMinutes)
        } label: {
            VStack(spacing: 3) {
                Text("Autre")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isSelected ? .white : Theme.text)
                    .lineLimit(1)
                if isSelected {
                    Text("\(customMinutes) min")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.vertical, 12)
            .background(isSelected ? Theme.orange : Theme.card,
                        in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    /// Roue dépliée SUR PLACE (pas de feuille au-dessus de la feuille) : la sheet est
    /// déjà en détent .large, la place existe, et l'estimation reste visible.
    private var customWheel: some View {
        VStack(spacing: 4) {
            Picker("Durée", selection: $customMinutes) {
                ForEach(Array(CustomDuration.range), id: \.self) { minutes in
                    Text("\(minutes) min").tag(minutes)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(height: 130)
            .accessibilityLabel("Durée en minutes")

            Text("~\(activity.estimatedKcal(minutes: customMinutes).frFormatted) kcal")
                .font(.caption)
                .foregroundStyle(Theme.subtext)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }
```

- [ ] **Step 3: Adapter les puces du catalogue et les `onChange`**

Dans `durationButton`, remplacer la condition de sélection et l'action :

```swift
        let isSelected = selection == .preset(minutes)
        return Button {
            selection = .preset(minutes)
        } label: {
```

Remplacer les deux `onChange` de durée par :

```swift
        // La roue met à jour la sélection tant qu'elle est active.
        .onChange(of: customMinutes) { _, minutes in
            if selection?.isCustom == true { selection = .custom(minutes) }
        }
        // Recrée le timer (reset implicite) à chaque nouvelle durée. Re-taper la durée
        // déjà sélectionnée ne relance rien (même valeur, pas d'événement) : c'est le
        // rôle de « Recommencer ».
        .onChange(of: selection?.minutes) { _, minutes in
            timer = minutes.map { ExerciseTimerModel(durationMinutes: $0) }
            UIApplication.shared.isIdleTimerDisabled = false
        }
```

Enfin, remplacer les usages restants de `selectedMinutes` dans `bottomBar` et `validate` par `selection`.

- [ ] **Step 4: Compiler et vérifier à l'œil**

Run: `xcodebuild -project Nivel.xcodeproj -scheme Nivel -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
Expected: compilation propre.

Ouvrir la preview « Durée choisie (timer) » puis, dans le simulateur, taper « Autre » : la roue apparaît sous les puces, les kcal suivent, l'anneau se recrée sur la valeur de la roue.

- [ ] **Step 5: Lancer toute la suite d'app**

Run: `xcodebuild -project Nivel.xcodeproj -scheme Nivel -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`
Expected: tout au vert.

- [ ] **Step 6: Commit**

```bash
git add App/Views/Sport/ActivityLogSheet.swift
git commit -m "feat(sport): puce « Autre » et roue de durée libre"
```

---

### Task 12 : Enregistrer le temps réellement écoulé

**Files:**
- Modify: `App/Views/Sport/ActivityLogSheet.swift` (`bottomBar`, `validate`)

- [ ] **Step 1: Calculer la durée résolue**

Ajouter aux données dérivées :

```swift
    /// Durée qui sera réellement enregistrée (spec v1.9 §5.2). `now` est injecté par
    /// le TimelineView de la barre basse : le libellé doit suivre le timer qui tourne.
    private func loggedMinutes(at now: Date) -> Int? {
        guard let selection else { return nil }
        guard let timer else { return selection.minutes }
        return LoggedDuration.resolve(chosenMinutes: selection.minutes,
                                      elapsedSeconds: timer.elapsed(at: now),
                                      timerUsed: !timer.isIdle)
    }
```

- [ ] **Step 2: Ajouter la ligne « noté » à la barre basse**

Remplacer `bottomBar` par :

```swift
    private var bottomBar: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let logged = loggedMinutes(at: context.date)
            VStack(spacing: 6) {
                // Affichée seulement quand l'app s'apprête à noter autre chose que la
                // durée choisie (arrêt anticipé). Le bouton, lui, ne bouge jamais :
                // « C'est fait ! (+30 XP) » y tient déjà tout juste.
                if let logged, let selection, logged != selection.minutes {
                    Text("noté : \(logged) min")
                        .font(.caption)
                        .foregroundStyle(Theme.subtext)
                }
                Button(xpReward > 0 ? "C'est fait ! (+\(xpReward) XP)" : "C'est fait !",
                       action: validate)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(selection == nil || isSaving)
                    // Pulse dérivé de `timer?.isFinished` à chaque rendu (pas de latch
                    // séparé) : « Recommencer » l'éteint du même coup.
                    .gentlePulse(timer?.isFinished == true, reduceMotion: reduceMotion)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Theme.card.ignoresSafeArea(edges: .bottom))
            .shadow(color: Theme.floatingShadow, radius: 10, y: -4)
        }
    }
```

- [ ] **Step 3: Enregistrer la durée résolue**

```swift
    private func validate() {
        guard let minutes = loggedMinutes(at: .now), !isSaving else { return }
        isSaving = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            await game.logActivity(activity: activity, durationMinutes: minutes)
            dismiss()
        }
    }
```

Les kcal sont recalculées par `logActivity` à partir de cette durée : rien d'autre à faire.

- [ ] **Step 4: Vérifier le comportement dans le simulateur**

1. Ouvrir une activité, choisir 10 min, lancer le timer, attendre ~70 s, valider.
   Attendu : « noté : 1 min » apparaît, l'entrée du jour affiche 1 min.
2. Choisir 10 min, ne pas lancer le timer, valider.
   Attendu : aucune ligne « noté », l'entrée affiche 10 min.
3. Laisser un timer d'1 min aller au bout, valider.
   Attendu : aucune ligne « noté », l'entrée affiche 1 min.

- [ ] **Step 5: Lancer toute la suite d'app**

Run: `xcodebuild -project Nivel.xcodeproj -scheme Nivel -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`
Expected: tout au vert.

- [ ] **Step 6: Commit**

```bash
git add App/Views/Sport/ActivityLogSheet.swift
git commit -m "feat(sport): enregistrer le temps réellement écoulé en cas d'arrêt anticipé"
```

---

### Task 13 : Version, documentation, vérification finale

**Files:**
- Modify: `project.yml` (deux blocs `info.properties`)
- Modify: `README.md`

- [ ] **Step 1: Passer les deux cibles en 1.9 / build 10**

Dans `project.yml`, cible `Nivel` **et** cible `NivelWidgets` :

```yaml
        CFBundleShortVersionString: "1.9"
        CFBundleVersion: "10"
```

Les deux doivent bouger ensemble, sinon XcodeGen retombe sur 1.0/1 pour l'extension (leçon v1.6).

Run: `xcodegen generate && grep -rn "1\.9" Nivel.xcodeproj/project.pbxproj | head`
Expected: la version apparaît pour les deux cibles.

- [ ] **Step 2: Mettre le README à jour**

Ajouter dans le bloc de commandes, après la régénération des icônes :

```sh
# Régénérer les chimes du timer (App/Resources/Sounds)
swift scripts/gen-sounds.swift
```

Mettre à jour le badge de version (1.8 → 1.9) et le badge de tests avec les comptes réels obtenus à l'étape suivante.

- [ ] **Step 3: Lancer les deux suites en entier**

Run: `cd NivelCore && swift test`
Expected: 74 tests d'origine + environ 20 nouveaux, tous au vert. Noter le compte exact.

Run: `xcodebuild -project Nivel.xcodeproj -scheme Nivel -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`
Expected: 56 tests d'origine + environ 7 nouveaux, tous au vert. Noter le compte exact.

Reporter les deux comptes dans les badges du README.

- [ ] **Step 4: Vérifications transverses**

Run: `grep -rn "AudioServicesPlaySystemSound\|NotificationService.reminders\|selectedMinutes" App/`
Expected: aucun résultat. Les trois symboles ont disparu.

Run: `grep -rn "—" App/Views/Settings/SettingsView.swift App/Views/Sport/ActivityLogSheet.swift NivelCore/Sources/NivelCore/Reminders.swift`
Expected: aucun tiret cadratin dans une chaîne affichée (les commentaires de code sont tolérés, la règle vise les textes utilisateur).

- [ ] **Step 5: Commit**

```bash
git add project.yml README.md
git commit -m "chore: version 1.9 (build 10) et documentation du script de sons"
```

---

## Vérification sur les téléphones (par Michaël, après merge)

Ces points ne sont pas testables en simulateur et conditionnent la réussite du lot.

- [ ] Le chime sonne avec l'interrupteur silencieux activé.
- [ ] Le chime ne coupe pas une musique ou un podcast en cours.
- [ ] Les chimes « une note » et « trois notes » se distinguent sans regarder l'écran.
- [ ] Au premier lancement, le store existant s'ouvre et **les quatre rappels ont gardé leurs horaires actuels** (migration des deux dictionnaires sur `UserProfile`).
- [ ] Une notification arrive bien à l'heure modifiée, le lendemain.
- [ ] Le sélecteur d'heure d'un rappel éteint apparaît bien grisé.
- [ ] Les deux iPhones sont buildés depuis le même commit.
