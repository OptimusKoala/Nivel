// Widgets/Views/WidgetNivelito.swift
// Nivelito STATIQUE pour le widget : mêmes formes que NivelitoView (Shared),
// aucune animation (un widget est un rendu figé), deux expressions seulement.
//
// v1.13 — les couleurs de la mascotte passent par une `NivelitoInk` au lieu d'être
// lues directement dans `NivelitoColors`. C'est ce qui permet au mode teinté (spec
// §3.3) de réécrire le dessin en alpha sans dupliquer ce corps de vue : une variante
// séparée divergerait au premier changement de dessin.

import SwiftUI

struct WidgetNivelito: View {
    let sleepy: Bool
    let palette: ThemePalette
    let size: CGFloat
    /// Encres du dessin — `.full` par défaut, `.tinted` en mode accentué.
    var ink: NivelitoInk = .full

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
            NivelitoEarLeft().fill(ink.cream)
            NivelitoEarLeft().stroke(palette.outline, style: outlineStyle)
            NivelitoEarInnerLeft().fill(ink.earBrown)
            NivelitoEarRight().fill(ink.cream)
            NivelitoEarRight().stroke(palette.outline, style: outlineStyle)
            NivelitoEarInnerRight().fill(ink.earBrown)

            NivelitoHead().fill(ink.fur)
            NivelitoHead().stroke(palette.outline, style: outlineStyle)

            NivelitoEllipse(center: .init(x: 45, y: 134), rx: 19, ry: 16).fill(ink.cheekBrown)
            NivelitoEllipse(center: .init(x: 155, y: 134), rx: 19, ry: 16).fill(ink.cheekBrown)
            NivelitoMuzzle().fill(ink.cream)

            NivelitoBrowLeft().fill(ink.cream)
            NivelitoBrowLeft().stroke(ink.cream, style: StrokeStyle(lineWidth: 4 * scale, lineJoin: .round))
            NivelitoBrowRight().fill(ink.cream)
            NivelitoBrowRight().stroke(ink.cream, style: StrokeStyle(lineWidth: 4 * scale, lineJoin: .round))

            NivelitoEllipse(center: .init(x: 62, y: 122), rx: 8, ry: 5)
                .fill(ink.blushPink.opacity(0.85))
            NivelitoEllipse(center: .init(x: 138, y: 122), rx: 8, ry: 5)
                .fill(ink.blushPink.opacity(0.85))

            if sleepy {
                NivelitoSleepyEye(center: .init(x: 70, y: 104))
                    .stroke(palette.outline, style: closedEyeStyle)
                NivelitoSleepyEye(center: .init(x: 130, y: 104))
                    .stroke(palette.outline, style: closedEyeStyle)
            } else {
                NivelitoEllipse(center: .init(x: 70, y: 104), r: 12).fill(palette.outline)
                NivelitoEllipse(center: .init(x: 74, y: 99), r: 4.2).fill(ink.eyeHighlight)
                NivelitoEllipse(center: .init(x: 130, y: 104), r: 12).fill(palette.outline)
                NivelitoEllipse(center: .init(x: 134, y: 99), r: 4.2).fill(ink.eyeHighlight)
            }

            NivelitoNose().fill(palette.outline)

            if sleepy {
                NivelitoSmallMouth().stroke(palette.outline, style: mouthStyle)
            } else {
                NivelitoMouth().stroke(palette.outline, style: mouthStyle)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Previews

#Preview("Expressions") {
    HStack(spacing: 16) {
        VStack { WidgetNivelito(sleepy: false, palette: .creme, size: 72); Text("happy").font(.caption2) }
        VStack { WidgetNivelito(sleepy: true, palette: .creme, size: 72); Text("sleepy").font(.caption2) }
    }
    .padding()
    .background(ThemePalette.creme.background)
}
