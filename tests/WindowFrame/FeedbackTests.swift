import AppKit
import AVFoundation

@MainActor final class RecordingOutput: WindowFrameCrankSoundOutput {
    var played: [WindowFrameCrankCue] = []
    var stops = 0
    var warms = 0
    func warm() { warms += 1 }
    func play(_ cue: WindowFrameCrankCue) { played.append(cue) }
    func stop() { stops += 1 }
}

@main @MainActor struct WindowFrameFeedbackTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("WindowFrame feedback: \(message)") }
    }
    static func peak(_ x: [Float]) -> Float { x.map { abs($0) }.max() ?? 0 }
    static func crossings(_ x: [Float]) -> Int { zip(x, x.dropFirst()).filter { ($0 < 0) != ($1 < 0) }.count }

    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        typealias S = WindowFrameCrankSound
        let rate = S.sampleRate
        check(S.notchClick(seed: 9, deep: false) == S.notchClick(seed: 9, deep: false), "clicks are deterministic")
        check(S.notchClick(seed: 9, deep: false).count == Int(rate * 0.07), "a notch click lasts 70 ms")
        check(S.notchClick(seed: 9, deep: true).count == Int(rate * 0.16), "the deep click at 10 lasts long enough to seat twice")
        check(S.endThunk(seed: 11, high: true).count == Int(rate * 0.75), "the end thunk carries its short creak")
        check(S.render(.notch(10)).count == Int(rate * 0.16) && S.render(.notch(9)).count == Int(rate * 0.07), "10 uses the deep click")

        for point in WindowFrameThickness.range {
            let samples = S.render(.notch(point))
            check(samples.allSatisfy { $0.isFinite }, "click \(point) is finite")
            check(peak(samples) > 0.02 && peak(samples) < 0.5, "click \(point) is audible but quiet (peak \(peak(samples)))")
        }
        for end in [WindowFrameCrank.End.thin, .thick] {
            let samples = S.render(.end(end))
            check(peak(samples) > 0.02 && peak(samples) <= S.ceiling, "the \(end) thunk is quiet and soft-clipped")
        }
        check(S.mastered([100, -100, 0], gain: 1).allSatisfy { abs($0) <= S.ceiling }, "soft clip never exceeds the ceiling")
        check(abs(S.mastered([0.01], gain: S.clickGain)[0] - 0.01 * S.clickGain * S.ceiling) < 0.0001, "quiet samples pass linearly at the click gain")
        let low = S.notchClick(seed: 1, deep: false, pitch: WindowFrameThickness.notchPitch(3))
        let high = S.notchClick(seed: 1, deep: false, pitch: WindowFrameThickness.notchPitch(13))
        check(crossings(high) > crossings(low), "clicks rise with the frame")
        check(S.render(.end(.thick)) != S.render(.end(.thin)), "the two ends sound different")
        check(S.normalized(.notch(20)) == .notch(13) && S.normalized(.notch(-4)) == .notch(3) && S.normalized(.end(.thin)) == .end(.thin),
              "cues are keyed by the clamped point")
        check(S.render(.notch(20)) == S.render(.notch(13)), "out-of-range notches sound like the nearest end point")
        check(S.allCues.count == WindowFrameThickness.range.count + 2 && Set(S.allCues).count == S.allCues.count, "every cue is listed once")
        let deep = S.notchClick(seed: 9, deep: true)
        let seatStart = Int(rate * 0.021)
        check(deep.allSatisfy { $0.isFinite } && peak(Array(deep[seatStart..<(seatStart + Int(rate * 0.004))])) > 0.01,
              "the deep click seats a second time")

        typealias V = WindowFrameCrankVoice
        let quiet = [V](repeating: V(), count: 3)
        check(V.pick(quiet, for: .notch(5), now: 1) == 0, "an idle voice plays first")
        let busy = [V(cue: .end(.thick), started: 0, until: 5), V(cue: .notch(5), started: 1, until: 5),
                    V(cue: .notch(10), started: 2, until: 5), V(cue: .notch(6), started: 3, until: 5)]
        check(V.pick(busy, for: .notch(7), now: 4) == 1, "a notch steals the oldest ordinary notch")
        let ended = busy.enumerated().map { $0.offset == 3 ? V(cue: .notch(6), started: 3, until: 3.5) : $0.element }
        check(V.pick(ended, for: .notch(7), now: 4) == 3, "a finished voice is preferred over stealing")
        let guarded = [V(cue: .end(.thick), started: 0, until: 5), V(cue: .notch(10), started: 1, until: 5)]
        check(V.pick(guarded, for: .notch(7), now: 4) == nil, "a notch never cuts the thunk or the deep click")
        check(V.pick(guarded, for: .end(.thin), now: 4) == 0, "an end thunk may take the oldest voice when every voice is busy")

        typealias F = WindowFrameCrankFeedback
        check(F.pattern(for: .notch(11)) == .alignment && F.pattern(for: .notch(3)) == .alignment, "an ordinary notch is a light tick")
        check(F.pattern(for: .notch(10)) == .levelChange, "10 is a firmer tick")
        check(F.pattern(for: .end(.thin)) == .levelChange && F.pattern(for: .end(.thick)) == .levelChange, "the ends are firmer ticks")
        check(F.cue(for: .notch(5)) == .notch(5) && F.cue(for: .end(.thick)) == .end(.thick), "events map to cues")

        let suite = "parc.windowFrameFeedbackTests.\(ProcessInfo.processInfo.processIdentifier)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let preferences = InterfaceFeedbackPreferences(defaults: defaults)
        check(F.allowsSound(preferences, active: true), "sounds play by default while Parc is active")
        check(!F.allowsSound(preferences, active: false), "no sounds while Parc is in the background")
        try? preferences.setPlaysSoundEffects(false)
        check(!F.allowsSound(preferences, active: true), "the interface sound setting silences the crank")
        defaults.set(Data("nope".utf8), forKey: "parc.interfaceFeedback.v1")
        let broken = InterfaceFeedbackPreferences(defaults: defaults)
        check(broken.loadError && !F.allowsSound(broken, active: true), "unreadable preferences stay silent")
        defaults.removePersistentDomain(forName: suite)

        var allowed = true
        var clock = 100.0
        var haptics: [NSHapticFeedbackManager.FeedbackPattern] = []
        var made = 0
        let output = RecordingOutput()
        let feedback = F(allowsSound: { allowed }, haptic: { haptics.append($0) }, output: { made += 1; return output }, now: { clock })
        feedback.stop()
        check(made == 0 && output.stops == 0, "nothing is created before the first sound")
        allowed = false
        feedback.begin()
        check(made == 0 && output.warms == 0, "presenting with sound off leaves the audio engine alone")
        allowed = true
        feedback.perform(.notch(11))
        check(output.played == [.notch(11)] && haptics == [.alignment] && made == 1, "a notch clicks and ticks")
        check(output.warms == 1, "the first sound warms the output once")
        feedback.perform(.notch(12))
        check(output.played == [.notch(11)] && haptics == [.alignment], "a burst of notches does not pile up clicks")
        feedback.perform(.notch(10))
        check(output.played == [.notch(11), .notch(10)] && haptics.last == .levelChange, "10 always seats")
        clock += 0.03
        feedback.perform(.notch(9))
        check(output.played.last == .notch(9), "the next notch clicks after a moment")
        feedback.perform(.end(.thin))
        check(output.played.last == .end(.thin) && haptics.last == .levelChange, "the end thunks right away")
        allowed = false
        clock += 1
        let before = output.played.count
        feedback.perform(.notch(8))
        check(output.played.count == before && haptics.last == .alignment, "silenced sound keeps the haptic")
        feedback.stop()
        check(output.stops == 1 && made == 1, "stop reaches the output once it exists")
        feedback.stop()
        check(output.stops == 1, "a second stop does not release the output twice")
        allowed = true
        feedback.begin()
        check(output.warms == 2 && made == 1, "presenting again warms the same output")
        feedback.begin()
        check(output.warms == 2, "a crank holds the output only once")
        feedback.stop()
        check(output.stops == 2, "each presentation releases the output once")

        let audio = WindowFrameCrankAudioOutput()
        let buffer = audio.buffer(for: .notch(10))
        check(buffer?.frameLength == AVAudioFrameCount(rate * 0.16) && buffer?.format.sampleRate == rate, "buffers hold the rendered click")
        check(audio.buffer(for: .notch(10)) === buffer, "buffers are made once")
        check(audio.buffer(for: .notch(42)) === audio.buffer(for: .notch(13)), "an out-of-range notch reuses the end point's buffer")
        check(buffer?.floatChannelData?[0][100] == S.render(.notch(10))[100], "buffers carry the exact samples")
        check(WindowFrameCrankAudioOutput.usable(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!), "a real output format is usable")
        check(!WindowFrameCrankAudioOutput.usable(AVAudioFormat()), "a missing output device is not touched")
        let engine = audio.prepare()
        check(engine == nil || (engine === audio.prepare() && engine?.isRunning == false && audio.isGraphReady && audio.voices.count == 6),
              "the engine is prepared without starting")
        audio.stop()
        check(engine?.isRunning != true && audio.holders == 0, "stopping an idle engine is harmless")
        audio.configurationChanged()
        check(!audio.isGraphReady && audio.voices.isEmpty && !audio.isRunning, "a device change tears the graph down and waits for the next presentation")
        check(engine == nil || audio.prepare() === engine && audio.isGraphReady && audio.voices.count == 6, "the graph rebuilds on the same engine")
        print("WindowFrame feedback: \(count) checks passed")
    }
}
