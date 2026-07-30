// App/Views/Splash/SplashView.swift
// Splash "scène vivante" (v1.1) : chorégraphie ~2,5 s, skippable d'un tap à TOUT
// moment — l'orchestration (durée, tap, fondu de sortie) vit dans RootView ;
// cette vue ne gère que sa chorégraphie d'entrée.
//   0,0-0,5 s  halo radial (accent) qui s'étend + Nivelito rebondit depuis le bas
//              avec squash & stretch (écrasé à l'atterrissage, se pose en spring)
//   0,6-1,6 s  frétillement — rebond de célébration existant de NivelitoView (±4°)
//   0,9-2,0 s  étincelles discrètes qui scintillent autour de la mascotte
//   1,2-2,0 s  logotype "Nivel" lettre par lettre (80 ms d'écart)
//   2,0-2,4 s  tenue, puis le fondu de sortie de RootView prend le relais
// Reduce Motion : simple fondu (mascotte + logotype), ni étincelles ni rebonds.

import SwiftUI

struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Halo radial derrière la mascotte — s'étend doucement dès 0 s.
    @State private var glowOn = false
    // Mascotte : arrive du bas légèrement étirée (stretch), squash à
    // l'atterrissage, puis se pose à 1 en spring peu amorti (rebonds décroissants).
    @State private var mascotOpacity: Double = 0
    @State private var mascotOffsetY: CGFloat = 170
    @State private var mascotScaleX: CGFloat = 0.94
    @State private var mascotScaleY: CGFloat = 1.08
    @State private var celebration = 0
    @State private var sparkles = false
    @State private var titleVisible = false

    private static let letters = Array("Nivel")

    var body: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()

            VStack(spacing: 18) {
                NivelitoView(expression: .happy, size: 150, celebrationTrigger: celebration)
                    .scaleEffect(x: mascotScaleX, y: mascotScaleY, anchor: .bottom)
                    .offset(y: mascotOffsetY)
                    .opacity(mascotOpacity)
                    // background/overlay se calent sur le cadre de layout (que ni
                    // offset ni scaleEffect ne déplacent) : halo et étincelles
                    // restent centrés pendant que la mascotte rebondit, et ne
                    // poussent pas le logotype.
                    .background { glow }
                    .overlay { if !reduceMotion { SparklesView(trigger: sparkles) } }

                logotype
            }
        }
        .task { await runChoreography() }
    }

    // MARK: - Halo

    private var glow: some View {
        Circle()
            .fill(RadialGradient(colors: [Theme.accent.opacity(0.25), Theme.accent.opacity(0)],
                                 center: .center, startRadius: 10, endRadius: 165))
            .frame(width: 330, height: 330)
            .scaleEffect(glowOn ? 1 : 0.35)
            .opacity(glowOn ? 1 : 0)
    }

    // MARK: - Logotype

    /// "Nivel" lettre par lettre : opacité + remontée décalées de 80 ms par lettre.
    private var logotype: some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.letters.enumerated()), id: \.offset) { index, letter in
                Text(String(letter))
                    .opacity(titleVisible ? 1 : 0)
                    .offset(y: titleVisible || reduceMotion ? 0 : 16)
                    .animation(letterAnimation(index: index), value: titleVisible)
            }
        }
        .font(.system(size: 42, weight: .bold, design: .rounded))
        .foregroundStyle(Theme.text)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Nivel")
    }

    private func letterAnimation(index: Int) -> Animation {
        reduceMotion
            ? .easeIn(duration: 0.3)
            : .spring(response: 0.45, dampingFraction: 0.7).delay(Double(index) * 0.08)
    }

    // MARK: - Chorégraphie

    private func runChoreography() async {
        if reduceMotion {
            // Reduce Motion : tout apparaît en fondu, déjà en place (~1,2 s côté RootView).
            mascotOffsetY = 0
            mascotScaleX = 1
            mascotScaleY = 1
            withAnimation(.easeIn(duration: 0.3)) {
                glowOn = true
                mascotOpacity = 1
                titleVisible = true
            }
            return
        }

        // 0,0 s — le halo s'étend ; Nivelito monte depuis le bas, étiré pendant le vol.
        // Chaque pause vérifie l'annulation (tap-skip) : sans quoi les étapes
        // restantes se déclencheraient d'un coup sur la vue en cours de fondu.
        withAnimation(.easeOut(duration: 0.6)) { glowOn = true }
        withAnimation(.easeOut(duration: 0.18)) { mascotOpacity = 1 }
        withAnimation(.easeOut(duration: 0.32)) { mascotOffsetY = 0 }
        guard (try? await Task.sleep(for: .seconds(0.30))) != nil else { return }

        // 0,3 s — atterrissage : squash bref (aplati + élargi), ancré au sol.
        withAnimation(.easeOut(duration: 0.09)) {
            mascotScaleX = 1.10
            mascotScaleY = 0.84
        }
        guard (try? await Task.sleep(for: .seconds(0.10))) != nil else { return }

        // 0,4 s — détente en spring peu amorti → 2-3 rebonds décroissants vers 1.
        withAnimation(.spring(response: 0.42, dampingFraction: 0.32)) {
            mascotScaleX = 1
            mascotScaleY = 1
        }
        guard (try? await Task.sleep(for: .seconds(0.20))) != nil else { return }

        // 0,6 s — frétillement : rebond de célébration existant de NivelitoView (~1 s).
        celebration += 1
        guard (try? await Task.sleep(for: .seconds(0.30))) != nil else { return }

        // 0,9 s — étincelles (chacune scintille une fois, en décalé, jusqu'à ~2 s).
        sparkles = true
        guard (try? await Task.sleep(for: .seconds(0.30))) != nil else { return }

        // 1,2 s — logotype lettre par lettre.
        titleVisible = true
    }
}

// MARK: - Étincelles

/// Étincelles discrètes autour de la mascotte : chacune scintille UNE fois
/// (apparition/disparition en décalé) quand `trigger` bascule. Positions fixes
/// (chorégraphie reproductible), couleurs accent/primaire de la palette —
/// l'accent reste lumineux sur les 4 palettes, Nuit douce comprise.
private struct SparklesView: View {
    let trigger: Bool

    private struct Spec: Identifiable {
        let id: Int
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let delay: Double
        let accent: Bool
    }

    private static let specs: [Spec] = [
        Spec(id: 0, x: -92, y: -78, size: 13, delay: 0.02, accent: true),
        Spec(id: 1, x: 88, y: -92, size: 17, delay: 0.12, accent: false),
        Spec(id: 2, x: -116, y: -8, size: 11, delay: 0.24, accent: false),
        Spec(id: 3, x: 112, y: -28, size: 14, delay: 0.06, accent: true),
        Spec(id: 4, x: -64, y: -118, size: 15, delay: 0.34, accent: true),
        Spec(id: 5, x: 50, y: -126, size: 11, delay: 0.18, accent: false),
        Spec(id: 6, x: 124, y: 44, size: 12, delay: 0.42, accent: true),
        Spec(id: 7, x: -102, y: 62, size: 14, delay: 0.16, accent: false),
        Spec(id: 8, x: 4, y: -140, size: 12, delay: 0.50, accent: true),
        Spec(id: 9, x: 84, y: 90, size: 10, delay: 0.30, accent: true),
    ]

    var body: some View {
        ZStack {
            ForEach(Self.specs) { spec in
                Image(systemName: "sparkle")
                    .font(.system(size: spec.size))
                    .foregroundStyle(spec.accent ? Theme.accent : Theme.orange)
                    .keyframeAnimator(initialValue: 0.0, trigger: trigger) { content, phase in
                        content
                            .opacity(phase)
                            .scaleEffect(0.2 + 0.8 * phase)
                            .rotationEffect(.degrees(phase * 30))
                    } keyframes: { _ in
                        MoveKeyframe(0)
                        LinearKeyframe(0, duration: spec.delay)
                        CubicKeyframe(1, duration: 0.30)
                        CubicKeyframe(0, duration: 0.40)
                    }
                    .offset(x: spec.x, y: spec.y)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview {
    SplashView()
        .fontDesign(.rounded)
}
