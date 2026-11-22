import QuartzCore

enum StartPageMarkEasterEgg: Equatable {
    case taffy, swoop, charge
}

enum StartPageMarkCue: Equatable {
    case begin(StartPageMarkEasterEgg)
    case track(CGVector)
    case release(CGVector)
    case discharge(CGFloat)
    case cancel(CGFloat)
}

enum StartPageMarkMotionStyle: Equatable {
    case motion, shimmer

    init(reduceMotion: Bool) { self = reduceMotion ? .shimmer : .motion }
}

enum StartPageMarkPlay: Equatable {
    case snap(CGVector)
    case swoop
    case loop
    case relax(CGFloat, StartPageMarkMotionStyle)
}

struct StartPageMarkActivity: Equatable {
    var windowVisible: Bool
    var occluded: Bool
    var miniaturized: Bool
    var hidden: Bool

    static let inactive = Self(windowVisible: false, occluded: true, miniaturized: false, hidden: true)

    var canAnimate: Bool { windowVisible && !occluded && !miniaturized && !hidden }
}

struct StartPageMarkSession: Equatable {
    enum Phase: Equatable {
        case rest
        case interacting(StartPageMarkEasterEgg, StartPageMarkMotionStyle)
        case playing(StartPageMarkEasterEgg, StartPageMarkMotionStyle)
    }

    enum Effect: Equatable {
        case track(CGVector)
        case charge(StartPageMarkMotionStyle)
        case play(StartPageMarkPlay)
        case shimmer
        case haptic
        case reset
    }

    private(set) var phase = Phase.rest
    private(set) var generation = 0
    private(set) var landing = false

    var isIdle: Bool { phase == .rest }

    mutating func handle(_ cue: StartPageMarkCue, canAnimate: Bool, reduceMotion: Bool) -> [Effect] {
        guard canAnimate else { return pause() }
        switch (cue, phase) {
        case (.begin(let egg), .rest):
            generation += 1
            let style = StartPageMarkMotionStyle(reduceMotion: reduceMotion)
            switch egg {
            case .taffy:
                phase = .interacting(.taffy, style)
                return []
            case .charge:
                phase = .interacting(.charge, style)
                return [.charge(style)]
            case .swoop:
                phase = .playing(.swoop, style)
                landing = style == .motion
                return style == .motion ? [.play(.swoop)] : [.shimmer, .haptic]
            }
        case (.track(let pull), .interacting(.taffy, .motion)):
            return [.track(pull)]
        case (.release(let pull), .interacting(.taffy, let style)):
            phase = .playing(.taffy, style)
            return style == .motion ? [.play(.snap(pull)), .haptic] : [.shimmer, .haptic]
        case (.discharge(let level), .interacting(.charge, let style)):
            phase = .playing(.charge, style)
            guard StartPageMarkCharge.launches(level) else { return [.play(.relax(level, style))] }
            landing = style == .motion
            return style == .motion ? [.play(.loop)] : [.shimmer, .haptic]
        case (.cancel(let level), .interacting(.charge, let style)):
            phase = .playing(.charge, style)
            return [.play(.relax(level, style))]
        default:
            return []
        }
    }

    mutating func land(generation landed: Int) -> [Effect] {
        guard landed == generation, landing, case .playing(_, .motion) = phase else { return [] }
        landing = false
        return [.haptic]
    }

    mutating func pause() -> [Effect] {
        guard phase != .rest else { return [] }
        generation += 1
        phase = .rest
        landing = false
        return [.reset]
    }

    mutating func finish(generation finished: Int) {
        guard finished == generation, case .playing = phase else { return }
        phase = .rest
        landing = false
    }
}

enum StartPageMarkFill: Equatable {
    case theme, ink, art

    init(colorMark: Bool, themeHasColor: Bool, incognito: Bool) {
        if colorMark { self = .art }
        else if incognito || !themeHasColor { self = .ink }
        else { self = .theme }
    }

    init(colorMark: Bool, themeHasColor: Bool, pagingHasColor: (from: Bool, to: Bool)?, incognito: Bool) {
        self.init(colorMark: colorMark, themeHasColor: pagingHasColor.map { $0.from || $0.to } ?? themeHasColor,
                  incognito: incognito)
    }
}

enum StartPageMarkTint {
    static func blend(_ from: CGColor, _ to: CGColor, progress: CGFloat) -> CGColor {
        let amount = StartPageMarkEasing.clamp(progress)
        guard let space = CGColorSpace(name: CGColorSpace.extendedSRGB),
              let start = from.converted(to: space, intent: .defaultIntent, options: nil)?.components,
              let end = to.converted(to: space, intent: .defaultIntent, options: nil)?.components,
              start.count == 4, end.count == 4,
              let mixed = CGColor(colorSpace: space, components: zip(start, end).map { $0 + ($1 - $0) * amount })
        else { return amount < 0.5 ? from : to }
        return mixed
    }
}

@MainActor
enum StartPageMarkShimmer {
    static let key = "parc.start-page-mark.shimmer"
    static let duration: CFTimeInterval = 0.9
    static let peakAlpha: CGFloat = 0.7

    static func sequence(_ colors: [CGColor]) -> [CGColor] {
        guard let first = colors.first, let last = colors.last else { return [] }
        return [first.copy(alpha: 0) ?? first] + colors.map { $0.copy(alpha: peakAlpha) ?? $0 } + [last.copy(alpha: 0) ?? last]
    }

    static func play(on layer: CALayer, colors: [CGColor], completion: @escaping @MainActor () -> Void) {
        guard colors.count > 1 else { completion(); return }
        let animation = CAKeyframeAnimation(keyPath: "backgroundColor")
        animation.values = colors
        animation.duration = duration
        animation.calculationMode = .linear
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { MainActor.assumeIsolated { completion() } }
        layer.backgroundColor = nil
        layer.add(animation, forKey: key)
        CATransaction.commit()
    }

    static func reset(_ layer: CALayer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAnimation(forKey: key)
        layer.backgroundColor = nil
        CATransaction.commit()
    }
}
