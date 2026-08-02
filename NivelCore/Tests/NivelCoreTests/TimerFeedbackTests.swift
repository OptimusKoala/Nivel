import XCTest
@testable import NivelCore

final class TimerFeedbackTests: XCTestCase {
    private func decide(overrun: TimeInterval? = 0.1, transitioned: Bool = true,
                        isCurrent: Bool = true, soundEnabled: Bool = true,
                        chime: TimerChime = .done) -> TimerChime.Feedback? {
        TimerChime.decide(overrun: overrun, transitioned: transitioned,
                          isCurrent: isCurrent, soundEnabled: soundEnabled, chime: chime)
    }

    func testFinDirecteJoueLeChime() {
        XCTAssertEqual(decide()?.chime, .done)
        XCTAssertEqual(decide(chime: .step)?.chime, .step)
    }

    func testSansTransitionRienNeSePasse() {
        XCTAssertNil(decide(transitioned: false))
    }

    func testPageNonCouranteResteMuette() {
        XCTAssertNil(decide(isCurrent: false))
    }

    /// Fin vécue en différé (app en arrière-plan) : on ne célèbre pas après coup.
    func testDepassementAuDelaDeLaToleranceResteMuet() {
        XCTAssertNil(decide(overrun: 2))
        XCTAssertNil(decide(overrun: 30))
        XCTAssertNotNil(decide(overrun: 1.99))
    }

    /// Timer en pause dont l'échéance est passée : le modèle renvoie nil pour overrun.
    func testOverrunInconnuResteMuet() {
        XCTAssertNil(decide(overrun: nil))
    }

    /// Son coupé dans les Réglages : l'haptique reste, le chime disparaît.
    func testSonCoupeGardeLHaptique() {
        let feedback = decide(soundEnabled: false)
        XCTAssertNotNil(feedback)
        XCTAssertNil(feedback?.chime)
    }

    func testChimeDeLEtape() {
        XCTAssertEqual(TimerChime.forStep(number: 1, stepCount: 3), .step)
        XCTAssertEqual(TimerChime.forStep(number: 2, stepCount: 3), .step)
        XCTAssertEqual(TimerChime.forStep(number: 3, stepCount: 3), .done)
        XCTAssertEqual(TimerChime.forStep(number: 1, stepCount: 1), .done)
    }
}
