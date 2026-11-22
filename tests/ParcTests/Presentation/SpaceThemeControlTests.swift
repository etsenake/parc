import AppKit
import Combine
import Testing
import ParcCore
@testable import Parc

@MainActor
struct SpaceThemeControlTests {
    @MainActor final class CursorLog {
        var current: NSCursor = .iBeam
        var cursor: ThemeEditorCursor { ThemeEditorCursor(set: { self.current = $0 }, current: { self.current }) }
    }

    @MainActor final class ScrollDelivery {
        var latest: (() -> Void)?

        func hold(_ input: AnyPublisher<Double, Never>) -> AnyPublisher<Double, Never> {
            let output = PassthroughSubject<Double, Never>()
            let upstream = input.sink { [weak self, weak output] value in
                self?.latest = { [weak output] in output?.send(value) }
            }
            return output.handleEvents(receiveCancel: { upstream.cancel() }).eraseToAnyPublisher()
        }

        func deliver() {
            let work = latest
            latest = nil
            work?()
        }
    }

    final class ThemeEvent: NSEvent {
        let eventPhase: NSEvent.Phase
        let eventMomentum: NSEvent.Phase
        let degrees: Float
        let delta: CGFloat
        let point: NSPoint

        @MainActor init(over view: NSView? = nil, at point: NSPoint? = nil, phase: NSEvent.Phase = [], momentum: NSEvent.Phase = [],
             rotation: Float = 0, delta: CGFloat = 0) {
            eventPhase = phase
            eventMomentum = momentum
            degrees = rotation
            self.delta = delta
            self.point = view.map { $0.convert(point ?? NSPoint(x: $0.bounds.midX, y: $0.bounds.midY), to: nil) } ?? .zero
            super.init()
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override var phase: NSEvent.Phase { eventPhase }
        override var momentumPhase: NSEvent.Phase { eventMomentum }
        override var locationInWindow: NSPoint { point }
        override var rotation: Float { degrees }
        override var scrollingDeltaY: CGFloat { delta }
        override var timestamp: TimeInterval { 30 }
    }

    final class KeyHostWindow: NSWindow {
        var pointer = NSPoint.zero
        override var isKeyWindow: Bool { true }
        override var mouseLocationOutsideOfEventStream: NSPoint { pointer }
    }

    @MainActor final class Fixture {
        let cursor: CursorLog
        let delivery: ScrollDelivery
        let view: SpaceThemeEditorView
        let pad: NSView
        let intensity: NSView
        let noise: NSView
        var commits = 0
        var previews = 0
        private(set) var window: NSWindow?

        init(_ theme: SpaceTheme = SpaceTheme(), hosted: Bool = false) throws {
            _ = NSApplication.shared
            let cursor = CursorLog(), delivery = ScrollDelivery()
            self.cursor = cursor
            self.delivery = delivery
            view = SpaceThemeEditorView(theme: theme, scrollPublisher: delivery.hold, scrollTime: { 30 },
                                        performHapticFeedback: {}, cursor: cursor.cursor, resources: ThemeEditorResources(bundle: .module))
            view.layoutSubtreeIfNeeded()
            pad = try SpaceThemeControlTests.control("Theme color pad", in: view)
            intensity = try SpaceThemeControlTests.control("Theme intensity", in: view)
            noise = try SpaceThemeControlTests.control("Theme texture and noise", in: view)
            view.onCommit = { [weak self] _ in self?.commits += 1 }
            view.onPreview = { [weak self] _ in self?.previews += 1 }
            if hosted { host(NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: true)) }
        }

        func host(_ window: NSWindow) {
            window.isReleasedWhenClosed = false
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            self.window = window
        }

        func control(_ name: String) throws -> NSView { try SpaceThemeControlTests.control(name, in: view) }
        func button(_ name: String) throws -> NSButton { try #require(try control(name) as? NSButton) }
        func press(_ target: NSView, _ point: NSPoint) throws { target.mouseDown(with: try SpaceThemeControlTests.mouse(.leftMouseDown, target, point)) }
        func drag(_ target: NSView, _ point: NSPoint) throws { target.mouseDragged(with: try SpaceThemeControlTests.mouse(.leftMouseDragged, target, point)) }
        func release(_ target: NSView, _ point: NSPoint) throws { target.mouseUp(with: try SpaceThemeControlTests.mouse(.leftMouseUp, target, point)) }
        func move(_ target: NSView, _ point: NSPoint) throws { target.mouseMoved(with: try SpaceThemeControlTests.mouse(.mouseMoved, target, point)) }
        func click(_ target: NSView, _ point: NSPoint) throws { try press(target, point); try release(target, point) }
        func center(_ target: NSView) -> NSPoint { NSPoint(x: target.bounds.midX, y: target.bounds.midY) }
        func hoverCenter() throws { try move(noise, center(noise)) }
        func rotate(at point: NSPoint? = nil, _ phase: NSEvent.Phase, _ degrees: Float = 0) {
            noise.rotate(with: ThemeEvent(over: noise, at: point, phase: phase, rotation: degrees))
        }
        func scroll(phase: NSEvent.Phase = [], momentum: NSEvent.Phase = [], _ delta: CGFloat) {
            noise.scrollWheel(with: ThemeEvent(phase: phase, momentum: momentum, delta: delta))
        }
        func padCursor(at point: NSPoint) throws -> NSCursor {
            cursor.current = .iBeam
            try move(pad, point)
            return cursor.current
        }
        func knobs() throws -> [CALayer] {
            let layers = try #require(pad.layer?.sublayers)
            let container = try #require(layers.first { layer in
                !pad.subviews.contains { $0.layer === layer } && layer.sublayers?.isEmpty == false
            })
            return try #require(container.sublayers)
        }
        func drawn(_ knob: CALayer) throws -> NSPoint {
            var point = knob.position
            var layer = try #require(knob.superlayer)
            let root = try #require(pad.layer)
            while layer !== root {
                if layer.isGeometryFlipped { point.y = layer.bounds.height - point.y }
                point.x += layer.frame.minX - layer.bounds.minX
                point.y += layer.frame.minY - layer.bounds.minY
                layer = try #require(layer.superlayer)
            }
            return point
        }
        func cursorUpdate(_ target: NSView, _ point: NSPoint) throws {
            target.cursorUpdate(with: try SpaceThemeControlTests.edge(.cursorUpdate, target, point))
        }
    }

    static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    static func control(_ label: String, in view: NSView) throws -> NSView {
        try #require(descendants(view).first { $0.accessibilityLabel() == label })
    }

    static func mouse(_ type: NSEvent.EventType, _ view: NSView, _ point: NSPoint) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 30,
                                        windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
    }

    static func edge(_ type: NSEvent.EventType, _ view: NSView? = nil, _ point: NSPoint = .zero) throws -> NSEvent {
        try #require(NSEvent.enterExitEvent(with: type, location: view?.convert(point, to: nil) ?? .zero, modifierFlags: [],
                                            timestamp: 30, windowNumber: 0, context: nil, eventNumber: 0,
                                            trackingNumber: 0, userData: nil))
    }

    static func offAxisColor() throws -> ThemeColor {
        try #require(ThemeColor.hsl(hue: 0.15, saturation: 0.85, lightness: 0.81, colorSpace: .displayP3))
    }

    static func offAxisTheme(colors: Int = 1) throws -> SpaceTheme {
        var theme = SpaceTheme.singleColor(try offAxisColor())
        theme.appearance = .light
        theme.colorCount = colors
        return theme
    }

    static func snapshot(_ view: NSView) throws -> NSBitmapImageRep {
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    static func pixels(_ view: NSView) throws -> [UInt8] {
        let rep = try snapshot(view)
        let data = try #require(rep.bitmapData)
        return Array(UnsafeBufferPointer(start: data, count: rep.bytesPerRow * rep.pixelsHigh))
    }

    static func ink(_ rep: NSBitmapImageRep, _ view: NSView, _ point: NSPoint) throws -> CGFloat {
        let scale = CGFloat(rep.pixelsWide) / view.bounds.width
        return try #require(rep.colorAt(x: Int(point.x * scale), y: Int(point.y * scale))).alphaComponent
    }

    static func near(_ value: Double, _ expected: Double) -> Bool { abs(value - expected) < 0.000001 }
    static func distance(_ a: NSPoint, _ b: NSPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
}
