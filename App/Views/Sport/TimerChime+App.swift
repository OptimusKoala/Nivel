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
    /// - Returns: true si le timer vient de basculer sur `finished`.
    @MainActor
    @discardableResult
    static func onTick(timer: ExerciseTimerModel, at date: Date,
                       isCurrent: Bool, chime: TimerChime) -> Bool {
        let overrun = timer.overrun(at: date)
        guard timer.syncNow(at: date) else { return false }
        guard let feedback = decide(overrun: overrun, transitioned: true,
                                    isCurrent: isCurrent,
                                    soundEnabled: SoundSettings.shared.timerSoundEnabled,
                                    chime: chime) else { return true }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if let chime = feedback.chime { SoundPlayer.shared.play(chime) }
        return true
    }
}
