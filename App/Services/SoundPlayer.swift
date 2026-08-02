// App/Services/SoundPlayer.swift
// Lecture des chimes du timer (spec v1.9 §3.2).
// Catégorie `.playback` : le son passe MALGRÉ l'interrupteur silencieux, ce qui est
// tout l'intérêt d'un timer qu'on pose par terre. `.mixWithOthers` : la musique en
// cours n'est ni coupée ni baissée. La session est activée une fois et jamais
// désactivée (désactiver à chaque son produit des micro-coupures chez les autres apps).

import Foundation
import AVFoundation
import NivelCore

@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()

    private var players: [TimerChime: AVAudioPlayer] = [:]
    private var sessionConfigured = false

    static func fileName(for chime: TimerChime) -> String {
        switch chime {
        case .step: "timer_step"
        case .done: "timer_done"
        }
    }

    func play(_ chime: TimerChime) {
        configureSessionIfNeeded()
        guard let player = player(for: chime) else { return }
        // Rejoue depuis le début plutôt que de superposer une deuxième instance : un
        // déclenchement rapproché coupe donc le précédent. Sans risque ici, `decide`
        // (TimerFeedback) ne fait jouer que la surface `isCurrent`, et une étape
        // d'exercice dure des dizaines de secondes, jamais deux fins en une frappe.
        player.currentTime = 0
        player.play()
    }

    private func configureSessionIfNeeded() {
        guard !sessionConfigured else { return }
        // Le flag est levé AVANT les `try?`, pas après : c'est ce qui rend un échec
        // définitif plutôt que retenté à chaque chime. Le déplacer après ressemblerait
        // à une correction d'ordre mais réintroduirait un martèlement de la session sur
        // chaque son si la configuration échoue une première fois. Voulu.
        sessionConfigured = true
        // Erreurs avalées : un son qui ne part pas ne casse jamais une séance.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    /// Construit à la demande puis conservé : `prepareToPlay` supprime la latence
    /// du premier déclenchement, qui tomberait pile sur la fin du timer.
    private func player(for chime: TimerChime) -> AVAudioPlayer? {
        if let existing = players[chime] { return existing }
        guard let url = Bundle.main.url(forResource: Self.fileName(for: chime),
                                        withExtension: "caf"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.prepareToPlay()
        players[chime] = player
        return player
    }
}
