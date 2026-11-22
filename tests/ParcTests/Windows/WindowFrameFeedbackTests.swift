import AppKit
import AVFoundation
import ParcTestSupport
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcKit
@testable import ParcSettings

struct WindowFrameFeedbackTests {
    private typealias Sound = WindowFrameCrankSound
    private typealias Voice = WindowFrameCrankVoice
    private typealias Feedback = WindowFrameCrankFeedback

    @Test
    func renderingTheSameClickTwiceProducesTheSameSamples() {
        #expect(Sound.notchClick(seed: 9, deep: false) == Sound.notchClick(seed: 9, deep: false))
    }

    @Test(arguments: [(false, 0.07), (true, 0.16)])
    func theSynthesizedClickLastsForItsCueDuration(deep: Bool, duration: Double) {
        #expect(Sound.notchClick(seed: 9, deep: deep).count == Int(Sound.sampleRate * duration))
    }

    @Test
    func theEndThunkHasTimeForItsCreak() {
        #expect(Sound.endThunk(seed: 11, high: true).count == Int(Sound.sampleRate * 0.75))
    }

    @Test(arguments: [(9, 0.07), (10, 0.16)])
    func theTenPointNotchUsesTheLongerClick(point: Int, duration: Double) {
        #expect(Sound.render(.notch(point)).count == Int(Sound.sampleRate * duration))
    }

    @Test(arguments: WindowFrameThickness.range)
    func eachNotchHasFiniteAudibleButQuietSamples(point: Int) {
        let samples = Sound.render(.notch(point))
        #expect(samples.allSatisfy { $0.isFinite })
        let peak = peakLevel(samples)
        #expect(peak > 0.02 && peak < 0.5)
    }

    @Test(arguments: [WindowFrameCrank.End.thin, .thick])
    func eachEndThunkStaysBelowTheCeiling(end: WindowFrameCrank.End) {
        let peak = peakLevel(Sound.render(.end(end)))
        #expect(peak > 0.02 && peak <= Sound.ceiling)
    }

    @Test
    func softClippingKeepsLoudSamplesWithinTheCeiling() {
        #expect(Sound.mastered([100, -100, 0], gain: 1).allSatisfy { abs($0) <= Sound.ceiling })
    }

    @Test
    func masteringPreservesTheLinearGainForQuietSamples() throws {
        let sample = try #require(Sound.mastered([0.01], gain: Sound.clickGain).first)
        #expect(abs(sample - 0.01 * Sound.clickGain * Sound.ceiling) < 0.0001)
    }

    @Test
    func clickPitchRisesWithTheFrameThickness() {
        let low = Sound.notchClick(seed: 1, deep: false, pitch: WindowFrameThickness.notchPitch(3))
        let high = Sound.notchClick(seed: 1, deep: false, pitch: WindowFrameThickness.notchPitch(13))
        #expect(zeroCrossings(high) > zeroCrossings(low))
    }

    @Test
    func theTwoEndsHaveDifferentThunks() {
        #expect(Sound.render(.end(.thick)) != Sound.render(.end(.thin)))
    }

    @Test(arguments: [
        (WindowFrameCrankCue.notch(20), WindowFrameCrankCue.notch(13)),
        (.notch(-4), .notch(3)),
        (.end(.thin), .end(.thin)),
    ])
    func cueIdentityUsesTheClampedNotch(cue: WindowFrameCrankCue, normalized: WindowFrameCrankCue) {
        #expect(Sound.normalized(cue) == normalized)
    }

    @Test
    func anOutOfRangeNotchSoundsLikeItsEndpoint() {
        #expect(Sound.render(.notch(20)) == Sound.render(.notch(13)))
    }

    @Test
    func everyCueAppearsExactlyOnce() {
        let notches = WindowFrameThickness.range.map(WindowFrameCrankCue.notch)
        let expected = Set(notches + [.end(.thin), .end(.thick)])
        #expect(Set(Sound.allCues) == expected)
        #expect(Sound.allCues.count == expected.count)
    }

    @Test
    func theDeepClickSeatsASecondTime() {
        let samples = Sound.notchClick(seed: 9, deep: true)
        let start = Int(Sound.sampleRate * 0.021)
        let end = start + Int(Sound.sampleRate * 0.004)
        #expect(samples.allSatisfy { $0.isFinite })
        #expect(peakLevel(samples[start..<end]) > 0.01)
    }

    @Test
    func theFirstIdleVoicePlaysTheClick() {
        let voices = Array(repeating: Voice(), count: 3)
        #expect(Voice.pick(voices, for: .notch(5), now: 1) == 0)
    }

    @Test
    func aClickTakesTheOldestOrdinaryNotchWhenAllVoicesAreBusy() {
        #expect(Voice.pick(busyVoices(), for: .notch(7), now: 4) == 1)
    }

    @Test
    func aClickPrefersAFinishedVoiceToInterruptingOne() {
        var voices = busyVoices()
        voices[3].until = 3.5
        #expect(Voice.pick(voices, for: .notch(7), now: 4) == 3)
    }

    @Test
    func anOrdinaryNotchLeavesTheDeepClickAndThunkPlaying() {
        let voices = [Voice(cue: .end(.thick), started: 0, until: 5), Voice(cue: .notch(10), started: 1, until: 5)]
        #expect(Voice.pick(voices, for: .notch(7), now: 4) == nil)
    }

    @Test
    func aThunkCanTakeTheOldestProtectedVoice() {
        let voices = [Voice(cue: .end(.thick), started: 0, until: 5), Voice(cue: .notch(10), started: 1, until: 5)]
        #expect(Voice.pick(voices, for: .end(.thin), now: 4) == 0)
    }

    @Test(arguments: [
        (WindowFrameCrank.Event.notch(11), false), (.notch(3), false), (.notch(10), true),
        (.end(.thin), true), (.end(.thick), true),
    ]) @MainActor
    func theDeepNotchAndEndsHaveAFirmerTick(event: WindowFrameCrank.Event, firm: Bool) {
        #expect(Feedback.pattern(for: event) == (firm ? .levelChange : .alignment))
    }

    @Test(arguments: [
        (WindowFrameCrank.Event.notch(5), WindowFrameCrankCue.notch(5)), (.end(.thick), .end(.thick)),
    ]) @MainActor
    func crankEventsMapToTheCorrespondingSoundCue(event: WindowFrameCrank.Event, cue: WindowFrameCrankCue) {
        #expect(Feedback.cue(for: event) == cue)
    }

    @Test(arguments: [true, false]) @MainActor
    func defaultSoundsPlayOnlyWhileParcIsActive(active: Bool) throws {
        let fixture = try Defaults()
        let preferences = InterfaceFeedbackPreferences(defaults: fixture.store)
        #expect(Feedback.allowsSound(preferences, active: active) == active)
    }

    @Test @MainActor
    func disablingInterfaceSoundsSilencesTheCrank() throws {
        let fixture = try Defaults()
        let preferences = InterfaceFeedbackPreferences(defaults: fixture.store)
        try preferences.setPlaysSoundEffects(false)
        #expect(!Feedback.allowsSound(preferences, active: true))
    }

    @Test @MainActor
    func unreadablePreferencesKeepTheCrankSilent() throws {
        let fixture = try Defaults()
        fixture.store.set(Data("nope".utf8), forKey: "parc.interfaceFeedback.v1")
        let preferences = InterfaceFeedbackPreferences(defaults: fixture.store)
        #expect(preferences.loadError)
        #expect(!Feedback.allowsSound(preferences, active: true))
    }

    @Test @MainActor
    func stoppingBeforeAnySoundDoesNotCreateAudioOutput() {
        let fixture = RecordingFeedback()
        fixture.feedback.stop()
        #expect(fixture.createdOutputs == 0)
        #expect(fixture.stops == 0)
    }

    @Test @MainActor
    func beginningWithSoundOffDoesNotWarmTheAudioOutput() {
        let fixture = RecordingFeedback()
        fixture.allowed = false
        fixture.feedback.begin()
        #expect(fixture.createdOutputs == 0)
        #expect(fixture.warms == 0)
    }

    @Test @MainActor
    func theFirstNotchWarmsTheOutputAndClicksAndTicks() {
        let fixture = RecordingFeedback()
        fixture.feedback.perform(.notch(11))
        #expect(fixture.played == [.notch(11)])
        #expect(fixture.haptics == [.alignment])
        #expect(fixture.createdOutputs == 1)
        #expect(fixture.warms == 1)
    }

    @Test @MainActor
    func rapidOrdinaryNotchesDoNotPileUpFeedback() {
        let fixture = RecordingFeedback()
        fixture.feedback.perform(.notch(11))
        fixture.feedback.perform(.notch(12))
        #expect(fixture.played == [.notch(11)])
        #expect(fixture.haptics == [.alignment])
    }

    @Test @MainActor
    func theDeepClickCanFollowAnOrdinaryNotchImmediately() {
        let fixture = RecordingFeedback()
        fixture.feedback.perform(.notch(11))
        fixture.feedback.perform(.notch(10))
        #expect(fixture.played == [.notch(11), .notch(10)])
        #expect(fixture.haptics == [.alignment, .levelChange])
    }

    @Test @MainActor
    func anOrdinaryNotchClicksAgainAfterTheMinimumInterval() {
        let fixture = RecordingFeedback()
        fixture.feedback.perform(.notch(10))
        fixture.time += 0.03
        fixture.feedback.perform(.notch(9))
        #expect(fixture.played == [.notch(10), .notch(9)])
    }

    @Test @MainActor
    func theThunkPlaysImmediatelyAfterAClick() {
        let fixture = RecordingFeedback()
        fixture.feedback.perform(.notch(9))
        fixture.feedback.perform(.end(.thin))
        #expect(fixture.played == [.notch(9), .end(.thin)])
        #expect(fixture.haptics == [.alignment, .levelChange])
    }

    @Test @MainActor
    func aMutedNotchStillTicks() {
        let fixture = RecordingFeedback()
        fixture.allowed = false
        fixture.feedback.perform(.notch(8))
        #expect(fixture.played.isEmpty)
        #expect(fixture.haptics == [.alignment])
    }

    @Test @MainActor
    func stoppingTwiceReleasesTheHeldOutputOnce() {
        let fixture = RecordingFeedback()
        fixture.feedback.begin()
        fixture.feedback.stop()
        fixture.feedback.stop()
        #expect(fixture.createdOutputs == 1)
        #expect(fixture.stops == 1)
    }

    @Test @MainActor
    func presentingAgainReusesTheSameOutput() {
        let fixture = RecordingFeedback()
        fixture.feedback.begin()
        fixture.feedback.stop()
        fixture.feedback.begin()
        #expect(fixture.createdOutputs == 1)
        #expect(fixture.warms == 2)
    }

    @Test @MainActor
    func beginningAgainDoesNotAcquireTheOutputTwice() {
        let fixture = RecordingFeedback()
        fixture.feedback.begin()
        fixture.feedback.begin()
        #expect(fixture.warms == 1)
    }

    @Test @MainActor
    func eachPresentationReleasesTheOutputOnce() {
        let fixture = RecordingFeedback()
        fixture.feedback.begin()
        fixture.feedback.stop()
        fixture.feedback.begin()
        fixture.feedback.stop()
        #expect(fixture.stops == 2)
    }

    @Test @MainActor
    func buffersCarryTheExactSynthesizedSamples() throws {
        let output = WindowFrameCrankAudioOutput()
        let buffer = try #require(output.buffer(for: .notch(10)))
        let samples = try #require(buffer.floatChannelData?[0])
        #expect(buffer.frameLength == AVAudioFrameCount(Sound.sampleRate * 0.16))
        #expect(buffer.format.sampleRate == Sound.sampleRate)
        #expect(samples[100] == Sound.render(.notch(10))[100])
    }

    @Test(arguments: [(10, 10), (42, 13)]) @MainActor
    func equivalentCuesReuseTheSameAudioBuffer(point: Int, equivalent: Int) throws {
        let output = WindowFrameCrankAudioOutput()
        let buffer = try #require(output.buffer(for: .notch(point)))
        #expect(output.buffer(for: .notch(equivalent)) === buffer)
    }

    @Test(arguments: [true, false]) @MainActor
    func usableAudioFormatsRequireAnOutputDevice(available: Bool) throws {
        let format = available ? try #require(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)) : AVAudioFormat()
        #expect(WindowFrameCrankAudioOutput.usable(format) == available)
    }

    @Test @MainActor
    func preparingBuildsTheGraphOnceWithoutStartingAudio() throws {
        let output = try offlineOutput()
        let engine = try #require(output.prepare())
        #expect(output.prepare() === engine)
        #expect(!engine.isRunning)
        #expect(output.isGraphReady)
        #expect(output.voices.count == 6)
    }

    @Test @MainActor
    func stoppingAnIdleEngineLeavesItStopped() throws {
        var pendingStop: DispatchWorkItem?
        let output = try offlineOutput { pendingStop = $0 }
        let engine = try #require(output.prepare())
        output.stop()
        let stop = try #require(pendingStop)
        stop.perform()
        #expect(!engine.isRunning)
        #expect(output.holders == 0)
    }

    @Test @MainActor
    func configurationChangeDropsTheIdleGraphWithoutStartingAudio() throws {
        let output = try offlineOutput()
        _ = try #require(output.prepare())
        output.configurationChanged()
        #expect(!output.isGraphReady)
        #expect(output.voices.isEmpty)
        #expect(!output.isRunning)
    }

    @Test @MainActor
    func preparationAfterAConfigurationChangeRebuildsTheSameEngine() throws {
        let output = try offlineOutput()
        let engine = try #require(output.prepare())
        output.configurationChanged()
        #expect(output.prepare() === engine)
        #expect(output.isGraphReady)
        #expect(output.voices.count == 6)
    }

    @MainActor
    private func offlineOutput(scheduleStop: @escaping (DispatchWorkItem) -> Void = { _ in }) throws -> WindowFrameCrankAudioOutput {
        let engine = AVAudioEngine()
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
        return WindowFrameCrankAudioOutput(now: { 100 }, makeAudioEngine: { engine }, scheduleStop: scheduleStop)
    }

    private func peakLevel(_ samples: some Collection<Float>) -> Float {
        samples.lazy.map { abs($0) }.max() ?? 0
    }

    private func zeroCrossings(_ samples: [Float]) -> Int {
        zip(samples, samples.dropFirst()).filter { ($0 < 0) != ($1 < 0) }.count
    }

    private func busyVoices() -> [WindowFrameCrankVoice] {
        [
            Voice(cue: .end(.thick), started: 0, until: 5),
            Voice(cue: .notch(5), started: 1, until: 5),
            Voice(cue: .notch(10), started: 2, until: 5),
            Voice(cue: .notch(6), started: 3, until: 5),
        ]
    }

    private final class Defaults {
        let store: UserDefaults
        init() throws { store = try #require(TestDefaults("parc.windowFrameFeedbackTests.")) }
    }

    @MainActor
    private final class RecordingFeedback {
        var allowed = true
        var time = 100.0
        var played: [WindowFrameCrankCue] = []
        var haptics: [NSHapticFeedbackManager.FeedbackPattern] = []
        var createdOutputs = 0
        var warms = 0
        var stops = 0

        lazy var feedback = Feedback(allowsSound: { [unowned self] in allowed },
                                     haptic: { [unowned self] in haptics.append($0) },
                                     output: { [unowned self] in
                                         createdOutputs += 1
                                         return output
                                     }, now: { [unowned self] in time })
        private lazy var output = Output(self)

        func warm() { warms += 1 }
        func play(_ cue: WindowFrameCrankCue) { played.append(cue) }
        func stop() { stops += 1 }

        private final class Output: WindowFrameCrankSoundOutput {
            unowned let recording: RecordingFeedback
            init(_ recording: RecordingFeedback) { self.recording = recording }
            func warm() { recording.warm() }
            func play(_ cue: WindowFrameCrankCue) { recording.play(cue) }
            func stop() { recording.stop() }
        }
    }
}
