// App/Views/Sport/TimerRingView.swift
// UI du timer d'exercice (spec timer §3, §5) : anneau de progression autour de
// l'illustration (cousin de CalorieRing), graduations de séries optionnelles,
// temps restant, contrôles. Fin = vert + « Bien joué ! », jamais de rouge.

import SwiftUI

/// Anneau + illustration circulaire. Décoratif pour VoiceOver (le temps est à côté).
struct TimerRingView: View {
    let illustrationName: String
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
                .trim(from: 0, to: min(max(0, fraction), 1))
                .stroke(
                    finished
                        ? AnyShapeStyle(Theme.green)
                        : AnyShapeStyle(LinearGradient(colors: [Theme.accent, Theme.orange],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                // Calée sur le tick 1 Hz de l'appelant (TimelineView) : un sweep continu
                // plutôt qu'un effet cliquet à chaque valeur de fraction.
                .animation(.linear(duration: 1), value: fraction)
            if let segments, segments >= 2 {
                ForEach(1..<segments, id: \.self) { index in
                    Capsule()
                        .fill(Theme.background)
                        .frame(width: 4, height: lineWidth + 6)
                        // Suit le rayon RÉEL du trait (après le padding ci-dessous), pas le rayon
                        // géométrique du frame : sinon les encoches dérivent hors de l'anneau.
                        .offset(y: -(size - lineWidth) / 2)
                        .rotationEffect(.degrees(Double(index) / Double(segments) * 360))
                }
            }
            SportIllustration(name: illustrationName,
                              size: size - lineWidth * 2 - 12,
                              cornerRadius: (size - lineWidth * 2 - 12) / 2)
        }
        .padding(lineWidth / 2) // le trait déborde du cercle géométrique (cf. CalorieRing)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Gros temps restant (ou « Bien joué ! » une fois fini), piloté par le modèle.
/// `now` vient du TimelineView de l'appelant (lecture pure, pas de tick interne) : l'appelant
/// DOIT appeler `timer.syncNow(at:)` sur chaque tick (`.onChange`/`.task`) pour que la
/// transition vers `.finished` se produise — cette vue ne mute jamais le modèle elle-même.
/// Lit `timer.isFinished` directement (SOURCE UNIQUE de l'état fini, cf. `TimerButtons`) :
/// le contrat « l'appelant appelle syncNow à chaque tick » couvre le décalage d'au plus une frame.
struct TimerTimeLabel: View {
    let timer: ExerciseTimerModel
    let now: Date

    var body: some View {
        Group {
            if timer.isFinished {
                Text("Bien joué !")
                    .foregroundStyle(Theme.green)
            } else {
                Text(Self.format(timer.remaining(at: now)))
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: timer.remaining(at: now))
            }
        }
        .font(.system(.largeTitle, design: .rounded).weight(.heavy))
        .minimumScaleFactor(0.7)
        .monospacedDigit()
        .accessibilityLabel(timer.isFinished ? "Terminé, bien joué" : Self.spokenRemaining(timer.remaining(at: now)))
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// "2:41" (minutes:secondes, arrondi à la seconde supérieure pour ne jamais afficher 0:00 en cours).
    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }

    static func spokenRemaining(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let minutes = total / 60, secs = total % 60
        let minutesPart = minutes > 0 ? "\(minutes) minute\(minutes > 1 ? "s" : "")" : nil
        let secondsPart = secs > 0 ? "\(secs) seconde\(secs > 1 ? "s" : "")" : nil
        let parts = [minutesPart, secondsPart].compactMap { $0 }
        guard !parts.isEmpty else { return "0 seconde restante" }
        // "restante" ne s'accorde au singulier que si l'unique quantité énoncée vaut 1
        // (« 1 minute restante », « 1 seconde restante ») ; sinon pluriel, y compris
        // pour une durée composée (« 1 minute 30 secondes restantes »).
        let isSingular = parts.count == 1 && (minutes == 1 || secs == 1)
        return parts.joined(separator: " ") + (isSingular ? " restante" : " restantes")
    }
}

/// Contrôles Lancer/Pause/Reprendre/Recommencer + message de pause, pilotés par le modèle.
/// Contrairement à `TimerTimeLabel`, aucune lecture de date : chaque action (`start`/`pause`/
/// `resume`/`reset`) prend l'horloge murale réelle au moment du tap, pas un `now` figé par
/// l'appelant (piège repéré en review : un `now` de TimelineView non rafraîchi entre deux ticks).
struct TimerButtons: View {
    let timer: ExerciseTimerModel

    var body: some View {
        VStack(spacing: 8) {
            if timer.isPaused {
                Text("En pause, prends ton temps 🧡")
                    .font(.footnote)
                    .foregroundStyle(Theme.subtext)
            }

            HStack(spacing: 10) {
                if timer.isIdle {
                    Button { timer.start() } label: {
                        Label { Text("Lancer le timer") } icon: { CozyIcon(name: "icon_play", size: 20) }
                    }
                    .buttonStyle(PrimaryButtonStyle(size: .compact))
                    .frame(minWidth: 130)
                } else if timer.isRunning {
                    Button { timer.pause() } label: {
                        Label { Text("Pause") } icon: { CozyIcon(name: "icon_pause", size: 20) }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .frame(minWidth: 130, minHeight: 44)
                    .contentShape(Rectangle())
                } else if timer.isPaused {
                    Button { timer.resume() } label: {
                        Label { Text("Reprendre") } icon: { CozyIcon(name: "icon_play", size: 20) }
                    }
                    .buttonStyle(PrimaryButtonStyle(size: .compact))
                    .frame(minWidth: 130)
                }
                if !timer.isIdle {
                    Button { timer.reset() } label: {
                        Label { Text("Recommencer") } icon: { CozyIcon(name: "icon_restart", size: 20) }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Anneau (idle)") {
    TimerRingView(illustrationName: "plank",
                  fraction: 0, finished: false, segments: 3)
        .padding()
        .background(Theme.background)
}

#Preview("Anneau (en cours, segments 3)") {
    TimerRingView(illustrationName: "plank",
                  fraction: 0.6, finished: false, segments: 3)
        .padding()
        .background(Theme.background)
}

#Preview("Anneau (terminé, vert)") {
    TimerRingView(illustrationName: "plank",
                  fraction: 1, finished: true, segments: 3)
        .padding()
        .background(Theme.background)
}

#Preview("Anneau (sans graduations, activité libre)") {
    TimerRingView(illustrationName: "walk",
                  fraction: 0.4, finished: false, segments: nil)
        .padding()
        .background(Theme.background)
}

#Preview("Anneau (180pt, ActivityLogSheet)") {
    TimerRingView(illustrationName: "walk",
                  fraction: 0.4, finished: false, segments: nil, size: 180)
        .padding()
        .background(Theme.background)
}

#Preview("Temps (idle)") {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    let timer = ExerciseTimerModel(durationMinutes: 3)
    return TimerTimeLabel(timer: timer, now: t0)
        .padding()
        .background(Theme.background)
}

#Preview("Temps (en cours)") {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    let timer = ExerciseTimerModel(durationMinutes: 3)
    timer.start(at: t0)
    return TimerTimeLabel(timer: timer, now: t0.addingTimeInterval(90))
        .padding()
        .background(Theme.background)
}

#Preview("Temps (terminé)") {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    let timer = ExerciseTimerModel(durationMinutes: 3)
    timer.start(at: t0)
    timer.syncNow(at: t0.addingTimeInterval(200))
    return TimerTimeLabel(timer: timer, now: t0.addingTimeInterval(200))
        .padding()
        .background(Theme.background)
}

#Preview("Temps (Dynamic Type AX3)") {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    let timer = ExerciseTimerModel(durationMinutes: 3)
    timer.start(at: t0)
    return TimerTimeLabel(timer: timer, now: t0.addingTimeInterval(90))
        .padding()
        .background(Theme.background)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Boutons (idle)") {
    let timer = ExerciseTimerModel(durationMinutes: 3)
    return TimerButtons(timer: timer)
        .padding()
        .background(Theme.background)
}

#Preview("Boutons (en cours)") {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    let timer = ExerciseTimerModel(durationMinutes: 3)
    timer.start(at: t0)
    return TimerButtons(timer: timer)
        .padding()
        .background(Theme.background)
}

#Preview("Boutons (en pause)") {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    let timer = ExerciseTimerModel(durationMinutes: 3)
    timer.start(at: t0)
    timer.pause(at: t0.addingTimeInterval(30))
    return TimerButtons(timer: timer)
        .padding()
        .background(Theme.background)
}
