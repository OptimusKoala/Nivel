// NivelTests/SessionPlayerTests.swift
import XCTest
import NivelCore
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

    /// Les deux tables de correspondance de `SessionPlayerKind`, épinglées ensemble :
    /// `overlineText` (l'aperçu) et `xpAction` (le montant annoncé par le CTA). Elles
    /// vivent à côté d'un TROISIÈME `switch`, celui de `validate()`, qui choisit la
    /// méthode de log — trois routages parallèles sur le même `kind`.
    ///
    /// Les trois actions valant 40 XP aujourd'hui, une `xpAction` inversée ne se
    /// verrait NULLE PART à l'écran : le CTA annoncerait le bon nombre en créditant la
    /// mauvaise règle, jusqu'au jour où l'un des barèmes changerait.
    func testCorrespondancesDeSessionPlayerKind() {
        let attendu: [(SessionPlayerKind, String, XPAction)] = [
            (.dailySession, "Séance du jour", .dailySessionDone),
            (.posture, "Séance du soir", .postureSessionDone),
            (.muscu, "Séance muscu", .muscuSessionDone),
        ]
        for (kind, overline, action) in attendu {
            XCTAssertEqual(kind.overlineText, overline)
            XCTAssertEqual(kind.xpAction, action)
        }
    }
}
