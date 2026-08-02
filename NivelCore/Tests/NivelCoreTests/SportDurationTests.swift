import XCTest
@testable import NivelCore

final class SportDurationTests: XCTestCase {

    // MARK: Valeur d'ouverture de la roue

    func testOuvreSurLaDureeDejaChoisie() {
        XCTAssertEqual(CustomDuration.openingValue(current: 25, durations: [10, 20, 40]), 25)
    }

    func testSansSelectionOuvreSurLaMediane() {
        XCTAssertEqual(CustomDuration.openingValue(current: nil, durations: [10, 20, 40]), 20)
        XCTAssertEqual(CustomDuration.openingValue(current: nil, durations: [5, 10]), 10)
    }

    func testCatalogueVideOuValeurAberranteDonneVingt() {
        XCTAssertEqual(CustomDuration.openingValue(current: nil, durations: []), 20)
        XCTAssertEqual(CustomDuration.openingValue(current: 0, durations: []), 20)
        XCTAssertEqual(CustomDuration.openingValue(current: 999, durations: []), 20)
    }

    func testBornesDeLaRoue() {
        XCTAssertEqual(CustomDuration.range.lowerBound, 1)
        XCTAssertEqual(CustomDuration.range.upperBound, 240)
    }

    func testSelectionExposeSesMinutes() {
        XCTAssertEqual(DurationSelection.preset(20).minutes, 20)
        XCTAssertEqual(DurationSelection.custom(25).minutes, 25)
        XCTAssertFalse(DurationSelection.preset(20).isCustom)
        XCTAssertTrue(DurationSelection.custom(25).isCustom)
    }

    // MARK: Durée réellement enregistrée

    func testTimerJamaisLanceEnregistreLaDureeChoisie() {
        XCTAssertEqual(LoggedDuration.resolve(chosenMinutes: 20, elapsedSeconds: 0,
                                              timerUsed: false), 20)
    }

    func testTimerAlleAuBoutEnregistreLaDureeChoisie() {
        XCTAssertEqual(LoggedDuration.resolve(chosenMinutes: 20, elapsedSeconds: 1200,
                                              timerUsed: true), 20)
    }

    func testArretAnticipeEnregistreLEcoule() {
        XCTAssertEqual(LoggedDuration.resolve(chosenMinutes: 20, elapsedSeconds: 840,
                                              timerUsed: true), 14)
    }

    func testArrondiALaMinuteLaPlusProche() {
        // 13 min 40 s → 14 min ; 13 min 20 s → 13 min.
        XCTAssertEqual(LoggedDuration.resolve(chosenMinutes: 20, elapsedSeconds: 820,
                                              timerUsed: true), 14)
        XCTAssertEqual(LoggedDuration.resolve(chosenMinutes: 20, elapsedSeconds: 800,
                                              timerUsed: true), 13)
    }

    /// Une validation quasi immédiate ne doit pas enregistrer zéro minute.
    func testPlancherAUneMinute() {
        XCTAssertEqual(LoggedDuration.resolve(chosenMinutes: 20, elapsedSeconds: 0,
                                              timerUsed: true), 1)
        XCTAssertEqual(LoggedDuration.resolve(chosenMinutes: 20, elapsedSeconds: 29,
                                              timerUsed: true), 1)
    }

    /// L'écoulé du modèle est déjà plafonné, mais on ne dépend pas de ça.
    func testJamaisPlusQueLaDureeChoisie() {
        XCTAssertEqual(LoggedDuration.resolve(chosenMinutes: 20, elapsedSeconds: 9_999,
                                              timerUsed: true), 20)
    }

    func testDureeLibreMaximale() {
        XCTAssertEqual(LoggedDuration.resolve(chosenMinutes: 240, elapsedSeconds: 14_400,
                                              timerUsed: true), 240)
    }
}
