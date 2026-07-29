// App/Nivelito/NivelitoShapes.swift
// Traduction fidèle de design/nivelito.svg (espace de référence 200×200).
// Chaque Shape reprend mécaniquement les coordonnées du SVG :
//   C x1 y1, x2 y2, x y  →  addCurve(to: (x,y), control1: (x1,y1), control2: (x2,y2))
//   Q cx cy, x y         →  addQuadCurve(to: (x,y), control: (cx,cy))

import SwiftUI

// MARK: - Mise à l'échelle

extension Path {
    /// Met à l'échelle un path défini dans un espace de référence carré (200×200) vers rect.
    func scaled(toFit rect: CGRect, reference: CGFloat = 200) -> Path {
        let s = min(rect.width, rect.height) / reference
        return applying(CGAffineTransform(scaleX: s, y: s))
    }
}

// MARK: - Oreilles

/// SVG : M36 76 C26 48 34 26 56 24 C70 30 82 42 87 56 C68 58 50 66 36 76 Z
struct NivelitoEarLeft: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: .init(x: 36, y: 76))
        p.addCurve(to: .init(x: 56, y: 24), control1: .init(x: 26, y: 48), control2: .init(x: 34, y: 26))
        p.addCurve(to: .init(x: 87, y: 56), control1: .init(x: 70, y: 30), control2: .init(x: 82, y: 42))
        p.addCurve(to: .init(x: 36, y: 76), control1: .init(x: 68, y: 58), control2: .init(x: 50, y: 66))
        p.closeSubpath()
        return p.scaled(toFit: rect, reference: 200)
    }
}

/// SVG : M164 76 C174 48 166 26 144 24 C130 30 118 42 113 56 C132 58 150 66 164 76 Z
struct NivelitoEarRight: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: .init(x: 164, y: 76))
        p.addCurve(to: .init(x: 144, y: 24), control1: .init(x: 174, y: 48), control2: .init(x: 166, y: 26))
        p.addCurve(to: .init(x: 113, y: 56), control1: .init(x: 130, y: 30), control2: .init(x: 118, y: 42))
        p.addCurve(to: .init(x: 164, y: 76), control1: .init(x: 132, y: 58), control2: .init(x: 150, y: 66))
        p.closeSubpath()
        return p.scaled(toFit: rect, reference: 200)
    }
}

/// SVG : M46 66 C41 49 46 37 58 35 C65 39 71 46 74 53 C64 56 54 60 46 66 Z
struct NivelitoEarInnerLeft: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: .init(x: 46, y: 66))
        p.addCurve(to: .init(x: 58, y: 35), control1: .init(x: 41, y: 49), control2: .init(x: 46, y: 37))
        p.addCurve(to: .init(x: 74, y: 53), control1: .init(x: 65, y: 39), control2: .init(x: 71, y: 46))
        p.addCurve(to: .init(x: 46, y: 66), control1: .init(x: 64, y: 56), control2: .init(x: 54, y: 60))
        p.closeSubpath()
        return p.scaled(toFit: rect, reference: 200)
    }
}

/// SVG : M154 66 C159 49 154 37 142 35 C135 39 129 46 126 53 C136 56 146 60 154 66 Z
struct NivelitoEarInnerRight: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: .init(x: 154, y: 66))
        p.addCurve(to: .init(x: 142, y: 35), control1: .init(x: 159, y: 49), control2: .init(x: 154, y: 37))
        p.addCurve(to: .init(x: 126, y: 53), control1: .init(x: 135, y: 39), control2: .init(x: 129, y: 46))
        p.addCurve(to: .init(x: 154, y: 66), control1: .init(x: 136, y: 56), control2: .init(x: 146, y: 60))
        p.closeSubpath()
        return p.scaled(toFit: rect, reference: 200)
    }
}

// MARK: - Tête

/// SVG : M100 44 C146 44 173 64 176 104 C179 142 148 168 100 168 C52 168 21 142 24 104 C27 64 54 44 100 44 Z
struct NivelitoHead: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: .init(x: 100, y: 44))
        p.addCurve(to: .init(x: 176, y: 104), control1: .init(x: 146, y: 44), control2: .init(x: 173, y: 64))
        p.addCurve(to: .init(x: 100, y: 168), control1: .init(x: 179, y: 142), control2: .init(x: 148, y: 168))
        p.addCurve(to: .init(x: 24, y: 104), control1: .init(x: 52, y: 168), control2: .init(x: 21, y: 142))
        p.addCurve(to: .init(x: 100, y: 44), control1: .init(x: 27, y: 64), control2: .init(x: 54, y: 44))
        p.closeSubpath()
        return p.scaled(toFit: rect, reference: 200)
    }
}

// MARK: - Museau

/// SVG : M100 94 C128 94 148 108 148 130 C148 152 127 166 100 166 C73 166 52 152 52 130 C52 108 72 94 100 94 Z
struct NivelitoMuzzle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: .init(x: 100, y: 94))
        p.addCurve(to: .init(x: 148, y: 130), control1: .init(x: 128, y: 94), control2: .init(x: 148, y: 108))
        p.addCurve(to: .init(x: 100, y: 166), control1: .init(x: 148, y: 152), control2: .init(x: 127, y: 166))
        p.addCurve(to: .init(x: 52, y: 130), control1: .init(x: 73, y: 166), control2: .init(x: 52, y: 152))
        p.addCurve(to: .init(x: 100, y: 94), control1: .init(x: 52, y: 108), control2: .init(x: 72, y: 94))
        p.closeSubpath()
        return p.scaled(toFit: rect, reference: 200)
    }
}

// MARK: - Sourcils (virgules crème)

/// SVG : M60 84 C68 76 82 75 90 80 C80 72 64 74 60 84 Z
struct NivelitoBrowLeft: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: .init(x: 60, y: 84))
        p.addCurve(to: .init(x: 90, y: 80), control1: .init(x: 68, y: 76), control2: .init(x: 82, y: 75))
        p.addCurve(to: .init(x: 60, y: 84), control1: .init(x: 80, y: 72), control2: .init(x: 64, y: 74))
        p.closeSubpath()
        return p.scaled(toFit: rect, reference: 200)
    }
}

/// SVG : M140 84 C132 76 118 75 110 80 C120 72 136 74 140 84 Z
struct NivelitoBrowRight: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: .init(x: 140, y: 84))
        p.addCurve(to: .init(x: 110, y: 80), control1: .init(x: 132, y: 76), control2: .init(x: 118, y: 75))
        p.addCurve(to: .init(x: 140, y: 84), control1: .init(x: 120, y: 72), control2: .init(x: 136, y: 74))
        p.closeSubpath()
        return p.scaled(toFit: rect, reference: 200)
    }
}

// MARK: - Truffe

/// SVG : M90 122 Q100 116 110 122 Q108 134 100 136 Q92 134 90 122 Z
struct NivelitoNose: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: .init(x: 90, y: 122))
        p.addQuadCurve(to: .init(x: 110, y: 122), control: .init(x: 100, y: 116))
        p.addQuadCurve(to: .init(x: 100, y: 136), control: .init(x: 108, y: 134))
        p.addQuadCurve(to: .init(x: 90, y: 122), control: .init(x: 92, y: 134))
        p.closeSubpath()
        return p.scaled(toFit: rect, reference: 200)
    }
}

// MARK: - Bouches (tracés à stroker, largeur 5.5 × échelle, caps ronds)

/// Bouche par défaut (sourire).
/// SVG : M100 136 L100 143 M100 143 Q92 151 83 145 M100 143 Q108 151 117 145
struct NivelitoMouth: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: .init(x: 100, y: 136))
        p.addLine(to: .init(x: 100, y: 143))
        p.move(to: .init(x: 100, y: 143))
        p.addQuadCurve(to: .init(x: 83, y: 145), control: .init(x: 92, y: 151))
        p.move(to: .init(x: 100, y: 143))
        p.addQuadCurve(to: .init(x: 117, y: 145), control: .init(x: 108, y: 151))
        return p.scaled(toFit: rect, reference: 200)
    }
}

/// Sourire plus large (expression « encouraging ») : mêmes attaches, courbes amplifiées.
struct NivelitoBigSmileMouth: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: .init(x: 100, y: 136))
        p.addLine(to: .init(x: 100, y: 143))
        p.move(to: .init(x: 100, y: 143))
        p.addQuadCurve(to: .init(x: 79, y: 146), control: .init(x: 90, y: 155))
        p.move(to: .init(x: 100, y: 143))
        p.addQuadCurve(to: .init(x: 121, y: 146), control: .init(x: 110, y: 155))
        return p.scaled(toFit: rect, reference: 200)
    }
}

/// Petite bouche (expression « sleepy »).
struct NivelitoSmallMouth: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: .init(x: 100, y: 136))
        p.addLine(to: .init(x: 100, y: 142))
        p.move(to: .init(x: 94, y: 145))
        p.addQuadCurve(to: .init(x: 106, y: 145), control: .init(x: 100, y: 149))
        return p.scaled(toFit: rect, reference: 200)
    }
}

/// Bouche ouverte (expression « joy ») — forme pleine sous la truffe.
struct NivelitoOpenMouth: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: .init(x: 86, y: 141))
        p.addQuadCurve(to: .init(x: 114, y: 141), control: .init(x: 100, y: 136))
        p.addQuadCurve(to: .init(x: 86, y: 141), control: .init(x: 100, y: 163))
        p.closeSubpath()
        return p.scaled(toFit: rect, reference: 200)
    }
}

// MARK: - Yeux fermés (arcs à stroker)

/// Œil fermé joyeux « ∩ » (joy / wink), centré sur le centre de l'œil rond (r 12).
struct NivelitoJoyEye: Shape {
    var center: CGPoint
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: .init(x: center.x - 12, y: center.y + 3))
        p.addQuadCurve(to: .init(x: center.x + 12, y: center.y + 3),
                       control: .init(x: center.x, y: center.y - 13))
        return p.scaled(toFit: rect, reference: 200)
    }
}

/// Œil endormi : paupière lourde, arc plat légèrement tombant.
struct NivelitoSleepyEye: Shape {
    var center: CGPoint
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: .init(x: center.x - 12, y: center.y - 1))
        p.addQuadCurve(to: .init(x: center.x + 12, y: center.y - 1),
                       control: .init(x: center.x, y: center.y + 7))
        return p.scaled(toFit: rect, reference: 200)
    }
}

// MARK: - Formes rondes positionnées (yeux, reflets, blush, joues)

/// Ellipse définie dans l'espace de référence 200×200 (cercle si rx == ry).
struct NivelitoEllipse: Shape {
    var center: CGPoint
    var rx: CGFloat
    var ry: CGFloat

    init(center: CGPoint, rx: CGFloat, ry: CGFloat) {
        self.center = center
        self.rx = rx
        self.ry = ry
    }

    init(center: CGPoint, r: CGFloat) {
        self.init(center: center, rx: r, ry: r)
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: center.x - rx, y: center.y - ry, width: rx * 2, height: ry * 2))
        return p.scaled(toFit: rect, reference: 200)
    }
}
