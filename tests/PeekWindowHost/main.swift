import AppKit
import QuartzCore

@main
@MainActor
struct PeekWindowHostChecks {
    static let window = CGRect(x: 0, y: 0, width: 1280, height: 800)
    static let sidebarWidth: CGFloat = 228

    static func page(thickness t: CGFloat, docked: Bool = true) -> CGRect {
        let left = docked ? sidebarWidth : t
        return CGRect(x: left, y: t, width: window.width - left - t, height: window.height - 2 * t)
    }

    static func close(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.01) -> Bool { abs(a - b) <= tolerance }

    static func main() { exitOnFailure(runChecks) }

    static func runChecks() {
        cardIsMeasuredFromTheWindow()
        pageStepsBackEvenly()
        stepTransformKeepsTheCenter()
        stepFollowsASlidingPage()
        openingRidesASlide()
        regionsRouteClicks()
        steppedPageRejectsTheRevealedBand()
        hitTestingThroughTheViewTree()
        print("Peek window host checks passed")
    }

    static func cardIsMeasuredFromTheWindow() {
        for t: CGFloat in [3, 10, 13] {
            for docked in [true, false] {
                let page = page(thickness: t, docked: docked)
                let card = PeekWindowLayout(bounds: window, page: page, stepsBack: true).card
                assert(card.minY == 12 && card.maxY == window.maxY - 12,
                       "the card sits 12 points from the window's top and bottom at frame \(t): \(card)")
                assert(card.width == (page.width * 0.8).rounded(.down), "the card keeps 80% of the page width: \(card)")
                assert(abs(card.midX - page.midX) <= 1, "the card stays centred on the page: \(card)")
            }
        }
        let classic = page(thickness: 10)
        let today = classic.minY + 12
        assert(today - PeekWindowLayout(bounds: window, page: classic, stepsBack: true).card.minY == 10,
               "with the classic frame the card moves 10 points closer to each window edge")
        let tight = CGRect(x: 0, y: 0, width: 400, height: 300)
        let narrow = PeekWindowLayout(bounds: tight, page: tight, stepsBack: true)
        assert(narrow.card.minX >= PeekWindowLayout.controlGap + PeekWindowLayout.controlSize,
               "a narrow page keeps room for the round controls: \(narrow.card)")
        let controls = narrow.controls(closeWidth: PeekWindowLayout.controlSize)
        assert(controls.minX == narrow.card.maxX + 13 && controls.minY == narrow.card.minY + 7,
               "the controls sit 13 points right of the card and 7 below its top: \(controls)")
        let wide = PeekWindowLayout(bounds: window, page: classic, stepsBack: true).controls(closeWidth: 400)
        assert(wide.maxX <= classic.maxX - 4, "a widened Close stays inside the page, clear of the split grip: \(wide)")
    }

    static func pageStepsBackEvenly() {
        for t: CGFloat in [3, 10, 13] {
            let page = page(thickness: t)
            let layout = PeekWindowLayout(bounds: window, page: page, stepsBack: true)
            let stepped = layout.steppedPage()
            assert(close(stepped.minX - page.minX, 9) && close(page.maxX - stepped.maxX, 9),
                   "the page steps back 9 points at each side at frame \(t): \(stepped)")
            let vertical = stepped.minY - page.minY
            assert(close(vertical, 9 * page.height / page.width) && vertical > 6 && vertical < 9,
                   "the step is an even scale, a little less top and bottom: \(vertical)")
            assert(close(stepped.midX, page.midX) && close(stepped.midY, page.midY), "the page shrinks about its centre")
            assert(layout.steppedPage(progress: 0) == page, "no progress means no step")
            let half = layout.steppedPage(progress: 0.5)
            assert(close(half.minX - page.minX, 4.5), "half progress is half the step: \(half)")
        }
        let still = PeekWindowLayout(bounds: window, page: page(thickness: 10), stepsBack: false)
        assert(still.scale == 1 && still.steppedPage() == still.page, "Reduce Motion keeps the page where it is")
        let tiny = PeekWindowLayout(bounds: window, page: CGRect(x: 0, y: 0, width: 30, height: 30), stepsBack: true)
        assert(tiny.scale == 1, "a page too small to step back stays put")
    }

    static func stepTransformKeepsTheCenter() {
        let bounds = CGRect(x: 0, y: 0, width: 1042, height: 780)
        let scale = (bounds.width - 18) / bounds.width
        for anchor in [CGPoint.zero, CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0, y: 1)] {
            let transform = PeekWindowLayout.stepTransform(bounds: bounds, anchor: anchor, scale: scale)
            let layer = CALayer()
            layer.anchorPoint = anchor
            layer.bounds = bounds
            layer.position = CGPoint(x: 300, y: 200)
            let host = CALayer()
            host.addSublayer(layer)
            layer.transform = transform
            let left = layer.convert(CGPoint(x: bounds.minX, y: bounds.midY), to: host)
            let right = layer.convert(CGPoint(x: bounds.maxX, y: bounds.midY), to: host)
            let center = layer.convert(CGPoint(x: bounds.midX, y: bounds.midY), to: host)
            layer.transform = CATransform3DIdentity
            let originalLeft = layer.convert(CGPoint(x: bounds.minX, y: bounds.midY), to: host)
            let originalCenter = layer.convert(CGPoint(x: bounds.midX, y: bounds.midY), to: host)
            assert(close(center.x, originalCenter.x) && close(center.y, originalCenter.y),
                   "the step keeps the page centre fixed for anchor \(anchor)")
            assert(close(left.x - originalLeft.x, 9) && close(right.x - left.x, bounds.width - 18),
                   "the step moves each side 9 points in for anchor \(anchor)")
        }
        assert(CATransform3DIsIdentity(PeekWindowLayout.stepTransform(bounds: bounds, anchor: .zero, scale: 1)),
               "no scale is the identity")
    }

    static func regionsRouteClicks() {
        let t: CGFloat = 10
        let page = page(thickness: t)
        let layout = PeekWindowLayout(bounds: window, page: page, stepsBack: true)
        let controls = layout.controls(closeWidth: PeekWindowLayout.controlSize)
        let card = layout.card
        let stepped = layout.steppedPage()
        func region(_ x: CGFloat, _ y: CGFloat) -> PeekWindowLayout.Region { layout.region(at: CGPoint(x: x, y: y), controls: controls) }
        assert(region(page.midX + card.width / 2 + 60, 4) == .frame, "the top frame drags the window")
        assert(region(page.minX + 20, 4) == .frame, "the top frame left of the card drags the window")
        assert(region(card.midX, card.minY + 2) == .card, "the card's top edge in the old frame band is the Peek")
        assert(region(page.minX + 3, page.midY) == .frame, "the band the step reveals acts as frame")
        assert(region(page.maxX - 3, page.midY) == .frame, "the band the step reveals on the right acts as frame")
        assert(region(page.minX + 40, page.maxY - 2) == .frame, "the band the step reveals at the bottom acts as frame")
        assert(region(stepped.minX + 4, page.midY) == .page, "the faded page closes the Peek")
        assert(region(card.maxX + 5, page.midY) == .page, "the faded page beside the card closes the Peek")
        assert(region(card.midX, page.midY) == .card, "the card is the Peek")
        assert(region(controls.midX, controls.minY + 4) == .controls, "the round buttons are the Peek's controls")
        assert(region(page.maxX + t / 2, page.midY) == .frame, "the split grip margin stays the grip's")
        assert(region(sidebarWidth / 2, 300) == .frame, "the docked sidebar stays the sidebar's")
        let still = PeekWindowLayout(bounds: window, page: page, stepsBack: false)
        assert(still.region(at: CGPoint(x: page.minX + 3, y: page.midY), controls: controls) == .page,
               "without the step, the page's edge still closes the Peek")
    }

    static func steppedPageRejectsTheRevealedBand() {
        let bounds = CGRect(x: 0, y: 0, width: 1042, height: 780)
        let scale = (bounds.width - 18) / bounds.width
        assert(!PeekWindowLayout.pageAcceptsHit(at: CGPoint(x: 4, y: 390), in: bounds, scale: scale),
               "the parent page ignores clicks in the band the step reveals")
        assert(PeekWindowLayout.pageAcceptsHit(at: CGPoint(x: 20, y: 390), in: bounds, scale: scale),
               "the parent page keeps its stepped area")
        assert(PeekWindowLayout.pageAcceptsHit(at: CGPoint(x: 4, y: 390), in: bounds, scale: 1),
               "a page that isn't stepped back takes every click")
    }

    final class Page: NSView {
        var scale: CGFloat = 1
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let superview, PeekWindowLayout.pageAcceptsHit(at: convert(point, from: superview), in: bounds, scale: scale) else {
                return nil
            }
            return super.hitTest(point)
        }
    }

    static func transform(_ value: Any?) -> CATransform3D? { (value as? NSValue)?.caTransform3DValue }

    static func centreOffset(of transform: CATransform3D, width: CGFloat) -> CGFloat {
        transform.m41 + transform.m11 * width / 2 - width / 2
    }

    static func midway(_ from: CATransform3D, _ to: CATransform3D, _ fraction: CGFloat) -> CATransform3D {
        var result = to
        result.m41 = from.m41 + (to.m41 - from.m41) * fraction
        result.m42 = from.m42 + (to.m42 - from.m42) * fraction
        return result
    }

    static func stepFollowsASlidingPage() {
        let narrow = CGRect(x: 0, y: 0, width: 1042, height: 780)
        let wide = CGRect(x: 0, y: 0, width: 1042 + sidebarWidth, height: 780)
        let scale = PeekWindowLayout(bounds: window, page: wide, stepsBack: true).scale
        func page() -> (NSView, CALayer) {
            let view = NSView(frame: wide)
            view.wantsLayer = true
            guard let layer = view.layer else { fatalError("a windowless view still gets its layer") }
            return (view, layer)
        }

        let (still, stillLayer) = page()
        let resting = PeekStepBack([still])
        resting.set(1, scale: scale)
        let held = stillLayer.animation(forKey: PeekStepBack.key) as? CABasicAnimation
        assert(held.flatMap { transform($0.fromValue) }.map { CATransform3DEqualToTransform($0, transform(held?.toValue)!) } == true,
               "without a slide the step simply holds")
        let heldTransform = transform(held?.toValue)!
        assert(close(centreOffset(of: heldTransform, width: wide.width), 0), "a held step is centred on the page")
        assert(abs(centreOffset(of: heldTransform, width: narrow.width)) > 1,
               "a step held for the final width sits off-centre on a page still sliding from the old width")

        let (view, layer) = page()
        let slide = CABasicAnimation(keyPath: PeekStepBack.slideKey)
        slide.fromValue = NSValue(rect: narrow)
        slide.toValue = NSValue(rect: wide)
        slide.duration = 0.2
        slide.beginTime = 500
        slide.isRemovedOnCompletion = false
        slide.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.46, 0.45, 0.94)
        layer.add(slide, forKey: PeekStepBack.slideKey)
        let step = PeekStepBack([view])
        step.set(1, scale: scale)
        guard let follow = layer.animation(forKey: PeekStepBack.key) as? CABasicAnimation,
              let from = transform(follow.fromValue), let to = transform(follow.toValue) else {
            return assert(false, "a sliding page gets a step that follows the slide")
        }
        assert(follow.keyPath == "transform" && follow.isAdditive && !follow.isRemovedOnCompletion && follow.fillMode == .both,
               "the following step is an additive transform that stays once the slide ends")
        assert(follow.duration == slide.duration && follow.beginTime == 500 && follow.timingFunction == slide.timingFunction,
               "the step rides the slide's own clock and curve")
        assert(CATransform3DEqualToTransform(to, PeekWindowLayout.stepTransform(bounds: wide, anchor: layer.anchorPoint, scale: scale)),
               "the step ends centred on the final page")
        for fraction: CGFloat in [0, 0.25, 0.5, 0.75, 1] {
            let width = narrow.width + (wide.width - narrow.width) * fraction
            assert(close(centreOffset(of: midway(from, to, fraction), width: width), 0),
                   "the step stays centred on the page at \(fraction) of the slide")
        }

        step.set(0.5, scale: scale)
        let fading = layer.animation(forKey: PeekStepBack.key) as? CABasicAnimation
        let factor = 1 - 0.5 * (1 - scale)
        assert(fading?.beginTime == 500 && transform(fading?.fromValue).map {
            CATransform3DEqualToTransform($0, PeekWindowLayout.stepTransform(bounds: narrow, anchor: layer.anchorPoint, scale: factor))
        } == true, "a fade during the slide keeps following it from the same start")

        step.set(1, scale: scale)
        layer.removeAnimation(forKey: PeekStepBack.slideKey)
        step.refresh()
        let after = layer.animation(forKey: PeekStepBack.key) as? CABasicAnimation
        assert(after.flatMap { transform($0.fromValue) }.map { CATransform3DEqualToTransform($0, transform(after?.toValue)!) } == true
               && after?.duration == 1, "a slide cut short snaps the step to the final page at the next layout, centred")
        step.refresh()
        assert(layer.animation(forKey: PeekStepBack.key) === after, "a settled step isn't re-applied on every layout")

        let (springing, springLayer) = page()
        let spring = CASpringAnimation(keyPath: PeekStepBack.slideKey)
        spring.isAdditive = true
        spring.fromValue = NSValue(rect: CGRect(x: 0, y: 0, width: narrow.width - wide.width, height: 0))
        spring.toValue = NSValue(rect: .zero)
        spring.stiffness = 1218; spring.damping = 55.8
        spring.duration = spring.settlingDuration
        springLayer.add(spring, forKey: PeekStepBack.slideKey)
        PeekStepBack([springing]).set(1, scale: scale)
        let sprung = springLayer.animation(forKey: PeekStepBack.key) as? CASpringAnimation
        assert(sprung?.stiffness == 1218 && sprung?.damping == 55.8 && transform(sprung?.fromValue).map {
            CATransform3DEqualToTransform($0, PeekWindowLayout.stepTransform(bounds: narrow, anchor: springLayer.anchorPoint, scale: scale))
        } == true, "a floating sidebar's spring slide is followed with the same spring from the page's old width")

        let (moving, movingLayer) = page()
        let move = CABasicAnimation(keyPath: PeekStepBack.slideKey)
        move.fromValue = NSValue(rect: wide.offsetBy(dx: 40, dy: 0))
        movingLayer.add(move, forKey: PeekStepBack.slideKey)
        PeekStepBack([moving]).set(1, scale: scale)
        let moved = movingLayer.animation(forKey: PeekStepBack.key) as? CABasicAnimation
        assert(moved.flatMap { transform($0.fromValue) }.map { CATransform3DEqualToTransform($0, transform(moved?.toValue)!) } == true,
               "a slide that doesn't change the page's size keeps the plain hold")
    }

    static func slidingPage(from start: CGRect, to end: CGRect, slide: CABasicAnimation) -> (NSView, CALayer) {
        let view = NSView(frame: end)
        view.wantsLayer = true
        guard let layer = view.layer else { fatalError("a windowless view still gets its layer") }
        slide.fromValue = NSValue(rect: start)
        slide.isRemovedOnCompletion = false
        layer.add(slide, forKey: PeekStepBack.slideKey)
        return (view, layer)
    }

    static func openingRidesASlide() {
        let narrow = CGRect(x: 0, y: 0, width: 1042, height: 780)
        let wide = CGRect(x: 0, y: 0, width: 1042 + sidebarWidth, height: 780)
        let scale = PeekWindowLayout(bounds: window, page: wide, stepsBack: true).scale
        let final = PeekWindowLayout.stepTransform(bounds: wide, anchor: .zero, scale: scale)

        let resting = NSView(frame: wide)
        resting.wantsLayer = true
        guard let restingLayer = resting.layer else { return assert(false, "a windowless view still gets its layer") }
        PeekStepBack([resting]).animateIn(scale: scale)
        let plain = restingLayer.animation(forKey: PeekStepBack.key) as? CABasicAnimation
        assert(plain?.duration == PeekStepBack.openDuration && plain?.timingFunction == CAMediaTimingFunction(name: .easeOut)
               && transform(plain?.toValue).map { CATransform3DEqualToTransform($0, final) } == true,
               "a Peek opening with no slide keeps its plain 0.3-second ease-out step")

        func check(_ slide: CABasicAnimation, _ label: String) -> (CAKeyframeAnimation, [CATransform3D], [Double])? {
            let (view, layer) = slidingPage(from: narrow, to: wide, slide: slide)
            PeekStepBack([view]).animateIn(scale: scale)
            guard let opening = layer.animation(forKey: PeekStepBack.key) as? CAKeyframeAnimation,
                  let values = opening.values?.compactMap(transform), let times = opening.keyTimes?.map(\.doubleValue),
                  values.count == times.count, values.count > 2 else {
                assert(false, "a Peek opening \(label) rides the slide"); return nil
            }
            assert(opening.isAdditive && !opening.isRemovedOnCompletion && opening.fillMode == .both
                   && opening.calculationMode == .linear, "the opening that rides a slide stays put once it ends")
            assert(CATransform3DEqualToTransform(values[values.count - 1], final), "it ends exactly on the final step \(label)")
            assert(close(values[0].m11, 1), "it starts from the page at rest \(label)")
            return (opening, values, times)
        }

        let now = CACurrentMediaTime()
        let library = CABasicAnimation(keyPath: PeekStepBack.slideKey)
        library.duration = 0.2; library.beginTime = now - 0.05
        guard let first = check(library, "while the Library is already sliding") else { return }
        let (opening, values, times) = first
        assert(close(opening.duration, PeekStepBack.openDuration, 0.005), "the opening keeps its 0.3 seconds when the slide ends first")
        func aimedOnlyAtTheEnd(_ value: CATransform3D, width: CGFloat) -> CGFloat {
            let eased = (1 - value.m11) / (1 - final.m11)
            return abs(eased * final.m41 + (1 + eased * (final.m11 - 1)) * width / 2 - width / 2)
        }
        var worst: CGFloat = 0
        for (value, time) in zip(values, times) {
            let moment = opening.beginTime + time * opening.duration
            let slid = CGFloat(min(1, max(0, (moment - library.beginTime) / library.duration)))
            let width = narrow.width + (wide.width - narrow.width) * slid
            assert(close(centreOffset(of: value, width: width), 0), "the opening step stays centred on the sliding page at \(time)")
            worst = max(worst, aimedOnlyAtTheEnd(value, width: width))
        }
        assert(zip(values, values.dropFirst()).allSatisfy { $1.m11 <= $0.m11 + 1e-9 }, "the page only steps back while opening")

        let long = CABasicAnimation(keyPath: PeekStepBack.slideKey)
        long.duration = 0.5; long.beginTime = now
        guard let second = check(long, "when the slide outlasts it") else { return }
        let (outlasting, longValues, longTimes) = second
        assert(close(outlasting.duration, long.beginTime + long.duration - outlasting.beginTime, 0.001),
               "the composed step lasts until the slide ends")
        for (value, time) in zip(longValues, longTimes) {
            let moment = outlasting.beginTime + time * outlasting.duration
            let width = narrow.width + (wide.width - narrow.width) * CGFloat(min(1, (moment - long.beginTime) / long.duration))
            assert(close(centreOffset(of: value, width: width), 0), "the step stays centred while the long slide runs at \(time)")
            worst = max(worst, aimedOnlyAtTheEnd(value, width: width))
            if time * outlasting.duration >= PeekStepBack.openDuration + 0.01 {
                assert(close(value.m11, final.m11), "after the opening ends the step holds its final size")
            }
        }
        assert(worst > 0.5, "an opening aimed only at the final width would sit off-centre during these slides")

        let spring = CASpringAnimation(keyPath: PeekStepBack.slideKey)
        spring.stiffness = 1218; spring.damping = 55.8
        spring.duration = spring.settlingDuration
        guard let third = check(spring, "while the floating sidebar springs") else { return }
        let (sprung, springValues, springTimes) = third
        assert(close(sprung.duration, max(PeekStepBack.openDuration, spring.duration), 0.01),
               "a spring slide is composed for as long as the spring runs")
        func springWidth(at elapsed: Double) -> CGFloat {
            var offset = 1.0, velocity = 0.0, clock = 0.0
            let step = 1e-5, mass = Double(spring.mass), stiffness = Double(spring.stiffness), damping = Double(spring.damping)
            while clock < elapsed {
                velocity += (-stiffness * offset - damping * velocity) / mass * step
                offset += velocity * step
                clock += step
            }
            return narrow.width + (wide.width - narrow.width) * CGFloat(1 - offset)
        }
        var springChecks = 0
        for (index, (value, time)) in zip(springValues, springTimes).enumerated()
        where index > 0 && index < springValues.count - 1 && index % 4 == 0 {
            springChecks += 1
            let elapsed = time * sprung.duration
            assert(close(centreOffset(of: value, width: springWidth(at: elapsed)), 0, 0.02),
                   "the opening step stays centred on the springing page at \(elapsed) seconds")
        }
        assert(springChecks >= 6, "the spring is checked all the way through")
    }

    final class Flipped: NSView { override var isFlipped: Bool { true } }

    static func hitTestingThroughTheViewTree() {
        let t: CGFloat = 10
        let frame = page(thickness: t)
        let content = Flipped(frame: window)
        let root = Flipped(frame: window)
        content.addSubview(root)
        let page = Page(frame: frame)
        let pageContent = Flipped(frame: page.bounds)
        page.addSubview(pageContent)
        let grip = Flipped(frame: CGRect(x: frame.maxX, y: frame.midY - 22, width: t, height: 44))
        let layer = PeekLayerView(frame: window)
        let host = PeekHitView(frame: layer.bounds)
        let layout = PeekWindowLayout(bounds: host.bounds, page: frame, stepsBack: true)
        host.hitLayout = layout
        let controls = layout.controls(closeWidth: PeekWindowLayout.controlSize)
        host.hitControls = controls
        let card = Flipped(frame: layout.card)
        let cardContent = Flipped(frame: card.bounds)
        card.addSubview(cardContent)
        let close = Flipped(frame: CGRect(origin: controls.origin, size: CGSize(width: 32, height: 32)))
        host.addSubview(card); host.addSubview(close)
        layer.addSubview(host)
        let sidebar = Flipped(frame: CGRect(x: 5, y: 5, width: sidebarWidth, height: window.height - 10))
        root.addSubview(page); root.addSubview(grip); root.addSubview(layer); root.addSubview(sidebar)
        page.scale = layout.scale
        func hit(_ x: CGFloat, _ y: CGFloat) -> NSView? { root.hitTest(CGPoint(x: x, y: y)) }

        assert(hit(frame.midX + layout.card.width / 2 + 60, 4) === root, "the top frame reaches the window, so it drags")
        assert(root.mouseDownCanMoveWindow, "the window background lets a top-edge press move the window")
        assert(hit(frame.maxX - 3, frame.midY) === root, "the revealed band reaches the window for the frame menu")
        assert(hit(frame.maxX + 3, 4) === root, "the right frame reaches the window")
        assert(hit(frame.minX + 30, frame.midY) === host, "the faded page goes to the Peek, which closes it")
        assert(hit(layout.card.midX, frame.midY) === cardContent, "the card's page gets its own clicks")
        assert(hit(layout.card.midX, layout.card.minY + 2) === cardContent, "the card's top above the old frame line is the page")
        assert(hit(close.frame.midX, close.frame.midY) === close, "Close gets its click")
        assert(hit(grip.frame.midX, grip.frame.midY) === grip, "the split grip keeps working")
        assert(host.claims(CGPoint(x: frame.minX + 30, y: frame.midY)) && host.claims(CGPoint(x: layout.card.midX, y: 14)),
               "the faded page and the card count as the Peek's for the window's click and swipe watch")
        assert(!host.claims(CGPoint(x: frame.maxX - 3, y: frame.midY)) && !host.claims(CGPoint(x: 100, y: 4))
               && !host.claims(grip.frame.origin), "the frame, the revealed band and the grip are not the Peek's")
        assert(hit(100, 300) === sidebar, "the floating sidebar stays above the Peek")
        sidebar.removeFromSuperview()
        assert(hit(100, 300) === root, "with the sidebar away, its area is frame again")
        assert(hit(frame.minX + 3, frame.midY) === root, "the revealed band on the left is frame too")
        host.isHidden = true; page.scale = 1
        assert(hit(frame.minX + 3, frame.midY) === pageContent, "with the Peek hidden the page takes clicks at its edge")
        assert(hit(frame.minX + 30, frame.midY) === pageContent, "with the Peek hidden the page takes its own clicks")
    }
}
