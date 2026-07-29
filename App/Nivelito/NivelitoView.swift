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

    @State private var breathe = false
    @State private var isBlinking = false

    // Palette du SVG (le contour/yeux/truffe/bouche viennent de Theme.outline).
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
            // Oreilles (fill crème + contour), intérieurs bruns
            NivelitoEarLeft().fill(cream)
            NivelitoEarLeft().stroke(Theme.outline, style: outlineStyle)
            NivelitoEarRight().fill(cream)
            NivelitoEarRight().stroke(Theme.outline, style: outlineStyle)
            NivelitoEarInnerLeft().fill(earBrown)
            NivelitoEarInnerRight().fill(earBrown)

            // Tête (fill orange + contour)
            NivelitoHead().fill(Theme.orange)
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

            // Yeux (dépendent de l'expression)
            eyes
                .transition(.opacity.combined(with: .scale(scale: 0.85)))

            // Truffe
            NivelitoNose().fill(Theme.outline)

            // Bouche (dépend de l'expression)
            mouth
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: expressionKey)
        .frame(width: size, height: size)
        .scaleEffect(y: breathe ? 1.02 : 0.98, anchor: .bottom)
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
        .task(id: expressionKey) { await blinkLoop() }
        .accessibilityLabel("Nivelito")
    }

    /// Clé stable pour animer les changements d'expression.
    private var expressionKey: Int {
        switch expression {
        case .happy: 0
        case .joy: 1
        case .wink: 2
        case .sleepy: 3
        case .encouraging: 4
        }
    }

    // MARK: - Yeux

    @ViewBuilder private var eyes: some View {
        switch expression {
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
        switch expression {
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
        switch expression {
        case .happy, .encouraging, .wink: true
        case .joy, .sleepy: false
        }
    }

    /// Cligne des yeux toutes les 3–6 s (uniquement quand des yeux ronds sont visibles).
    private func blinkLoop() async {
        guard hasOpenEyes else { return }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64.random(in: 3_000_000_000...6_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.06)) { isBlinking = true }
            try? await Task.sleep(nanoseconds: 120_000_000)
            withAnimation(.easeOut(duration: 0.09)) { isBlinking = false }
        }
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
