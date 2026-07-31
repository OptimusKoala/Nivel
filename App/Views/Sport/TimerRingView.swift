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
                .animation(.linear(duration: 0.3), value: fraction)
            if let segments, segments >= 2 {
                ForEach(1..<segments, id: \.self) { index in
                    Capsule()
                        .fill(Theme.background)
                        .frame(width: 4, height: lineWidth + 6)
                        .offset(y: -size / 2 + lineWidth / 2)
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
            .font(.system(size: 34, weight: .heavy, design: .rounded))
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

// MARK: - Previews

#Preview("Anneau — idle") {
    TimerRingView(illustrationName: "plank", fallbackEmoji: "🧘",
                  fraction: 0, finished: false, segments: 3)
        .padding()
        .background(Theme.background)
}

#Preview("Anneau — en cours (segments 3)") {
    TimerRingView(illustrationName: "plank", fallbackEmoji: "🧘",
                  fraction: 0.6, finished: false, segments: 3)
        .padding()
        .background(Theme.background)
}

#Preview("Anneau — terminé (vert)") {
    TimerRingView(illustrationName: "plank", fallbackEmoji: "🧘",
                  fraction: 1, finished: true, segments: 3)
        .padding()
        .background(Theme.background)
}

#Preview("Contrôles — idle") {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    let timer = ExerciseTimerModel(durationMinutes: 3)
    return TimerControls(timer: timer, now: t0)
        .padding()
        .background(Theme.background)
}

#Preview("Contrôles — en cours") {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    let timer = ExerciseTimerModel(durationMinutes: 3)
    timer.start(at: t0)
    return TimerControls(timer: timer, now: t0.addingTimeInterval(90))
        .padding()
        .background(Theme.background)
}

#Preview("Contrôles — en pause") {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    let timer = ExerciseTimerModel(durationMinutes: 3)
    timer.start(at: t0)
    timer.pause(at: t0.addingTimeInterval(30))
    return TimerControls(timer: timer, now: t0.addingTimeInterval(120))
        .padding()
        .background(Theme.background)
}

#Preview("Contrôles — terminé") {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    let timer = ExerciseTimerModel(durationMinutes: 3)
    timer.start(at: t0)
    timer.syncNow(at: t0.addingTimeInterval(200))
    return TimerControls(timer: timer, now: t0.addingTimeInterval(200))
        .padding()
        .background(Theme.background)
}
