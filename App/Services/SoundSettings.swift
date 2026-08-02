// App/Services/SoundSettings.swift
// Préférence de son du timer, PAR APPAREIL (spec v1.9 §3.5) : UserDefaults comme le
// thème, pas SwiftData. Aucune migration, aucun impact sur l'instantané du widget.

import Foundation
import Observation

@Observable
final class SoundSettings {
    static let shared = SoundSettings()
    static let defaultsKey = "nivel.timerSound"

    var timerSoundEnabled: Bool {
        didSet { defaults.set(timerSoundEnabled, forKey: Self.defaultsKey) }
    }

    private let defaults: UserDefaults

    /// `defaults` injectable pour les tests (suite dédiée, pas de pollution des vrais
    /// réglages). `object(forKey:)` et non `bool(forKey:)` : il faut distinguer
    /// « jamais réglé » (donc actif) de « réglé à false ».
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.timerSoundEnabled = defaults.object(forKey: Self.defaultsKey) as? Bool ?? true
    }
}
