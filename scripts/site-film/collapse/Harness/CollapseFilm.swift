import AppKit
import QuartzCore
@testable import Parc
@testable import ParcKit
@testable import ParcSidebar
import ParcCore

enum AnchoredCurve {
    static let duration = 0.08
    static let points = (0.25, 0.46, 0.45, 0.94)

    static func value(_ u: Double) -> Double {
        let u = min(1, max(0, u))
        let (x1, y1, x2, y2) = points
        func bezier(_ t: Double, _ a: Double, _ b: Double) -> Double { 3 * (1 - t) * (1 - t) * t * a + 3 * (1 - t) * t * t * b + t * t * t }
        var low = 0.0, high = 1.0, t = u
        for _ in 0..<60 {
            t = (low + high) / 2
            if bezier(t, x1, x2) < u { low = t } else { high = t }
        }
        return bezier(t, y1, y2)
    }
}

struct FloatingSpring {
    let response = 0.18, dampingRatio = 0.8
    let mass: Double, stiffness: Double, damping: Double, settling: Double

    init() {
        let frequency = 2 * Double.pi / response
        mass = 1
        stiffness = frequency * frequency
        damping = 2 * dampingRatio * frequency
        let animation = CASpringAnimation()
        animation.mass = mass; animation.stiffness = stiffness; animation.damping = damping
        settling = animation.settlingDuration
    }

    func value(_ t: Double) -> Double {
        guard t > 0 else { return 0 }
        guard t < settling else { return 1 }
        let omega = (stiffness / mass).squareRoot()
        let zeta = damping / (2 * (stiffness * mass).squareRoot())
        let wd = omega * (1 - zeta * zeta).squareRoot()
        return 1 - exp(-zeta * omega * t) * (cos(wd * t) + zeta * omega / wd * sin(wd * t))
    }
}

struct PresentationChange {
    let time: Double
    let from: SidebarPresentation
    let to: SidebarPresentation
    let cause: String
    var transition: SidebarTransition { SidebarTransition(from: from, to: to) }
    var duration: Double { transition.style == .floating ? FloatingSpring().settling : AnchoredCurve.duration }
}

struct PointerKey {
    let time: Double
    let point: NSPoint
}

@MainActor enum CollapseFilm {
    static let fps = 60
    static let duration = 9.0
    static let width: CGFloat = 228
    static let windowBounds = NSRect(x: 0, y: 0, width: 1280, height: 840)
    static let thickness = frameThickness
    static let rest = NSPoint(x: 760, y: 520)
    static let clicks: [(down: Double, up: Double)] = [(1.20, 1.30), (7.35, 7.45)]
    static let spring = FloatingSpring()

    struct Plan {
        var keys: [PointerKey]
        var changes: [PresentationChange] = []
        var hoverLog: [[String: Any]] = []
    }

    static func ease(_ u: Double) -> Double { let u = min(1, max(0, u)); return u * u * (3 - 2 * u) }

    static func pointer(_ keys: [PointerKey], at t: Double) -> NSPoint {
        guard let first = keys.first else { return rest }
        if t <= first.time { return first.point }
        for (a, b) in zip(keys, keys.dropFirst()) where t <= b.time {
            let u = CGFloat(ease((t - a.time) / max(1e-9, b.time - a.time)))
            return NSPoint(x: a.point.x + (b.point.x - a.point.x) * u, y: a.point.y + (b.point.y - a.point.y) * u)
        }
        return keys.last!.point
    }

    static func placement(_ p: SidebarPresentation, inMotion: Bool, floating: Bool, reveals: Bool) -> NSRect {
        SidebarPresentationFrame(p, inMotion: inMotion, floatingSurface: floating, revealsAnchored: reveals).rect(width: width, in: windowBounds)
    }

    static func page(_ p: SidebarPresentation, placement: SidebarPresentationFrame) -> NSRect {
        SidebarChromeFrames(bounds: windowBounds, sidebarWidth: width, presentation: p, placement: placement, thickness: thickness).pageHost
    }

    static func simulate(keys: [PointerKey]) -> Plan {
        var plan = Plan(keys: keys)
        var presentation = SidebarPresentation.locked
        var hoverActive = false
        var tracking = SidebarHoverTracking()
        var lingers: [(Double, SidebarHoverRegion)] = []
        var stopAt: Double?
        var previous = pointer(keys, at: 0)
        let dt = 1.0 / 1200
        func set(_ next: SidebarPresentation, _ t: Double, _ cause: String) {
            if next == .floating { hoverActive = true }
            guard next != presentation else { return }
            plan.changes.append(PresentationChange(time: t, from: presentation, to: next, cause: cause))
            presentation = next
        }
        var step = 0
        var clicked = 0
        while Double(step) * dt <= duration {
            let t = Double(step) * dt
            step += 1
            if clicked < clicks.count, t >= clicks[clicked].up {
                clicked += 1
                let label = presentation == .locked ? "Hide sidebar" : "Lock sidebar"
                set(presentation == .locked ? .hidden : .locked, t, "sidebar toggle clicked (\(label), toggleSidebar)")
            }
            let p = pointer(keys, at: t)
            let moved = p != previous
            previous = p
            let zones = SidebarHoverZones.rects(size: windowBounds.size, presentation: zonePresentation(presentation), sidebarWidth: Double(width),
                                                showingToolbar: false, trafficLightHeight: 0, info: tracking.info)
            let flipped = CGPoint(x: p.x, y: windowBounds.height - p.y)
            let before = tracking.info
            let entered = tracking.update { zones[$0]?.contains(flipped) == true }
            for region in entered { lingers.append((t + region.lingerRequirement, region)) }
            if moved { stopAt = t + SidebarHoverTracking.stopDelay }
            lingers.removeAll { due, region in
                guard t >= due else { return false }
                _ = tracking.linger(region); return true
            }
            if let due = stopAt, t >= due {
                stopAt = nil
                if tracking.needsStopPromotion { _ = tracking.stop() }
            }
            if tracking.info != before || moved {
                let decision = SidebarHoverPresentationRule.decide(stored: hoverActive, presentation: zonePresentation(presentation),
                    info: tracking.info, fullscreen: false, includesTopLeft: true, isKeyWindow: true, ownerDefers: false,
                    interactionDefers: false)
                hoverActive = decision.isActive
                switch decision.action {
                case .keep: break
                case .reveal:
                    plan.hoverLog.append(["t": t, "event": "reveal", "info": describe(tracking.info)])
                    set(.floating, t, "hover at the left edge (SidebarHoverPresentationRule.reveal)")
                case .dismiss:
                    plan.hoverLog.append(["t": t, "event": "dismiss", "info": describe(tracking.info)])
                    set(.hidden, t, "pointer left the floating sidebar's reach (SidebarHoverPresentationRule.dismiss)")
                }
            }
        }
        return plan
    }

    static func zonePresentation(_ p: SidebarPresentation) -> SidebarHoverZones.Presentation {
        switch p { case .locked: .locked; case .floating: .floating; case .hidden: .hidden }
    }

    static func describe(_ info: SidebarHoverInfo) -> [String: String] {
        var out: [String: String] = [:]
        for region in SidebarHoverRegion.allCases where info[region] != .none { out["\(region)"] = "\(info[region])" }
        return out
    }

    struct Geometry {
        var sidebar: NSRect
        var page: NSRect
        var floatingSurface: Bool
        var floatingLabel: Bool
        var presented: Bool
        var presentation: SidebarPresentation
        var moving: Bool
        var progress: Double?
        var dock: Double = 0
    }

    static func lerp(_ a: NSRect, _ b: NSRect, _ f: CGFloat) -> NSRect {
        NSRect(x: a.minX + (b.minX - a.minX) * f, y: a.minY + (b.minY - a.minY) * f,
               width: a.width + (b.width - a.width) * f, height: a.height + (b.height - a.height) * f)
    }

    static func geometry(_ plan: Plan, at t: Double) -> Geometry {
        guard let change = plan.changes.last(where: { $0.time <= t + 1e-9 }) else {
            return Geometry(sidebar: placement(.locked, inMotion: false, floating: false, reveals: false),
                            page: page(.locked, placement: .locked), floatingSurface: false, floatingLabel: false, presented: true,
                            presentation: .locked, moving: false, progress: nil)
        }
        let transition = change.transition
        let elapsed = t - change.time
        let to = change.to
        if elapsed >= change.duration {
            let frame = SidebarPresentationFrame(to, inMotion: false, floatingSurface: false, revealsAnchored: false)
            return Geometry(sidebar: frame.rect(width: width, in: windowBounds), page: page(to, placement: frame),
                            floatingSurface: to == .floating, floatingLabel: to != .locked, presented: to.presents(inMotion: false),
                            presentation: to, moving: false, progress: nil)
        }
        let keeps = transition.keepsFloatingSurface, reveals = transition.revealsAnchored
        let startFrame = SidebarPresentationFrame(change.from, inMotion: true, floatingSurface: keeps, revealsAnchored: reveals)
        let endFrame = SidebarPresentationFrame(to, inMotion: true, floatingSurface: keeps, revealsAnchored: false)
        let f = transition.style == .floating ? spring.value(elapsed) : AnchoredCurve.value(elapsed / AnchoredCurve.duration)
        return Geometry(sidebar: lerp(startFrame.rect(width: width, in: windowBounds), endFrame.rect(width: width, in: windowBounds), CGFloat(f)),
                        page: lerp(page(change.from, placement: startFrame), page(to, placement: endFrame), CGFloat(f)),
                        floatingSurface: keeps || change.from == .floating, floatingLabel: change.from != .locked,
                        presented: true, presentation: to, moving: true, progress: f,
                        dock: transition.docksFloatingSurface ? min(1, max(0, f)) : 0)
    }

    static func trackingEvent(_ sidebar: SidebarView, entered: Bool) -> NSEvent? {
        guard let area = Mirror(reflecting: sidebar).children.first(where: { $0.label == "revealTracking" })?.value as? NSTrackingArea
        else { return nil }
        let event = NSEvent.enterExitEvent(with: entered ? .mouseEntered : .mouseExited, location: .zero, modifierFlags: [],
                                           timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                                           trackingNumber: Int(bitPattern: Unmanaged.passUnretained(area).toOpaque()), userData: nil)
        return event?.trackingArea === area ? event : nil
    }

    static func toggleButton(_ scene: BrowserScene) -> ActionButton? {
        BrowserScene.descendants(scene.sidebar).compactMap { $0 as? ActionButton }.first {
            let label = $0.accessibilityLabel() ?? ""
            return label == SidebarAccessibility.hideSidebar || label == SidebarAccessibility.lockSidebar
        }
    }

    static func rowFrame(_ scene: BrowserScene, _ title: String) -> NSRect? {
        scene.row(titled: title).map { scene.holder.convert($0.bounds, from: $0) }
    }

    @MainActor final class Driver {
        let scene: BrowserScene
        let plan: Plan
        let toggle: ActionButton?
        var pointerInside = false
        var previousPointer: NSPoint?
        var wasMoving = false
        var lastSize = NSSize.zero
        var trackingWorks = false
        var log: [[String: Any]] = []

        init(scene: BrowserScene, plan: Plan) {
            self.scene = scene; self.plan = plan
            toggle = CollapseFilm.toggleButton(scene)
            scene.sidebar.updateTrackingAreas()
            trackingWorks = CollapseFilm.trackingEvent(scene.sidebar, entered: true) != nil
        }

        func apply(_ t: Double) -> Geometry {
            RunLoop.main.run(until: Date().addingTimeInterval(0.002))
            var g = CollapseFilm.geometry(plan, at: t)
            g.sidebar.origin = NSPoint(x: (g.sidebar.minX * 2).rounded() / 2, y: (g.sidebar.minY * 2).rounded() / 2)
            g.sidebar.size.height = (g.sidebar.height * 2).rounded() / 2
            let p = CollapseFilm.pointer(plan.keys, at: t)
            scene.holder.frame = g.sidebar
            scene.sidebar.frame = scene.holder.bounds
            if g.sidebar.size != lastSize { lastSize = g.sidebar.size; scene.sidebar.layoutSubtreeIfNeeded() }
            scene.sidebar.setFloating(g.floatingLabel)
            scene.sidebar.isPresented = g.presented
            if !g.presented { pointerInside = false }
            let moved = previousPointer.map { $0 != p } ?? true
            let settled = wasMoving && !g.moving
            previousPointer = p; wasMoving = g.moving
            let inside = moved || settled ? g.presented && g.sidebar.contains(p) : pointerInside && g.presented
            if inside != pointerInside {
                pointerInside = inside
                if let event = CollapseFilm.trackingEvent(scene.sidebar, entered: inside) {
                    if inside { scene.sidebar.mouseEntered(with: event) } else { scene.sidebar.mouseExited(with: event) }
                }
            }
            scene.sidebar.layoutSubtreeIfNeeded()
            let local = NSPoint(x: p.x - g.sidebar.minX, y: p.y - g.sidebar.minY)
            let hovered = inside ? scene.tabRows.first { scene.holder.convert($0.bounds, from: $0).contains(local) } : nil
            scene.setHover(hovered)
            if let toggle {
                let onToggle = inside && scene.holder.convert(toggle.bounds, from: toggle).contains(local)
                toggle.translucentFace?.setHovered(onToggle, animated: false)
                toggle.isHighlighted = onToggle && CollapseFilm.clicks.contains { t >= $0.down && t < $0.up }
                toggle.needsDisplay = true
            }
            scene.surface.pageCard = g.page
            scene.surface.needsDisplay = true
            pointerLocation = p
            scene.floating.isHidden = !g.floatingSurface
            if g.floatingSurface {
                scene.sidebar.layoutSubtreeIfNeeded()
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(g.sidebar.width * 2), pixelsHigh: Int(g.sidebar.height * 2),
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                           bytesPerRow: 0, bitsPerPixel: 0)!
                rep.size = g.sidebar.size
                NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance { scene.holder.cacheDisplay(in: scene.holder.bounds, to: rep) }
                scene.floating.content = rep.cgImage
                scene.floating.surfaceRect = g.sidebar
                scene.floating.dock = CGFloat(g.dock)
                scene.holder.setFrameOrigin(NSPoint(x: -5000, y: g.sidebar.minY))
            }
            scene.floating.needsDisplay = true
            log.append(["t": t, "presentation": "\(g.presentation)", "moving": g.moving, "progress": g.progress as Any,
                        "sidebar": [g.sidebar.minX, g.sidebar.minY, g.sidebar.width, g.sidebar.height],
                        "pageCard": [g.page.minX, g.page.minY, g.page.width, g.page.height],
                        "floatingSurface": g.floatingSurface, "dockCrossfade": g.dock, "pointer": [p.x, p.y], "pointerInSidebar": inside,
                        "hoveredRow": hovered.flatMap { row in BrowserScene.descendants(row).compactMap { $0 as? NSTextField }.first?.stringValue } as Any])
            return g
        }

        var stageBase: CGImage?
        var pointerLocation: NSPoint?

        func prepareStage() {
            scene.pointer.removeFromSuperview()
            scene.surface.isHidden = true
            stageBase = scene.render(NSRect(origin: .zero, size: scene.stage.bounds.size), pixelsWide: 2880, pixelsHigh: 1800).cgImage
            scene.surface.isHidden = false
        }

        func render() -> CGImage {
            scene.stage.layoutSubtreeIfNeeded()
            let surface = scene.surface
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2560, pixelsHigh: 1680, bitsPerSample: 8, samplesPerPixel: 4,
                                       hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = surface.bounds.size
            NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance { surface.cacheDisplay(in: surface.bounds, to: rep) }
            if !scene.floating.isHidden { scene.holder.setFrameOrigin(scene.floating.surfaceRect.origin) }
            let context = CGContext(data: nil, width: 2880, height: 1800, bitsPerComponent: 8, bytesPerRow: 2880 * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            let full = CGRect(x: 0, y: 0, width: 2880, height: 1800)
            if let stageBase { context.draw(stageBase, in: full) }
            let window = scene.windowRect
            let placed = CGRect(x: window.minX * 2, y: (900 - window.maxY) * 2, width: window.width * 2, height: window.height * 2)
            context.saveGState()
            context.addPath(CGPath(roundedRect: placed, cornerWidth: windowCornerRadius * 2, cornerHeight: windowCornerRadius * 2, transform: nil))
            context.clip()
            context.interpolationQuality = .none
            context.draw(rep.cgImage!, in: placed)
            context.restoreGState()
            if let location = pointerLocation {
                context.saveGState()
                context.translateBy(x: 0, y: 1800); context.scaleBy(x: 2, y: -2)
                let graphics = NSGraphicsContext(cgContext: context, flipped: true)
                NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
                let cursor = NSCursor.arrow, hot = cursor.hotSpot, size = cursor.image.size
                let point = NSPoint(x: location.x + window.minX, y: location.y + window.minY)
                cursor.image.draw(in: NSRect(x: point.x - hot.x, y: point.y - hot.y, width: size.width, height: size.height),
                                  from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                NSGraphicsContext.restoreGraphicsState()
                context.restoreGState()
            }
            return context.makeImage()!
        }
    }

    static func buildKeys(_ scene: BrowserScene) -> [PointerKey] {
        let toggle = toggleButton(scene).map { scene.holder.convert($0.bounds, from: $0) } ?? NSRect(x: 80, y: 12, width: 28, height: 28)
        let target = NSPoint(x: toggle.midX + 1, y: toggle.midY + 1)
        let floating = placement(.floating, inMotion: false, floating: false, reveals: false)
        func row(_ title: String) -> CGFloat { (rowFrame(scene, title)?.midY ?? 450) + floating.minY + 1 }
        let edge = NSPoint(x: 2.5, y: 372)
        let edgeAgain = NSPoint(x: 2.5, y: 300)
        let away = NSPoint(x: 640, y: 450)
        let toggleFloating = NSPoint(x: target.x + floating.minX, y: target.y + floating.minY)
        return [
            PointerKey(time: 0, point: rest),
            PointerKey(time: 0.30, point: rest),
            PointerKey(time: 1.05, point: target),
            PointerKey(time: 2.15, point: target),
            PointerKey(time: 2.95, point: edge),
            PointerKey(time: 3.45, point: edge),
            PointerKey(time: 3.85, point: NSPoint(x: 118, y: row("Urban parks — Field Notes"))),
            PointerKey(time: 3.98, point: NSPoint(x: 118, y: row("Urban parks — Field Notes"))),
            PointerKey(time: 4.23, point: NSPoint(x: 124, y: row("Quarterly roadmap draft"))),
            PointerKey(time: 4.36, point: NSPoint(x: 124, y: row("Quarterly roadmap draft"))),
            PointerKey(time: 4.61, point: NSPoint(x: 130, y: row("Release checklist"))),
            PointerKey(time: 4.76, point: NSPoint(x: 130, y: row("Release checklist"))),
            PointerKey(time: 5.30, point: away),
            PointerKey(time: 5.75, point: away),
            PointerKey(time: 6.35, point: edgeAgain),
            PointerKey(time: 6.75, point: edgeAgain),
            PointerKey(time: 7.20, point: toggleFloating),
            PointerKey(time: 7.75, point: toggleFloating),
            PointerKey(time: 8.45, point: rest),
        ]
    }

    static let sheetTimes: [Double] = [0.50, 1.20, 1.317, 2.0, 3.05, 4.30, 5.033, 6.4667, 7.40, 7.4833, 7.60, 8.80]
    static let keyTimes: [(String, Double)] = [("rest", 0), ("toggle-press", 1.20), ("mid-hide", 1.317), ("hidden", 2.0), ("mid-reveal", 3.05),
                                               ("floating", 3.40), ("floating-hover", 4.30), ("mid-dismiss", 5.033),
                                               ("mid-reveal-again", 6.4667), ("lock-press", 7.40), ("mid-dock", 7.4667),
                                               ("mid-dock-late", 7.50), ("docked", 7.60), ("redocked", 9.0 - 1.0 / 60)]

    static func run(_ scene: BrowserScene, out: String, keysOnly: Bool) {
        let keys = buildKeys(scene)
        let plan = simulate(keys: keys)
        for change in plan.changes {
            print(String(format: "change t=%.4f %@ -> %@ (%@) duration %.4f", change.time, "\(change.from)", "\(change.to)", change.cause, change.duration))
        }
        print("spring settling", spring.settling, "stiffness", spring.stiffness, "damping", spring.damping)
        let driver = Driver(scene: scene, plan: plan)
        print("toggle", driver.toggle.map { "\(scene.holder.convert($0.bounds, from: $0))" } ?? "missing", "tracking events", driver.trackingWorks)
        scene.floating.backdrop = backdrop(scene, plan: plan, driver: driver)
        driver.prepareStage()
        let frames = Int(duration * Double(fps))
        let writer = keysOnly ? nil : try! AlphaVideoWriter(path: out + "/collapse.mov", width: 2880, height: 1800)
        var sheet: [(Double, CGImage)] = []
        var started = Date()
        for frame in 0..<frames {
            let t = Double(frame) / Double(fps)
            let wantsKey = keyTimes.contains { abs($0.1 - t) < 0.5 / Double(fps) }
            let wantsSheet = sheetTimes.contains { abs($0 - t) < 0.5 / Double(fps) }
            if keysOnly && !wantsKey && !wantsSheet { continue }
            autoreleasepool {
                _ = driver.apply(t)
                let image = driver.render()
                writer?.append(image)
                if wantsSheet { sheet.append((t, image)) }
                for (name, time) in keyTimes where abs(time - t) < 0.5 / Double(fps) {
                    Render.writePNG(NSBitmapImageRep(cgImage: image), out + "/key-\(name).png")
                }
            }
            if frame % 60 == 0 {
                print(String(format: "frame %d t=%.2f (%.1fs)", frame, t, Date().timeIntervalSince(started))); started = Date()
            }
        }
        if let writer {
            let result = writer.finish()
            print("wrote", out + "/collapse.mov", result.frames, "frames status", result.status.rawValue, result.error?.localizedDescription ?? "")
        }
        SpacesSheet.write(sheet, path: out + "/collapse-strip.png", fps: fps)
        writeBeats(plan, driver: driver, path: out + "/collapse-beats.json")
    }

    static func backdrop(_ scene: BrowserScene, plan: Plan, driver: Driver) -> CGImage? {
        let hidden = SidebarPresentationFrame.hidden
        scene.holder.setFrameOrigin(NSPoint(x: -5000, y: 0))
        scene.floating.isHidden = true
        scene.pointer.location = nil
        scene.surface.pageCard = page(.hidden, placement: hidden)
        scene.surface.needsDisplay = true
        let window = scene.render(scene.windowRect, pixelsWide: 2560, pixelsHigh: 1680).cgImage
        scene.holder.setFrameOrigin(.zero)
        return window.flatMap(PopoverMaterial.make)
    }

    static func writeBeats(_ plan: Plan, driver: Driver, path: String) {
        func frame(_ t: Double) -> Int { Int((t * Double(fps)).rounded()) }
        var beats: [[String: Any]] = []
        var cursor = 0.0
        let names = ["resting docked; pointer glides to the sidebar toggle (hover plate) and presses it",
                     "hidden: page card fills the window inside the frame; pointer drifts to the left edge",
                     "floating: pointer moves down Urban parks, Quarterly roadmap draft, Release checklist (hover fills), then leaves",
                     "hidden again; pointer returns to the left edge",
                     "floating again; pointer moves up to the floating sidebar's toggle (Lock sidebar), hover plate, press",
                     "re-docked; pointer glides back to its resting spot; resting docked window"]
        for (index, change) in plan.changes.enumerated() {
            beats.append(["beat": index < names.count ? names[index] : "hold", "start": cursor, "end": change.time,
                          "startFrame": frame(cursor), "endFrame": frame(change.time)])
            let style = change.transition.style == .floating ? "spring (response 0.18, damping ratio 0.8)" : "0.08 s cubic (0.25, 0.46, 0.45, 0.94)"
            beats.append(["beat": "\(change.from) -> \(change.to): \(change.cause); \(style)", "start": change.time,
                          "end": change.time + change.duration, "startFrame": frame(change.time), "endFrame": frame(change.time + change.duration)])
            cursor = change.time + change.duration
        }
        beats.append(["beat": names.last!, "start": cursor, "end": duration, "startFrame": frame(cursor), "endFrame": frame(duration)])
        let root: [String: Any] = [
            "file": "collapse.mov", "codec": "hevcWithAlpha", "width": 2880, "height": 1800, "pointSize": [1440, 900], "scale": 2, "fps": fps,
            "duration": duration, "frames": Int(duration * Double(fps)),
            "window": ["x": 80, "y": 18, "width": 1280, "height": 840, "origin": "top-left, points"],
            "sidebarWidth": Double(width), "frameThickness": Double(thickness),
            "motion": [
                "lockedTransitions": "NSAnimationContext 0.08 s, CAMediaTimingFunction(0.25, 0.46, 0.45, 0.94) (SidebarMotionController.animate .anchored)",
                "floatingTransitions": "CASpringAnimation mass 1, stiffness \(spring.stiffness), damping \(spring.damping), settling \(spring.settling) s (response 0.18, damping ratio 0.8)",
                "frames": "SidebarPresentationFrame / SidebarChromeFrames from Parc's source, evaluated per frame",
                "hover": "SidebarHoverTracking + SidebarHoverZones + SidebarHoverPresentationRule from ParcCore, stepped at 1/1200 s with the tracker's 0.15 s linger and 0.08 s stop timers"],
            "beats": beats,
            "presentationChanges": plan.changes.map { ["time": $0.time, "frame": frame($0.time), "from": "\($0.from)", "to": "\($0.to)", "cause": $0.cause,
                                                       "duration": $0.duration] },
            "hoverDecisions": plan.hoverLog,
            "pointerKeys": plan.keys.map { ["time": $0.time, "x": Double($0.point.x), "y": Double($0.point.y)] },
            "trace": driver.log]
        let data = try! JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try! data.write(to: URL(fileURLWithPath: path))
        print("wrote", path)
    }
}

@MainActor enum SpacesSheet {
    static func write(_ frames: [(Double, CGImage)], path: String, fps: Int) {
        let columns = 4, cell = CGSize(width: 720, height: 450), label: CGFloat = 28
        let rows = (frames.count + columns - 1) / columns
        let width = Int(cell.width) * columns, height = Int(cell.height + label) * rows
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.setFillColor(hex(0xE6E6EA).cgColor); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
        for (index, (time, image)) in frames.enumerated() {
            let column = index % columns, row = index / columns
            let x = CGFloat(column) * cell.width, top = CGFloat(height) - CGFloat(row) * (cell.height + label)
            context.draw(image, in: CGRect(x: x, y: top - label - cell.height, width: cell.width, height: cell.height))
            NSAttributedString(string: String(format: "t = %.3f s  ·  frame %d", time, Int((time * Double(fps)).rounded())),
                               attributes: [.font: NSFont.monospacedSystemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor.black])
                .draw(at: NSPoint(x: x + 14, y: top - label + 6))
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage() else { return }
        Render.writePNG(NSBitmapImageRep(cgImage: image), path)
    }
}
