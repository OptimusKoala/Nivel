// NivelTests/SessionPlayerTests.swift
import XCTest
@testable import Nivel

final class SessionPlayerTests: XCTestCase {
    /// Le contrat EXHAUSTIF du bouton (spec illustrations §5.1, 5 lignes).
    func testButtonStateContract() {
        // Page 0 (aperçu)
        XCTAssertEqual(SessionPlayerSheet.buttonState(page: 0, stepCount: 3, done: false), .start)
        XCTAssertEqual(SessionPlayerSheet.buttonState(page: 0, stepCount: 3, done: true), .alreadyDone)
        // Étapes intermédiaires (done indifférent)
        XCTAssertEqual(SessionPlayerSheet.buttonState(page: 1, stepCount: 3, done: false), .next)
        XCTAssertEqual(SessionPlayerSheet.buttonState(page: 2, stepCount: 3, done: true), .next)
        // Dernière étape
        XCTAssertEqual(SessionPlayerSheet.buttonState(page: 3, stepCount: 3, done: false), .validate)
        XCTAssertEqual(SessionPlayerSheet.buttonState(page: 3, stepCount: 3, done: true), .alreadyDone)
        // Séance à une seule étape (fresh_air) : la page 1 est déjà la dernière.
        // (stepCount ≥ 1 est garanti par le catalogue — testSessionsLoadAndStepsResolve.)
        XCTAssertEqual(SessionPlayerSheet.buttonState(page: 1, stepCount: 1, done: false), .validate)
    }
}
