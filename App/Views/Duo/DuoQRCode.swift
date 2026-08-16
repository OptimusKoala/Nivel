// App/Views/Duo/DuoQRCode.swift
// Le QR code de l'invitation (spec 1.15 §3.6).
//
// Un carré noir et blanc pour n'avoir à taper aucune URL : les deux téléphones sont côte
// à côte, l'un montre, l'autre scanne. Le lien reste offert en dessous pour le cas
// contraire.
//
// Rendu en `UIImage` plutôt qu'en `Image(ciImage:)` pour une raison mesurable, épinglée
// par un test : `CIFilter.qrCodeGenerator` sort un carré d'une vingtaine de pixels de
// côté. Confié tel quel à SwiftUI, il est étiré avec lissage et devient un flou gris que
// la caméra d'en face ne lit pas. L'agrandissement doit se faire AVANT le rendu, sur
// l'image vectorielle, et l'affichage doit couper l'interpolation.

import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

enum DuoQRCode {
    /// Côté de l'image produite, en points. 260 pt tient dans la largeur d'un iPhone SE
    /// avec ses marges, et laisse de quoi scanner à trente centimètres.
    static let side: CGFloat = 260

    /// Le QR code du texte donné, ou `nil` s'il n'y a rien à encoder.
    ///
    /// `nil` et pas une image vide : `DuoIdentity.shareURL` est nil tant que le partage
    /// n'a pas été créé, et un carré affiché à ce moment-là se ferait scanner pour rien.
    /// L'écran montre alors son indicateur d'attente.
    static func image(from text: String, side: CGFloat = side) -> UIImage? {
        let contenu = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !contenu.isEmpty else { return nil }

        let filtre = CIFilter.qrCodeGenerator()
        filtre.message = Data(contenu.utf8)
        // « M » : 15 % de redondance, le compromis d'Apple par défaut. Plus haut
        // épaissirait le motif sans gagner grand-chose sur un écran, qui n'a ni pli ni tache.
        filtre.correctionLevel = "M"

        guard let sortie = filtre.outputImage, sortie.extent.width > 0 else { return nil }

        let facteur = side / sortie.extent.width
        let agrandi = sortie.transformed(by: CGAffineTransform(scaleX: facteur, y: facteur))
        guard let bitmap = CIContext().createCGImage(agrandi, from: agrandi.extent) else {
            return nil
        }
        return UIImage(cgImage: bitmap)
    }
}
