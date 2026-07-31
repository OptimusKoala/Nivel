# Icônes cozy (v1.7) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remplacer les SF Symbols d'identité par 15 glyphes cozy générés (PDF template auto-teintés) : tab bar contour→rempli, ⚙️, coche, play/pause/recommencer.

**Architecture:** Un générateur CoreGraphics (`scripts/gen-icons.swift`, source unique) émet les PDF dans `Assets.xcassets/Icons/` (namespace, template) ET une planche-contact PNG dans `design/icons/` pour la relecture visuelle. L'intégration est un pur remplacement d'images (aucune logique). Spec : `docs/superpowers/specs/2026-07-31-cozy-icons-design.md`.

**Tech Stack:** Swift script (CoreGraphics/ImageIO, zéro dépendance), XCTest, XcodeGen.

**Branche : créer `feat/cozy-icons` depuis `main`.**

### Task 0 : Branche

- [ ] `cd /Users/mbernard/perso/Nivel && git checkout -b feat/cozy-icons`

**Commandes de test :** NivelCore `cd NivelCore && swift test` (51 attendus, non touché) ; app `xcodebuild -project Nivel.xcodeproj -scheme Nivel -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test` (55 actuels → 56 après Task 1).

**Pièges connus :**
1. Les PDF s'affichent en NOIR si `template-rendering-intent` manque dans le Contents.json de l'imageset.
2. La géométrie des glyphes est un PREMIER JET : la boucle qualité passe par la planche-contact (`design/icons/contact-sheet.png`) — générer, REGARDER, ajuster les coordonnées, re-générer. Ne pas intégrer (Task 2) avant validation visuelle du contrôleur.
3. Le contexte PDF CG est en y-vers-le-haut : le script applique un flip (translate/scale) pour dessiner en coordonnées « SVG » (y vers le bas) — ne pas le retirer.
4. `xcodegen generate` après ajout de fichiers Swift (le script sous `scripts/` n'est PAS compilé dans l'app ; seul le fichier de test l'exige).
5. OnboardingFlow contient DEUX `checkmark.circle.fill` : remplacer UNIQUEMENT le badge de permission (~ligne 461), PAS le radio de sélection (~ligne 356, paire avec `circle`) — spec §2.

---

## Task 1 : Générateur + assets + planche-contact + test

**Files:**
- Create: `scripts/gen-icons.swift`
- Create: `App/Assets.xcassets/Icons/` (généré — 15 imagesets PDF)
- Create: `design/icons/contact-sheet.png` (généré)
- Test (create): `NivelTests/IconAssetsTests.swift`

- [ ] **Step 1 : Test (rouge)**

```swift
// NivelTests/IconAssetsTests.swift
import XCTest
import UIKit
@testable import Nivel

final class IconAssetsTests: XCTestCase {
    /// Les 15 glyphes cozy (spec icônes §2) — liste PINNÉE, garde anti-typo de nommage.
    static let iconNames = [
        "tab_home", "tab_home_fill", "tab_meals", "tab_meals_fill",
        "tab_sport", "tab_sport_fill", "tab_progress", "tab_progress_fill",
        "tab_quests", "tab_quests_fill",
        "icon_settings", "icon_check", "icon_play", "icon_pause", "icon_restart",
    ]

    func testEveryCozyIconAssetExists() {
        for name in Self.iconNames {
            XCTAssertNotNil(UIImage(named: "Icons/\(name)"), "asset manquant : Icons/\(name)")
        }
    }
}
```

- [ ] **Step 2 : Vérifier l'échec** — `xcodegen generate && xcodebuild ... test` → FAIL (15 assertions).

- [ ] **Step 3 : Écrire le générateur**

```swift
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
    let p = CGMutablePath()
    p.move(to: P(14, 16))
    p.addCurve(to: P(20.4, 10.8), control1: P(14, 12.8), control2: P(16.6, 10.8))
    p.addCurve(to: P(14, 16), control1: P(20.4, 14.2), control2: P(17.8, 16.2))
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
    ("tab_home", { ctx in
        let roof = CGMutablePath()
        roof.move(to: P(4, 13)); roof.addLine(to: P(14, 4.5)); roof.addLine(to: P(24, 13))
        strokePath(ctx, roof)
        strokePath(ctx, rr(6, 12.5, 16, 11.5, 3))
        strokePath(ctx, doorPath(closed: false), width: 2.2)
    }),
    ("tab_home_fill", { ctx in
        let p = houseSilhouette()
        p.addPath(doorPath(closed: true))
        fillPath(ctx, p, evenOdd: true)
    }),
    ("tab_meals", { ctx in strokePath(ctx, bowlPath()); steam(ctx) }),
    ("tab_meals_fill", { ctx in fillPath(ctx, bowlPath()); steam(ctx) }),
    ("tab_sport", { ctx in
        strokePath(ctx, rr(4, 9.5, 4.5, 9, 2.25))
        strokePath(ctx, rr(19.5, 9.5, 4.5, 9, 2.25))
        let bar = CGMutablePath(); bar.move(to: P(8.5, 14)); bar.addLine(to: P(19.5, 14))
        strokePath(ctx, bar)
    }),
    ("tab_sport_fill", { ctx in
        fillPath(ctx, rr(3.8, 9, 5.2, 10, 2.6))
        fillPath(ctx, rr(19, 9, 5.2, 10, 2.6))
        fillPath(ctx, pill(8, 12.6, 12, 2.8))
    }),
    ("tab_progress", { ctx in
        strokePath(ctx, leafLeft(), width: 2.2)
        strokePath(ctx, leafRight(), width: 2.2)
        sproutLines(ctx)
    }),
    ("tab_progress_fill", { ctx in
        fillPath(ctx, leafLeft()); fillPath(ctx, leafRight()); sproutLines(ctx)
    }),
    ("tab_quests", { ctx in
        strokePath(ctx, cupPath()); trophyHandles(ctx); trophyStem(ctx)
        strokePath(ctx, trophyBase(), width: 2.2)
    }),
    ("tab_quests_fill", { ctx in
        fillPath(ctx, cupPath()); trophyHandles(ctx); trophyStem(ctx)
        fillPath(ctx, trophyBase())
    }),
    ("icon_settings", { ctx in
        strokePath(ctx, circle(14, 14, 5.6))
        for i in 0..<8 {
            let a = CGFloat(i) * .pi / 4
            let stub = CGMutablePath()
            stub.move(to: P(14 + 8.2 * cos(a), 14 + 8.2 * sin(a)))
            stub.addLine(to: P(14 + 10.2 * cos(a), 14 + 10.2 * sin(a)))
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
let iconsDir = root.appendingPathComponent("App/Assets.xcassets/Icons")
let designDir = root.appendingPathComponent("design/icons")
let fm = FileManager.default
try? fm.removeItem(at: iconsDir)
try fm.createDirectory(at: iconsDir, withIntermediateDirectories: true)
try fm.createDirectory(at: designDir, withIntermediateDirectories: true)

try #"""
{
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "provides-namespace" : true }
}
"""#.write(to: iconsDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

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
    try #"""
{
  "images" : [ { "filename" : "\#(glyph.name).pdf", "idiom" : "universal" } ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "preserves-vector-representation" : true, "template-rendering-intent" : "template" }
}
"""#.write(to: setDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

// Planche-contact PNG : chaque glyphe à 50px (≈25pt) et 100px (≈50pt), grille 2 rangées.
let cell = 110, pad = 10
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
```

⚠️ Détails susceptibles d'ajustement à la compilation (adapter mécaniquement, signaler) : `CGPath.copy(strokingWithWidth:...)` (existe, vérifier la signature), la couleur du glyphe dans `drawFlipped` est posée APRÈS le flip pour rester dans le GState — si un glyphe repose la couleur, la re-poser. Le `setFill/setStroke` orange dans la planche-contact écrase le noir : c'est voulu (aperçu teinté).

- [ ] **Step 4 : Générer + BOUCLE QUALITÉ VISUELLE**

`chmod +x` inutile (lancé via `swift scripts/gen-icons.swift`). Lancer, puis OUVRIR `design/icons/contact-sheet.png` (outil Read) et JUGER chaque glyphe : lisibilité à 50px (rangée du bas ≈ taille tab bar), équilibre optique entre les 5 onglets, coche bien évidée, flèche du restart correctement orientée. **Ajuster les coordonnées et re-générer autant que nécessaire.** Ne passer à la suite qu'avec une planche propre. Dans le rapport final, DONNER le chemin de la planche : le contrôleur la regardera aussi avant d'autoriser la Task 2.

- [ ] **Step 5 : Vert** — `xcodegen generate && xcodebuild ... test` → TEST SUCCEEDED, **56 tests** (55 + 1).

- [ ] **Step 6 : Commit** — `git add scripts/gen-icons.swift App/Assets.xcassets/Icons design/icons NivelTests/IconAssetsTests.swift Nivel.xcodeproj && git commit -m "feat(app): générateur d'icônes cozy (15 glyphes PDF template + planche-contact)"`

---

## Task 2 : Intégration (remplacement des SF Symbols d'identité)

**GATE : ne commencer qu'après validation de la planche-contact par le contrôleur.**

**Files:**
- Modify: `App/RootView.swift` (5 tabItems)
- Modify: `App/Views/Home/HomeView.swift` (⚙️)
- Modify: `App/Views/Sport/DailySessionCard.swift`, `App/Views/Sport/SessionPlayerSheet.swift`, `App/Views/Settings/SettingsView.swift`, `App/Views/Quests/QuestsView.swift`, `App/Views/Onboarding/OnboardingFlow.swift` (coches badge)
- Modify: `App/Views/Sport/TimerRingView.swift` (play/pause/restart)

- [ ] **Step 1 : Tab bar** — dans `MainTabView`, chaque `.tabItem { Label("X", systemImage: "...") }` devient (exemple Accueil) :
```swift
                .tabItem { Label("Accueil", image: selectedTab == .home ? "Icons/tab_home_fill" : "Icons/tab_home") }
```
Mapping : home→tab_home, meals→tab_meals, sport→tab_sport, progress→tab_progress, quests→tab_quests. Adapter le commentaire d'en-tête si besoin.

- [ ] **Step 2 : ⚙️** — HomeView : `Image(systemName: "gearshape.fill")` → `Image("Icons/icon_settings")` (modifiers identiques).

- [ ] **Step 3 : Coches badge (5 sites, PAS le radio d'onboarding — piège #5)** — remplacer `checkmark.circle.fill` par l'asset :
`Label(..., systemImage: "checkmark.circle.fill")` → `Label(..., image: "Icons/icon_check")` ; `Image(systemName: "checkmark.circle.fill")` → `Image("Icons/icon_check")`. Sites : DailySessionCard (~l.43), SessionPlayerSheet (~l.169), SettingsView (~l.409), QuestsView (~l.127), OnboardingFlow (~l.461 UNIQUEMENT).

- [ ] **Step 4 : Timer** — TimerRingView, les 4 `Label(..., systemImage:)` → `Label(..., image:)` : Lancer/Reprendre `Icons/icon_play`, Pause `Icons/icon_pause`, Recommencer `Icons/icon_restart`.

- [ ] **Step 5 : Vert** — suite complète → 56 tests. Vérifier qu'AUCUN des symboles remplacés ne reste : `grep -rn 'house.fill\|fork.knife\|figure.walk\|chart.line.uptrend\|trophy.fill\|gearshape.fill' App` → vide ; `grep -rn 'checkmark.circle.fill' App` → exactement 1 hit (le radio d'OnboardingFlow ~l.356, dont la ligne ternaire contient l'unique occurrence restante) ; `grep -rn 'play.fill\|pause.fill\|arrow.counterclockwise' App` → vide.

- [ ] **Step 6 : Commit** — `git add -A && git commit -m "feat(app): icônes cozy branchées (tab bar contour/rempli, ⚙️, coches, timer)"`

---

## Task 3 : Version 1.7 + vérification finale

**Files:**
- Modify: `project.yml` (1.6/7 → 1.7/8)

- [ ] **Step 1 : Bump** — `CFBundleShortVersionString: "1.7"`, `CFBundleVersion: "8"` dans les DEUX targets de `project.yml` (app ET Widgets — le commentaire du fichier l'exige : versions alignées sinon XcodeGen retombe sur 1.0/1), puis `xcodegen generate`.
- [ ] **Step 2 : Suites** — NivelCore 51 + app 56, tout vert.
- [ ] **Step 3 : Vérification simulateur (spec §7)** — tab bar : contour au repos, rempli + orange sur l'onglet actif, sur les 4 palettes (surtout Nuit douce) ; pas de rendu NOIR (piège #1) ; ⚙️, coches, boutons timer ; équilibre optique des 5 glyphes à taille réelle.
- [ ] **Step 4 : Commit** — `git add -A && git commit -m "chore: version 1.7 (build 8)"`

Fin de branche : options merge/PR présentées à Michaël.
