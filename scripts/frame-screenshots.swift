// scripts/frame-screenshots.swift
// Habillage des captures App Store : accroche en français + téléphone sur fond
// dégradé aux couleurs de Nivel. Exécution : swift scripts/frame-screenshots.swift
// Lit  : docs/appstore/raw/*.png      (captures brutes du simulateur, 1320 × 2868)
// Émet : docs/appstore/framed/*.png   (mêmes dimensions, prêtes pour App Store Connect)
//
// Les dimensions sont celles du 6,9 pouces (iPhone 17 Pro Max) : la seule taille
// iPhone exigée par Apple. Le téléphone déborde volontairement en bas — on gagne
// de la place pour l'accroche sans rétrécir l'écran.

import Foundation
import CoreGraphics
import CoreText
import ImageIO
import AppKit
import UniformTypeIdentifiers

// MARK: - Gabarit

let W: CGFloat = 1320
let H: CGFloat = 2868

/// Marge haute de l'accroche, hauteur réservée au texte, puis départ du téléphone.
let TITLE_TOP: CGFloat = 170
let TITLE_WIDTH: CGFloat = W - 200
let PHONE_TOP: CGFloat = 620
let PHONE_WIDTH: CGFloat = 1064
let BEZEL: CGFloat = 14
/// Rayon des coins de l'écran, ramené à l'échelle de la vignette.
let SCREEN_RADIUS: CGFloat = 165 * (PHONE_WIDTH / W)

struct Palette {
    let top: CGColor
    let bottom: CGColor
    let title: CGColor
    let subtitle: CGColor
    let bezel: CGColor
}

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

/// Crème : le fond et le texte de la palette par défaut de l'app.
let light = Palette(top: rgb(0xFFF8EE), bottom: rgb(0xFBE3C6), title: rgb(0x5B4A3F),
                    subtitle: rgb(0x9C8474), bezel: rgb(0x3A1220))
/// Nuit douce : brun chaud, jamais gris.
let night = Palette(top: rgb(0x33241F), bottom: rgb(0x1A1210), title: rgb(0xF2E4D3),
                    subtitle: rgb(0xBDA391), bezel: rgb(0x120A08))

struct Shot {
    let file: String
    let title: String
    let subtitle: String
    let palette: Palette
}

/// L'ordre EST celui de la fiche App Store : les trois premières sont les seules
/// visibles sans faire défiler, elles portent donc la promesse.
let shots: [Shot] = [
    Shot(file: "01-home",
         title: "Ta journée d'un coup d'œil",
         subtitle: "Calories, pas, quête du jour. Rien de rouge, jamais.",
         palette: light),
    Shot(file: "02-meallog",
         title: "Un repas en trois gestes",
         subtitle: "85 aliments, estimation immédiate, au gramme si tu veux.",
         palette: light),
    // « Tout doux » ne peut plus être seul dans le titre : depuis la 1.14 cette capture
    // cadre la section « Ça pousse » (course, pompes, burpees), et une accroche gravée
    // dans l'image ne se relit jamais — elle doit dire ce que l'image montre.
    Shot(file: "03-sport",
         title: "Tout doux, ou ça pousse",
         subtitle: "20 activités et 11 séances, illustrées par Nivelito.",
         palette: light),
    Shot(file: "04-session",
         title: "Nivelito bouge avec toi",
         subtitle: "Une séance du jour différente, jamais deux fois la même.",
         palette: light),
    Shot(file: "05-step",
         title: "Une étape par écran",
         subtitle: "Le minuteur en anneau, tu le lances seulement si tu veux.",
         palette: light),
    Shot(file: "06-progress",
         title: "Des progrès honnêtes",
         subtitle: "Tendance de poids lissée, pas quotidiens, historique.",
         palette: light),
    Shot(file: "07-quests",
         title: "Des quêtes, zéro reproche",
         subtitle: "18 quêtes tirées le lundi, 24 badges à débloquer.",
         palette: light),
    Shot(file: "08-night",
         title: "Quatre thèmes cozy",
         subtitle: "Crème, Menthe, Océan et Nuit douce.",
         palette: night),
    Shot(file: "09-idees",
         title: "Des idées de saison",
         subtitle: "Classées selon ce que tu as déjà dans le frigo.",
         palette: light),
    Shot(file: "10-recette",
         title: "La recette, puis c'est noté",
         subtitle: "Les ingrédients, la préparation, et hop, dans le journal.",
         palette: light),
]

// MARK: - Texte

/// Police système arrondie — celle de l'app (`.fontDesign(.rounded)`).
func roundedFont(size: CGFloat, weight: NSFont.Weight) -> CTFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base as CTFont }
    return NSFont(descriptor: descriptor, size: size) ?? base
}

/// Dessine un paragraphe centré et renvoie la hauteur occupée.
@discardableResult
func drawCentered(_ ctx: CGContext, _ text: String, font: CTFont, color: CGColor,
                  lineSpacing: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
    // Les pointeurs passés à CTParagraphStyleCreate doivent rester valides pendant
    // l'appel : on les garde vivants dans deux blocs `withUnsafeBytes` imbriqués.
    var alignment = CTTextAlignment.center
    var spacing = lineSpacing
    let style = withUnsafeBytes(of: &alignment) { alignmentBytes in
        withUnsafeBytes(of: &spacing) { spacingBytes in
            let settings = [
                CTParagraphStyleSetting(spec: .alignment,
                                        valueSize: MemoryLayout<CTTextAlignment>.size,
                                        value: alignmentBytes.baseAddress!),
                CTParagraphStyleSetting(spec: .lineSpacingAdjustment,
                                        valueSize: MemoryLayout<CGFloat>.size,
                                        value: spacingBytes.baseAddress!),
            ]
            return CTParagraphStyleCreate(settings, settings.count)
        }
    }
    let attributed = NSAttributedString(string: text, attributes: [
        .font: font, .foregroundColor: color, .paragraphStyle: style,
    ])

    let framesetter = CTFramesetterCreateWithAttributedString(attributed)
    let bounds = CGSize(width: width, height: .greatestFiniteMagnitude)
    let fitted = CTFramesetterSuggestFrameSizeWithConstraints(
        framesetter, CFRange(location: 0, length: 0), nil, bounds, nil)

    // Coordonnées CoreGraphics : origine en BAS. `top` est mesuré depuis le HAUT.
    let rect = CGRect(x: (W - width) / 2, y: H - top - fitted.height, width: width, height: fitted.height)
    let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0),
                                         CGPath(rect: rect, transform: nil), nil)
    CTFrameDraw(frame, ctx)
    return fitted.height
}

// MARK: - Rendu

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let rawDir = root.appendingPathComponent("docs/appstore/raw")
let outDir = root.appendingPathComponent("docs/appstore/framed")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func loadImage(_ url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

var written = 0
for shot in shots {
    let rawURL = rawDir.appendingPathComponent("\(shot.file).png")
    guard let screen = loadImage(rawURL) else {
        FileHandle.standardError.write("⚠️  capture absente : \(rawURL.path)\n".data(using: .utf8)!)
        continue
    }

    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8,
                              bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        fatalError("contexte impossible")
    }

    // Fond dégradé vertical.
    let gradient = CGGradient(colorsSpace: space,
                              colors: [shot.palette.top, shot.palette.bottom] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])

    // Accroche puis sous-titre.
    let titleHeight = drawCentered(ctx, shot.title,
                                   font: roundedFont(size: 92, weight: .bold),
                                   color: shot.palette.title, lineSpacing: 8,
                                   top: TITLE_TOP, width: TITLE_WIDTH)
    drawCentered(ctx, shot.subtitle,
                 font: roundedFont(size: 46, weight: .medium),
                 color: shot.palette.subtitle, lineSpacing: 6,
                 top: TITLE_TOP + titleHeight + 34, width: TITLE_WIDTH)

    // Téléphone : coque arrondie + écran clippé dedans. Il déborde en bas du cadre.
    let phoneHeight = PHONE_WIDTH * H / W
    let screenRect = CGRect(x: (W - PHONE_WIDTH) / 2, y: H - PHONE_TOP - phoneHeight,
                            width: PHONE_WIDTH, height: phoneHeight)
    let bezelRect = screenRect.insetBy(dx: -BEZEL, dy: -BEZEL)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 48, color: rgb(0x000000, 0.18))
    ctx.addPath(CGPath(roundedRect: bezelRect, cornerWidth: SCREEN_RADIUS + BEZEL,
                       cornerHeight: SCREEN_RADIUS + BEZEL, transform: nil))
    ctx.setFillColor(shot.palette.bezel)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: screenRect, cornerWidth: SCREEN_RADIUS,
                       cornerHeight: SCREEN_RADIUS, transform: nil))
    ctx.clip()
    ctx.draw(screen, in: screenRect)
    ctx.restoreGState()

    guard let image = ctx.makeImage() else { fatalError("image impossible") }
    let outURL = outDir.appendingPathComponent("\(shot.file).png")
    guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL,
                                                     UTType.png.identifier as CFString, 1, nil) else {
        fatalError("écriture impossible")
    }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    written += 1
}

print("OK : \(written) captures habillées dans docs/appstore/framed/")
