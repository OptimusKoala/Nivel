// App/Views/Duo/DuoScannerView.swift
// Le scanner de QR code de l'appairage (spec 1.15 §3.6), c'est-à-dire
// `DataScannerViewController` de VisionKit enveloppé pour SwiftUI.
//
// Il ne décide de rien : il rend la chaîne lue, telle quelle, et c'est
// `DuoService.shareURL(from:)` qui juge. Un scanner lit n'importe quel carré noir, une
// étiquette de colis comme une affiche, et c'est très bien ainsi — le tri se fait à un
// seul endroit, éprouvé par des tests.
//
// Indisponible sur le simulateur et sans caméra autorisée : l'écran d'appairage teste
// `isSupported` et `isAvailable` avant de l'afficher et retombe sur son champ de saisie,
// jamais sur une impasse.

import SwiftUI
import VisionKit

struct DuoScannerView: UIViewControllerRepresentable {
    /// Appelé UNE seule fois, à la première lecture. Voir le coordinateur.
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            // Les QR codes et rien d'autre : un code-barres de paquet de pâtes n'a aucune
            // chance d'être une invitation, autant ne pas le proposer.
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: false,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        // `try?` : démarrer un scanner déjà démarré lève, et la caméra refusée lève aussi.
        // Ni l'un ni l'autre ne mérite d'interrompre qui que ce soit — l'écran affiche de
        // toute façon son champ « coller un lien » juste en dessous.
        try? scanner.startScanning()
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController,
                                          coordinator: Coordinator) {
        // Sans cela la caméra reste allumée derrière la feuille refermée.
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        /// Un QR code posé devant l'objectif est redétecté en continu. Sans ce verrou, on
        /// lancerait une acceptation de partage par image de caméra, soit plusieurs par
        /// seconde, sur la même invitation.
        private var aDejaLu = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ scanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !aDejaLu else { return }
            for item in addedItems {
                guard case .barcode(let code) = item,
                      let contenu = code.payloadStringValue, !contenu.isEmpty else { continue }
                aDejaLu = true
                onScan(contenu)
                return
            }
        }
    }
}
