// NivelTests/CelebrationDismissTests.swift
// Le glissement vers le haut qui écarte une célébration (spec v1.13 §4) — la partie
// PURE de la décision, extraite de `CelebrationsHost` pour être testable sans geste.

import XCTest
@testable import Nivel

final class CelebrationDismissTests: XCTestCase {
    private let threshold: CGFloat = 20
    private let limit: CGFloat = 60

    // MARK: Le seuil de fermeture

    func testUpwardDragBeyondThresholdDismisses() {
        XCTAssertTrue(CelebrationsHost.dismisses(translationHeight: -21, threshold: threshold))
        XCTAssertTrue(CelebrationsHost.dismisses(translationHeight: -200, threshold: threshold))
    }

    func testUpwardDragBelowThresholdDoesNotDismiss() {
        XCTAssertFalse(CelebrationsHost.dismisses(translationHeight: -19, threshold: threshold))
        XCTAssertFalse(CelebrationsHost.dismisses(translationHeight: 0, threshold: threshold))
    }

    /// Exactement au seuil : on NE ferme PAS (comparaison stricte). Pinné pour que le
    /// jour où quelqu'un passe de `<` à `<=`, le test le dise.
    func testExactlyAtThresholdDoesNotDismiss() {
        XCTAssertFalse(CelebrationsHost.dismisses(translationHeight: -20, threshold: threshold))
    }

    /// Une célébration se tire vers le HAUT, jamais vers le bas : un glissement
    /// descendant, même ample, ne la ferme pas.
    func testDownwardDragNeverDismisses() {
        XCTAssertFalse(CelebrationsHost.dismisses(translationHeight: 200, threshold: threshold))
    }

    // MARK: Le suivi du doigt

    func testFollowOffsetTracksUpwardMovement() {
        XCTAssertEqual(CelebrationsHost.followOffset(translationHeight: -15, limit: limit), -15)
    }

    /// Borné : sans plafond, la bannière irait se cacher sous l'encoche avant même
    /// d'être relâchée.
    func testFollowOffsetIsCappedUpwards() {
        XCTAssertEqual(CelebrationsHost.followOffset(translationHeight: -500, limit: limit), -limit)
    }

    /// Jamais de valeur positive : la bannière ne descend pas sous le doigt.
    func testFollowOffsetIgnoresDownwardMovement() {
        XCTAssertEqual(CelebrationsHost.followOffset(translationHeight: 80, limit: limit), 0)
        XCTAssertEqual(CelebrationsHost.followOffset(translationHeight: 0, limit: limit), 0)
    }
}
