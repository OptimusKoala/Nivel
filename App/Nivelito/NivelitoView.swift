// App/Nivelito/NivelitoView.swift
// Nivelito — mascotte officielle de Nivel (panda roux, d'après design/nivelito.svg).
// Rendu vectoriel dans un espace de référence 200×200, mis à l'échelle par `size`.

import SwiftUI

enum NivelitoExpression {
    case happy        // défaut : yeux ronds + sourire
    case joy          // yeux fermés joyeux « ∩ » + bouche ouverte
    case wink         // un œil rond + un œil fermé
    case sleepy       // paupières lourdes + petite bouche
    case encouraging  // yeux ronds + grand sourire
}

struct NivelitoView: View {
    var expression: NivelitoExpression = .happy
    var size: CGFloat = 100
    /// Les appelants incrémentent cet Int pour déclencher un rebond de célébration
    /// (rotation ±4° + offset y −8 en spring, ~1 s) — utilisé par les Tasks 11/13/19.
    var celebrationTrigger: Int = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false
    @State private var isBlinking = false
    @State private var bounceOffsetY: CGFloat = 0
    @State private var wobbleDegrees: Double = 0

    // Micro-gestes d'idle (v1.2-B) : toutes les 6–14 s, UN geste aléatoire parmi
    // frémissement d'oreilles / inclinaison de tête / clin d'œil / regard de côté.
    // Jamais deux à la fois, suspendus pendant un rebond de célébration,
    // désactivés sous Reduce Motion. Premier délai ≥ 6 s : la chorégraphie du
    // splash (~2,5 s) et les pages d'onboarding ne sont pas perturbées.
    @State private var earWiggleDegrees: Double = 0
    @State private var headTiltDegrees: Double = 0
    @State private var eyeGlanceX: CGFloat = 0
    @State private var microWink = false
    @State private var isCelebrating = false

    // Palette du SVG — les couleurs de Nivelito sont FIXES (identité de la
    // mascotte) : sa fourrure reste orange quel que soit le thème choisi.
    // Le contour/yeux/truffe/bouche restent Theme.outline, identique dans
    // les 4 palettes (bordeaux #3A1220).
    private let fur = Color(hex: 0xF57C1F)
    private let cream = Color(hex: 0xF2EDE0)
    private let earBrown = Color(hex: 0x7D3F1E)
    private let cheekBrown = Color(hex: 0x8A4B2A)
    private let blushPink = Color(hex: 0xFFB09B)

    private var scale: CGFloat { size / 200 }
    private var outlineStyle: StrokeStyle {
        StrokeStyle(lineWidth: 9 * scale, lineJoin: .round)
    }
    private var mouthStyle: StrokeStyle {
        StrokeStyle(lineWidth: 5.5 * scale, lineCap: .round)
    }
    private var closedEyeStyle: StrokeStyle {
        StrokeStyle(lineWidth: 6 * scale, lineCap: .round)
    }

    var body: some View {
        ZStack {
            // Oreilles (fill crème + contour), intérieurs bruns — chaque paire
            // oreille + intérieur est groupée pour le frémissement : rotation
            // miroir ±6° ancrée à la base de l'oreille (jonction avec la tête,
            // ~(61,66) et ~(139,66) dans l'espace 200×200), la tête couvre la base.
            ZStack {
                NivelitoEarLeft().fill(cream)
                NivelitoEarLeft().stroke(Theme.outline, style: outlineStyle)
                NivelitoEarInnerLeft().fill(earBrown)
            }
            .rotationEffect(.degrees(earWiggleDegrees),
                            anchor: UnitPoint(x: 61.0 / 200.0, y: 66.0 / 200.0))
            ZStack {
                NivelitoEarRight().fill(cream)
                NivelitoEarRight().stroke(Theme.outline, style: outlineStyle)
                NivelitoEarInnerRight().fill(earBrown)
            }
            .rotationEffect(.degrees(-earWiggleDegrees),
                            anchor: UnitPoint(x: 139.0 / 200.0, y: 66.0 / 200.0))

            // Tête (fill orange + contour)
            NivelitoHead().fill(fur)
            NivelitoHead().stroke(Theme.outline, style: outlineStyle)

            // Joues brunes
            NivelitoEllipse(center: .init(x: 45, y: 134), rx: 19, ry: 16).fill(cheekBrown)
            NivelitoEllipse(center: .init(x: 155, y: 134), rx: 19, ry: 16).fill(cheekBrown)

            // Museau crème
            NivelitoMuzzle().fill(cream)

            // Sourcils virgules (fill + stroke crème 4, comme le SVG)
            NivelitoBrowLeft().fill(cream)
            NivelitoBrowLeft().stroke(cream, style: StrokeStyle(lineWidth: 4 * scale, lineJoin: .round))
            NivelitoBrowRight().fill(cream)
            NivelitoBrowRight().stroke(cream, style: StrokeStyle(lineWidth: 4 * scale, lineJoin: .round))

            // Blush rose
            NivelitoEllipse(center: .init(x: 62, y: 122), rx: 8, ry: 5)
                .fill(blushPink.opacity(0.85))
            NivelitoEllipse(center: .init(x: 138, y: 122), rx: 8, ry: 5)
                .fill(blushPink.opacity(0.85))

            // Yeux (dépendent de l'expression) — le regard de côté décale la
            // couche des yeux horizontalement (micro-geste « glance »).
            eyes
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
                .offset(x: eyeGlanceX)

            // Truffe
            NivelitoNose().fill(Theme.outline)

            // Bouche (dépend de l'expression)
            mouth
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
        }
        .animation(reduceMotion ? .default : .spring(response: 0.3, dampingFraction: 0.65),
                   value: effectiveExpression)
        .frame(width: size, height: size)
        .scaleEffect(y: reduceMotion ? 1 : (breathe ? 1.02 : 0.98), anchor: .bottom)
        // Une seule rotation : célébration (wobble) et inclinaison de tête ne
        // jouent jamais ensemble (micro-gestes suspendus pendant la célébration).
        .rotationEffect(.degrees(wobbleDegrees + headTiltDegrees))
        .offset(y: bounceOffsetY)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
        .onChange(of: celebrationTrigger) { _, _ in
            guard !reduceMotion else { return }
            Task { await celebrate() }
        }
        .onChange(of: expression) { _, _ in
            // Un changement d'expression piloté par l'appelant annule un
            // micro-clin d'œil en cours (pas de .wink fantôme sur .joy/.sleepy).
            microWink = false
        }
        .task(id: hasOpenEyes) { await blinkLoop() }
        .task { await microGestureLoop() }
        .accessibilityLabel("Nivelito")
    }

    /// Expression réellement affichée : le micro-clin d'œil remplace brièvement
    /// happy/encouraging par .wink ; les autres expressions ne sont jamais altérées.
    private var effectiveExpression: NivelitoExpression {
        if microWink, expression == .happy || expression == .encouraging { return .wink }
        return expression
    }

    // MARK: - Yeux

    @ViewBuilder private var eyes: some View {
        switch effectiveExpression {
        case .happy, .encouraging:
            openEye(cx: 70)
            openEye(cx: 130)
        case .joy:
            NivelitoJoyEye(center: .init(x: 70, y: 104))
                .stroke(Theme.outline, style: closedEyeStyle)
            NivelitoJoyEye(center: .init(x: 130, y: 104))
                .stroke(Theme.outline, style: closedEyeStyle)
        case .wink:
            openEye(cx: 70)
            NivelitoJoyEye(center: .init(x: 130, y: 104))
                .stroke(Theme.outline, style: closedEyeStyle)
        case .sleepy:
            NivelitoSleepyEye(center: .init(x: 70, y: 104))
                .stroke(Theme.outline, style: closedEyeStyle)
            NivelitoSleepyEye(center: .init(x: 130, y: 104))
                .stroke(Theme.outline, style: closedEyeStyle)
        }
    }

    /// Œil rond (r 12) + reflet blanc (r 4.2, décalé en haut à droite), qui cligne.
    private func openEye(cx: CGFloat) -> some View {
        ZStack {
            NivelitoEllipse(center: .init(x: cx, y: 104), r: 12).fill(Theme.outline)
            NivelitoEllipse(center: .init(x: cx + 4, y: 99), r: 4.2).fill(.white)
        }
        .scaleEffect(y: isBlinking ? 0.12 : 1,
                     anchor: UnitPoint(x: cx / 200, y: 104.0 / 200.0))
    }

    // MARK: - Bouche

    @ViewBuilder private var mouth: some View {
        switch effectiveExpression {
        case .happy, .wink:
            NivelitoMouth().stroke(Theme.outline, style: mouthStyle)
        case .encouraging:
            NivelitoBigSmileMouth().stroke(Theme.outline, style: mouthStyle)
        case .sleepy:
            NivelitoSmallMouth().stroke(Theme.outline, style: mouthStyle)
        case .joy:
            NivelitoOpenMouth().fill(Theme.outline)
        }
    }

    // MARK: - Clignement

    private var hasOpenEyes: Bool {
        switch effectiveExpression {
        case .happy, .encouraging, .wink: true
        case .joy, .sleepy: false
        }
    }

    // MARK: - Célébration

    /// Rebond de célébration : offset y −8 + oscillation ±4° en spring (~1 s au total).
    /// Suspend les micro-gestes le temps du rebond et remet leurs états à zéro
    /// (un geste qui serait en cours ne doit pas se superposer au wobble).
    private func celebrate() async {
        isCelebrating = true
        defer { isCelebrating = false }
        let spring = Animation.spring(response: 0.25, dampingFraction: 0.5)
        withAnimation(spring) {
            earWiggleDegrees = 0
            headTiltDegrees = 0
            eyeGlanceX = 0
        }
        microWink = false
        withAnimation(spring) { bounceOffsetY = -8; wobbleDegrees = 4 }
        try? await Task.sleep(nanoseconds: 250_000_000)
        withAnimation(spring) { wobbleDegrees = -4 }
        try? await Task.sleep(nanoseconds: 250_000_000)
        withAnimation(spring) { wobbleDegrees = 4 }
        try? await Task.sleep(nanoseconds: 250_000_000)
        withAnimation(spring) { wobbleDegrees = 0; bounceOffsetY = 0 }
    }

    /// Cligne des yeux toutes les 3–6 s (uniquement quand des yeux ronds sont visibles).
    private func blinkLoop() async {
        guard hasOpenEyes, !reduceMotion else { return }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64.random(in: 3_000_000_000...6_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.06)) { isBlinking = true }
            try? await Task.sleep(nanoseconds: 120_000_000)
            withAnimation(.easeOut(duration: 0.09)) { isBlinking = false }
        }
    }

    // MARK: - Micro-gestes d'idle

    private enum MicroGesture: CaseIterable {
        case earWiggle, headTilt, quickWink, glance
    }

    /// Toutes les 6–14 s (aléatoire), joue UN micro-geste tiré au sort.
    /// Jamais pendant une célébration ; rien sous Reduce Motion ; le premier
    /// tirage n'arrive qu'après 6 s minimum (splash/onboarding non perturbés).
    private func microGestureLoop() async {
        guard !reduceMotion else { return }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64.random(in: 6_000_000_000...14_000_000_000))
            guard !Task.isCancelled else { return }
            guard !isCelebrating else { continue }
            switch MicroGesture.allCases.randomElement() ?? .headTilt {
            case .earWiggle: await playEarWiggle()
            case .headTilt: await playHeadTilt()
            case .quickWink: await playQuickWink()
            case .glance: await playGlance()
            }
        }
    }

    /// Frémissement d'oreilles : 3 oscillations rapides ±6°, rotation miroir
    /// ancrée à la base de chaque oreille (voir le corps de la vue).
    private func playEarWiggle() async {
        let quick = Animation.easeInOut(duration: 0.09)
        for _ in 0..<3 {
            guard !Task.isCancelled, !isCelebrating else { return }
            withAnimation(quick) { earWiggleDegrees = 6 }
            try? await Task.sleep(nanoseconds: 90_000_000)
            withAnimation(quick) { earWiggleDegrees = -6 }
            try? await Task.sleep(nanoseconds: 90_000_000)
        }
        withAnimation(quick) { earWiggleDegrees = 0 }
    }

    /// Inclinaison de tête : ±3° (côté aléatoire) en spring, tenue brève, retour.
    private func playHeadTilt() async {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            headTiltDegrees = Bool.random() ? 3 : -3
        }
        try? await Task.sleep(nanoseconds: 450_000_000)
        guard !isCelebrating else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { headTiltDegrees = 0 }
    }

    /// Clin d'œil éclair : bascule sur .wink ~0,6 s puis retour — uniquement
    /// depuis happy/encouraging (les autres expressions restent intactes).
    private func playQuickWink() async {
        guard expression == .happy || expression == .encouraging else { return }
        microWink = true
        try? await Task.sleep(nanoseconds: 600_000_000)
        microWink = false
    }

    /// Regard de côté : les yeux glissent de ±6 pt (à l'échelle de référence 200,
    /// proportionnel à `size`) pendant ~0,8 s puis reviennent au centre.
    private func playGlance() async {
        let dx: CGFloat = (Bool.random() ? 6 : -6) * scale
        withAnimation(.easeInOut(duration: 0.18)) { eyeGlanceX = dx }
        try? await Task.sleep(nanoseconds: 800_000_000)
        guard !isCelebrating else { return }
        withAnimation(.easeInOut(duration: 0.25)) { eyeGlanceX = 0 }
    }
}

// MARK: - Previews

#Preview("Expressions") {
    HStack(spacing: 12) {
        VStack { NivelitoView(expression: .happy, size: 70); Text("happy").font(.caption2) }
        VStack { NivelitoView(expression: .joy, size: 70); Text("joy").font(.caption2) }
        VStack { NivelitoView(expression: .wink, size: 70); Text("wink").font(.caption2) }
        VStack { NivelitoView(expression: .sleepy, size: 70); Text("sleepy").font(.caption2) }
        VStack { NivelitoView(expression: .encouraging, size: 70); Text("encouraging").font(.caption2) }
    }
    .padding()
    .background(Theme.background)
}

#Preview("Avec bulle") {
    VStack(spacing: 24) {
        SpeechBubble(text: "Salut ! Moi c'est Nivelito 🧡 On y va tranquillement, à ton rythme.")
        NivelitoView(expression: .happy, size: 200)
    }
    .padding(32)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.background)
}
