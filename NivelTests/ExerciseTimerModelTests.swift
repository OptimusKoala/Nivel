// NivelTests/ExerciseTimerModelTests.swift
import XCTest
@testable import Nivel

@MainActor
final class ExerciseTimerModelTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func t(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    func testIdleThenRunningCountsDown() {
        let timer = ExerciseTimerModel(durationMinutes: 3)   // 180 s
        XCTAssertEqual(timer.remaining(at: t0), 180)
        XCTAssertEqual(timer.fraction(at: t0), 0)
        timer.start(at: t0)
        XCTAssertEqual(timer.remaining(at: t(60)), 120)
        XCTAssertEqual(timer.fraction(at: t(90)), 0.5, accuracy: 0.001)
    }

    func testPauseFreezesAndResumeContinues() {
        let timer = ExerciseTimerModel(durationMinutes: 3)
        timer.start(at: t0)
        timer.pause(at: t(30))
        XCTAssertEqual(timer.remaining(at: t(999)), 150)     // figé pendant la pause
        timer.resume(at: t(100))
        XCTAssertEqual(timer.remaining(at: t(130)), 120)     // 30 s écoulées + 30 s après reprise
    }

    func testExpiryFlipsToFinishedIncludingWhileAway() {
        let timer = ExerciseTimerModel(durationMinutes: 3)
        timer.start(at: t0)
        // Retour au premier plan APRÈS l'échéance (app en arrière-plan pendant le timer).
        XCTAssertTrue(timer.syncNow(at: t(190)))              // transition → finished (une seule fois)
        XCTAssertTrue(timer.isFinished)
        XCTAssertEqual(timer.remaining(at: t(999)), 0)
        XCTAssertFalse(timer.syncNow(at: t(200)))             // pas de double transition
    }

    func testResetReturnsToIdle() {
        let timer = ExerciseTimerModel(durationMinutes: 3)
        timer.start(at: t0)
        timer.pause(at: t(10))
        timer.reset()
        XCTAssertEqual(timer.remaining(at: t(500)), 180)
        XCTAssertFalse(timer.isRunning)
        XCTAssertFalse(timer.isFinished)
    }

    func testFractionClampsAtOne() {
        let timer = ExerciseTimerModel(durationMinutes: 3)
        timer.start(at: t0)
        XCTAssertEqual(timer.fraction(at: t(9_999)), 1.0)
    }

    func testSyncNowIsNoOpBeforeDeadline() {
        let timer = ExerciseTimerModel(durationMinutes: 3)
        timer.start(at: t0)
        XCTAssertFalse(timer.syncNow(at: t(179)))
        XCTAssertTrue(timer.isRunning)
    }

    func testPauseAndResumeAreNoOpsOutsideTheirPhase() {
        let timer = ExerciseTimerModel(durationMinutes: 3)
        timer.pause(at: t0);  XCTAssertTrue(timer.isIdle)
        timer.resume(at: t0); XCTAssertTrue(timer.isIdle)
        XCTAssertFalse(timer.syncNow(at: t(9_999)))
        XCTAssertTrue(timer.isIdle)
    }

    func testPauseAtExactDeadlineStillFinishesOnNextSync() {
        let timer = ExerciseTimerModel(durationMinutes: 3)
        timer.start(at: t0)
        timer.pause(at: t(180))                          // pile à l'échéance
        XCTAssertTrue(timer.syncNow(at: t(180.5)))       // le tick suivant termine
        XCTAssertTrue(timer.isFinished)
    }

    func testOverrunReportsSmallDelayAndNilWhenNotRunning() {
        let timer = ExerciseTimerModel(durationMinutes: 3)
        XCTAssertNil(timer.overrun(at: t0))              // idle
        timer.start(at: t0)
        XCTAssertNil(timer.overrun(at: t(100)))          // avant l'échéance
        XCTAssertEqual(try XCTUnwrap(timer.overrun(at: t(181))), 1, accuracy: 0.001)
        timer.syncNow(at: t(181))
        XCTAssertNil(timer.overrun(at: t(182)))          // finished → nil
    }
}
