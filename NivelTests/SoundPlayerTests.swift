// NivelTests/SoundPlayerTests.swift
// `SoundAssetsTests` vérifie que les deux fichiers .caf sont embarqués, mais avec
// leurs noms écrits en dur indépendamment : si `fileName(for:)` inversait `.step`
// et `.done`, ce test-là resterait vert alors que l'app jouerait « séance terminée »
// à la fin d'une étape intermédiaire, et inversement. C'est ce mapping qu'on teste ici.

import XCTest
import NivelCore
@testable import Nivel

final class SoundPlayerTests: XCTestCase {
    // `fileName(for:)` est isolée @MainActor (elle vit sur `SoundPlayer`, lui-même
    // @MainActor) : le test doit l'être aussi pour l'appeler de façon synchrone.
    @MainActor
    func testFileNameCorrespondAuBonChime() {
        XCTAssertEqual(SoundPlayer.fileName(for: .step), "timer_step")
        XCTAssertEqual(SoundPlayer.fileName(for: .done), "timer_done")
    }
}
