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

// MARK: - Les 15 glyphes

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

// Planche-contact PNG : chaque glyphe à 50px (≈25pt) et 100px (≈50pt), grille 2 rangées.
let cell = 110
let sheetW = glyphs.count * cell, sheetH = 2 * cell
guard let bmp = CGContext(data: nil, width: sheetW, height: sheetH, bitsPerComponent: 8,
                          bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("bmp") }
bmp.setFillColor(CGColor(red: 0.99, green: 0.96, blue: 0.92, alpha: 1))   // fond crème
bmp.fill(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))
for (i, glyph) in glyphs.enumerated() {
    for (row, scale) in [(0, CGFloat(100.0 / 28.0)), (1, CGFloat(50.0 / 28.0))] {
        bmp.saveGState()
        let inset = (CGFloat(cell) - SIZE * scale) / 2
        bmp.translateBy(x: CGFloat(i * cell) + inset, y: CGFloat(row * cell) + inset)
        bmp.scaleBy(x: scale, y: scale)
        // Le contexte bitmap est déjà y-vers-le-haut : le flip de drawFlipped remet y vers le bas.
        drawFlipped(bmp) { c in
            c.setFillColor(CGColor(red: 0.96, green: 0.49, blue: 0.12, alpha: 1))
            c.setStrokeColor(CGColor(red: 0.96, green: 0.49, blue: 0.12, alpha: 1))
            glyph.draw(c)
        }
        bmp.restoreGState()
    }
}
let sheetURL = designDir.appendingPathComponent("contact-sheet.png")
guard let img = bmp.makeImage(),
      let dest = CGImageDestinationCreateWithURL(sheetURL as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("png") }
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("OK : \(glyphs.count) imagesets + contact-sheet.png")
