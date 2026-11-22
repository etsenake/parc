import AppKit
import AVFoundation
import ParcCore

enum WindowFrameCrankCue: Hashable {
    case notch(Int)
    case end(WindowFrameCrank.End)
}

enum WindowFrameCrankSound {
    static let sampleRate: Double = 48000
    static let clickGain: Float = 0.24
    static let deepGain: Float = 0.32
    static let thunkGain: Float = 0.26
    static let ceiling: Float = 0.92

    static func normalized(_ cue: WindowFrameCrankCue) -> WindowFrameCrankCue {
        if case .notch(let point) = cue { return .notch(WindowFrameThickness.clamped(point)) }
        return cue
    }

    static func isProtected(_ cue: WindowFrameCrankCue) -> Bool {
        switch normalized(cue) {
        case .notch(let point): return point == WindowFrameThickness.standard
        case .end: return true
        }
    }

    static var allCues: [WindowFrameCrankCue] {
        WindowFrameThickness.range.map { WindowFrameCrankCue.notch($0) } + [.end(.thin), .end(.thick)]
    }

    static func render(_ cue: WindowFrameCrankCue) -> [Float] {
        switch cue {
        case .notch(let raw):
            let point = WindowFrameThickness.clamped(raw)
            let deep = point == WindowFrameThickness.standard
            return mastered(notchClick(seed: UInt64(3 + point * 2), deep: deep, pitch: WindowFrameThickness.notchPitch(point)),
                            gain: deep ? deepGain : clickGain)
        case .end(let end):
            return mastered(endThunk(seed: end == .thick ? 11 : 12, high: end == .thick), gain: thunkGain)
        }
    }

    static func mastered(_ samples: [Float], gain: Float) -> [Float] { samples.map { tanh($0 * gain) * ceiling } }

    static func notchClick(seed: UInt64, deep: Bool, pitch k: Double = 1) -> [Float] {
        let n = Int(sampleRate * (deep ? 0.16 : 0.07))
        var out = [Float](repeating: 0, count: n)
        var noise = Noise(state: seed)
        var bright = Biquad(), ring = Biquad(), seat = Biquad()
        bright.bandpass((deep ? 2400 : 3600) * k, q: 3.2)
        ring.bandpass((deep ? 1150 : 2150) * k, q: 9)
        seat.bandpass(2400 * k, q: 3.2)
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let hit = Float(exp(-t / 0.0011))
            let decay = Float(exp(-t / (deep ? 0.016 : 0.006)))
            let body = Float(exp(-t / (deep ? 0.03 : 0.009)))
            var x = bright.run(noise.white() * hit) * 1.6
            x += ring.run(noise.white() * hit * 2.5) * 1.4 * decay / max(hit, 0.05) * 0.25
            x += tone((deep ? 1150 : 2150) * k, i) * decay * (deep ? 0.22 : 0.16)
            x += tone((deep ? 150 : 210) * k, i) * body * (deep ? 0.55 : 0.22)
            if deep {
                let since = t - 0.021
                if since > 0 {
                    x += seat.run(noise.white() * Float(exp(-since / 0.0009))) * 0.9
                    x += tone(1600 * k, i) * Float(exp(-since / 0.006)) * 0.1
                }
            }
            out[i] = x
        }
        return out
    }

    static func endThunk(seed: UInt64, high: Bool) -> [Float] {
        let n = Int(sampleRate * 0.75)
        var out = [Float](repeating: 0, count: n)
        var noise = Noise(state: seed)
        var low = Biquad(), creak = Biquad()
        low.lowpass(420)
        creak.bandpass(high ? 900 : 700, q: 6)
        var nextSlip = 0.06
        var slip: Double = 0
        let slipDecay = exp(-1 / (sampleRate * 0.004))
        for i in 0..<n {
            let t = Double(i) / sampleRate
            var x = tone(high ? 92 : 78, i) * Float(exp(-t / 0.09)) * 0.75
            x += low.run(noise.white()) * Float(exp(-t / 0.05)) * 0.9
            if t >= nextSlip && t < 0.55 {
                slip = 1
                nextSlip = t + 0.022 + 0.012 * Double(abs(noise.white()))
            }
            slip *= slipDecay
            let strain = smooth(0.04, 0.12, Float(t)) * (1 - smooth(0.42, 0.6, Float(t)))
            x += creak.run(noise.white() * Float(slip)) * 2.2 * strain
            out[i] = x
        }
        return out
    }

    private static func tone(_ frequency: Double, _ i: Int) -> Float { Float(sin(2 * Double.pi * frequency * Double(i) / sampleRate)) }

    private static func smooth(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        let t = min(max((x - e0) / (e1 - e0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private struct Noise {
        var state: UInt64
        mutating func white() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float(Int64(bitPattern: state) >> 40) / Float(1 << 23)
        }
    }

    private struct Biquad {
        var b0: Float = 0, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
        var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0
        mutating func bandpass(_ f: Double, q: Double) {
            let w = 2 * Double.pi * f / WindowFrameCrankSound.sampleRate, alpha = sin(w) / (2 * q), a0 = 1 + alpha
            b0 = Float(alpha / a0); b1 = 0; b2 = Float(-alpha / a0); a1 = Float(-2 * cos(w) / a0); a2 = Float((1 - alpha) / a0)
        }
        mutating func lowpass(_ f: Double, q: Double = 0.707) {
            let w = 2 * Double.pi * f / WindowFrameCrankSound.sampleRate, alpha = sin(w) / (2 * q), c = cos(w), a0 = 1 + alpha
            b0 = Float((1 - c) / 2 / a0); b1 = Float((1 - c) / a0); b2 = b0; a1 = Float(-2 * c / a0); a2 = Float((1 - alpha) / a0)
        }
        mutating func run(_ x: Float) -> Float {
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x; y2 = y1; y1 = y
            return y
        }
    }
}

@MainActor
protocol WindowFrameCrankSoundOutput: AnyObject {
    func warm()
    func play(_ cue: WindowFrameCrankCue)
    func stop()
}

struct WindowFrameCrankVoice: Equatable {
    var cue: WindowFrameCrankCue?
    var started: TimeInterval = -.infinity
    var until: TimeInterval = -.infinity

    static func pick(_ voices: [WindowFrameCrankVoice], for cue: WindowFrameCrankCue, now: TimeInterval) -> Int? {
        func oldest(_ candidates: [Int]) -> Int? { candidates.min { voices[$0].started < voices[$1].started } }
        if let idle = oldest(voices.indices.filter { voices[$0].until <= now }) { return idle }
        if let ordinary = oldest(voices.indices.filter { voices[$0].cue.map { !WindowFrameCrankSound.isProtected($0) } ?? true }) {
            return ordinary
        }
        return WindowFrameCrankSound.isProtected(cue) ? oldest(Array(voices.indices)) : nil
    }
}

private final class NotificationToken {
    let token: NSObjectProtocol
    init(_ token: NSObjectProtocol) { self.token = token }
    deinit { NotificationCenter.default.removeObserver(token) }
}

@MainActor
final class WindowFrameCrankAudioOutput: WindowFrameCrankSoundOutput {
    static let shared = WindowFrameCrankAudioOutput()
    static let voiceCount = 6
    static let stopDelay: TimeInterval = 0.9

    private let format = AVAudioFormat(standardFormatWithSampleRate: WindowFrameCrankSound.sampleRate, channels: 1)
    private let now: () -> TimeInterval
    private let makeAudioEngine: () -> AVAudioEngine
    private let scheduleStop: (DispatchWorkItem) -> Void
    private var engine: AVAudioEngine?
    private var players: [AVAudioPlayerNode] = []
    private(set) var voices: [WindowFrameCrankVoice] = []
    private var buffers: [WindowFrameCrankCue: AVAudioPCMBuffer] = [:]
    private var graphReady = false
    private var graphFailed = false
    private var startFailed = false
    private var observer: NotificationToken?
    private var pendingStop: DispatchWorkItem?
    private(set) var holders = 0

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         makeAudioEngine: @escaping () -> AVAudioEngine = { AVAudioEngine() },
         scheduleStop: ((DispatchWorkItem) -> Void)? = nil) {
        self.now = now
        self.makeAudioEngine = makeAudioEngine
        self.scheduleStop = scheduleStop ?? { work in
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.stopDelay, execute: work)
        }
    }

    var isGraphReady: Bool { graphReady }
    var isRunning: Bool { engine?.isRunning == true }

    func buffer(for cue: WindowFrameCrankCue) -> AVAudioPCMBuffer? {
        let key = WindowFrameCrankSound.normalized(cue)
        if let cached = buffers[key] { return cached }
        let samples = WindowFrameCrankSound.render(key)
        guard let format, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            channel.update(from: base, count: samples.count)
        }
        buffers[key] = buffer
        return buffer
    }

    func synthesizeAll() {
        for cue in WindowFrameCrankSound.allCues { _ = buffer(for: cue) }
    }

    static func usable(_ format: AVAudioFormat) -> Bool { format.sampleRate > 0 && format.channelCount > 0 }

    @discardableResult
    func prepare() -> AVAudioEngine? {
        if graphReady, let engine { return engine }
        guard let format else { return nil }
        let made = engine ?? makeEngine()
        let hardware = made.outputNode.outputFormat(forBus: 0)
        guard Self.usable(hardware) else {
            graphFailed = true
            return nil
        }
        let mixer = made.mainMixerNode
        if let output = AVAudioFormat(standardFormatWithSampleRate: hardware.sampleRate, channels: hardware.channelCount) {
            made.connect(mixer, to: made.outputNode, format: output)
        }
        players = (0..<Self.voiceCount).map { _ in
            let player = AVAudioPlayerNode()
            made.attach(player)
            made.connect(player, to: mixer, format: format)
            return player
        }
        voices = Array(repeating: WindowFrameCrankVoice(), count: players.count)
        made.prepare()
        graphReady = true
        graphFailed = false
        return made
    }

    private func makeEngine() -> AVAudioEngine {
        let made = makeAudioEngine()
        engine = made
        observer = NotificationToken(NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: made,
                                                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.configurationChanged() }
        })
        return made
    }

    func configurationChanged() {
        guard let engine else { return }
        players.forEach { $0.stop(); engine.detach($0) }
        players = []
        voices = []
        graphReady = false
        graphFailed = false
        startFailed = false
        guard holders > 0 else { return }
        start()
    }

    @discardableResult
    private func start() -> Bool {
        guard !startFailed, let engine = prepare() else { return false }
        if !engine.isRunning {
            do { try engine.start() } catch { startFailed = true; return false }
        }
        return engine.isRunning
    }

    func warm() {
        pendingStop?.cancel(); pendingStop = nil
        holders += 1
        graphFailed = false
        startFailed = false
        synthesizeAll()
        start()
    }

    func play(_ cue: WindowFrameCrankCue) {
        guard let buffer = buffer(for: cue) else { return }
        if !graphReady && graphFailed { return }
        guard start(), let index = WindowFrameCrankVoice.pick(voices, for: cue, now: now()), players.indices.contains(index) else { return }
        let time = now()
        voices[index] = WindowFrameCrankVoice(cue: WindowFrameCrankSound.normalized(cue), started: time,
                                              until: time + Double(buffer.frameLength) / WindowFrameCrankSound.sampleRate)
        let player = players[index]
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    func stop() {
        holders = max(0, holders - 1)
        guard holders == 0, pendingStop == nil, engine != nil else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pendingStop = nil
                guard self.holders == 0 else { return }
                self.players.forEach { $0.stop() }
                self.voices = Array(repeating: WindowFrameCrankVoice(), count: self.players.count)
                self.engine?.stop()
            }
        }
        pendingStop = work
        scheduleStop(work)
    }
}

@MainActor
final class WindowFrameCrankFeedback {
    static let minimumClickInterval: TimeInterval = 0.025

    private let allowsSound: () -> Bool
    private let haptic: (NSHapticFeedbackManager.FeedbackPattern) -> Void
    private let makeOutput: () -> WindowFrameCrankSoundOutput
    private let now: () -> TimeInterval
    private var output: WindowFrameCrankSoundOutput?
    private var holding = false
    private var lastClick = -TimeInterval.infinity

    convenience init() {
        self.init(allowsSound: { WindowFrameCrankFeedback.allowsSound(.shared, active: NSApp?.isActive == true) },
                  haptic: { NSHapticFeedbackManager.defaultPerformer.perform($0, performanceTime: .now) },
                  output: { WindowFrameCrankAudioOutput.shared },
                  now: { ProcessInfo.processInfo.systemUptime })
    }

    init(allowsSound: @escaping () -> Bool, haptic: @escaping (NSHapticFeedbackManager.FeedbackPattern) -> Void,
         output: @escaping () -> WindowFrameCrankSoundOutput, now: @escaping () -> TimeInterval) {
        self.allowsSound = allowsSound; self.haptic = haptic; makeOutput = output; self.now = now
    }

    static func allowsSound(_ preferences: InterfaceFeedbackPreferences, active: Bool) -> Bool {
        active && !preferences.loadError && preferences.state.playsSoundEffects
    }

    static func pattern(for event: WindowFrameCrank.Event) -> NSHapticFeedbackManager.FeedbackPattern {
        switch event {
        case .notch(let point): return point == WindowFrameThickness.standard ? .levelChange : .alignment
        case .end: return .levelChange
        }
    }

    static func cue(for event: WindowFrameCrank.Event) -> WindowFrameCrankCue {
        switch event {
        case .notch(let point): return .notch(point)
        case .end(let end): return .end(end)
        }
    }

    func perform(_ event: WindowFrameCrank.Event) {
        if case .notch(let point) = event {
            let time = now()
            guard point == WindowFrameThickness.standard || time - lastClick >= Self.minimumClickInterval else { return }
            lastClick = time
        }
        haptic(Self.pattern(for: event))
        guard allowsSound() else { return }
        hold()?.play(Self.cue(for: event))
    }

    func begin() {
        guard allowsSound() else { return }
        hold()
    }

    @discardableResult
    private func hold() -> WindowFrameCrankSoundOutput? {
        let target = output ?? makeOutput()
        output = target
        if !holding {
            holding = true
            target.warm()
        }
        return target
    }

    func stop() {
        guard holding, let output else { return }
        holding = false
        output.stop()
    }
}
