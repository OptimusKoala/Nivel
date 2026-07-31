// Widgets/Views/WidgetNivelito.swift
// Nivelito STATIQUE pour le widget : mêmes formes que NivelitoView (Shared),
// aucune animation (un widget est un rendu figé), deux expressions seulement.

import SwiftUI

struct WidgetNivelito: View {
    let sleepy: Bool
    let palette: ThemePalette
    let size: CGFloat

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
            NivelitoEarLeft().fill(NivelitoColors.cream)
            NivelitoEarLeft().stroke(palette.outline, style: outlineStyle)
            NivelitoEarInnerLeft().fill(NivelitoColors.earBrown)
            NivelitoEarRight().fill(NivelitoColors.cream)
            NivelitoEarRight().stroke(palette.outline, style: outlineStyle)
            NivelitoEarInnerRight().fill(NivelitoColors.earBrown)

            NivelitoHead().fill(NivelitoColors.fur)
            NivelitoHead().stroke(palette.outline, style: outlineStyle)

            NivelitoEllipse(center: .init(x: 45, y: 134), rx: 19, ry: 16).fill(NivelitoColors.cheekBrown)
            NivelitoEllipse(center: .init(x: 155, y: 134), rx: 19, ry: 16).fill(NivelitoColors.cheekBrown)
            NivelitoMuzzle().fill(NivelitoColors.cream)

            NivelitoBrowLeft().fill(NivelitoColors.cream)
            NivelitoBrowLeft().stroke(NivelitoColors.cream, style: StrokeStyle(lineWidth: 4 * scale, lineJoin: .round))
            NivelitoBrowRight().fill(NivelitoColors.cream)
            NivelitoBrowRight().stroke(NivelitoColors.cream, style: StrokeStyle(lineWidth: 4 * scale, lineJoin: .round))

            NivelitoEllipse(center: .init(x: 62, y: 122), rx: 8, ry: 5)
                .fill(NivelitoColors.blushPink.opacity(0.85))
            NivelitoEllipse(center: .init(x: 138, y: 122), rx: 8, ry: 5)
                .fill(NivelitoColors.blushPink.opacity(0.85))

            if sleepy {
                NivelitoSleepyEye(center: .init(x: 70, y: 104))
                    .stroke(palette.outline, style: closedEyeStyle)
                NivelitoSleepyEye(center: .init(x: 130, y: 104))
                    .stroke(palette.outline, style: closedEyeStyle)
            } else {
                NivelitoEllipse(center: .init(x: 70, y: 104), r: 12).fill(palette.outline)
                NivelitoEllipse(center: .init(x: 74, y: 99), r: 4.2).fill(.white)
                NivelitoEllipse(center: .init(x: 130, y: 104), r: 12).fill(palette.outline)
                NivelitoEllipse(center: .init(x: 134, y: 99), r: 4.2).fill(.white)
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
