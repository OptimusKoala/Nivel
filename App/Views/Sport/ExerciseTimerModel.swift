// App/Views/Sport/ExerciseTimerModel.swift
// État du timer d'exercice (spec timer §5) : machine à états sur HORLOGE MURALE
// (robuste au passage en arrière-plan), logique pure interrogeable avec une date
// injectée — les tests ne dorment jamais. Opt-in : ne démarre jamais seul.

import Foundation
import Observation

@Observable @MainActor
final class ExerciseTimerModel {
    enum Phase: Equatable {
        case idle
        case running(since: Date, alreadyElapsed: TimeInterval)
        case paused(elapsed: TimeInterval)
        case finished
    }

    let duration: TimeInterval
    private(set) var phase: Phase = .idle

    init(durationMinutes: Int) {
        self.duration = TimeInterval(durationMinutes) * 60
    }

    // MARK: Lecture (pures, date injectée)

    func elapsed(at now: Date = .now) -> TimeInterval {
        switch phase {
        case .idle: 0
        case .running(let since, let already): min(duration, already + now.timeIntervalSince(since))
        case .paused(let elapsed): elapsed
        case .finished: duration
        }
    }

    func remaining(at now: Date = .now) -> TimeInterval { max(0, duration - elapsed(at: now)) }

    func fraction(at now: Date = .now) -> Double {
        duration > 0 ? min(1, elapsed(at: now) / duration) : 1
    }

    var isRunning: Bool { if case .running = phase { true } else { false } }
    var isPaused: Bool { if case .paused = phase { true } else { false } }
    var isFinished: Bool { phase == .finished }
    var isIdle: Bool { phase == .idle }

    // MARK: Transitions

    func start(at now: Date = .now) { phase = .running(since: now, alreadyElapsed: 0) }

    func pause(at now: Date = .now) {
        guard isRunning else { return }
        phase = .paused(elapsed: elapsed(at: now))
    }

    func resume(at now: Date = .now) {
        guard case .paused(let elapsed) = phase else { return }
        phase = .running(since: now, alreadyElapsed: elapsed)
    }

    func reset() { phase = .idle }

    /// À appeler à chaque tick d'affichage et au retour au premier plan : bascule en
    /// `.finished` si l'échéance est passée. Retourne true UNIQUEMENT à la transition
    /// (pour ne déclencher haptique/son qu'une fois).
    @discardableResult
    func syncNow(at now: Date = .now) -> Bool {
        guard isRunning, remaining(at: now) <= 0 else { return false }
        phase = .finished
        return true
    }
}
