// App/Views/Sport/TimerChime+App.swift
// Unique site d'appel du tick de fin de timer (spec v1.9 §3.4). Avant la v1.9 ce bloc
// était copié dans ActivityLogSheet et dans StepPageView, avec l'ordre « overrun avant
// syncNow » à retenir des deux côtés.

import Foundation
import UIKit
import NivelCore

extension TimerChime {
    /// Fait avancer le timer d'un tick et joue le retour de fin s'il y a lieu.
    /// L'ordre est imposé par le modèle : lire `overrun` AVANT `syncNow`, car une
    /// fois `.finished` il retourne toujours nil.
    /// Ne rend rien : les vues qui ont besoin de savoir que le timer est fini
    /// observent `timer.isFinished`, elles n'ont pas à guetter le retour d'ici.
    @MainActor
    static func onTick(timer: ExerciseTimerModel, at date: Date,
                       isCurrent: Bool, chime: TimerChime) {
        let overrun = timer.overrun(at: date)
        guard timer.syncNow(at: date) else { return }
        // `transitioned` est toujours vrai ici, le guard ci-dessus l'exige. Le paramètre
        // existe pour que `decide` reste interrogeable seule, y compris sur ce cas.
        guard let feedback = decide(overrun: overrun, transitioned: true,
                                    isCurrent: isCurrent,
                                    soundEnabled: SoundSettings.shared.timerSoundEnabled,
                                    chime: chime) else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        // Distinct du paramètre `chime` : celui-ci vaut nil quand le son est coupé
        // dans les Réglages, auquel cas seule l'haptique part.
        if let audibleChime = feedback.chime { SoundPlayer.shared.play(audibleChime) }
    }
}
