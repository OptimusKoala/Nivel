// NivelTests/SoundSettingsTests.swift
import XCTest
@testable import Nivel

final class SoundSettingsTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "nivel.tests.sound.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// Le son est actif par défaut : c'est tout l'intérêt de la fonctionnalité.
    func testActifParDefaut() {
        XCTAssertTrue(SoundSettings(defaults: defaults).timerSoundEnabled)
    }

    func testLeChoixEstPersiste() {
        SoundSettings(defaults: defaults).timerSoundEnabled = false
        XCTAssertFalse(SoundSettings(defaults: defaults).timerSoundEnabled)
    }

    /// `false` persisté doit survivre : un `bool(forKey:)` naïf le confondrait
    /// avec l'absence de clé, mais ici les deux donnent des résultats différents.
    func testFauxPersisteNEstPasConfonduAvecLAbsence() {
        defaults.set(false, forKey: SoundSettings.defaultsKey)
        XCTAssertFalse(SoundSettings(defaults: defaults).timerSoundEnabled)
        defaults.removeObject(forKey: SoundSettings.defaultsKey)
        XCTAssertTrue(SoundSettings(defaults: defaults).timerSoundEnabled)
    }
}
