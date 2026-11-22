import AppKit
import Metal
import SceneKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcSettings

enum WindowFrameViewTestsSupport {
    typealias CrankView = WindowFrameCrankView

    static let lightPalette = WindowFrameCrankPalette(
        accent: NSColor(srgbRed: 0.76, green: 0.31, blue: 0.42, alpha: 1),
        deep: NSColor(srgbRed: 0.93, green: 0.59, blue: 0.71, alpha: 1),
        cap: NSColor(srgbRed: 0.90, green: 0.56, blue: 0.62, alpha: 1), dark: false
    )
    static var light: WindowFrameCrankPalette { Self.lightPalette }
    static let dark = WindowFrameCrankPalette(
        accent: NSColor(srgbRed: 0.30, green: 0.55, blue: 1, alpha: 1),
        deep: NSColor(srgbRed: 0.05, green: 0.06, blue: 0.08, alpha: 1),
        cap: NSColor(srgbRed: 0.14, green: 0.15, blue: 0.18, alpha: 1), dark: true
    )

    static func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.01) -> Bool {
        abs(a - b) < tolerance
    }

    static func near(_ a: CGPoint, _ b: CGPoint, _ tolerance: CGFloat = 0.01) -> Bool {
        hypot(a.x - b.x, a.y - b.y) < tolerance
    }

    @MainActor
    static func makeModel() -> WindowFrameCrankModel {
        WindowFrameCrankModel(side: CrankView.side, palette: light)
    }

    @MainActor
    static func shadowImage() throws -> CrankImage {
        let model = makeModel()
        model.setArm(degrees: 90)
        model.root.isHidden = true
        return try CrankImage(model: model)
    }

    struct Finish: Equatable {
        let commit: Bool
        let value: Int
    }

    @MainActor
    final class Harness {
        let window: NSWindow?
        let view: WindowFrameCrankView
        let output = RecordingOutput()
        var haptics: [NSHapticFeedbackManager.FeedbackPattern] = []
        var events: [WindowFrameCrank.Event] = []
        var previews: [CGFloat] = []
        var finishes: [Finish] = []
        private let clock: TestClock
        var reduceMotion: Bool {
            get { clock.reduceMotion }
            set { clock.reduceMotion = newValue }
        }

        init(value: Int = 10, palette: WindowFrameCrankPalette? = nil, reduceMotion: Bool = false, hosted: Bool = false) {
            _ = NSApplication.shared
            if hosted {
                let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                                    styleMask: .borderless, backing: .buffered, defer: false)
                host.isReleasedWhenClosed = false
                window = host
            } else {
                window = nil
            }
            let clock = TestClock(reduceMotion: reduceMotion)
            self.clock = clock
            let feedback = WindowFrameCrankFeedback(allowsSound: { true }, haptic: { clock.haptics.append($0) },
                                                    output: { [output] in output }, now: { clock.time })
            view = WindowFrameCrankView(value: value, palette: palette ?? lightPalette,
                                       feedback: feedback, reducesMotion: { clock.reduceMotion },
                                       now: { clock.time }, startTimer: clock.startTimer)
            if let window {
                view.frame.origin = CGPoint(x: 40, y: 30)
                window.contentView?.addSubview(view)
            }
            view.onEvent = { [weak self] event in
                self?.haptics = clock.haptics
                self?.events.append(event)
            }
            view.onPreview = { [weak self] in self?.previews.append($0) }
            view.onFinish = { [weak self] in self?.finishes.append(Finish(commit: $0, value: $1)) }
        }

        deinit {
            MainActor.assumeIsolated {
                if let window {
                    view.removeFromSuperview()
                    window.close()
                }
            }
        }

        static func presented(value: Int = 10, reduceMotion: Bool = false, hosted: Bool = false) -> Harness {
            let fixture = Harness(value: value, reduceMotion: reduceMotion, hosted: hosted)
            fixture.view.present()
            fixture.advance(0.5)
            return fixture
        }

        static func steppedUp() -> Harness {
            let fixture = presented()
            fixture.view.keyDown(with: fixture.key(126))
            return fixture
        }

        static func escaping(hosted: Bool = false) -> Harness {
            let fixture = presented(hosted: hosted)
            fixture.view.keyDown(with: fixture.key(126))
            fixture.view.keyDown(with: fixture.key(126))
            fixture.advance(0.1)
            fixture.view.keyDown(with: fixture.key(53))
            return fixture
        }

        func advance(_ seconds: Double) {
            clock.time += seconds
            if let pending = clock.wheel, pending.deadline <= clock.time {
                clock.wheel = nil
                if pending.timer.isValid { pending.timer.fire() }
            }
            view.advance(by: seconds)
        }

        func sample(_ seconds: Double) {
            let frameInterval = 1.0 / 60
            for _ in 0..<Int((seconds / frameInterval).rounded(.up)) { advance(frameInterval) }
        }

        func superPoint(_ local: CGPoint) -> CGPoint { view.convert(local, to: view.superview) }

        func mouse(_ type: NSEvent.EventType, _ local: CGPoint) -> NSEvent {
            let point = view.convert(local, to: nil)
            return NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                      windowNumber: window?.windowNumber ?? 0, context: nil,
                                      eventNumber: 0, clickCount: 1, pressure: 1)!
        }

        func key(_ code: UInt16) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                             windowNumber: window?.windowNumber ?? 0, context: nil, characters: "",
                             charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
        }

        func scroll(_ delta: Int32, precise: Bool, phase: Int64 = 0, momentum: Int64 = 0, horizontal: Int32 = 0) -> NSEvent {
            let event = CGEvent(scrollWheelEvent2Source: nil, units: precise ? .pixel : .line, wheelCount: 2,
                                wheel1: delta, wheel2: horizontal, wheel3: 0)!
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
            event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: precise ? 1 : 0)
            return NSEvent(cgEvent: event)!
        }

        func scrollTrackpad() -> WindowFrameCrank {
            var reference = WindowFrameCrank(value: view.crank.value)
            let began = scroll(40, precise: true, phase: 1)
            let changed = scroll(40, precise: true, phase: 2)
            view.scrollWheel(with: began)
            view.scrollWheel(with: changed)
            reference.turn(degrees: WindowFrameCrank.scrollDegrees(deltaY: Double(began.scrollingDeltaY), precise: true))
            reference.turn(degrees: WindowFrameCrank.scrollDegrees(deltaY: Double(changed.scrollingDeltaY), precise: true))
            return reference
        }

        func dragKnob(degrees: CGFloat) {
            let hub = view.hub
            let radius: CGFloat = 60
            let angle = (90 - degrees) * .pi / 180
            view.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: hub.x, y: hub.y + radius)))
            view.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: hub.x + radius * cos(angle), y: hub.y + radius * sin(angle))))
        }

        func makeFocusView() -> NSView {
            let responder = FocusView(frame: NSRect(x: 600, y: 400, width: 60, height: 20))
            window?.contentView?.addSubview(responder)
            return responder
        }
    }

    @MainActor
    final class TestClock {
        var time: TimeInterval = 0
        var wheel: (deadline: TimeInterval, timer: Timer)?
        var haptics: [NSHapticFeedbackManager.FeedbackPattern] = []
        var reduceMotion: Bool

        init(reduceMotion: Bool) { self.reduceMotion = reduceMotion }

        func startTimer(_ period: TimeInterval, _ repeats: Bool, _ tick: @escaping @Sendable (Timer) -> Void) -> Timer {
            let timer = Timer(timeInterval: period, repeats: repeats, block: tick)
            if !repeats { wheel = (time + period, timer) }
            return timer
        }
    }

    @MainActor
    final class RecordingOutput: WindowFrameCrankSoundOutput {
        var played: [WindowFrameCrankCue] = []
        var stops = 0
        func warm() {}
        func play(_ cue: WindowFrameCrankCue) { played.append(cue) }
        func stop() { stops += 1 }
    }

    @MainActor
    final class FocusView: NSView {
        override var acceptsFirstResponder: Bool { true }
    }

    @MainActor
    struct LightsImage {
        let lights: WindowFrameCrankLightsView
        let bitmap: NSBitmapImageRep

        init() throws {
            let frame = CGRect(x: 0, y: 0, width: CrankView.side, height: CrankView.side)
            lights = WindowFrameCrankLightsView(frame: frame, litCount: 8, readout: 10, palette: lightPalette)
            let image = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(frame.width),
                                                       pixelsHigh: Int(frame.height), bitsPerSample: 8, samplesPerPixel: 4,
                                                       hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                       bytesPerRow: 0, bitsPerPixel: 0))
            bitmap = image
            let context = try #require(NSGraphicsContext(bitmapImageRep: image))
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = context
            context.cgContext.clear(frame)
            lights.draw(frame)
        }

        func alpha(at point: CGPoint) -> CGFloat {
            bitmap.colorAt(x: Int(point.x), y: Int(lights.bounds.height - point.y))?.alphaComponent ?? 0
        }
    }

    @MainActor
    struct CrankImage {
        let bitmap: NSBitmapImageRep

        init(model: WindowFrameCrankModel) throws {
            let device = try #require(MTLCreateSystemDefaultDevice())
            let renderer = SCNRenderer(device: device, options: nil)
            renderer.scene = model.scene
            renderer.pointOfView = model.camera
            renderer.autoenablesDefaultLighting = false
            let side = CrankView.side
            let snapshot = renderer.snapshot(atTime: 0, with: CGSize(width: side, height: side), antialiasingMode: .none)
            var rect = CGRect(origin: .zero, size: snapshot.size)
            bitmap = NSBitmapImageRep(cgImage: try #require(snapshot.cgImage(forProposedRect: &rect, context: nil, hints: nil)))
        }

        func alpha(x: CGFloat, y: CGFloat) -> CGFloat {
            let side = CrankView.side
            let column = Int((side / 2 + x) * CGFloat(bitmap.pixelsWide) / side)
            let row = Int((side / 2 - y) * CGFloat(bitmap.pixelsHigh) / side)
            return bitmap.colorAt(x: column, y: row)?.alphaComponent ?? 0
        }
    }
}
