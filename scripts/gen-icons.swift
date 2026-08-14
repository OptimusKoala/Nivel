// scripts/gen-icons.swift
// Source UNIQUE des icônes cozy (spec icônes §3). Exécution : swift scripts/gen-icons.swift
// Émet : App/Assets.xcassets/Icons/<nom>.imageset/<nom>.pdf (template, vecteur préservé)
//        design/icons/contact-sheet.png (relecture visuelle, 25pt et 50pt)
// Style : canvas 28×28, traits 2,4 à bouts ronds, formes dodues (démo validée le 31/07/2026).

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let SIZE: CGFloat = 28
let STROKE: CGFloat = 2.4

// MARK: - Aides géométrie (coordonnées y VERS LE BAS, comme un SVG)

func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
}
func pill(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGPath { rr(x, y, w, h, min(w, h) / 2) }
func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r), transform: nil)
}
func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

func strokePath(_ ctx: CGContext, _ path: CGPath, width: CGFloat = STROKE) {
    ctx.addPath(path)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
}
func fillPath(_ ctx: CGContext, _ path: CGPath, evenOdd: Bool = false) {
    ctx.addPath(path)
    evenOdd ? ctx.fillPath(using: .evenOdd) : ctx.fillPath()
}

// MARK: - Aides géométrie (vague 2)

/// Ellipse tournée : feuilles de menthe, mèches de cheveux, empreintes.
func blob(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ angle: CGFloat) -> CGPath {
    var t = CGAffineTransform(translationX: cx, y: cy).rotated(by: angle)
    return CGPath(ellipseIn: CGRect(x: -rx, y: -ry, width: 2 * rx, height: 2 * ry), transform: &t)
}

/// Étoile à `points` branches. Angle de départ -90° : la première pointe est vers le HAUT.
func starPath(_ cx: CGFloat, _ cy: CGFloat, points: Int, r: CGFloat, inner: CGFloat) -> CGMutablePath {
    let p = CGMutablePath()
    for i in 0..<(points * 2) {
        let radius = i.isMultiple(of: 2) ? r : inner
        let a = -CGFloat.pi / 2 + CGFloat(i) * .pi / CGFloat(points)
        let pt = P(cx + radius * cos(a), cy + radius * sin(a))
        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
    }
    p.closeSubpath()
    return p
}

/// Feuille pointue aux deux bouts, de la base `b` à la pointe `t`, renflée de `bulge`.
/// Deux quadratiques symétriques : une ellipse tournée donne un bâtonnet, pas une feuille.
func leafShape(_ bx: CGFloat, _ by: CGFloat, _ tx: CGFloat, _ ty: CGFloat, bulge: CGFloat) -> CGMutablePath {
    let mx = (bx + tx) / 2, my = (by + ty) / 2
    let dx = tx - bx, dy = ty - by
    let len = max(sqrt(dx * dx + dy * dy), 0.001)
    let nx = -dy / len, ny = dx / len
    let p = CGMutablePath()
    p.move(to: P(bx, by))
    p.addQuadCurve(to: P(tx, ty), control: P(mx + nx * bulge * 2, my + ny * bulge * 2))
    p.addQuadCurve(to: P(bx, by), control: P(mx - nx * bulge * 2, my - ny * bulge * 2))
    p.closeSubpath()
    return p
}

/// Croissant : disque `r` en (cx, cy) MOINS un disque `hole` décalé de (dx, dy).
/// Sert à la lune et à la barbe — un croissant est plus dodu qu'un arc épaissi.
///
/// Construit en DEUX ARCS, et pas en empilant les deux disques pour un remplissage
/// even-odd : even-odd donne la différence SYMÉTRIQUE, donc la part du trou qui dépasse du
/// disque se remplit elle aussi. Tant que le trou reste petit et centré, ça passe presque ;
/// dès qu'il grandit — ce qu'exige un croissant mince — on obtient une masse pleine avec
/// une lentille évidée au milieu. Diagnostiqué au simulateur après deux fausses pistes.
///
/// L'arc du disque part d'une corne, contourne par le côté opposé au trou, et l'arc du trou
/// revient en creusant vers l'intérieur. L'angle balayé par le disque vaut 2·(π − θ) avec
/// cos θ = a/r : c'est lui qui décide si on lit « croissant » (~160°) ou « anneau à
/// encoche » (~220°). Le trou doit couper le disque, sinon il n'y a pas de cornes.
func crescent(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat,
              dx: CGFloat, dy: CGFloat, hole: CGFloat) -> CGMutablePath {
    let d = (dx * dx + dy * dy).squareRoot()
    let phi = atan2(dy, dx)
    let a = (d * d + r * r - hole * hole) / (2 * d)      // distance signée du centre à la corde
    guard d > 0, abs(a) <= r else { fatalError("crescent : les deux disques ne se coupent pas") }
    let theta = acos(a / r)                             // demi-angle des cornes, vu du disque
    let b = a - d                                       // idem, vu du trou
    let thetaHole = acos(max(-1, min(1, b / hole)))
    let p = CGMutablePath()
    p.addArc(center: P(cx, cy), radius: r,
             startAngle: phi + theta, endAngle: phi + 2 * .pi - theta, clockwise: false)
    p.addArc(center: P(cx + dx, cy + dy), radius: hole,
             startAngle: phi - thetaHole, endAngle: phi + thetaHole - 2 * .pi, clockwise: true)
    p.closeSubpath()
    return p
}

/// Fait tourner un tracé autour du centre du canvas.
func rotated(_ path: CGPath, degrees: CGFloat) -> CGPath {
    var t = CGAffineTransform(translationX: SIZE / 2, y: SIZE / 2)
        .rotated(by: degrees * .pi / 180)
        .translatedBy(x: -SIZE / 2, y: -SIZE / 2)
    return path.copy(using: &t) ?? path
}

/// Recentre la boîte englobante d'un tracé dans le canvas. Indispensable au croissant, qui
/// n'occupe QU'UN CÔTÉ de son disque : sans ça, la lune s'affichait en filet collé au bord
/// gauche de sa case, deux fois plus petite que les glyphes voisins.
func centered(_ path: CGPath) -> CGPath {
    let b = path.boundingBoxOfPath
    var t = CGAffineTransform(translationX: SIZE / 2 - b.midX, y: SIZE / 2 - b.midY)
    return path.copy(using: &t) ?? path
}

/// Pointe de flèche pleine. `angle` = direction vers laquelle la pointe regarde.
func arrowHead(_ ctx: CGContext, tip: CGPoint, angle: CGFloat,
               length: CGFloat = 4.2, half: CGFloat = 2.7) {
    let back = P(tip.x - length * cos(angle), tip.y - length * sin(angle))
    let nx = -sin(angle), ny = cos(angle)
    let h = CGMutablePath()
    h.move(to: tip)
    h.addLine(to: P(back.x + half * nx, back.y + half * ny))
    h.addLine(to: P(back.x - half * nx, back.y - half * ny))
    h.closeSubpath()
    fillPath(ctx, h)
    strokePath(ctx, h, width: 1.4)   // fill + stroke = coins arrondis (comme icon_play)
}

// MARK: - Tracés partagés

func houseSilhouette() -> CGMutablePath {
    let p = CGMutablePath()
    p.move(to: P(14, 4.5))
    p.addLine(to: P(24, 12.8)); p.addLine(to: P(22, 12.8))
    p.addLine(to: P(22, 21))
    p.addCurve(to: P(19, 24), control1: P(22, 22.7), control2: P(20.7, 24))
    p.addLine(to: P(9, 24))
    p.addCurve(to: P(6, 21), control1: P(7.3, 24), control2: P(6, 22.7))
    p.addLine(to: P(6, 12.8)); p.addLine(to: P(4, 12.8))
    p.closeSubpath()
    return p
}
func doorPath(closed: Bool) -> CGMutablePath {
    let p = CGMutablePath()
    p.move(to: P(11.8, 24))
    p.addLine(to: P(11.8, 19))
    p.addCurve(to: P(14, 16.8), control1: P(11.8, 17.8), control2: P(12.8, 16.8))
    p.addCurve(to: P(16.2, 19), control1: P(15.2, 16.8), control2: P(16.2, 17.8))
    p.addLine(to: P(16.2, 24))
    if closed { p.closeSubpath() }
    return p
}
func bowlPath() -> CGMutablePath {
    let p = CGMutablePath()
    p.move(to: P(5, 14.5)); p.addLine(to: P(23, 14.5))
    p.addCurve(to: P(16.5, 23), control1: P(23, 19.5), control2: P(20.5, 23))
    p.addLine(to: P(11.5, 23))
    p.addCurve(to: P(5, 14.5), control1: P(7.5, 23), control2: P(5, 19.5))
    p.closeSubpath()
    return p
}
func steam(_ ctx: CGContext) {
    let s = CGMutablePath()
    s.move(to: P(11, 10.5)); s.addCurve(to: P(11.5, 6), control1: P(10, 9), control2: P(10.5, 7.3))
    s.move(to: P(16.5, 10.5)); s.addCurve(to: P(17, 6), control1: P(15.5, 9), control2: P(16, 7.3))
    strokePath(ctx, s, width: 2.2)
}
func leafLeft() -> CGMutablePath {
    let p = CGMutablePath()
    p.move(to: P(14, 13.5))
    p.addCurve(to: P(7.6, 7.6), control1: P(14, 9.8), control2: P(11.2, 7.6))
    p.addCurve(to: P(14, 13.5), control1: P(7.6, 11.2), control2: P(10.2, 13.5))
    p.closeSubpath(); return p
}
func leafRight() -> CGMutablePath {
    // Feuille droite légèrement élargie vs le plan (gate visuel : équilibre avec la gauche).
    let p = CGMutablePath()
    p.move(to: P(14, 16))
    p.addCurve(to: P(20.8, 10.4), control1: P(14, 12.4), control2: P(16.6, 10.4))
    p.addCurve(to: P(14, 16), control1: P(20.8, 14.4), control2: P(17.6, 16.4))
    p.closeSubpath(); return p
}
func sproutLines(_ ctx: CGContext) {
    let stem = CGMutablePath()
    stem.move(to: P(14, 24)); stem.addCurve(to: P(14, 13.5), control1: P(14, 19.5), control2: P(14, 17))
    strokePath(ctx, stem)
    let ground = CGMutablePath(); ground.move(to: P(9, 24)); ground.addLine(to: P(19, 24))
    strokePath(ctx, ground)
}
func cupPath() -> CGMutablePath {
    let p = CGMutablePath()
    p.move(to: P(9, 5)); p.addLine(to: P(19, 5))
    p.addCurve(to: P(20, 6), control1: P(19.6, 5), control2: P(20, 5.4))
    p.addCurve(to: P(14, 14.5), control1: P(20, 10.5), control2: P(18.3, 14.5))
    p.addCurve(to: P(8, 6), control1: P(9.7, 14.5), control2: P(8, 10.5))
    p.addCurve(to: P(9, 5), control1: P(8, 5.4), control2: P(8.4, 5))
    p.closeSubpath(); return p
}
func trophyHandles(_ ctx: CGContext) {
    let h = CGMutablePath()
    h.move(to: P(8.2, 6.6)); h.addLine(to: P(5.6, 6.6))
    h.addCurve(to: P(9.4, 11.9), control1: P(5.6, 9.9), control2: P(7, 11.4))
    h.move(to: P(19.8, 6.6)); h.addLine(to: P(22.4, 6.6))
    h.addCurve(to: P(18.6, 11.9), control1: P(22.4, 9.9), control2: P(21, 11.4))
    strokePath(ctx, h, width: 2.2)
}
func trophyBase() -> CGMutablePath {
    let p = CGMutablePath()
    p.move(to: P(10.6, 21.4))
    p.addCurve(to: P(14, 18.1), control1: P(10.6, 19.6), control2: P(12.1, 18.1))
    p.addCurve(to: P(17.4, 21.4), control1: P(15.9, 18.1), control2: P(17.4, 19.6))
    p.addLine(to: P(17.4, 22.4)); p.addLine(to: P(10.6, 22.4))
    p.closeSubpath(); return p
}
func trophyStem(_ ctx: CGContext) {
    let s = CGMutablePath(); s.move(to: P(14, 14.5)); s.addLine(to: P(14, 17.8))
    strokePath(ctx, s)
}

/// Corps, barre d'en-tête et anneaux : partagés par les deux calendriers, qui ne
/// diffèrent QUE par la densité des pastilles (paliers 7 jours vs 30 jours, spec §3.1).
func calendarFrame(_ ctx: CGContext) {
    strokePath(ctx, rr(4.2, 7.4, 19.6, 16.2, 3.4))
    let bar = CGMutablePath(); bar.move(to: P(4.2, 12.6)); bar.addLine(to: P(23.8, 12.6))
    strokePath(ctx, bar, width: 2.2)
    let rings = CGMutablePath()
    rings.move(to: P(9.6, 4.6)); rings.addLine(to: P(9.6, 8.2))
    rings.move(to: P(18.4, 4.6)); rings.addLine(to: P(18.4, 8.2))
    strokePath(ctx, rings, width: 2.2)
}

func calendarDots(_ ctx: CGContext, ys: [CGFloat], r: CGFloat) {
    for y in ys {
        for x in [CGFloat(9.2), 14, 18.8] { fillPath(ctx, circle(x, y, r)) }
    }
}

/// Tête et épaules : partagées par les deux avatars, qui ne diffèrent QUE par la
/// chevelure. Monochromes et teintées, elles ne figent aucune carnation (spec §3.2).
func avatarBust(_ ctx: CGContext) {
    strokePath(ctx, circle(14, 10.4, 5.6))
    let shoulders = CGMutablePath()
    shoulders.move(to: P(5.2, 23.6))
    shoulders.addCurve(to: P(22.8, 23.6), control1: P(5.2, 17.2), control2: P(22.8, 17.2))
    strokePath(ctx, shoulders)
}

// MARK: - Les 54 glyphes

let glyphs: [(name: String, draw: (CGContext) -> Void)] = [
    // UNE silhouette canonique pour la paire (retour Michaël : structure toit-chapeau
    // vs masse pleine lisait comme deux maisons) : le contour est LE tracé du plein.
    ("tab_home", { ctx in
        strokePath(ctx, houseSilhouette())
        strokePath(ctx, doorPath(closed: false), width: 2.2)
    }),
    ("tab_home_fill", { ctx in
        let p = houseSilhouette()
        // Porte fermée PILE sur le bord inférieur (y = 24) : le trou even-odd s'ouvre
        // sur le bord sans déborder dessous (un dépassement crée un îlot rempli).
        p.addPath(doorPath(closed: true))
        fillPath(ctx, p, evenOdd: true)
        strokePath(ctx, houseSilhouette())   // même poids de contour que la version outline
    }),
    ("tab_meals", { ctx in strokePath(ctx, bowlPath()); steam(ctx) }),
    ("tab_meals_fill", { ctx in
        fillPath(ctx, bowlPath()); strokePath(ctx, bowlPath())   // même silhouette que le contour
        steam(ctx)
    }),
    ("tab_sport", { ctx in
        // Trait 2,6 (vs 2,4 ailleurs) : l'haltère était optiquement le plus léger des 5 (gate visuel).
        strokePath(ctx, rr(4, 9.5, 4.5, 9, 2.25), width: 2.6)
        strokePath(ctx, rr(19.5, 9.5, 4.5, 9, 2.25), width: 2.6)
        let bar = CGMutablePath(); bar.move(to: P(8.5, 14)); bar.addLine(to: P(19.5, 14))
        strokePath(ctx, bar, width: 2.6)
    }),
    ("tab_sport_fill", { ctx in
        // MÊMES rects et barre que tab_sport, remplis sous les mêmes traits (2,6).
        for r in [rr(4, 9.5, 4.5, 9, 2.25), rr(19.5, 9.5, 4.5, 9, 2.25)] {
            fillPath(ctx, r); strokePath(ctx, r, width: 2.6)
        }
        let bar = CGMutablePath(); bar.move(to: P(8.5, 14)); bar.addLine(to: P(19.5, 14))
        strokePath(ctx, bar, width: 2.6)
    }),
    ("tab_progress", { ctx in
        strokePath(ctx, leafLeft(), width: 2.2)
        strokePath(ctx, leafRight(), width: 2.2)
        sproutLines(ctx)
    }),
    ("tab_progress_fill", { ctx in
        for leaf in [leafLeft(), leafRight()] {
            fillPath(ctx, leaf); strokePath(ctx, leaf, width: 2.2)   // même silhouette que le contour
        }
        sproutLines(ctx)
    }),
    ("tab_quests", { ctx in
        strokePath(ctx, cupPath()); trophyHandles(ctx); trophyStem(ctx)
        strokePath(ctx, trophyBase(), width: 2.2)
    }),
    ("tab_quests_fill", { ctx in
        // MÊMES tracés que tab_quests, remplis sous les mêmes traits.
        fillPath(ctx, cupPath()); strokePath(ctx, cupPath())
        trophyHandles(ctx); trophyStem(ctx)
        fillPath(ctx, trophyBase()); strokePath(ctx, trophyBase(), width: 2.2)
    }),
    ("icon_settings", { ctx in
        strokePath(ctx, circle(14, 14, 5.6))
        // Dents ATTACHÉES à l'anneau (gate visuel : détachées, ça lisait "soleil").
        for i in 0..<8 {
            let a = CGFloat(i) * .pi / 4
            let stub = CGMutablePath()
            stub.move(to: P(14 + 6.6 * cos(a), 14 + 6.6 * sin(a)))
            stub.addLine(to: P(14 + 9.0 * cos(a), 14 + 9.0 * sin(a)))
            strokePath(ctx, stub)
        }
        fillPath(ctx, circle(14, 14, 1.7))
    }),
    ("icon_check", { ctx in
        let check = CGMutablePath()
        check.move(to: P(9.2, 14.4)); check.addLine(to: P(12.7, 17.9)); check.addLine(to: P(18.9, 10.9))
        let strokedCheck = check.copy(strokingWithWidth: 2.8, lineCap: .round, lineJoin: .round, miterLimit: 10)
        let seal = CGMutablePath()
        seal.addPath(circle(14, 14, 10.5))
        seal.addPath(strokedCheck)
        fillPath(ctx, seal, evenOdd: true)   // coche évidée dans le sceau
    }),
    ("icon_play", { ctx in
        let t = CGMutablePath()
        t.move(to: P(10.6, 7.6)); t.addLine(to: P(20.8, 14)); t.addLine(to: P(10.6, 20.4))
        t.closeSubpath()
        fillPath(ctx, t)
        strokePath(ctx, t, width: 3)         // fill + stroke même couleur = coins arrondis
    }),
    ("icon_pause", { ctx in
        fillPath(ctx, pill(9.4, 7.6, 3.6, 12.8))
        fillPath(ctx, pill(15, 7.6, 3.6, 12.8))
    }),
    ("icon_restart", { ctx in
        // Arc ouvert en haut à droite (gap ~70°), pointe de flèche tangente au départ.
        let c = P(14, 14.6); let r: CGFloat = 7
        let start: CGFloat = -0.35 * .pi   // ~-63° (y vers le bas : haut-droit)
        let end: CGFloat = 1.15 * .pi
        let arc = CGMutablePath()
        arc.addArc(center: c, radius: r, startAngle: start, endAngle: end, clockwise: false)
        strokePath(ctx, arc)
        let tip = P(c.x + r * cos(start), c.y + r * sin(start))
        let tangent = start - .pi / 2      // direction "avant" de l'arc au départ
        let head = CGMutablePath()
        head.move(to: P(tip.x + 4.2 * cos(tangent), tip.y + 4.2 * sin(tangent)))
        head.addLine(to: P(tip.x + 2.6 * cos(start), tip.y + 2.6 * sin(start)))
        head.addLine(to: P(tip.x - 2.6 * cos(start), tip.y - 2.6 * sin(start)))
        head.closeSubpath()
        fillPath(ctx, head)
        strokePath(ctx, head, width: 1.6)
    }),

    // MARK: Vague 2 — pas et mouvement

    ("icon_footprint", { ctx in
        // UNE empreinte, là où la basket du premier jet ne convainquait pas (retour
        // Michaël) : la semelle plus trois orteils ne se confond avec rien, et la paire
        // avec icon_footprints donne un palier lisible sans changer de métaphore.
        fillPath(ctx, blob(13.6, 16.6, 4.2, 6.0, -0.06))
        fillPath(ctx, circle(11.2, 7.6, 1.6))
        fillPath(ctx, circle(14.8, 6.8, 1.5))
        fillPath(ctx, circle(18.0, 8.2, 1.35))
    }),
    ("icon_boot", { ctx in
        let upper = CGMutablePath()
        upper.move(to: P(6.4, 17.4))
        upper.addLine(to: P(6.4, 7.6))
        upper.addCurve(to: P(13.2, 7.6), control1: P(6.4, 5.6), control2: P(13.2, 5.6))
        upper.addLine(to: P(13.2, 13.4))
        upper.addCurve(to: P(22.8, 17.4), control1: P(17.6, 13.4), control2: P(22.8, 14.2))
        upper.closeSubpath()
        strokePath(ctx, upper)
        fillPath(ctx, pill(5.4, 17.2, 18.2, 3.8))
        let laces = CGMutablePath()
        laces.move(to: P(7.6, 10.0)); laces.addLine(to: P(12.0, 10.0))
        laces.move(to: P(7.6, 12.8)); laces.addLine(to: P(12.0, 12.8))
        strokePath(ctx, laces, width: 1.6)
    }),
    ("icon_footprints", { ctx in
        // Deux empreintes plutôt qu'un marcheur : à 25pt, un marcheur et un coureur se
        // confondent, une empreinte ne se confond avec rien.
        fillPath(ctx, blob(9.6, 18.2, 3.1, 4.9, -0.16))
        fillPath(ctx, circle(11.8, 12.4, 1.5))
        fillPath(ctx, blob(18.4, 10.0, 3.1, 4.9, 0.16))
        fillPath(ctx, circle(16.2, 4.6, 1.5))
    }),
    ("icon_runner", { ctx in
        fillPath(ctx, circle(11.6, 6.2, 2.6))
        let torso = CGMutablePath()
        torso.move(to: P(12.6, 8.8))
        torso.addCurve(to: P(14.8, 15.0), control1: P(13.4, 10.6), control2: P(14.4, 13.0))
        strokePath(ctx, torso)
        let legs = CGMutablePath()
        legs.move(to: P(14.8, 15.0)); legs.addLine(to: P(19.0, 17.2)); legs.addLine(to: P(18.0, 22.6))
        legs.move(to: P(14.8, 15.0)); legs.addLine(to: P(10.6, 18.4)); legs.addLine(to: P(6.4, 20.2))
        strokePath(ctx, legs)
        let arms = CGMutablePath()
        arms.move(to: P(8.6, 13.4)); arms.addLine(to: P(12.6, 10.6)); arms.addLine(to: P(17.4, 12.6))
        strokePath(ctx, arms, width: 2.2)
    }),
    ("icon_map", { ctx in
        let p = CGMutablePath()
        p.move(to: P(4.2, 8.2)); p.addLine(to: P(10.6, 6.0))
        p.addLine(to: P(17.4, 9.0)); p.addLine(to: P(23.8, 6.8))
        p.addLine(to: P(23.8, 20.0)); p.addLine(to: P(17.4, 22.2))
        p.addLine(to: P(10.6, 19.2)); p.addLine(to: P(4.2, 21.4))
        p.closeSubpath()
        strokePath(ctx, p)
        let folds = CGMutablePath()
        folds.move(to: P(10.6, 6.0)); folds.addLine(to: P(10.6, 19.2))
        folds.move(to: P(17.4, 9.0)); folds.addLine(to: P(17.4, 22.2))
        strokePath(ctx, folds, width: 2.0)
    }),
    ("icon_flame", { ctx in
        // Ce qui fait une flamme et pas une goutte : une POINTE SECONDAIRE à mi-hauteur
        // à gauche, et le CREUX qui la sépare de la pointe principale. Une simple épaule
        // rentrante ne suffisait pas — deux planches de suite se lisaient « goutte ».
        let outer = CGMutablePath()
        outer.move(to: P(14.4, 3.6))                                                        // pointe principale
        outer.addCurve(to: P(20.8, 14.6), control1: P(15.4, 7.6), control2: P(20.8, 10.4))  // flanc droit
        outer.addCurve(to: P(14.0, 23.8), control1: P(20.8, 20.0), control2: P(18.0, 23.8)) // bulbe droit
        outer.addCurve(to: P(8.0, 17.4), control1: P(10.2, 23.8), control2: P(8.0, 21.4))   // bulbe gauche
        outer.addCurve(to: P(9.6, 10.2), control1: P(8.0, 14.4), control2: P(9.0, 12.6))    // pointe secondaire
        outer.addCurve(to: P(13.0, 14.4), control1: P(11.2, 13.0), control2: P(12.4, 12.2)) // le creux
        outer.addCurve(to: P(14.4, 3.6), control1: P(14.2, 10.6), control2: P(13.4, 6.4))
        strokePath(ctx, outer)
        let core = CGMutablePath()
        core.move(to: P(14.8, 14.2))
        core.addCurve(to: P(17.0, 19.0), control1: P(16.0, 15.6), control2: P(17.0, 17.0))
        core.addCurve(to: P(12.2, 19.2), control1: P(17.0, 21.2), control2: P(12.2, 21.4))
        core.addCurve(to: P(14.8, 14.2), control1: P(12.2, 17.0), control2: P(13.6, 15.6))
        fillPath(ctx, core)
    }),
    ("icon_repeat", { ctx in
        // Deux arcs et DEUX pointes, contre un arc et une seule pointe pour icon_restart :
        // les deux ne coexistent jamais (timer vs grille de badges), mais la boucle fermée
        // à deux têtes se lit « ça recommence », pas « rejouer ».
        let c = P(14, 14); let r: CGFloat = 7.6
        let top = CGMutablePath()
        top.addArc(center: c, radius: r, startAngle: 200 * .pi / 180,
                   endAngle: 340 * .pi / 180, clockwise: false)
        strokePath(ctx, top)
        let bottom = CGMutablePath()
        bottom.addArc(center: c, radius: r, startAngle: 20 * .pi / 180,
                      endAngle: 160 * .pi / 180, clockwise: false)
        strokePath(ctx, bottom)
        for (end, sweep) in [(340.0, 90.0), (160.0, 90.0)] {
            let a = CGFloat(end) * .pi / 180
            arrowHead(ctx, tip: P(c.x + r * cos(a), c.y + r * sin(a)),
                      angle: a + CGFloat(sweep) * .pi / 180, length: 4.0, half: 2.5)
        }
    }),

    // MARK: Vague 2 — journal

    ("icon_calendar", { ctx in calendarFrame(ctx); calendarDots(ctx, ys: [18.4], r: 1.35) }),
    ("icon_calendar_month", { ctx in calendarFrame(ctx); calendarDots(ctx, ys: [17.0, 21.0], r: 1.2) }),
    ("icon_notebook", { ctx in
        strokePath(ctx, rr(6.6, 4.6, 14.8, 18.8, 3.2))
        let spine = CGMutablePath(); spine.move(to: P(10.2, 4.6)); spine.addLine(to: P(10.2, 23.4))
        strokePath(ctx, spine, width: 2.0)
        let lines = CGMutablePath()
        lines.move(to: P(13.2, 11.0)); lines.addLine(to: P(18.6, 11.0))
        lines.move(to: P(13.2, 15.4)); lines.addLine(to: P(18.6, 15.4))
        strokePath(ctx, lines, width: 1.8)
    }),
    ("icon_meal_log", { ctx in
        // NOURRITURE + ÉCRITURE (direction Michaël) : c'est l'action « logger un repas »
        // qu'il faut dire, pas « un repas » ni « écrire ». Un stylo nu ne la portait pas.
        //
        // Composition CÔTE À CÔTE — pomme à gauche sur toute la hauteur, crayon en diagonale
        // à droite — et non un crayon posé en pastille dans un coin : côte à côte, chacun
        // garde sa pleine taille et reste lisible à 25 pt. Les deux formes ne se CHEVAUCHENT
        // PAS, et ce n'est pas un choix esthétique : un PDF template est monochrome, rien ne
        // peut en masquer une autre, un crayon passant sur la pomme fusionnerait avec elle.
        let apple = CGMutablePath()
        apple.move(to: P(10.4, 9.4))                                                        // creux du sommet
        apple.addCurve(to: P(4.6, 13.8), control1: P(7.8, 7.6), control2: P(4.6, 10.4))     // lobe gauche
        apple.addCurve(to: P(10.4, 20.4), control1: P(4.6, 17.4), control2: P(7.2, 20.4))
        apple.addCurve(to: P(16.2, 13.8), control1: P(13.6, 20.4), control2: P(16.2, 17.4))
        apple.addCurve(to: P(10.4, 9.4), control1: P(16.2, 10.4), control2: P(13.0, 7.6))   // lobe droit
        strokePath(ctx, apple)
        let stem = CGMutablePath()
        stem.move(to: P(10.6, 9.2)); stem.addLine(to: P(11.2, 5.8))
        strokePath(ctx, stem, width: 2.0)
        fillPath(ctx, leafShape(11.2, 6.6, 15.0, 5.0, bulge: 1.2))
        // Crayon : corps en parallélogramme, pointe en bas, bague aux trois quarts.
        let pencil = CGMutablePath()
        pencil.move(to: P(17.4, 23.0))                 // pointe
        pencil.addLine(to: P(16.49, 19.97))
        pencil.addLine(to: P(20.69, 7.04))
        pencil.addLine(to: P(24.11, 8.16))
        pencil.addLine(to: P(19.91, 21.09))
        pencil.closeSubpath()
        strokePath(ctx, pencil, width: 2.1)
        let band = CGMutablePath()
        band.move(to: P(17.72, 15.16)); band.addLine(to: P(21.14, 16.28))
        strokePath(ctx, band, width: 1.4)
    }),
    ("icon_book", { ctx in
        for mirrored in [false, true] {
            let s: CGFloat = mirrored ? -1 : 1
            let p = CGMutablePath()
            p.move(to: P(14, 10.0))
            p.addCurve(to: P(14 + s * 9.4, 8.0),
                       control1: P(14 + s * 3.0, 7.8), control2: P(14 + s * 6.4, 7.4))
            p.addLine(to: P(14 + s * 9.4, 19.6))
            p.addCurve(to: P(14, 21.6),
                       control1: P(14 + s * 6.4, 19.0), control2: P(14 + s * 3.0, 19.4))
            p.closeSubpath()                    // la fermeture EST la reliure
            strokePath(ctx, p)
        }
    }),
    ("icon_books", { ctx in
        // DEUX livres couchés, pas trois : à 28pt de canvas, trois tranches de 4pt ne
        // laissent que 2pt de blanc et la pile se lit « menu ». Décalage horizontal et
        // tranche marquée pour que ce soit une pile et pas deux barres.
        strokePath(ctx, rr(4.6, 16.6, 18.8, 5.6, 2.0), width: 2.2)
        strokePath(ctx, rr(6.6, 7.2, 15.0, 5.6, 2.0), width: 2.2)
        let edges = CGMutablePath()
        edges.move(to: P(19.8, 18.2)); edges.addLine(to: P(19.8, 20.6))
        edges.move(to: P(18.0, 8.8)); edges.addLine(to: P(18.0, 11.2))
        strokePath(ctx, edges, width: 1.6)
    }),
    ("icon_ribbon", { ctx in
        strokePath(ctx, circle(14, 10.4, 5.6))
        strokePath(ctx, circle(14, 10.4, 2.4), width: 1.8)
        for s in [CGFloat(-1), 1] {
            let tail = CGMutablePath()
            tail.move(to: P(14 + s * 3.4, 15.2))
            tail.addLine(to: P(14 + s * 5.6, 23.4))
            tail.addLine(to: P(14 + s * 1.6, 20.8))
            tail.closeSubpath()
            fillPath(ctx, tail)
            strokePath(ctx, tail, width: 1.4)
        }
    }),

    // MARK: Vague 2 — niveaux et objectifs

    ("icon_star", { ctx in
        let s = starPath(14, 14.4, points: 5, r: 8.8, inner: 4.1)
        fillPath(ctx, s); strokePath(ctx, s, width: 2.6)   // pointes arrondies
    }),
    ("icon_star_double", { ctx in
        let s = starPath(11.8, 12.0, points: 5, r: 6.8, inner: 3.2)
        fillPath(ctx, s); strokePath(ctx, s, width: 2.2)
        let sparkle = starPath(19.8, 19.8, points: 4, r: 3.9, inner: 1.4)
        fillPath(ctx, sparkle); strokePath(ctx, sparkle, width: 1.8)
    }),
    ("icon_comet", { ctx in
        let head = starPath(18.6, 9.6, points: 4, r: 4.8, inner: 1.7)
        fillPath(ctx, head); strokePath(ctx, head, width: 1.8)
        let t1 = CGMutablePath()
        t1.move(to: P(14.6, 13.6))
        t1.addCurve(to: P(5.4, 21.6), control1: P(11.6, 16.0), control2: P(8.0, 18.4))
        strokePath(ctx, t1)
        let t2 = CGMutablePath()
        t2.move(to: P(17.2, 16.2))
        t2.addCurve(to: P(10.6, 23.0), control1: P(15.0, 18.6), control2: P(12.6, 20.6))
        strokePath(ctx, t2, width: 2.0)
    }),
    ("icon_medal", { ctx in
        let ribbon = CGMutablePath()
        ribbon.move(to: P(10.2, 4.6)); ribbon.addLine(to: P(12.6, 10.6))
        ribbon.move(to: P(17.8, 4.6)); ribbon.addLine(to: P(15.4, 10.6))
        strokePath(ctx, ribbon)
        strokePath(ctx, circle(14, 16.4, 6.4))
        fillPath(ctx, starPath(14, 16.4, points: 5, r: 3.2, inner: 1.4))
    }),
    ("icon_target", { ctx in
        strokePath(ctx, circle(14, 14, 9.0))
        strokePath(ctx, circle(14, 14, 5.0), width: 2.2)
        fillPath(ctx, circle(14, 14, 1.9))
    }),
    ("icon_flag", { ctx in
        // Fanion planté, et non l'arc de 🏹 : un arc, sa corde et sa flèche font trois
        // tracés qui se croisent dans 20pt d'encre, et la première planche le lisait
        // « triangle de lecture ». Le fanion dit « conquis » aussi bien, et se lit à 25pt.
        let pole = CGMutablePath()
        pole.move(to: P(7.6, 4.6)); pole.addLine(to: P(7.6, 23.4))
        strokePath(ctx, pole, width: 2.6)
        let banner = CGMutablePath()
        banner.move(to: P(7.6, 6.0))
        banner.addCurve(to: P(21.6, 8.4), control1: P(12.4, 4.0), control2: P(16.8, 10.4))
        banner.addLine(to: P(21.6, 15.6))
        banner.addCurve(to: P(7.6, 13.2), control1: P(16.8, 17.6), control2: P(12.4, 11.2))
        banner.closeSubpath()
        strokePath(ctx, banner)
    }),
    ("icon_clover", { ctx in
        for (dx, dy) in [(CGFloat(-3.4), CGFloat(-3.4)), (3.4, -3.4), (-3.4, 3.4), (3.4, 3.4)] {
            fillPath(ctx, circle(14 + dx, 13.2 + dy, 4.1))
        }
        let stem = CGMutablePath()
        stem.move(to: P(14, 16.4))
        stem.addCurve(to: P(17.6, 23.6), control1: P(15.0, 19.4), control2: P(17.0, 21.4))
        strokePath(ctx, stem, width: 2.2)
    }),
    ("icon_scale", { ctx in
        // Balance à plateaux : un pèse-personne vu de dessus (rectangle plus cadran) se
        // lisait « écran » sur la première planche.
        let frame = CGMutablePath()
        frame.move(to: P(14, 6.6)); frame.addLine(to: P(14, 21.4))       // mât
        frame.move(to: P(6.8, 9.4)); frame.addLine(to: P(21.2, 9.4))     // fléau
        frame.move(to: P(9.2, 21.6)); frame.addLine(to: P(18.8, 21.6))   // socle
        strokePath(ctx, frame)
        fillPath(ctx, circle(14, 6.4, 1.5))
        for x in [CGFloat(6.8), 21.2] {
            let hanger = CGMutablePath()
            hanger.move(to: P(x, 9.4)); hanger.addLine(to: P(x, 13.2))
            strokePath(ctx, hanger, width: 1.6)
            let pan = CGMutablePath()
            pan.addArc(center: P(x, 13.2), radius: 2.8, startAngle: 0,
                       endAngle: .pi, clockwise: false)                  // demi-coupe
            strokePath(ctx, pan, width: 2.2)
        }
    }),
    ("icon_trend_down", { ctx in
        let axis = CGMutablePath()
        axis.move(to: P(5.6, 5.0)); axis.addLine(to: P(5.6, 22.4)); axis.addLine(to: P(23.0, 22.4))
        strokePath(ctx, axis, width: 2.2)
        let curve = CGMutablePath()
        curve.move(to: P(8.6, 8.6)); curve.addLine(to: P(13.2, 13.4))
        curve.addLine(to: P(16.6, 10.4)); curve.addLine(to: P(20.2, 16.4))
        strokePath(ctx, curve)
        arrowHead(ctx, tip: P(21.6, 18.8), angle: atan2(7.2, 4.4), length: 4.0, half: 2.6)
    }),
    ("icon_compass", { ctx in
        // Aiguille en DEUX moitiés, nord plein et sud évidé, séparées par la petite
        // diagonale : un losange entièrement rempli se lisait « feuille dans un cercle ».
        strokePath(ctx, circle(14, 14, 9.0))
        let d: CGFloat = 0.7071
        let north = P(14 + 6.2 * d, 14 - 6.2 * d), south = P(14 - 6.2 * d, 14 + 6.2 * d)
        let side1 = P(14 + 2.3 * d, 14 + 2.3 * d), side2 = P(14 - 2.3 * d, 14 - 2.3 * d)
        let n = CGMutablePath()
        n.move(to: north); n.addLine(to: side1); n.addLine(to: side2); n.closeSubpath()
        fillPath(ctx, n)
        let s = CGMutablePath()
        s.move(to: south); s.addLine(to: side1); s.addLine(to: side2); s.closeSubpath()
        strokePath(ctx, s, width: 2.0)
    }),

    // MARK: Vague 2 — sobriété, moments, thèmes

    ("icon_drop", { ctx in
        // Fond RÉELLEMENT rond : deux courbes de pointe à pointe donnaient une amande.
        let p = CGMutablePath()
        p.move(to: P(14, 4.6))
        p.addCurve(to: P(21.0, 16.0), control1: P(15.6, 8.6), control2: P(21.0, 11.4))
        p.addCurve(to: P(7.0, 16.0), control1: P(21.0, 21.4), control2: P(7.0, 21.4))
        p.addCurve(to: P(14, 4.6), control1: P(7.0, 11.4), control2: P(12.4, 8.6))
        strokePath(ctx, p)
    }),
    ("icon_glass_empty", { ctx in
        // Verre droit et VIDE : ni pied ni anse, donc aucune confusion avec la coupe de
        // tab_quests ni avec le flan.
        let p = CGMutablePath()
        p.move(to: P(9.4, 5.6))
        p.addLine(to: P(11.2, 20.6))
        p.addCurve(to: P(16.8, 20.6), control1: P(11.6, 22.4), control2: P(16.4, 22.4))
        p.addLine(to: P(18.6, 5.6))
        p.closeSubpath()
        strokePath(ctx, p)
    }),
    ("icon_sun", { ctx in
        // Rayons DÉTACHÉS et disque plein : exactement ce qui faisait lire icon_settings
        // comme un soleil quand ses dents l'étaient (retour de la vague 1), assumé ici.
        fillPath(ctx, circle(14, 14, 4.4))
        for i in 0..<8 {
            let a = CGFloat(i) * .pi / 4
            let ray = CGMutablePath()
            ray.move(to: P(14 + 6.8 * cos(a), 14 + 6.8 * sin(a)))
            ray.addLine(to: P(14 + 9.0 * cos(a), 14 + 9.0 * sin(a)))
            strokePath(ctx, ray, width: 2.2)
        }
    }),
    ("icon_moon", { ctx in
        // Angle balayé par le disque = 2·(π − acos(a/r)) ≈ 162° ici, et épaisseur au plus
        // large r − (hole − d) = 3,3 : un croissant qui pointe ses deux cornes. À ~200°
        // (trou de même rayon, à peine décalé) ça se lisait « anneau à encoche ».
        // Incliné de 30° puis recentré : construit droit, il tenait dans une bande verticale
        // de 8 pt sur les 28 du canvas.
        fillPath(ctx, centered(rotated(crescent(14, 14, 9.8, dx: 5.4, dy: 0, hole: 11.9),
                                       degrees: -30)))
    }),
    ("icon_tree", { ctx in
        // La BASE LARGE ET PLATE du houppier (8 → 20, soit les deux tiers de la largeur)
        // est ce qui empêche de lire « ballon » : un ballon a un fond rond. Un houppier
        // simplement lobé ne suffisait pas.
        let crown = CGMutablePath()
        crown.move(to: P(8.0, 16.4))
        crown.addCurve(to: P(5.6, 11.6), control1: P(6.0, 15.8), control2: P(5.6, 13.8))
        crown.addCurve(to: P(9.8, 6.6), control1: P(5.6, 9.0), control2: P(7.4, 7.0))
        crown.addCurve(to: P(18.2, 6.6), control1: P(11.6, 3.8), control2: P(16.4, 3.8))
        crown.addCurve(to: P(22.4, 11.6), control1: P(20.6, 7.0), control2: P(22.4, 9.0))
        crown.addCurve(to: P(20.0, 16.0), control1: P(22.4, 13.8), control2: P(22.0, 15.4))
        // Bas FESTONNÉ (deux lobes qui retombent) : un bord inférieur droit et large donnait
        // un chapeau de champignon. Du feuillage pend, un chapeau non.
        crown.addCurve(to: P(14.0, 16.0), control1: P(19.0, 18.6), control2: P(15.0, 18.6))
        crown.addCurve(to: P(8.0, 16.4), control1: P(13.0, 18.6), control2: P(9.0, 18.6))
        crown.closeSubpath()
        strokePath(ctx, crown)
        fillPath(ctx, pill(12.4, 17.2, 3.2, 6.4))
    }),
    ("icon_heart", { ctx in
        let h = CGMutablePath()
        h.move(to: P(14, 22.2))
        h.addCurve(to: P(4.8, 11.8), control1: P(9.2, 18.4), control2: P(4.8, 15.2))
        h.addCurve(to: P(14, 9.2), control1: P(4.8, 7.0), control2: P(11.2, 6.0))
        h.addCurve(to: P(23.2, 11.8), control1: P(16.8, 6.0), control2: P(23.2, 7.0))
        h.addCurve(to: P(14, 22.2), control1: P(23.2, 15.2), control2: P(18.8, 18.4))
        strokePath(ctx, h)
    }),
    ("icon_bell", { ctx in
        let body = CGMutablePath()
        body.move(to: P(7.2, 19.0))
        body.addCurve(to: P(9.6, 12.0), control1: P(8.6, 17.0), control2: P(9.6, 14.4))
        body.addCurve(to: P(18.4, 12.0), control1: P(9.6, 7.0), control2: P(18.4, 7.0))
        body.addCurve(to: P(20.8, 19.0), control1: P(18.4, 14.4), control2: P(19.4, 17.0))
        body.closeSubpath()
        strokePath(ctx, body)
        fillPath(ctx, circle(14, 6.4, 1.5))     // pommeau, attaché au dôme
        fillPath(ctx, circle(14, 21.4, 1.9))    // battant
    }),
    ("icon_flan", { ctx in
        let dome = CGMutablePath()
        dome.move(to: P(7.0, 19.0))
        dome.addCurve(to: P(14, 8.0), control1: P(7.8, 12.4), control2: P(10.4, 8.0))
        dome.addCurve(to: P(21.0, 19.0), control1: P(17.6, 8.0), control2: P(20.2, 12.4))
        dome.closeSubpath()
        strokePath(ctx, dome)
        let plate = CGMutablePath(); plate.move(to: P(4.6, 21.8)); plate.addLine(to: P(23.4, 21.8))
        strokePath(ctx, plate, width: 2.2)
        let caramel = CGMutablePath()
        caramel.move(to: P(10.6, 11.8))
        caramel.addCurve(to: P(17.4, 11.8), control1: P(12.8, 14.0), control2: P(15.2, 9.6))
        strokePath(ctx, caramel, width: 1.8)
    }),
    ("icon_mint", { ctx in
        // Tige QUASI VERTICALE et feuilles OPPOSÉES par paires, plus une feuille au
        // sommet : une longue diagonale bordée de feuilles alternées se lisait « fléchette ».
        // La brindille se distingue de la pousse de tab_progress (deux grandes feuilles et
        // un sol) par le nombre et la taille.
        let stem = CGMutablePath()
        stem.move(to: P(14.6, 6.0))
        stem.addCurve(to: P(12.4, 22.8), control1: P(14.8, 11.0), control2: P(12.6, 17.0))
        strokePath(ctx, stem, width: 2.2)
        fillPath(ctx, leafShape(14.5, 7.6, 15.6, 3.4, bulge: 1.5))          // feuille de tête
        for (bx, by, tx, ty) in [(CGFloat(14.25), CGFloat(10.74), CGFloat(20.4), CGFloat(7.6)),
                                 (14.25, 10.74, 8.4, 8.6),
                                 (13.47, 14.94, 19.8, 12.4),
                                 (13.47, 14.94, 7.4, 13.0)] {
            fillPath(ctx, leafShape(bx, by, tx, ty, bulge: 1.6))
        }
    }),
    ("icon_wave", { ctx in
        for (y, w) in [(CGFloat(9.8), CGFloat(2.4)), (15.0, 2.4), (20.2, 2.2)] {
            let p = CGMutablePath()
            p.move(to: P(4.6, y))
            p.addCurve(to: P(14, y), control1: P(7.4, y - 3.4), control2: P(11.2, y + 3.4))
            p.addCurve(to: P(23.4, y), control1: P(16.8, y - 3.4), control2: P(20.6, y + 3.4))
            strokePath(ctx, p, width: w)
        }
    }),

    // MARK: Vague 3 — les cinq paliers hauts de la 1.14
    //
    // Cinq badges étaient partis en emoji couleur faute de glyphe libre. Dans une grille
    // de 38 pastilles monochromes, ils détonnaient, et leur état verrouillé ne se traitait
    // même pas pareil (grayscale pour un emoji, teinte pour un glyphe — voir CatalogGlyph).
    // Chacun des cinq est le HAUT d'une série existante : il doit se lire comme la version
    // supérieure de sa famille, et non comme un objet neuf tombé d'ailleurs.

    ("icon_barbell", { ctx in
        // Muscu, au-dessus de l'haltère court de tab_sport (badge « Première séance muscu »).
        // MÊME grammaire — des masses et une barre — mais la barre traverse tout le canvas
        // et porte DEUX disques par côté. Et surtout : plein là où tab_sport est en contour.
        // À 25 pt, personne ne compte les disques ; c'est la masse d'encre qui dit « lourd ».
        let bar = CGMutablePath(); bar.move(to: P(5.2, 14)); bar.addLine(to: P(22.8, 14))
        strokePath(ctx, bar)
        for x in [CGFloat(8.8), 15.6] { fillPath(ctx, rr(x, 6.8, 3.6, 14.4, 1.7)) }
        for x in [CGFloat(4.2), 21.2] { fillPath(ctx, rr(x, 10.2, 2.6, 7.6, 1.3)) }
    }),
    ("icon_crown", { ctx in
        // Niveau 50, au-dessus du soleil du niveau 30. La série des niveaux (étoile, double
        // étoile, comète, soleil) monte dans le ciel ; la couronne en sort exprès — elle est
        // le seul objet du jeu qui dise « plus haut que tout le reste » sans être un astre.
        // Base PLATE et flancs verticaux : c'est ce qui la sépare de la montagne d'icon_mountain,
        // dont le zigzag est proche.
        let c = CGMutablePath()
        c.move(to: P(5.9, 20.6))
        c.addLine(to: P(5.0, 9.6))       // pointe gauche
        c.addLine(to: P(9.8, 14.0))      // creux
        c.addLine(to: P(14.0, 7.4))      // pointe centrale, la plus haute
        c.addLine(to: P(18.2, 14.0))
        c.addLine(to: P(23.0, 9.6))
        c.addLine(to: P(22.1, 20.6))
        c.closeSubpath()
        fillPath(ctx, c)
        strokePath(ctx, c)               // fill + stroke = pointes et creux arrondis (cf. icon_play)
    }),
    ("icon_laurel", { ctx in
        // Cent activités, au-dessus de la médaille du tout premier pas. La couronne de
        // laurier est le seul cran au-dessus d'une médaille qui reste une récompense de
        // sport, et l'étoile qu'elle enserre est de la MÊME FAMILLE que celle de la
        // médaille — la même starPath à 5 branches, pas les mêmes réglages : ici elle est
        // seule au milieu d'un vide, donc un peu plus grande (3,6 contre 3,2) et contournée
        // à 1,4 pour peser autant que celle qui, là-bas, est calée dans un disque. Deux
        // fonds, deux réglages : rien à partager dans une aide commune.
        // Les feuilles ne touchent pas l'étoile (2,5 pt de blanc) — un PDF template est
        // monochrome, ce qui se touche fusionne.
        func polar(_ r: CGFloat, _ deg: CGFloat) -> CGPoint {
            P(14 + r * cos(deg * .pi / 180), 14 + r * sin(deg * .pi / 180))
        }
        for s in [CGFloat(-1), 1] {
            // s = -1 : la branche gauche, arc de 95° à 182°. s = +1 : la même en miroir
            // par rapport à l'axe vertical, d'où θ → 180 − θ et le sens de l'arc inversé.
            let stem = CGMutablePath()
            let a0: CGFloat = s < 0 ? 95 : 85
            let a1: CGFloat = s < 0 ? 182 : -2
            stem.addArc(center: P(14, 14), radius: 7.8,
                        startAngle: a0 * .pi / 180, endAngle: a1 * .pi / 180, clockwise: s > 0)
            strokePath(ctx, stem, width: 2.0)
            // La dernière feuille est POSÉE à 176°, donc pointe à 200° (176 + les 24° de
            // balayage ci-dessous) : plus haut sur la branche, sa pointe se redressait à la
            // verticale et la couronne prenait deux cornes.
            for a in [CGFloat(108), 142, 176] {
                let ang = s < 0 ? a : 180 - a
                let base = polar(7.8, ang)
                // 30° de balayage, et non la direction radiale : des feuilles plantées
                // DROIT vers l'extérieur donnaient une roue dentée autour d'une étoile.
                // Couchées le long de la branche, elles se lisent enfin comme du feuillage.
                let tip = polar(10.0, ang - s * 24)
                fillPath(ctx, leafShape(base.x, base.y, tip.x, tip.y, bulge: 1.15))
            }
        }
        let star = starPath(14, 15.0, points: 5, r: 3.6, inner: 1.6)
        fillPath(ctx, star); strokePath(ctx, star, width: 1.4)
    }),
    ("icon_cake", { ctx in
        // Une année de journal, au-dessus des 100 jours du ruban. Un TROISIÈME calendrier
        // était exclu : les deux existants ne diffèrent que par la densité de leurs
        // pastilles, un de plus serait illisible. Le gâteau dit « un an » d'un coup.
        // Ce qui le sépare du flan (dôme + assiette, lui aussi un dessert de la grille) :
        // des flancs droits, et surtout la bougie qui dépasse en haut.
        strokePath(ctx, rr(5.6, 13.0, 16.8, 9.4, 2.6))
        // Glaçage : trois festons qui retombent dans le gâteau. Un simple trait droit
        // aurait donné une part de mille-feuille.
        let icing = CGMutablePath()
        icing.move(to: P(5.7, 15.4))
        icing.addQuadCurve(to: P(11.3, 15.4), control: P(8.5, 19.6))
        icing.addQuadCurve(to: P(16.9, 15.4), control: P(14.1, 19.6))
        icing.addQuadCurve(to: P(22.3, 15.4), control: P(19.7, 19.6))
        strokePath(ctx, icing, width: 2.0)
        let candle = CGMutablePath()
        candle.move(to: P(14, 12.9)); candle.addLine(to: P(14, 9.2))
        strokePath(ctx, candle, width: 2.2)
        // Flamme large (1,45 de renflement) et bougie raccourcie d'autant : fine, la flamme
        // prolongeait la bougie et l'ensemble ne faisait plus qu'un bâtonnet à 25 pt.
        fillPath(ctx, leafShape(14, 9.4, 14, 4.8, bulge: 1.45))
    }),
    ("icon_mountain", { ctx in
        // 20 000 pas en un jour, au-dessus de l'empreinte des 10 000. Une TROISIÈME
        // empreinte ne se serait pas distinguée de la paire d'icon_footprints ; le sommet,
        // lui, dit la journée hors norme. Deux cimes et non une : une cime seule est un
        // triangle, deux cimes sont une montagne.
        let peaks = CGMutablePath()
        peaks.move(to: P(4.0, 22.4))
        peaks.addLine(to: P(13.0, 5.8))    // cime principale
        peaks.addLine(to: P(17.0, 13.0))   // col
        peaks.addLine(to: P(20.2, 9.4))    // seconde cime
        peaks.addLine(to: P(24.0, 22.4))
        peaks.closeSubpath()
        strokePath(ctx, peaks)
        // Ligne de neige : le zigzag va d'un flanc à l'autre à hauteur constante (y = 11,4),
        // sinon il flotte au milieu du vide et se lit « éclair ».
        let snow = CGMutablePath()
        snow.move(to: P(9.7, 11.4))
        snow.addLine(to: P(11.3, 13.0)); snow.addLine(to: P(12.8, 11.3))
        snow.addLine(to: P(14.4, 13.2)); snow.addLine(to: P(16.2, 11.4))
        strokePath(ctx, snow, width: 2.0)
    }),
]

// MARK: - Sorties

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
// Garde d'ancrage : à lancer depuis la RACINE du repo (sinon les sorties atterrissent n'importe où).
guard FileManager.default.fileExists(atPath: root.appendingPathComponent("project.yml").path) else {
    fatalError("Lancer depuis la racine du repo (project.yml introuvable dans \(root.path))")
}
let iconsDir = root.appendingPathComponent("App/Assets.xcassets/Icons")
let designDir = root.appendingPathComponent("design/icons")
let fm = FileManager.default
try? fm.removeItem(at: iconsDir)
try fm.createDirectory(at: iconsDir, withIntermediateDirectories: true)
try fm.createDirectory(at: designDir, withIntermediateDirectories: true)

try (#"""
{
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "provides-namespace" : true }
}
"""# + "\n").write(to: iconsDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

func drawFlipped(_ ctx: CGContext, _ draw: (CGContext) -> Void) {
    ctx.saveGState()
    ctx.translateBy(x: 0, y: SIZE)
    ctx.scaleBy(x: 1, y: -1)                 // coordonnées y vers le bas (piège #3)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
    draw(ctx)
    ctx.restoreGState()
}

for glyph in glyphs {
    let setDir = iconsDir.appendingPathComponent("\(glyph.name).imageset")
    try fm.createDirectory(at: setDir, withIntermediateDirectories: true)
    let pdfURL = setDir.appendingPathComponent("\(glyph.name).pdf")
    var box = CGRect(x: 0, y: 0, width: SIZE, height: SIZE)
    guard let ctx = CGContext(pdfURL as CFURL, mediaBox: &box, nil) else { fatalError("ctx PDF") }
    ctx.beginPDFPage(nil)
    drawFlipped(ctx, glyph.draw)
    ctx.endPDFPage()
    ctx.closePDF()
    try (#"""
{
  "images" : [ { "filename" : "\#(glyph.name).pdf", "idiom" : "universal" } ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "preserves-vector-representation" : true, "template-rendering-intent" : "template" }
}
"""# + "\n").write(to: setDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

// Planche-contact PNG : tous les glyphes à 100px (≈50pt), puis TOUS à 50px (≈25pt) —
// deux bandes en GRILLE de 10 colonnes (à 50 glyphes, une seule rangée serait illisible).
// La bande du bas est celle qui décide : c'est la taille réelle en tab bar et en grille.
let cols = 10
let rows = (glyphs.count + cols - 1) / cols
let bigCell = 110, smallCell = 62, gutter = 18
let sheetW = cols * bigCell
let smallBandH = rows * smallCell
let sheetH = rows * bigCell + gutter + smallBandH
guard let bmp = CGContext(data: nil, width: sheetW, height: sheetH, bitsPerComponent: 8,
                          bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("bmp") }
bmp.setFillColor(CGColor(red: 0.99, green: 0.96, blue: 0.92, alpha: 1))   // fond crème
bmp.fill(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))

// Le contexte bitmap est y-vers-le-HAUT : `rows - 1 - row` remet la rangée 0 en haut.
func drawBand(cell: Int, px: CGFloat, bandOriginY: Int) {
    let scale = px / SIZE
    let inset = (CGFloat(cell) - SIZE * scale) / 2
    for (i, glyph) in glyphs.enumerated() {
        let col = i % cols, row = i / cols
        bmp.saveGState()
        bmp.translateBy(x: CGFloat(col * cell) + inset,
                        y: CGFloat(bandOriginY + (rows - 1 - row) * cell) + inset)
        bmp.scaleBy(x: scale, y: scale)
        // Le flip de drawFlipped remet y vers le bas, comme dans les PDF.
        drawFlipped(bmp) { c in
            c.setFillColor(CGColor(red: 0.96, green: 0.49, blue: 0.12, alpha: 1))
            c.setStrokeColor(CGColor(red: 0.96, green: 0.49, blue: 0.12, alpha: 1))
            glyph.draw(c)
        }
        bmp.restoreGState()
    }
}
drawBand(cell: bigCell, px: 100, bandOriginY: smallBandH + gutter)
drawBand(cell: smallCell, px: 50, bandOriginY: 0)
let sheetURL = designDir.appendingPathComponent("contact-sheet.png")
guard let img = bmp.makeImage(),
      let dest = CGImageDestinationCreateWithURL(sheetURL as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("png") }
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("OK : \(glyphs.count) imagesets + contact-sheet.png")
