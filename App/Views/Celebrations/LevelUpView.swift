// App/Views/Celebrations/LevelUpView.swift
// Célébration de level-up plein écran (spec §7.1) : Nivelito saute de joie,
// confettis, haptique .success, bouton "Continuer".

import SwiftUI
import UIKit

// MARK: - Confettis

/// Pluie de confettis (~80 particules aux couleurs du thème) : gravité + rotation,
/// ~2,5 s puis arrêt COMPLET (le TimelineView est retiré — pas de CPU brûlé).
/// Reduce Motion → rien (les confettis sont purement décoratifs).
struct ConfettiView: View {
    /// Durée de la pluie ; les particules démarrent étalées sur ~0,5 s.
    var duration: Double = 2.5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var particles = ConfettiParticle.make(count: 80)
    @State private var startDate = Date()
    @State private var isFinished = false

    /// Gravité en pts/s² — assez pour traverser un écran d'iPhone en ~2 s.
    private static let gravity: CGFloat = 380

    var body: some View {
        if !reduceMotion && !isFinished {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let elapsed = timeline.date.timeIntervalSince(startDate)
                    for particle in particles {
                        particle.draw(in: context, canvasSize: size,
                                      elapsed: elapsed, gravity: Self.gravity)
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task {
                startDate = .now
                try? await Task.sleep(for: .seconds(duration))
                isFinished = true
            }
        }
    }
}

/// Une particule : position/vitesse tirées une fois (via @State dans ConfettiView,
/// stables entre les re-render), trajectoire dérivée du temps écoulé (pas d'état par frame).
private struct ConfettiParticle {
    let relativeX: CGFloat   // 0…1 de la largeur du canvas
    let delay: Double        // départ étalé (effet "pluie", pas "mur")
    let initialSpeed: CGFloat
    let drift: CGFloat       // dérive horizontale, pts/s
    let size: CGFloat
    let color: Color
    let spin: Double         // tours/s (négatif = sens anti-horaire)
    let isCircle: Bool

    static func make(count: Int) -> [ConfettiParticle] {
        let palette = [Theme.orange, Theme.accent, Theme.green, Theme.blue]
        return (0..<count).map { index in
            ConfettiParticle(
                relativeX: .random(in: 0...1),
                delay: .random(in: 0...0.5),
                initialSpeed: .random(in: 40...160),
                drift: .random(in: -45...45),
                size: .random(in: 6...11),
                color: palette[index % palette.count],
                spin: .random(in: -1.5...1.5),
                isCircle: index.isMultiple(of: 3)
            )
        }
    }

    func draw(in context: GraphicsContext, canvasSize: CGSize,
              elapsed: TimeInterval, gravity: CGFloat) {
        let t = CGFloat(elapsed - delay)
        guard t > 0 else { return }

        // Chute libre : y = y0 + v0·t + ½·g·t² (départ juste au-dessus du canvas).
        let y = -20 + initialSpeed * t + 0.5 * gravity * t * t
        guard y < canvasSize.height + 20 else { return }
        let x = relativeX * canvasSize.width + drift * t

        var ctx = context
        ctx.translateBy(x: x, y: y)
        ctx.rotate(by: .radians(spin * Double(t) * 2 * .pi))
        let rect = CGRect(x: -size / 2, y: -size / 2,
                          width: size, height: isCircle ? size : size * 0.55)
        let path = isCircle ? Path(ellipseIn: rect) : Path(rect)
        ctx.fill(path, with: .color(color))
    }
}

// MARK: - Level-up plein écran

/// Overlay plein écran présenté par `CelebrationsHost` quand un `.levelUp` est dépilé.
/// Le message est calculé PAR L'HÔTE (nivelitoSays persiste le dernier message —
/// pas d'effet de bord dans un body).
struct LevelUpView: View {
    let level: Int
    let message: String
    var onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Trigger LOCAL du rebond de Nivelito — indépendant de `celebrationsRaised`
    /// (le rebond de la mascotte de l'accueil est déjà géré là-bas, pas de doublon).
    @State private var bounceTrigger = 0

    /// Cadence des petits sauts de joie répétés (le rebond lui-même dure ~1 s).
    private static let bounceInterval: Duration = .seconds(1.6)

    var body: some View {
        ZStack {
            Theme.background.opacity(0.95)
                .ignoresSafeArea()

            ConfettiView()

            VStack(spacing: 20) {
                NivelitoView(expression: .joy, size: 160, celebrationTrigger: bounceTrigger)

                Text("NIVEAU \(level) !")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.orange)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Text(message)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)

                Button(action: onContinue) {
                    Text("Continuer")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(colors: [Theme.accent, Theme.orange],
                                           startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: Theme.buttonRadius)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
            }
            .padding(32)
        }
        .onAppear {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            bounceTrigger += 1
        }
        .task {
            // Petits rebonds répétés tant que l'écran est visible (saut de joie, spec §7.1).
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.bounceInterval)
                guard !Task.isCancelled else { return }
                bounceTrigger += 1
            }
        }
    }
}

#Preview("Level-up") {
    LevelUpView(level: 5, message: "Niveau 5 ! Tu avances à ton rythme, et ça paie 🧡") {}
        .fontDesign(.rounded)
}
