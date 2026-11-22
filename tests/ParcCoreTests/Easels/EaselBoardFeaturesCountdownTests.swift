import Foundation
import Testing
@testable import ParcCore

struct EaselBoardFeaturesCountdownTests {
    @Test
    func aNewTimerOffersFiveMinutes() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let timer = EaselCountdown()
        #expect(timer.phase == .idle && timer.remaining(at: start) == 300, "a new timer offers five minutes")
    }

    @Test
    func idleTimerAdjustsByOneOrFiveMinutes() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var timer = EaselCountdown()
        timer.adjust(minutes: 1, at: start)
        timer.adjust(minutes: 5, at: start)
        #expect(timer.duration == 660, "up and Shift-up add one and five minutes")
    }

    @Test
    func idleAdjustmentsCannotGoBelowZero() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var timer = EaselCountdown()
        timer.adjust(minutes: 1, at: start)
        timer.adjust(minutes: 5, at: start)
        timer.adjust(minutes: -20, at: start)
        #expect(timer.duration == 0, "the timer never goes below zero")
    }

    @Test
    func anIdleTimerCannotExceedItsMaximum() {
        var timer = EaselCountdown()
        timer.set(minutes: 120)
        #expect(timer.duration == EaselCountdown.maximum && EaselCountdown.label(timer.duration) == "99:59", "the timer tops out at 99:59")
    }

    @Test
    func steppingDownFromTheMaximumFindsThePreviousWholeMinute() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var timer = EaselCountdown()
        timer.set(minutes: 120)
        timer.adjust(minutes: -1, at: start)
        #expect(timer.duration == 99 * 60, "stepping down from 99:59 lands on the whole minute below")
    }

    @Test
    func aRunningTimerCountsDown() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var timer = EaselCountdown()
        timer.set(minutes: 3)
        timer.start(at: start)
        #expect(timer.phase == .running && timer.remaining(at: start.addingTimeInterval(61)) == 119, "a running timer counts down")
    }

    @Test
    func aRunningTimerCannotBeShortened() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var timer = EaselCountdown()
        timer.set(minutes: 3)
        timer.start(at: start)
        timer.adjust(minutes: -1, at: start.addingTimeInterval(61))
        #expect(timer.remaining(at: start.addingTimeInterval(61)) == 119, "a running timer can't be shortened")
    }

    @Test
    func aRunningTimerCanAddAMinute() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var timer = EaselCountdown()
        timer.set(minutes: 3)
        timer.start(at: start)
        timer.addMinute(at: start.addingTimeInterval(61))
        #expect(timer.remaining(at: start.addingTimeInterval(61)) == 179, "+1 min adds a minute while running")
    }

    @Test
    func aPausedTimerFreezesItsRemainingTime() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var timer = EaselCountdown()
        timer.set(minutes: 3)
        timer.start(at: start)
        timer.pause(at: start.addingTimeInterval(91))
        #expect(timer.phase == .paused && timer.remaining(at: start.addingTimeInterval(500)) == 89, "pausing freezes the time left")
    }

    @Test
    func aPausedTimerCanAddAMinute() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var timer = EaselCountdown()
        timer.set(minutes: 3)
        timer.start(at: start)
        timer.pause(at: start.addingTimeInterval(91))
        timer.addMinute(at: start.addingTimeInterval(500))
        #expect(timer.remaining(at: start.addingTimeInterval(500)) == 149, "+1 min works while paused")
    }

    @Test
    func resumingContinuesFromThePausedTime() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var timer = EaselCountdown()
        timer.set(minutes: 3)
        timer.start(at: start)
        timer.pause(at: start.addingTimeInterval(91))
        timer.toggle(at: start.addingTimeInterval(600))
        #expect(timer.phase == .running && timer.remaining(at: start.addingTimeInterval(660)) == 29, "resuming carries on from the pause")
    }

    @Test
    func aRunningTimerBecomesDueAtZero() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var timer = EaselCountdown()
        timer.set(minutes: 3)
        timer.start(at: start)
        #expect(!timer.isDue(at: start.addingTimeInterval(179)) && timer.isDue(at: start.addingTimeInterval(180)), "the timer is due right at zero")
    }

    @Test
    func aFinishedTimerRestartsAtTheSetDuration() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var timer = EaselCountdown()
        timer.set(minutes: 3)
        timer.start(at: start)
        timer.finish()
        #expect(timer.phase == .finished && timer.remaining(at: start) == 0, "a finished timer reads zero")
        timer.start(at: start.addingTimeInterval(900))
        #expect(timer.phase == .running && timer.remaining(at: start.addingTimeInterval(900)) == 180, "starting again runs the same length")
    }

    @Test
    func resetReturnsToTheSetDuration() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var timer = EaselCountdown()
        timer.set(minutes: 3)
        timer.start(at: start)
        timer.reset()
        #expect(timer.phase == .idle && timer.remaining(at: start) == 180, "reset goes back to the set length")
    }

    @Test
    func visibleTimeRoundsUpToWholeSeconds() {
        #expect(EaselCountdown.label(65.2) == "01:06" && EaselCountdown.label(0) == "00:00", "labels round up to whole seconds")
    }

    @Test
    func spokenTimeUsesMinutesAndSeconds() {
        #expect(EaselCountdown.spoken(65) == "1 minute 5 seconds" && EaselCountdown.spoken(120) == "2 minutes", "VoiceOver hears plain words")
    }

    @Test
    func aZeroDurationTimerDoesNotStart() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var empty = EaselCountdown()
        empty.set(minutes: 0)
        empty.start(at: start)
        #expect(empty.phase == .idle, "a zero timer doesn't start")
    }
}
