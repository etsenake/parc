import AppKit
import SwiftUI

struct ShortcutSmileyArtwork {
    private let layers: [[String: Any]]
    let frameRate: Double
    let endFrame: Double
    var duration: Double { endFrame / frameRate }
    init?(data: Data) {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let layers = root["layers"] as? [[String: Any]],
              let rate = root["fr"] as? Double, rate > 0,
              let end = root["op"] as? Double, end > 0,
              root["w"] as? Double == 100, root["h"] as? Double == 100 else { return nil }
        self.layers = layers; frameRate = rate; endFrame = end
    }
    private func numbers(_ value: Any?) -> [Double] {
        if let values = value as? [Double] { return values }
        if let value = value as? Double { return [value] }
        return []
    }
    private func progress(_ key: [String: Any], fraction: Double, component: Int = 0) -> Double {
        func control(_ name: String, _ axis: String, fallback: Double) -> Double {
            let values = numbers((key[name] as? [String: Any])?[axis])
            return values.isEmpty ? fallback : values[min(component, values.count - 1)]
        }
        func cubic(_ t: Double, _ a: Double, _ b: Double) -> Double {
            3 * (1-t) * (1-t) * t * a + 3 * (1-t) * t * t * b + t * t * t
        }
        let fraction = min(1, max(0, fraction))
        let x1 = control("o", "x", fallback: 0), x2 = control("i", "x", fallback: 1)
        var lo = 0.0, hi = 1.0
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            if cubic(mid, x1, x2) < fraction { lo = mid } else { hi = mid }
        }
        return cubic((lo + hi) / 2, control("o", "y", fallback: 0), control("i", "y", fallback: 1))
    }
    private func value(_ property: Any?, frame: Double, fallback: [Double]) -> [Double] {
        guard let p = property as? [String: Any] else { return fallback }
        if p["s"] as? Bool == true {
            return [value(p["x"], frame: frame, fallback: [0])[0], value(p["y"], frame: frame, fallback: [0])[0]]
        }
        guard p["a"] as? Int == 1, let keys = p["k"] as? [[String: Any]], !keys.isEmpty else {
            let n = numbers(p["k"]); return n.isEmpty ? fallback : n
        }
        let i = keys.lastIndex { ($0["t"] as? Double ?? 0) <= frame } ?? 0
        let key = keys[i], from = numbers(key["s"])
        guard i + 1 < keys.count else { return from.isEmpty ? fallback : from }
        let next = keys[i + 1], to = numbers(next["s"])
        let t0 = key["t"] as? Double ?? 0, t1 = next["t"] as? Double ?? t0
        guard t1 > t0, from.count == to.count else { return from }
        return from.enumerated().map { index, initial in
            initial + (to[index] - initial) * progress(key, fraction: (frame - t0) / (t1 - t0), component: index)
        }
    }
    private func transform(_ properties: [String: Any], frame: Double, context: CGContext) {
        let p = value(properties["p"], frame: frame, fallback: [0, 0])
        let a = value(properties["a"], frame: frame, fallback: [0, 0])
        let s = value(properties["s"], frame: frame, fallback: [100, 100])
        let r = value(properties["r"], frame: frame, fallback: [0])
        context.translateBy(x: p[0], y: p[1]); context.rotate(by: r[0] * .pi / 180)
        context.scaleBy(x: s[0] / 100, y: s[1] / 100); context.translateBy(x: -a[0], y: -a[1])
    }
    private func path(_ property: [String: Any], frame: Double) -> CGPath? {
        var shape = property["k"] as? [String: Any]
        if let keys = property["k"] as? [[String: Any]], !keys.isEmpty {
            let i = keys.lastIndex { ($0["t"] as? Double ?? 0) <= frame } ?? 0
            let key = keys[i]
            shape = (key["s"] as? [[String: Any]])?.first
            if i + 1 < keys.count, let next = (keys[i + 1]["s"] as? [[String: Any]])?.first {
                let t0 = key["t"] as? Double ?? 0, t1 = keys[i + 1]["t"] as? Double ?? 0
                if t1 > t0 {
                    let fraction = progress(key, fraction: (frame - t0) / (t1 - t0))
                    for name in ["v", "i", "o"] {
                        guard let from = shape?[name] as? [[Double]], let to = next[name] as? [[Double]], from.count == to.count else { return nil }
                        shape?[name] = zip(from, to).map { a, b in zip(a, b).map { $0 + ($1 - $0) * fraction } }
                    }
                }
            }
        }
        guard let shape, let vertices = shape["v"] as? [[Double]],
              let incoming = shape["i"] as? [[Double]], let outgoing = shape["o"] as? [[Double]],
              !vertices.isEmpty, incoming.count == vertices.count, outgoing.count == vertices.count,
              (vertices + incoming + outgoing).allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isFinite) }) else { return nil }
        let path = CGMutablePath(); path.move(to: CGPoint(x: vertices[0][0], y: vertices[0][1]))
        let closed = shape["c"] as? Bool == true
        for step in 1..<(vertices.count + (closed ? 1 : 0)) {
            let i = step % vertices.count, previous = step - 1
            path.addCurve(to: CGPoint(x: vertices[i][0], y: vertices[i][1]),
                control1: CGPoint(x: vertices[previous][0] + outgoing[previous][0], y: vertices[previous][1] + outgoing[previous][1]),
                control2: CGPoint(x: vertices[i][0] + incoming[i][0], y: vertices[i][1] + incoming[i][1]))
        }
        if closed { path.closeSubpath() }
        return path
    }
    func draw(in rect: NSRect, seconds: Double, context: CGContext) {
        let frame = min(endFrame, max(0, seconds * frameRate))
        context.saveGState(); defer { context.restoreGState() }
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / 100, y: rect.height / 100)
        for layer in layers.reversed() {
            guard let ks = layer["ks"] as? [String: Any], let groups = layer["shapes"] as? [[String: Any]] else { continue }
            context.saveGState()
            if let parent = layer["parent"] as? Int,
               let parentLayer = layers.first(where: { $0["ind"] as? Int == parent }),
               let parentProperties = parentLayer["ks"] as? [String: Any] {
                transform(parentProperties, frame: frame, context: context)
            }
            transform(ks, frame: frame, context: context)
            for group in groups {
                guard let items = group["it"] as? [[String: Any]],
                      let stroke = items.first(where: { $0["ty"] as? String == "st" }) else { continue }
                context.saveGState()
                if let tr = items.first(where: { $0["ty"] as? String == "tr" }) { transform(tr, frame: frame, context: context) }
                context.setStrokeColor(NSColor.white.cgColor)
                context.setLineWidth(value(stroke["w"], frame: frame, fallback: [8])[0]); context.setLineCap(.round)
                for item in items where item["ty"] as? String == "sh" {
                    if let ks = item["ks"] as? [String: Any], let path = path(ks, frame: frame) {
                        context.addPath(path); context.strokePath()
                    }
                }
                context.restoreGState()
            }
            context.restoreGState()
        }
    }

    func presentationFingerprint(seconds: Double, size: CGSize) -> Int {
        let frame = min(endFrame, max(0, seconds * frameRate))
        var hasher = Hasher()
        hasher.combine(Int((size.width * 1000).rounded()))
        hasher.combine(Int((size.height * 1000).rounded()))
        for layer in layers.reversed() {
            guard let ks = layer["ks"] as? [String: Any], let groups = layer["shapes"] as? [[String: Any]] else { continue }
            if let parent = layer["parent"] as? Int,
               let parentLayer = layers.first(where: { $0["ind"] as? Int == parent }),
               let parentProperties = parentLayer["ks"] as? [String: Any] {
                hashTransform(parentProperties, frame: frame, into: &hasher)
            }
            hashTransform(ks, frame: frame, into: &hasher)
            for group in groups {
                guard let items = group["it"] as? [[String: Any]],
                      let stroke = items.first(where: { $0["ty"] as? String == "st" }) else { continue }
                if let tr = items.first(where: { $0["ty"] as? String == "tr" }) {
                    hashTransform(tr, frame: frame, into: &hasher)
                }
                for component in value(stroke["w"], frame: frame, fallback: [8]) {
                    hasher.combine(component.bitPattern)
                }
                for item in items where item["ty"] as? String == "sh" {
                    if let shape = item["ks"] as? [String: Any] {
                        hashPath(shape, frame: frame, into: &hasher)
                    }
                }
            }
        }
        return hasher.finalize()
    }

    private func hashTransform(_ properties: [String: Any], frame: Double, into hasher: inout Hasher) {
        for key in ["p", "a", "s", "r"] {
            let fallback: [Double] = key == "s" ? [100, 100] : key == "r" ? [0] : [0, 0]
            for component in value(properties[key], frame: frame, fallback: fallback) {
                hasher.combine(component.bitPattern)
            }
        }
    }

    private func hashPath(_ property: [String: Any], frame: Double, into hasher: inout Hasher) {
        var shape = property["k"] as? [String: Any]
        if let keys = property["k"] as? [[String: Any]], !keys.isEmpty {
            let i = keys.lastIndex { ($0["t"] as? Double ?? 0) <= frame } ?? 0
            let key = keys[i]
            shape = (key["s"] as? [[String: Any]])?.first
            if i + 1 < keys.count, let next = (keys[i + 1]["s"] as? [[String: Any]])?.first {
                let t0 = key["t"] as? Double ?? 0, t1 = keys[i + 1]["t"] as? Double ?? 0
                if t1 > t0 {
                    let fraction = progress(key, fraction: (frame - t0) / (t1 - t0))
                    for name in ["v", "i", "o"] {
                        guard let from = shape?[name] as? [[Double]], let to = next[name] as? [[Double]],
                              from.count == to.count else { hasher.combine(0); return }
                        shape?[name] = zip(from, to).map { a, b in zip(a, b).map { $0 + ($1 - $0) * fraction } }
                    }
                }
            }
        }
        guard let shape, let vertices = shape["v"] as? [[Double]],
              let incoming = shape["i"] as? [[Double]], let outgoing = shape["o"] as? [[Double]],
              vertices.count == incoming.count, vertices.count == outgoing.count else {
            hasher.combine(0); return
        }
        hasher.combine(shape["c"] as? Bool == true)
        hasher.combine(vertices.count)
        for point in vertices + incoming + outgoing {
            for component in point.prefix(2) { hasher.combine(component.bitPattern) }
        }
    }
}

@MainActor final class ShortcutSmileyView: NSView {
    private static let artwork: ShortcutSmileyArtwork? = Bundle.main.url(forResource: "smiley", withExtension: "json", subdirectory: "Shortcuts")
        .flatMap { try? Data(contentsOf: $0) }.flatMap(ShortcutSmileyArtwork.init)
    private var timer: Timer?
    var now: () -> CFTimeInterval = { CACurrentMediaTime() }
    private var startedAt = 0.0
    private var elapsed = 0.0
    private var lastDisplayFingerprint: Int?
    private var leftRestingPose = false
    private var motionObserver: NSObjectProtocol?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override init(frame: NSRect) {
        super.init(frame: frame); setAccessibilityElement(false)
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.restartPlayback() } }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit { timer?.invalidate(); if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) } }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); restartPlayback() }
    private func restartPlayback() {
        stopFrames()
        elapsed = 0
        leftRestingPose = false
        if let artwork = Self.artwork {
            lastDisplayFingerprint = artwork.presentationFingerprint(seconds: 0, size: bounds.size)
        } else {
            lastDisplayFingerprint = nil
        }
        invalidateDisplay()
        guard window != nil, !isHidden, Self.artwork != nil,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        startedAt = now()
        startFrames()
    }
    private func tick(_ timer: Timer) {
        guard window != nil, !isHidden, self.timer === timer, let artwork = Self.artwork else {
            stopFrames(); return
        }
        elapsed = min(artwork.duration, now() - startedAt)
        let fingerprint = artwork.presentationFingerprint(seconds: elapsed, size: bounds.size)
        let endFingerprint = artwork.presentationFingerprint(seconds: artwork.duration, size: bounds.size)
        if fingerprint != endFingerprint { leftRestingPose = true }
        if fingerprint != lastDisplayFingerprint {
            lastDisplayFingerprint = fingerprint
            invalidateDisplay()
        }
        if elapsed >= artwork.duration || (leftRestingPose && fingerprint == endFingerprint) {
            stopFrames()
        }
    }
    private func startFrames() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated { self?.tick(timer) }
        }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func stopFrames() { timer?.invalidate(); timer = nil }
    private func invalidateDisplay() {
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        Self.artwork?.draw(in: bounds, seconds: elapsed, context: context)
    }
}

struct ShortcutSmileyRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> ShortcutSmileyView { ShortcutSmileyView(frame: .zero) }
    func updateNSView(_ nsView: ShortcutSmileyView, context: Context) {}
}
