// NivelTests/SoundAssetsTests.swift
import XCTest
import AVFoundation
@testable import Nivel

final class SoundAssetsTests: XCTestCase {
    /// Garde de packaging (même esprit que SportAssetsTests) : les deux chimes sont
    /// bien embarqués, non vides, et leur durée est épinglée pour attraper une
    /// régénération partie de travers.
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
        }
    }
}
