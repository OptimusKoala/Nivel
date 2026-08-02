// NivelTests/SoundAssetsTests.swift
import XCTest
import AVFoundation
@testable import Nivel

final class SoundAssetsTests: XCTestCase {
    /// Plancher d'amplitude : bien en dessous des pics mesurés aujourd'hui (34 % / 48 %),
    /// mais assez haut pour attraper un buffer de zéros (gain nul, envelope effondrée,
    /// boucle mal bornée). C'est exactement le genre de silence que le Tink système
    /// remplacé par v1.9 produisait déjà, donc la garde qui compte est celle-ci, pas
    /// la durée ou le format qui survivraient tels quels à un rendu muet.
    static let minimumPeakAmplitude: Float = 0.05

    /// Garde de packaging (même esprit que SportAssetsTests) : les deux chimes sont
    /// bien embarqués, non vides, leur durée est épinglée pour attraper une
    /// régénération partie de travers, et surtout leur pic audio n'est pas nul.
    func testLesDeuxChimesSontEmbarques() throws {
        let expected: [String: Double] = ["timer_step": 0.36, "timer_done": 0.90]
        for (name, duration) in expected {
            let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "caf"),
                                    "asset manquant : \(name).caf")
            let file = try AVAudioFile(forReading: url)
            let actual = Double(file.length) / file.fileFormat.sampleRate
            XCTAssertEqual(actual, duration, accuracy: 0.02, "\(name).caf : durée inattendue")
            XCTAssertEqual(file.fileFormat.sampleRate, 44_100)
            XCTAssertEqual(file.fileFormat.channelCount, 1)

            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                 frameCapacity: AVAudioFrameCount(file.length)) else {
                XCTFail("\(name).caf : allocation du buffer de lecture échouée")
                continue
            }
            try file.read(into: buffer)
            let channelData = try XCTUnwrap(buffer.floatChannelData, "\(name).caf : pas de plan flottant")
            let frames = UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength))
            let peak = frames.reduce(Float(0)) { max($0, abs($1)) }
            XCTAssertGreaterThan(peak, Self.minimumPeakAmplitude,
                                 "\(name).caf : pic quasi nul, chime probablement silencieux")
        }
    }
}
