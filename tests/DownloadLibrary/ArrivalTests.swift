import AppKit

@MainActor final class ManualArrivalSchedule: DownloadArrivalSchedule {
    var now = 0.0
    private var timers: [(due: Double, body: @MainActor () -> Void)] = []
    private var queued: [@MainActor () -> Void] = []
    override var drivesFrames: Bool { false }
    override func after(_ delay: TimeInterval, _ body: @escaping @MainActor () -> Void) { timers.append((now + delay, body)) }
    override func async(_ body: @escaping @MainActor () -> Void) { queued.append(body) }
    var pendingTimers: Int { timers.count }
    func run(until end: Double, frame: Double = 1 / 60, _ controllers: () -> [DownloadArrivalController]) {
        while now + 1e-9 < end {
            let dt = min(frame, end - now); now += dt
            while let index = timers.indices.filter({ timers[$0].due <= now + 1e-9 }).min(by: { timers[$0].due < timers[$1].due }) {
                timers.remove(at: index).body()
            }
            while !queued.isEmpty { let work = queued; queued = []; work.forEach { $0() } }
            for controller in controllers() { controller.advance(dt) }
        }
    }
}

@main @MainActor struct ArrivalChecks {
    static var count = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) { count += 1; precondition(value(), message) }
    static func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool { abs(a - b) <= tolerance }
    static func near(_ a: CGPoint, _ x: Double, _ y: Double, _ tolerance: Double = 1e-9) -> Bool {
        near(Double(a.x), x, tolerance) && near(Double(a.y), y, tolerance)
    }

    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        _ = NSApplication.shared
        expect(LibraryArtwork.directory == Bundle.main.resourceURL?.appendingPathComponent("Library", isDirectory: true)
               && LibraryArtwork.boxOfThings("box") != nil, "the bin item's artwork loads from the bundle's Library resources")
        springs(); flights(); admission()
        try controllers()
        liveFrames()
        if let directory = ProcessInfo.processInfo.environment["PARC_ARRIVAL_ACCEPTANCE"] { try acceptance(URL(fileURLWithPath: directory)) }
        print("Download arrival: \(count) assertions passed")
    }

    static func springs() {
        var spring = DownloadArrivalSpring()
        expect(spring.stiffness == 300 && spring.damping == 10, "Motion defaults 300/10 before configure")
        spring.configure(response: 0.9, dampingRatio: 0.82)
        expect(near(spring.stiffness, 48.738787165873376) && near(spring.damping, 11.4493598930828), "configure: (2π/r)², 4πζ/r")
        expect(near(spring.dampingRatio, 0.82, 1e-12), "Re-derived damping ratio")
        spring.value = SIMD2(-80, 0); spring.toValue = SIMD2(53, 0)
        let show = spring.keyframeValues()
        expect(show.count == 126, "Bin show spring resolves in 125 ticks plus toValue")
        expect(near(show[0].x, -79.15526349351643) && near(show[1].x, -76.83026975112878)
               && near(show[29].x, 46.23933728278481) && near(show[124].x, 52.99927581376286), "Underdamped closed form per 1/60 tick")
        expect(show.last == SIMD2(53, 0), "Keyframe population ends on toValue")
        var negated = DownloadArrivalSpring(); negated.setVelocity(SIMD2(5, -3))
        expect(negated.displacementVelocity == SIMD2(-5, 3), "Velocity setter stores 0 − newValue")
        var critical = DownloadArrivalSpring(initialValue: SIMD2(10, 0))
        critical.configure(response: 1.2, dampingRatio: 1); critical.toValue = .zero
        let w0 = 2 * Double.pi / 1.2, dt = 1.0 / 60
        critical.tick(dt)
        expect(near(critical.value.x, -((-10) * exp(-w0 * dt) * (1 + w0 * dt)) + 0, 1e-9), "Critical branch x' = (x0 + (v + w0·x0)·dt)·e^(−w0·dt)")
        var still = DownloadArrivalSpring(initialValue: SIMD2(4, 0))
        still.toValue = SIMD2(4.005, 0)
        expect(still.hasResolved, "ε = 0.01 resolution on value and velocity")
        still.toValue = SIMD2(4.02, 0)
        expect(!still.hasResolved, "Outside ε is unresolved")
        var broken = DownloadArrivalSpring(); broken.toValue = SIMD2(.nan, 0)
        expect(broken.keyframeValues().isEmpty, "Non-finite spring input produces no keyframes")
    }

    static func flights() {
        let size = CGSize(width: 1200, height: 800), raw = DownloadArrivalFlight.destinationArgument
        let bin = DownloadArrivalFlight(source: CGPoint(x: 615, y: 485), destination: raw, windowSize: size, showsBin: true)
        expect(bin.destination == CGPoint(x: 62, y: 70), "Bin destination stored as raw − 8")
        expect(near(bin.projectileDuration, 1.0137131602926661) && near(bin.initialVerticalVelocity, 933.125)
               && near(bin.horizontalVelocity, -545.5192076625947) && near(bin.apexTime, 0.35229546570015474), "Projectile helpers")
        expect(bin.positions.count == 129 && bin.scales.count == 129, "61 projectile and 68 bounce samples")
        expect(near(bin.duration, 2.1499999999999972), "Duration is the accumulated sample time")
        expect(near(bin.positions[0], 615, 485) && bin.scales[0] == CGPoint(x: 0.8, y: 1.2), "Start at the source with scale (0.8, 1.2)")
        expect(near(bin.positions[1], 605.9080132056234, 500.1842083333333), "Parabola sample")
        expect(near(bin.positions[21], 424.0682773180919, 649.360875) && near(bin.scales[21], 1.59478740790355, 1.597393703951775),
               "Ascending scale just before the apex")
        expect(near(bin.positions[30], 342.2403961687027, 620.475) && near(bin.scales[30], 1.3990164430787428, 1.3990164430787428),
               "Descending scale with the bin coefficient")
        expect(near(bin.positions[60], 69.48079233740464, 93.77499999999759) && near(bin.scales[60], 0.7186596826246112, 0.7186596826246112),
               "Last projectile sample before landing")
        expect(near(bin.positions[61], 62.2593126593285, 45.14132021649253), "First bounce value is one tick from the raw destination")
        expect(bin.positions[128] == CGPoint(x: 70, y: 70) && bin.scales[128] == bin.scales[60], "Bounce settles at the raw destination with the last scale")
        expect(near(Double(bin.positions[61...].map(\.y).min()!), 9.614704418421638), "Bounce dips along the landing velocity")
        let free = DownloadArrivalFlight(source: CGPoint(x: 615, y: 485), destination: raw, windowSize: size, showsBin: false)
        expect(free.destination == CGPoint(x: 32, y: 40), "Without the bin the destination is fixed (32, 40)")
        expect(near(free.projectileDuration, 1.0306213378007802) && near(free.horizontalVelocity, -565.6781774420183), "No-bin projectile")
        expect(free.positions.count == 70 && near(free.duration, 1.1666666666666674), "Eight extra frames, no bounce")
        expect(near(free.positions[30], 332.1609112789909, 620.475) && near(free.scales[30], 1.3169267715011843, 1.3169267715011843),
               "Descending scale with the no-bin coefficient")
        expect(near(free.positions[69], -35.52990405832145, -193.35912500000177) && near(free.scales[69], 0.07121282374444826, 0.07121282374444826),
               "Continues past (32, 40) and keeps shrinking")
        for (source, shows, duration, samples, total) in [(CGPoint(x: 100, y: 100), true, 1.1244606467093237, 136, 2.2666666666666635),
                                                          (CGPoint(x: 100, y: 100), false, 1.143920560767664, 77, 1.2833333333333337),
                                                          (CGPoint(x: 1100, y: 700), true, 0.9711866097121664, 127, 2.116666666666664),
                                                          (CGPoint(x: 70, y: 70), false, 1.1550740817055343, 78, 1.3000000000000003)] {
            let flight = DownloadArrivalFlight(source: source, destination: raw, windowSize: size, showsBin: shows)
            expect(near(flight.projectileDuration, duration) && flight.positions.count == samples && near(flight.duration, total),
                   "Model table \(source) bin \(shows)")
        }
        expect(DownloadArrivalFlight(source: CGPoint(x: 615, y: 485), destination: raw, windowSize: .zero, showsBin: true).initialVerticalVelocity == 1600,
               "Zero window height uses vy0 1600")
        let degenerate = DownloadArrivalFlight(source: CGPoint(x: 600, y: 29.09), destination: raw, windowSize: CGSize(width: 1200, height: 20), showsBin: false)
        expect(degenerate.projectileDuration == 0 && !degenerate.isRenderable, "Negative discriminant: T = 0 and nothing renderable")
        let degenerateBin = DownloadArrivalFlight(source: CGPoint(x: 600, y: 29.09), destination: raw, windowSize: CGSize(width: 1200, height: 20), showsBin: true)
        expect(degenerateBin.positions.isEmpty && !degenerateBin.isRenderable, "Bin with T = 0 samples nothing")
        expect(bin.isRenderable && free.isRenderable, "Ordinary flights render")
    }

    static func admission() {
        func admits(_ valid: Bool = true, page: Bool = true, popup: Bool = false, privateWindow: Bool = false,
                    context: String? = nil, live: Bool = false, profile: Bool = true) -> Bool {
            DownloadArrivalOwner.admits(valid: valid, hasPage: page, popupWindow: popup, privateWindow: privateWindow,
                                        privateContext: context, privateContextLive: live, profileKnown: profile)
        }
        expect(!admits(popup: true), "A popup window never shows the arrival")
        expect(!admits(popup: true, privateWindow: true, context: "otr", live: true),
               "A private popup window never shows the arrival")
        expect(admits(), "A valid regular receipt in a regular window arrives")
        expect(!admits(false), "A stale receipt is refused")
        expect(!admits(page: false), "A receipt whose page is gone is refused")
        expect(!admits(profile: false), "An unknown or retiring Profile is refused")
        expect(!admits(context: "otr"), "A private receipt never reaches a regular window")
        expect(!admits(privateWindow: true), "A regular receipt never reaches a private window")
        expect(!admits(privateWindow: true, context: "otr", live: false), "A retired private context is refused")
        expect(admits(privateWindow: true, context: "otr", live: true), "A live private receipt reaches its private window")
    }

    static func linear(_ function: CAMediaTimingFunction?) -> Bool {
        guard let function else { return false }
        var first: [Float] = [0, 0], second: [Float] = [0, 0]
        function.getControlPoint(at: 1, values: &first); function.getControlPoint(at: 2, values: &second)
        return first == [0, 0] && second == [1, 1]
    }
    static func glyphInk(_ image: CGImage?) -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
        guard let image, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        var ink: (minX: Int, minY: Int, maxX: Int, maxY: Int) = (.max, .max, -1, -1)
        for y in 0..<image.height { for x in 0..<image.width where data[(y * image.width + x) * 4 + 3] > 64 {
            ink = (min(ink.minX, x), min(ink.minY, y), max(ink.maxX, x), max(ink.maxY, y))
        } }
        return ink.maxX < 0 ? nil : ink
    }
    static func makeParent(_ frame: NSRect = NSRect(x: -20000, y: -20000, width: 1200, height: 800)) -> NSWindow {
        let parent = NSWindow(contentRect: frame, styleMask: [], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false; parent.isRestorable = false
        parent.orderFront(nil)
        return parent
    }
    static func palette(dark: Bool) -> ThemeChromePalette {
        ThemeChromePalette(theme: .singleColor(ThemeColor(red: 0.42, green: 0.33, blue: 0.9)!), isDark: dark)
    }
    static func screen(_ parent: NSWindow, _ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: parent.frame.minX + x, y: parent.frame.minY + y) }

    static func controllers() throws {
        let parent = makeParent()
        defer { parent.orderOut(nil) }
        expect(DownloadArrivalController.source(screenPoint: screen(parent, 600, 500), in: parent) == CGPoint(x: 615, y: 485),
               "Screen point → parent base point + (15, −15)")
        expect(DownloadArrivalController.source(screenPoint: NSPoint(x: CGFloat.nan, y: 5), in: parent) == CGPoint(x: 70, y: 70),
               "Non-finite source falls back to (70, 70)")

        let schedule = ManualArrivalSchedule()
        let owner = DownloadArrivalOwner(schedule: schedule)
        var showsBinReads = 0
        owner.arrive(at: screen(parent, 600, 500), in: parent, showsBin: { showsBinReads += 1; return true }(), palette: palette(dark: false))
        guard let controller = owner.controller else { preconditionFailure("Controller created") }
        let child = controller.window
        expect(child.styleMask == [] && !child.isOpaque && child.backgroundColor.alphaComponent == 0 && !child.hasShadow,
               "Clear, borderless, shadowless child window")
        expect(child.level == .floating && child.isVisible && parent.childWindows?.contains(child) == true, "Floating child above the parent")
        expect(child.frame == parent.frame.insetBy(dx: 1, dy: 1), "Child frame is the parent inset by one point")
        expect(controller.root.frame == NSRect(x: -1, y: -1, width: 1200, height: 800), "Root overflows by one point: parent frame space")
        expect(!child.canBecomeKey && !child.canBecomeMain && !child.isKeyWindow && NSApp.keyWindow !== child, "No key or main promotion")
        expect(!child.ignoresMouseEvents, "Mouse handling is never configured: drawn pixels receive clicks")
        expect(child.contentView?.gestureRecognizers.isEmpty == true && controller.root.gestureRecognizers.isEmpty
               && controller.root.bin.item is DownloadBinBoxOfThingsItem,
               "No tap or swipe handling; the bin item is the Library entry's BoxOfThingsIcon item")
        expect(controller.status == .animating && controller.isAnimating && controller.showsBin && showsBinReads == 1,
               "First arrival: animating, bin decision read once")
        let first = controller.downloads[0]
        expect(first.flight.source == CGPoint(x: 615, y: 485) && first.flight.destination == CGPoint(x: 62, y: 70), "Recovered source and bin destination")
        expect(controller.root.subviews.first === controller.root.bin && controller.root.subviews.last === first.view, "Bin below the icon")
        let content = first.view.content.layer!
        let position = content.animation(forKey: "parc.arrival.position") as? CAKeyframeAnimation
        let transform = content.animation(forKey: "parc.arrival.transform") as? CAKeyframeAnimation
        expect(position?.values?.count == first.flight.positions.count && transform?.values?.count == first.flight.scales.count,
               "Position and transform keyframes carry every sample")
        expect(position?.duration == first.flight.duration && position?.fillMode == .forwards && position?.isRemovedOnCompletion == false
               && position.map { linear($0.timingFunction) } == true && position?.keyTimes == nil && position?.calculationMode == .linear,
               "Linear, evenly spaced, forwards-filled keyframes")
        expect(content.position == CGPoint(x: 70, y: 70) && CATransform3DEqualToTransform(content.transform, CATransform3DMakeScale(0.7186596826246112, 0.7186596826246112, 1)),
               "Model layer already rests at the final keyframe")
        let alpha = first.view.face.animation(forKey: "parc.arrival.alpha") as? CASpringAnimation
        let rotation = first.view.face.animation(forKey: "parc.arrival.rotation") as? CASpringAnimation
        expect(alpha.map { near(Double($0.stiffness), pow(2 * .pi / 0.3, 2), 1e-6) && near(Double($0.damping), 4 * .pi / 0.3, 1e-6) } == true,
               "Alpha spring response 0.3, damping fraction 1")
        expect(rotation.map { near(Double($0.stiffness), pow(2 * .pi / 1.2, 2), 1e-6) && ($0.fromValue as? CGFloat) == DownloadArrivalPathView.radians(35)
                && ($0.toValue as? CGFloat) == DownloadArrivalPathView.radians(-5) } == true,
               "Rotation spring −35° → 5° (SwiftUI clockwise), response 1.2")
        expect(alpha?.beginTime == position?.beginTime && rotation?.beginTime == position?.beginTime, "On-appear springs start with the keyframes")
        expect(position != nil && alpha != nil && rotation != nil,
               "No Reduce Motion gate: the flight animates whatever the setting (now \(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion))")
        expect(first.view.icon.bounds.size == CGSize(width: 30, height: 30) && first.view.icon.shadowRadius == 8
               && first.view.icon.shadowOffset == CGSize(width: 0, height: -4), "30-point icon with the recovered shadow")
        expect(glyphInk(DownloadArrivalPathView.glyph(color: .black, scale: 4)).map { $0.minX <= 4 && $0.maxX >= 115 && $0.minY <= 4 && $0.maxY >= 115 } == true,
               "The stretched symbol's ring reaches the 30-point frame, meeting the disc (SwiftUI .resizable)")

        schedule.run(until: 0.5) { [owner.controller].compactMap { $0 } }
        expect(controller.binPositionX > -80 && controller.binPositionX < 60, "Bin slides in with the first flight")
        owner.arrive(at: screen(parent, 900, 300), in: parent, showsBin: { showsBinReads += 1; return false }(), palette: palette(dark: true))
        expect(owner.controller === controller && controller.downloads.count == 2 && showsBinReads == 1,
               "A second arrival appends; the bin decision is not re-read")
        let second = controller.downloads[1]
        expect(controller.root.subviews.last === second.view && second.view.content.layer?.animation(forKey: "parc.arrival.position") != nil,
               "Later arrivals draw above and start at once")
        let firstSlide = first.flight.projectileDuration + 1
        schedule.run(until: firstSlide - 0.05) { [owner.controller].compactMap { $0 } }
        expect(abs(controller.binPositionX - 53) < 0.2 && controller.binPositionX < 53.5, "Bin spring has nearly settled")
        expect(first.iconOffsetX == 0, "No slide before T + 1")
        schedule.run(until: firstSlide + 0.3) { [owner.controller].compactMap { $0 } }
        expect(controller.binPositionX == 53 && controller.root.bin.frame == NSRect(x: 22, y: 22, width: 62, height: 62),
               "Resolved bin rests centred 53 points from the leading and bottom edges")
        expect(first.iconOffsetX < -10 && first.offsetRunning && controller.status == .animating, "First icon slides at T + 1; the group still waits")
        expect(first.view.frame.origin == NSPoint(x: first.iconOffsetX, y: 0) && content.position == CGPoint(x: 70, y: 70)
               && CATransform3DEqualToTransform(content.transform, CATransform3DMakeScale(0.7186596826246112, 0.7186596826246112, 1))
               && content.animation(forKey: "parc.arrival.position") != nil,
               "The slide offsets the whole path view; the keyframed content keeps its resting model and animations")
        let secondSlide = 0.5 + second.flight.projectileDuration + 1
        schedule.run(until: secondSlide + 0.05) { [owner.controller].compactMap { $0 } }
        expect(controller.status == .ending && controller.binPositionX < 53, "Drained group: ending, bin hides with the last slide")
        owner.arrive(at: screen(parent, 300, 300), in: parent, showsBin: true, palette: palette(dark: false))
        expect(controller.downloads.count == 2 && owner.controller === controller, "An arrival while ending is dropped, not queued")
        controller.dismiss(force: false)
        expect(!controller.retired && child.isVisible, "Non-forced dismissal is a no-op while animating")
        schedule.run(until: secondSlide + 4) { [owner.controller].compactMap { $0 } }
        expect(controller.retired && !controller.isAnimating && !child.isVisible && owner.controller == nil,
               "Bin hide resolution retires: ordered out and released")
        expect(parent.childWindows?.contains(child) != true, "Ordering out detaches the child")
        expect(first.iconOffsetX == -133 && controller.binPositionX == -80, "Icon rode out with the bin")
        controller.dismiss(force: true)
        expect(owner.controller == nil && !controller.advance(1 / 60), "Retirement is exactly once and stops ticking")

        let plain = DownloadArrivalOwner(schedule: schedule)
        let start = schedule.now
        plain.arrive(at: screen(parent, 400, 600), in: parent, showsBin: false, palette: palette(dark: false))
        let unbinned = plain.controller!
        expect(unbinned.binPositionX == -80 && unbinned.root.bin.frame.maxX < 0, "Hidden bin stays off the leading edge")
        schedule.run(until: start + unbinned.downloads[0].flight.projectileDuration + 0.99) { [plain.controller].compactMap { $0 } }
        expect(!unbinned.retired && unbinned.downloads[0].iconOffsetX == 0, "No slide without the bin")
        schedule.run(until: start + unbinned.downloads[0].flight.projectileDuration + 1.05) { [plain.controller].compactMap { $0 } }
        expect(unbinned.retired && plain.controller == nil && !unbinned.window.isVisible, "Without the bin completion is immediate at T + 1")

        let combined = DownloadArrivalOwner(schedule: schedule)
        combined.arrive(at: screen(parent, 600, 500), in: parent, showsBin: true, palette: palette(dark: false))
        let other = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: other)
        expect(combined.controller != nil, "CombineLatest waits for both resign key and resign main")
        NotificationCenter.default.post(name: NSWindow.didResignMainNotification, object: other)
        expect(combined.controller == nil, "Any window resigning key/main force-dismisses")
        combined.arrive(at: screen(parent, 600, 500), in: parent, showsBin: true, palette: palette(dark: false))
        let forced = combined.controller!
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: other)
        expect(combined.controller == nil && forced.retired && !forced.window.isVisible, "After both have emitted, each resignation dismisses")
        schedule.run(until: schedule.now + 3) { [forced] }
        expect(forced.retired && combined.controller == nil, "Timers after a forced dismissal do nothing")

        let secure = DownloadArrivalOwner(schedule: schedule)
        secure.arrive(at: screen(parent, 600, 500), in: parent, showsBin: true, palette: palette(dark: false))
        NotificationCenter.default.post(name: Notification.Name("PCNativeWindowSecurityStateChanged"), object: other)
        expect(secure.controller != nil, "Another window's security state is ignored")
        NotificationCenter.default.post(name: Notification.Name("PCNativeWindowSecurityStateChanged"), object: parent)
        expect(secure.controller == nil, "A security surface on the parent retires the arrival (Parc adaptation)")

        let closing = DownloadArrivalOwner(schedule: schedule)
        closing.arrive(at: screen(parent, 600, 500), in: parent, showsBin: true, palette: palette(dark: false))
        let tracked = closing.controller!
        let original = tracked.window.frame
        parent.setFrame(NSRect(origin: parent.frame.origin, size: NSSize(width: 1400, height: 900)), display: false)
        expect(tracked.window.frame == original && tracked.windowSize == CGSize(width: 1200, height: 800) && !tracked.retired,
               "Parent resize is not tracked")
        parent.setFrameOrigin(NSPoint(x: parent.frame.minX + 40, y: parent.frame.minY + 30))
        expect(tracked.window.frame.origin == NSPoint(x: original.minX + 40, y: original.minY + 30), "The child moves with its parent (AppKit)")
        closing.dismiss(force: true)
        expect(closing.controller == nil && tracked.retired, "A forced dismissal (the windowWillClose path) retires")
        parent.setFrame(NSRect(x: -20000, y: -20000, width: 1200, height: 800), display: false)

        let probe = DownloadArrivalOwner(schedule: schedule)
        let base = schedule.now
        probe.arrive(at: screen(parent, 600, 500), in: parent, showsBin: true, palette: palette(dark: false))
        let shown = probe.controller!
        schedule.run(until: base + 1.2) { [probe.controller].compactMap { $0 } }
        let image = render(shown, at: 0.35, scale: 1, background: nil)
        func coverage(_ x: Int, _ y: Int) -> CGFloat { image.colorAt(x: x, y: 800 - 1 - y)?.alphaComponent ?? 0 }
        expect(coverage(1100, 700) == 0 && coverage(600, 100) == 0 && coverage(300, 400) == 0, "Undrawn regions are fully transparent")
        expect(coverage(53, 53) > 0.9, "The bin card is opaque at its centre")
        let apex = shown.downloads[0].flight.positions[21]
        expect(coverage(Int(apex.x), Int(apex.y)) > 0.5, "The flying icon is drawn at its keyframe")
        probe.dismiss(force: true)
    }

    static func liveFrames() {
        guard let screen = NSScreen.main else { return }
        let host = NSWindow(contentRect: NSRect(origin: screen.frame.origin, size: NSSize(width: 2, height: 2)),
                            styleMask: [], backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false; host.alphaValue = 0; host.ignoresMouseEvents = true; host.isOpaque = false
        host.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 2, height: 2))
        host.orderFront(nil)
        defer { host.orderOut(nil) }
        var intervals: [Double] = []
        let driver = DownloadArrivalFrameDriver { dt in intervals.append(dt); return intervals.count < 5 }
        driver.start(in: host.contentView!)
        let deadline = Date().addingTimeInterval(1)
        while intervals.count < 5 && Date() < deadline { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
        expect(intervals.count == 5 && !driver.isRunning, "Display frames tick until no spring runs, then the driver stops itself")
        expect(intervals.allSatisfy { $0 > 0 && $0 < 0.1 }, "Each tick carries the real frame interval: \(intervals)")
    }

    static func render(_ controller: DownloadArrivalController, at t: Double, scale: CGFloat, background: NSColor?) -> NSBitmapImageRep {
        let layer = controller.root.layer!
        let begin = controller.downloads.first?.view.content.layer?.animation(forKey: "parc.arrival.position")?.beginTime ?? 0
        layer.speed = 0; layer.timeOffset = begin + t
        CATransaction.flush()
        let size = controller.root.bounds.size
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
        context.scaleBy(x: scale, y: scale)
        if let background { context.setFillColor(background.cgColor); context.fill(CGRect(origin: .zero, size: size)) }
        (layer.presentation() ?? layer).render(in: context)
        return rep
    }

    static func acceptance(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        func write(_ rep: NSBitmapImageRep, _ name: String) throws {
            try rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
        }
        func crop(_ rep: NSBitmapImageRep, _ rect: CGRect) -> NSBitmapImageRep {
            let flipped = CGRect(x: rect.minX, y: CGFloat(rep.pixelsHigh) - rect.maxY, width: rect.width, height: rect.height)
            return NSBitmapImageRep(cgImage: rep.cgImage!.cropping(to: flipped)!)
        }
        let parent = makeParent()
        defer { parent.orderOut(nil) }
        for dark in [false, true] {
            let name = dark ? "dark" : "light"
            let backdrop = dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.93, alpha: 1)
            for shows in [true, false] {
                let schedule = ManualArrivalSchedule()
                let owner = DownloadArrivalOwner(schedule: schedule)
                owner.arrive(at: screen(parent, 600, 500), in: parent, showsBin: shows, palette: palette(dark: dark))
                let controller = owner.controller!
                controller.window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                let flight = controller.downloads[0].flight
                let slide = flight.projectileDuration + 1
                let times = shows ? [0, 0.18, 0.35, 0.7, 1.0, 1.05, 1.1, 1.2, 1.4, 1.95, slide + 0.15, slide + 0.5, slide + 1.2]
                                  : [0, 0.35, 0.8, 1.0, 1.1, flight.duration]
                let trail = render(controller, at: 0, scale: 1, background: backdrop)
                let trailContext = NSGraphicsContext(bitmapImageRep: trail)!.cgContext
                for step in 1...Int((min(flight.duration, slide) / 0.05).rounded(.down)) {
                    let layer = controller.root.layer!
                    layer.timeOffset = (controller.downloads[0].view.content.layer?.animation(forKey: "parc.arrival.position")?.beginTime ?? 0) + Double(step) * 0.05
                    CATransaction.flush()
                    (layer.presentation() ?? layer).render(in: trailContext)
                }
                try write(trail, "\(name)-\(shows ? "bin" : "nobin")-trail")
                let prefix = "\(name)-\(shows ? "bin" : "nobin")"
                for t in times {
                    schedule.run(until: t) { [owner.controller].compactMap { $0 } }
                    let rep = render(controller, at: t, scale: 1, background: backdrop)
                    try write(rep, prefix + "-t" + String(format: "%.2f", t))
                    if t == 0.35 {
                        let point = flight.positions[21]
                        try write(crop(render(controller, at: t, scale: 3, background: backdrop),
                                       CGRect(x: point.x * 3 - 120, y: point.y * 3 - 120, width: 240, height: 240)), prefix + "-apex-3x")
                    }
                    if t == (shows ? 1.1 : 1.0) || t == (shows ? 1.95 : flight.duration) {
                        try write(crop(render(controller, at: t, scale: 3, background: backdrop),
                                       CGRect(x: 0, y: 0, width: 420, height: 420)), prefix + "-corner-3x-t" + String(format: "%.2f", t))
                    }
                }
                owner.dismiss(force: true)
            }
        }
    }
}
