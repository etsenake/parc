import CoreGraphics
import Foundation

typealias M = HistorySwipeOverlayMetrics
typealias T = HistorySwipeOverlayTiming
typealias G = HistorySwipeOverlayGeometry
typealias Haptic = HistorySwipeOverlayModel.Haptic

let pane = CGSize(width: 832, height: 664)

func band(_ progress: Double, _ resistance: Double = 0.15) -> Double {
    let resisted = (progress - 1) * resistance
    return 1 + resisted / (resisted + 1)
}

struct Driver {
    var model = HistorySwipeOverlayModel()
    var time = 10.0
    var haptics: [Haptic] = []
    var size = pane

    init(back: Int = 3, forward: Int = 2, reduced: Bool = false) {
        model.backRows = back
        model.forwardRows = forward
        model.prefersReducedMotion = reduced
    }

    mutating func send(_ output: HistorySwipeOutput, after delay: Double = 0) {
        time += delay
        if let haptic = model.receive(output, at: time) { haptics.append(haptic) }
    }

    mutating func progress(_ value: Double, after delay: Double = 0) {
        send(.progress(HistorySwipeProgress(fraction: min(max(value, 0), 1), stretch: value)), after: delay)
    }

    mutating func wait(_ delay: Double) {
        time += delay
        model.advance(to: time)
    }

    mutating func settle() {
        for _ in 0..<180 { wait(1.0 / 120) }
    }

    var frame: HistorySwipeOverlayFrame? { model.frame(in: size) }

    static func armed(_ direction: HistorySwipeDirection = .back, back: Int = 3, forward: Int = 2,
                      reduced: Bool = false, stretch: Double = 1) -> Driver {
        var driver = Driver(back: back, forward: forward, reduced: reduced)
        driver.send(.begin(direction))
        driver.progress(stretch)
        driver.send(.armed(true))
        driver.settle()
        return driver
    }

    static func holding(_ direction: HistorySwipeDirection = .back, back: Int = 3, forward: Int = 2,
                        reduced: Bool = false) -> Driver {
        var driver = armed(direction, back: back, forward: forward, reduced: reduced)
        driver.send(.hold)
        driver.send(.selection(0))
        driver.settle()
        return driver
    }
}

struct Environment: HistorySwipeEnvironment {
    var back = 3
    var forward = 0
    var swipesBetweenPages = true
    var allowsHistorySwipe = true
    func historyEntries(toward direction: HistorySwipeDirection) -> Int { direction == .back ? back : forward }
}

struct Fingers {
    var recognizer = HistorySwipeRecognizer()
    var overlay = Driver()
    var environment = Environment()
    var time = 10.0
    var x = 0.30
    var y = 0.5
    var lastStep = HistorySwipeStep()
    var outputs: [HistorySwipeOutput] = []

    init(back: Int, reduced: Bool = false) {
        environment.back = back
        overlay = Driver(back: back, forward: 0, reduced: reduced)
    }

    mutating func feed(_ input: HistorySwipeInput) {
        lastStep = recognizer.receive(input, in: environment)
        outputs += lastStep.outputs
        for output in lastStep.outputs { overlay.time = max(overlay.time, time); overlay.send(output) }
    }

    var commits: [HistorySwipeCommit] {
        outputs.compactMap { if case let .commit(commit) = $0 { commit } else { nil } }
    }

    var points: [HistorySwipePoint] { [HistorySwipePoint(x: x - 0.06, y: y), HistorySwipePoint(x: x + 0.06, y: y)] }

    mutating func touch(_ phase: HistorySwipeTouchPhase, _ x: Double, _ y: Double? = nil) {
        time += 0.008
        self.x = x
        if let y { self.y = y }
        feed(.touches(phase, points, time: time))
    }

    mutating func scroll(_ phase: HistorySwipeEventPhase, dx: Double) {
        feed(.scroll(HistorySwipeScroll(phase: phase, deltaX: dx, directionInverted: true)))
    }

    mutating func open() {
        touch(.began, 0.30)
        scroll(.mayBegin, dx: 0)
        touch(.moved, 0.302)
        scroll(.began, dx: 2)
        feed(.pageScroll(.began(synthetic: false, momentum: false)))
        feed(.overscroll(propagatesX: true))
        feed(.pageScroll(.updated(consumed: false)))
        touch(.moved, 0.305)
        scroll(.changed, dx: 3)
    }

    mutating func clock() {
        guard let deadline = lastStep.clockDeadline else { return }
        time = deadline
        feed(.clock(deadline))
    }
}

@main struct HistorySwipeOverlayTests {
    static var count = 0

    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("HistorySwipeOverlay: \(message)") }
    }

    static func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }
    static func close(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 1e-6) -> Bool { abs(a - b) <= tolerance }
    static func close(_ a: CGRect, _ b: CGRect, _ tolerance: CGFloat = 1e-6) -> Bool {
        close(a.minX, b.minX, tolerance) && close(a.minY, b.minY, tolerance)
            && close(a.width, b.width, tolerance) && close(a.height, b.height, tolerance)
    }

    static func main() {
        diaValues()
        curves()
        springs()
        circleFollowsFingers()
        arming()
        collapse()
        holdMorph()
        listLayout()
        selectionSlides()
        selectionLeans()
        collapseBackToCircle()
        reopenDuringCollapse()
        longHistories()
        reduceMotion()
        reduceMotionCollapse()
        narrowPanes()
        looks()
        recognizerToOverlay()
        recognizerCollapseUnderReduceMotion()
        lifetimes()
        print("HistorySwipeOverlay: \(count) checks passed")
    }

    static func diaValues() {
        check(M.restingDiameter == 72 && M.armedDiameter == 82 && M.edgeInset == 14, "Dia's 72 pt circle, 82 pt armed, 14 pt inside the edge")
        check(M.restingChevron == 28 && M.armedChevron == 34 && M.chevronPointSize == 28 && M.restingChevronOpacity == 0.5,
              "Dia's 28 pt bold chevron growing to 34 pt and from half to full opacity")
        check(M.cardWidth == 200 && M.rowHeight == 38 && M.cardInset == 8 && M.cardRadius == 18,
              "Dia's 200 pt card with 38 pt rows, 8 pt insets and an 18 pt radius")
        check(M.highlightRadius == 10 && M.faviconSize == 16 && M.faviconRadius == 4 && M.titleSize == 13 && M.titleGap == 8,
              "Dia's 10 pt highlight radius, 16 pt favicons and 13 pt titles")
        check(M.ringWidth == 1 && M.shadowRadius == 8 && M.shadowDrop == 2, "Dia's 1 pt ring and soft shadow")
        check(T.arm == .init(damping: 0.70, response: 0.18) && T.morph == .init(damping: 0.77, response: 0.22)
              && T.selection == .init(damping: 0.9, response: 0.27), "Dia's arming, morph and highlight springs")
        check(T.fade == 0.18 && T.swap == 0.22 && T.swapScale == 0.9 && T.blur == 10, "Dia's fades and list swap")
        check(T.collapse == 0.2 && T.collapseScale == 0.01, "Dia's 0.2 s collapse to 1%")
        check(M.reducedAppearance == 0.2 && T.reducedFade == 0.12 && T.reducedSwap == 0.15 && T.reducedCollapse == 0.15,
              "the approved Reduce Motion crossfades")
        check(M.rowLean == 0.1, "Dia's 0.1 rubber band on the lean between rows")
    }

    static func curves() {
        let out = HistorySwipeCurve.easeOut, ease = HistorySwipeCurve.easeIn
        check(out(0) == 0 && out(1) == 1 && ease(0) == 0 && ease(1) == 1, "curves start at 0 and end at 1")
        check(close(out(0.5), 0.7713235628639843, 1e-6) && close(ease(0.5), 0.31535681250589304, 1e-6),
              "Dia's ease-out front-loads the fade and the collapse's ease-in back-loads it, as in the mockup")
        let samples = stride(from: 0.0, through: 1.0, by: 0.01).map { out($0) }
        check(zip(samples, samples.dropFirst()).allSatisfy { $1 >= $0 }, "the ease-out never runs backward")
        check(HistorySwipeCurve.linear(0.3) == 0.3, "the linear curve is linear")
    }

    static func springs() {
        var arm = HistorySwipeSpring(72, T.arm, tolerance: 0.01)
        var stepped = arm
        arm.advance(toward: 82, by: 0.1)
        for _ in 0..<100 { stepped.advance(toward: 82, by: 0.001) }
        check(close(arm.value, stepped.value, 1e-9) && close(arm.velocity, stepped.velocity, 1e-7),
              "the spring lands in the same place at any frame rate")
        let zeta = 0.70, omega = 2 * Double.pi / 0.18, damped = omega * (1 - zeta * zeta).squareRoot()
        var peak = HistorySwipeSpring(72, T.arm, tolerance: 0.0001)
        peak.advance(toward: 82, by: Double.pi / damped)
        check(close(peak.value, 82 + 10 * exp(-zeta * Double.pi / (1 - zeta * zeta).squareRoot()), 1e-9)
              && abs(peak.velocity) < 1e-9, "arming overshoots to Dia's damping-0.70 peak at the damped half period")
        var settle = HistorySwipeSpring(72, T.arm, tolerance: 0.01)
        settle.advance(toward: 82, by: 0.6)
        check(settle.value == 82 && settle.velocity == 0, "the arming spring settles and snaps within 0.6 s")
        var critical = HistorySwipeSpring(0, .init(damping: 1, response: 0.2), tolerance: 1e-6)
        var heavy = HistorySwipeSpring(0, .init(damping: 1.5, response: 0.2), tolerance: 1e-6)
        critical.advance(toward: 1, by: 0.1)
        heavy.advance(toward: 1, by: 0.1)
        check(critical.value > 0 && critical.value < 1 && heavy.value > 0 && heavy.value < critical.value,
              "critically and over-damped springs approach without overshoot")
    }

    static func circleFollowsFingers() {
        var back = Driver()
        back.send(.begin(.back))
        check(back.frame.map { close($0.circle.maxX, 0) } == true, "the circle starts fully hidden past the left edge")
        back.progress(0.5)
        check(back.frame.map { close($0.circle.minX, 0.5 * 86 - 72) } == true,
              "the circle tracks the fingers on the same input, with no lag")
        back.progress(1)
        check(back.frame.map { close($0.circle.minX, 14) && close($0.circle.midY, pane.height / 2) } == true,
              "at the commit point its edge sits 14 pt inside the pane, centred vertically")
        back.progress(band(2))
        check(back.frame.map { close($0.circle.minX, 14 + 86 * (band(2) - 1)) } == true,
              "past the commit point it follows the recognizer's rubber band")
        var armed = Driver.armed(stretch: band(2))
        check(armed.frame.map { abs($0.circle.minX - 26.5) < 0.1 && close($0.circle.width, 82) } == true,
              "an armed circle at twice the commit distance sits about 26 pt inside, as in Dia's screenshot")
        armed.progress(band(1.5))
        check(armed.frame.map { close($0.circle.minX, CGFloat(band(1.5)) * 96 - 82) } == true,
              "the rubber band scales with the armed circle's size")

        var forward = Driver()
        forward.send(.begin(.forward))
        check(forward.frame.map { close($0.circle.minX, pane.width) } == true, "Forward starts hidden past the right edge")
        forward.progress(1)
        check(forward.frame.map { close($0.circle.maxX, pane.width - 14) } == true, "Forward mirrors the 14 pt inset on the right")
        check(forward.frame.map { close($0.chevronCenter.x, $0.circle.midX) && close($0.chevronCenter.y, $0.circle.midY) } == true,
              "the chevron sits in the circle's centre without a nudge")
    }

    static func arming() {
        var driver = Driver()
        driver.send(.begin(.back))
        driver.progress(1)
        let start = driver.time
        check(driver.frame.map { $0.wash == 0 && $0.chevronOpacity == 0.5 && $0.chevronSize == 28 } == true,
              "before arming the chevron is 28 pt at half opacity with no wash")
        driver.send(.armed(true))
        check(driver.haptics == [.levelChange], "arming plays one level-change haptic")
        driver.wait(0.09)
        let half = HistorySwipeCurve.easeOut(0.5)
        check(driver.frame.map { close($0.wash, half) && close($0.chevronOpacity, 0.5 + 0.5 * half) } == true,
              "the wash and chevron brighten on Dia's 0.18 s ease-out")
        var sizes: [CGFloat] = []
        for _ in 0..<60 {
            driver.wait(0.01)
            if let frame = driver.frame { sizes.append(frame.circle.width) }
        }
        check(driver.frame.map { $0.wash == 1 && $0.chevronOpacity == 1 } == true && driver.time - start > T.fade,
              "the armed look completes after the fade")
        check(sizes.max()! > 82.3 && sizes.max()! < 82.6 && sizes.last == 82,
              "the circle springs past 82 pt and settles there")
        check(driver.frame?.chevronSize == 34 && !driver.model.isAnimating, "the chevron grows to 34 pt and the motion rests")
        driver.send(.armed(false))
        check(driver.haptics == [.levelChange], "backing off plays no haptic")
        driver.wait(T.fade + 0.0001)
        check(driver.frame?.wash == 0 && driver.frame?.chevronOpacity == 0.5, "backing off fades the armed look away")
        driver.settle()
        check(driver.frame?.circle.width == 72 && driver.frame?.chevronSize == 28, "backing off springs the circle back to 72 pt")
    }

    static func collapse() {
        var commit = Driver.armed()
        var cancel = Driver.armed()
        let before = commit.frame!.capsule
        commit.send(.commit(.adjacent(.back)))
        cancel.send(.cancel)
        commit.wait(0.1)
        cancel.wait(0.1)
        let amount = HistorySwipeCurve.easeIn(0.5)
        check(commit.frame.map { close($0.opacity, 1 - amount) && close($0.scale, 1 - 0.99 * amount)
                && close($0.blur, 10 * amount) && close($0.capsule, before) } == true,
              "committing collapses in place on a 0.2 s ease-in to 1% with a blur and fade")
        check(commit.frame == cancel.frame, "cancelling plays exactly the same collapse")
        check(commit.haptics == [.levelChange] && cancel.haptics == [.levelChange], "neither ending plays a haptic")
        commit.wait(0.1001)
        check(commit.frame == nil && !commit.model.isAnimating, "after 0.2 s nothing is left")
        commit.send(.progress(HistorySwipeProgress(fraction: 1, stretch: 1)))
        check(commit.frame == nil, "late progress never revives a finished swipe")
    }

    static func holdMorph() {
        var driver = Driver.armed(back: 3)
        let circle = driver.frame!.circle
        driver.send(.hold)
        driver.send(.selection(0))
        check(driver.haptics == [.levelChange, .generic], "opening the list plays a generic haptic")
        let opened = driver.time
        check(driver.frame.map { close($0.capsule, circle) && $0.list?.opacity == 0 && $0.list?.scale == 0.9
                && $0.list?.blur == 10 && $0.chevronOpacity == 1 } == true,
              "the list starts blurred, scaled to 0.9 and hidden inside the circle")
        driver.wait(0.11)
        let half = HistorySwipeCurve.easeOut(0.5)
        check(driver.frame.map { close($0.list!.opacity, half) && close($0.chevronScale, 1 - 0.1 * half)
                && close($0.chevronBlur, 10 * half) && close($0.chevronOpacity, 1 - half) } == true,
              "chevron and list swap on Dia's 0.22 s curve with blur and scale")
        let zeta = 0.77, omega = 2 * Double.pi / 0.22, damped = omega * (1 - zeta * zeta).squareRoot()
        let t = driver.time - opened
        let morph = 1 - exp(-zeta * omega * t) * (cos(damped * t) + zeta * omega / damped * sin(damped * t))
        check(driver.frame.map { close($0.capsule.width, 82 + (200 - 82) * CGFloat(morph), 1e-6) } == true,
              "the circle morphs into the card on Dia's 0.77 / 0.22 s spring")
        driver.wait(0.1101)
        check(driver.frame.map { $0.list?.opacity == 1 && $0.list?.scale == 1 && $0.list?.blur == 0 && $0.chevronOpacity == 0 } == true,
              "the swap completes after 0.22 s")
        driver.settle()
        check(driver.frame.map { close($0.capsule, $0.list!.card) && $0.cornerRadius == 18 } == true,
              "the morph settles on the card with an 18 pt radius")
    }

    static func listLayout() {
        let back = Driver.holding(.back, back: 3)
        let frame = back.frame!, list = frame.list!
        check(list.rows == 4 && close(list.card.width, 200) && close(list.card.height, 4 * 38 + 16),
              "the Back card holds the current page and three entries: 200 pt wide, rows × 38 + 16 tall")
        check(close(list.card.minX, frame.circle.minX), "the Back card's left edge stays on the circle's left edge")
        check(list.selection == 0 && close(list.highlight.midY, frame.circle.midY) && close(list.row(0), list.highlight),
              "the list opens with the current page highlighted, its row centred where the circle was")
        check(close(list.row(1).maxY, list.row(0).minY) && close(list.row(2).maxY, list.row(1).minY)
              && close(list.row(3).maxY, list.row(2).minY), "Back puts the current page at the bottom and older pages above")
        check(close(list.row(0).minX, list.content.minX + 8) && close(list.row(0).width, 184)
              && close(list.highlight.width, 184), "rows and the highlight sit 8 pt inside the card")

        let forward = Driver.holding(.forward, forward: 3)
        let ahead = forward.frame!, rows = ahead.list!
        check(close(rows.card.maxX, ahead.circle.maxX), "the Forward card's right edge stays on the circle's right edge")
        check(close(rows.row(0), rows.highlight) && close(rows.row(1).minY, rows.row(0).maxY)
              && close(rows.row(3).minY, rows.row(2).maxY), "Forward puts the current page at the top and newer pages below")
    }

    static func selectionSlides() {
        var driver = Driver.holding(.back, back: 3)
        let before = driver.frame!.list!.content
        driver.send(.selection(1))
        driver.send(.detent)
        check(driver.haptics.last == .alignment, "each row step plays an alignment haptic")
        driver.wait(0.1)
        let moving = driver.frame!.list!
        check(close(moving.highlight.midY, pane.height / 2) && moving.content.minY > before.minY
              && moving.content.minY < before.minY + 38, "the card slides on a spring while the highlight stays under the fingers")
        let zeta = 0.9, omega = 2 * Double.pi / 0.27, damped = omega * (1 - zeta * zeta).squareRoot()
        let shift = 38 * (1 - exp(-zeta * omega * 0.1) * (cos(damped * 0.1) + zeta * omega / damped * sin(damped * 0.1)))
        check(close(moving.content.minY, before.minY + CGFloat(shift), 1e-6), "the slide follows Dia's 0.9 / 0.27 s spring")
        driver.settle()
        let settled = driver.frame!.list!
        check(close(settled.content.minY, before.minY + 38) && close(settled.row(1), settled.highlight),
              "one row step moves the Back card down a row so the previous page lands under the fingers")

        var forward = Driver.holding(.forward, forward: 3)
        let top = forward.frame!.list!.content
        forward.send(.selection(3))
        forward.settle()
        check(forward.frame.map { close($0.list!.content.minY, top.minY - 114) && close($0.list!.row(3), $0.list!.highlight) } == true,
              "Forward slides its card up as the selection moves down the list")
        forward.send(.selection(9))
        forward.settle()
        check(forward.frame?.list?.selection == 3, "a selection beyond the rows stays on the last row")
    }

    static func selectionLeans() {
        check(close(G.lean(remainder: 0), 0) && close(G.lean(remainder: 0.5), 38 * (1 - 1 / 1.05))
              && close(G.lean(remainder: -0.5), -38 * (1 - 1 / 1.05)), "Dia's lean: 38 pt times 1 - 1 / (0.1 |r| + 1)")
        check(G.lean(remainder: 0.99) < 3.5 && G.lean(remainder: 20) < 38, "the lean resists, so it only hints at the next row")
        var driver = Driver.holding(.back, back: 3)
        let before = driver.frame!.list!
        driver.send(.rowRemainder(0.5))
        driver.wait(0.1)
        let zeta = 0.9, omega = 2 * Double.pi / 0.27, damped = omega * (1 - zeta * zeta).squareRoot()
        let lean = Double(G.lean(remainder: 0.5))
        let shift = lean * (1 - exp(-zeta * omega * 0.1) * (cos(damped * 0.1) + zeta * omega / damped * sin(damped * 0.1)))
        check(close(driver.frame!.list!.content.minY, before.content.minY + CGFloat(shift), 1e-6),
              "the lean rides the highlight's 0.9 / 0.27 s spring")
        driver.settle()
        let leaning = driver.frame!.list!
        check(close(leaning.content.minY, before.content.minY + CGFloat(lean)) && close(leaning.highlight, before.highlight)
              && leaning.highlight.midY < leaning.row(0).midY && leaning.highlight.midY > leaning.row(1).midY,
              "the highlight stays under the fingers and leans from the current page toward the previous one")
        driver.send(.rowRemainder(-0.5))
        driver.settle()
        check(close(driver.frame!.list!.content.minY, before.content.minY - CGFloat(lean)), "a negative remainder leans the other way")
        driver.send(.selection(1))
        driver.send(.rowRemainder(0))
        driver.settle()
        check(close(driver.frame!.list!.content.minY, before.content.minY + 38) && close(driver.frame!.list!.row(1), driver.frame!.list!.highlight),
              "a full row step lands squarely on the next row")

        var forward = Driver.holding(.forward, forward: 3)
        let top = forward.frame!.list!.content
        forward.send(.rowRemainder(0.5))
        forward.settle()
        check(close(forward.frame!.list!.content.minY, top.minY - CGFloat(lean)), "a Forward list leans its card up toward newer pages")

        var closed = Driver.armed()
        closed.send(.rowRemainder(0.5))
        check(closed.model.remainder == 0, "a closed list ignores the remainder")
    }

    static func collapseBackToCircle() {
        var driver = Driver.holding(.back, back: 3)
        driver.send(.selection(2))
        driver.settle()
        let open = driver.frame!.list!
        driver.send(.rowRemainder(0.5))
        driver.progress(0.9)
        driver.send(.armed(false))
        check(driver.haptics == [.levelChange, .generic] && !driver.model.listOpen && !driver.model.armed,
              "sliding below the commit point closes the list silently")
        check(driver.model.remainder == 0, "closing drops the lean toward the next row")
        let start = driver.frame!
        check(close(start.capsule, open.card) && start.list?.opacity == 1 && start.chevronOpacity == 0,
              "the collapse starts from the open card, with no jump")
        driver.wait(0.11)
        let mid = driver.frame!, half = HistorySwipeCurve.easeOut(0.5)
        let swapIn = 1 - half, armedAmount = 1 - HistorySwipeCurve.easeOut(0.11 / 0.18)
        check(mid.list.map { close($0.opacity, swapIn) && close($0.scale, 0.9 + 0.1 * swapIn) && close($0.blur, 10 * half) } == true,
              "the list swaps out on Dia's 0.22 s curve, blurring and shrinking to 0.9")
        check(close(mid.chevronOpacity, (0.5 + 0.5 * armedAmount) * half) && close(mid.chevronScale, 1 - 0.1 * swapIn)
              && close(mid.chevronBlur, 10 * swapIn), "while the chevron swaps back in")
        let zeta = 0.77, omega = 2 * Double.pi / 0.22, damped = omega * (1 - zeta * zeta).squareRoot(), t = 0.11
        let morph = exp(-zeta * omega * t) * (cos(damped * t) + zeta * omega / damped * sin(damped * t))
        check(close(mid.capsule.width, mid.circle.width + (200 - mid.circle.width) * CGFloat(morph), 1e-6)
              && mid.list.map { close($0.row(2), $0.highlight) } == true,
              "the card folds back into the circle on Dia's 0.77 / 0.22 s spring, keeping its rows in place")
        driver.settle()
        let rest = driver.frame!
        check(rest.list == nil && close(rest.capsule, rest.circle) && rest.cornerRadius == 36 && rest.circle.width == 72
              && rest.chevronOpacity == 0.5 && rest.chevronScale == 1 && rest.chevronBlur == 0 && rest.wash == 0
              && !driver.model.isAnimating, "the collapse settles on the resting circle")

        driver.progress(1.1)
        driver.send(.armed(true))
        driver.settle()
        let circle = driver.frame!.circle
        driver.send(.hold)
        driver.send(.selection(0))
        check(driver.haptics == [.levelChange, .generic, .levelChange, .generic], "rearming and reopening tick again")
        check(driver.frame.map { close($0.capsule, circle) && $0.list?.opacity == 0 && $0.list?.scale == 0.9 && $0.list?.blur == 10 } == true,
              "the list reopens from the circle the same way it first opened")
        driver.settle()
        check(driver.frame.map { close($0.capsule, $0.list!.card) && close($0.list!.row(0), $0.list!.highlight) } == true,
              "the reopened list sits on the current page")
    }

    static func reopenDuringCollapse() {
        var driver = Driver.holding(.back, back: 3)
        driver.send(.selection(2))
        driver.settle()
        driver.progress(0.9)
        driver.send(.armed(false))
        driver.wait(0.1)
        driver.progress(1.1)
        driver.send(.armed(true))
        let before = driver.frame!
        driver.send(.hold)
        driver.send(.selection(0))
        let after = driver.frame!
        check(close(after.capsule, before.capsule) && close(after.list!.content, before.list!.content)
              && close(after.list!.opacity, before.list!.opacity) && close(after.chevronOpacity, before.chevronOpacity),
              "reopening mid-collapse picks up exactly where the collapse is")
        var widths: [CGFloat] = []
        for _ in 0..<60 {
            driver.wait(1.0 / 120)
            widths.append(driver.frame!.capsule.width)
        }
        let jumps = zip(widths, widths.dropFirst()).map { abs($1 - $0) }
        check(jumps.max()! < 20, "and morphs back out smoothly")
        driver.settle()
        check(driver.frame.map { close($0.capsule, $0.list!.card) && close($0.list!.row(0), $0.list!.highlight) && $0.list!.opacity == 1 } == true,
              "ending on the current page")
    }

    static func longHistories() {
        var driver = Driver.holding(.back, back: 50)
        var everyRowShown = true
        var everyCardInside = true
        for row in 0...50 {
            driver.send(.selection(row))
            driver.settle()
            let list = driver.frame!.list!
            everyRowShown = everyRowShown && close(list.row(row), list.highlight) && list.card.contains(list.highlight)
            everyCardInside = everyCardInside && list.card.minY >= 14 - 1e-9 && list.card.maxY <= pane.height - 14 + 1e-9
        }
        check(everyRowShown, "every one of 50 Back entries scrolls into view under the fingers")
        check(everyCardInside, "a long card stays 14 pt inside the pane while its rows scroll")
        check(driver.frame.map { close($0.list!.content.height, 51 * 38 + 16) && $0.list!.card.height < $0.list!.content.height } == true,
              "the card shows a window onto the full list")
        check(driver.frame.map { close($0.capsule, $0.list!.card) } == true, "the material, ring and shadow follow the visible card")

        let short = Driver.holding(.back, back: 2).frame!.list!
        check(close(short.card, short.content), "a short history shows the whole card, as in Dia")

        var squat = Driver.holding(.forward, forward: 30)
        squat.size = CGSize(width: 600, height: 300)
        squat.send(.selection(15))
        squat.settle()
        check(squat.frame.map { close($0.list!.row(15), $0.list!.highlight) && $0.list!.card.minY >= 14 && $0.list!.card.maxY <= 286 } == true,
              "a short pane keeps the scrolling card inside it")
    }

    static func reduceMotion() {
        var driver = Driver(reduced: true)
        driver.send(.begin(.back))
        driver.progress(0.1)
        check(driver.frame?.opacity == 0, "with Reduce Motion nothing shows for the first 20% of travel")
        driver.progress(0.25)
        driver.wait(0.06)
        check(driver.frame.map { close($0.opacity, 0.5) && close($0.circle.minX, 14) && $0.circle.width == 72 } == true,
              "then a static circle fades in at its resting spot")
        driver.wait(0.0601)
        driver.progress(0.8)
        let still = driver.frame!.circle
        driver.progress(band(2))
        check(driver.frame.map { $0.opacity == 1 && close($0.circle, still) } == true, "the circle never slides or stretches")
        driver.send(.armed(true))
        check(driver.haptics == [.levelChange], "arming still plays its haptic")
        driver.wait(0.06)
        check(driver.frame.map { close($0.wash, 0.5) } == true, "arming crossfades linearly over 0.12 s")
        driver.settle()
        check(driver.frame.map { $0.circle.width == 72 && $0.chevronSize == 28 && $0.wash == 1 && $0.chevronOpacity == 1 } == true,
              "arming changes only opacity, not size")
        driver.send(.hold)
        driver.send(.selection(0))
        check(driver.frame.map { close($0.capsule, $0.list!.card) && $0.opacity == 0 && $0.list!.scale == 1
                && $0.list!.blur == 0 && $0.chevronBlur == 0 && $0.chevronScale == 1 } == true,
              "the list replaces the circle without a morph, scale or blur")
        driver.wait(0.075)
        check(driver.frame.map { close($0.opacity, 0.5) && close($0.list!.opacity, 0.5) } == true, "and crossfades in over 0.15 s")
        driver.settle()
        let before = driver.frame!.list!.content
        driver.send(.selection(1))
        check(driver.frame.map { close($0.list!.content.minY, before.minY + 38) } == true, "rows step without a slide")
        driver.send(.rowRemainder(0.6))
        driver.settle()
        check(driver.frame.map { close($0.list!.content.minY, before.minY + 38) } == true, "and never lean between rows")
        driver.send(.commit(.entry(.back, distance: 1)))
        driver.wait(0.075)
        check(driver.frame.map { close($0.opacity, 0.5) && $0.scale == 1 && $0.blur == 0 } == true,
              "the ending is a 0.15 s fade with no scale or blur")
        driver.wait(0.08)
        check(driver.frame == nil, "and then it is gone")

        var retreat = Driver(reduced: true)
        retreat.send(.begin(.back))
        retreat.progress(0.5)
        retreat.wait(0.2)
        retreat.progress(0.1)
        retreat.wait(0.1201)
        check(retreat.frame?.opacity == 0, "backing off below 20% fades the circle out")
    }

    static func reduceMotionCollapse() {
        var driver = Driver.holding(.back, back: 3, reduced: true)
        driver.send(.selection(2))
        driver.settle()
        driver.progress(0.9)
        driver.send(.armed(false))
        check(driver.frame.map { $0.list == nil && close($0.capsule, $0.circle) && $0.opacity == 0 && $0.scale == 1 && $0.blur == 0 } == true,
              "with Reduce Motion the card gives way to the circle without a morph, and no rows show through it")
        driver.wait(0.075)
        check(driver.frame.map { close($0.opacity, 0.5) && $0.chevronBlur == 0 && $0.chevronScale == 1 } == true,
              "the circle crossfades back in over 0.15 s")
        driver.settle()
        check(driver.frame.map { $0.opacity == 1 && $0.list == nil && $0.circle.width == 72 } == true && !driver.model.isAnimating,
              "and rests as the static circle")
        driver.send(.armed(true))
        driver.send(.hold)
        driver.send(.selection(0))
        check(driver.frame.map { close($0.capsule, $0.list!.card) && $0.opacity == 0 && close($0.list!.row(0), $0.list!.highlight) } == true,
              "reopening replaces the circle with the card on the current page")
        driver.wait(0.075)
        check(driver.frame.map { close($0.opacity, 0.5) } == true, "and crossfades it in again")

        var open = Driver.holding(.back, back: 3, reduced: true)
        open.send(.selection(2))
        open.progress(0.12)
        open.settle()
        check(open.frame.map { $0.opacity == 1 && $0.list != nil } == true, "an open list never fades while it can still navigate")
        open.send(.armed(false))
        var brightest = open.frame!.opacity
        for _ in 0..<40 {
            open.wait(1.0 / 120)
            brightest = max(brightest, open.frame?.opacity ?? 0)
        }
        check(brightest == 0 && open.frame?.list == nil, "closing it that far back hides the indicator at once, without flashing the circle")
    }

    static func narrowPanes() {
        var driver = Driver.holding(.back, back: 3)
        driver.size = CGSize(width: 220, height: 500)
        check(driver.frame.map { close($0.list!.card.minX, 14) && close($0.list!.card.width, 192) } == true,
              "a narrow pane narrows the card to keep it 14 pt inside")
        var right = Driver.holding(.forward, forward: 3)
        right.size = CGSize(width: 260, height: 500)
        check(right.frame.map { $0.list!.card.minX >= 14 && $0.list!.card.maxX <= 246 } == true,
              "a Forward card stays inside a narrow pane")
        var split = Driver.armed(.forward)
        split.size = CGSize(width: 412, height: 664)
        check(split.frame.map { close($0.circle.maxX, 398) } == true, "geometry is measured in the pane's own bounds")
    }

    static func looks() {
        let dark = HistorySwipeOverlayLook(dark: true), light = HistorySwipeOverlayLook(dark: false)
        check(dark.ringWhite == 1 && dark.ringAlpha == 0.15 && light.ringWhite == 0 && light.ringAlpha == 0.125,
              "the ring is white 15% in dark and black 12.5% in light")
        check(dark.shadowAlpha == 0.25 && light.shadowAlpha == 0.2, "the shadow is 25% in dark and 20% in light")
        check(dark.washAlpha == 0 && light.washAlpha == 0.4, "the armed wash is white 40% in light and absent in dark")
        check(dark.highlightWhite == 1 && light.highlightWhite == 0 && dark.highlightAlpha == 0.1 && light.highlightAlpha == 0.1,
              "the highlight is 10% white in dark and 10% black in light")
    }

    static func recognizerToOverlay() {
        var hand = Fingers(back: 50)
        hand.open()
        hand.touch(.moved, 0.38)
        check(hand.overlay.frame.map { abs($0.circle.minX - 14) < 0.001 } == true,
              "at the recognizer's commit point the circle's edge is 14 pt inside")
        check(hand.overlay.haptics == [.levelChange], "the recognizer's arming ticks the trackpad once")
        hand.clock()
        check(hand.overlay.haptics == [.levelChange, .generic] && hand.overlay.model.listOpen,
              "the recognizer's hold opens the list with a generic haptic")
        check(hand.overlay.model.selection == 0 && hand.overlay.frame.map { close($0.list!.row(0), $0.list!.highlight) } == true,
              "the recognizer opens the list on the current page")
        hand.touch(.moved, 0.38, 0.70)
        hand.touch(.moved, 0.38, 0.88)
        check(hand.overlay.model.selection == 4 && hand.overlay.haptics.filter { $0 == .alignment }.count == 4,
              "every row the fingers travel ticks once")
        check(abs(hand.overlay.model.remainder - 0.75) < 1e-9, "and the recognizer's remainder reaches the overlay")
        for _ in 0..<100 where hand.lastStep.clockDeadline != nil { hand.clock() }
        hand.overlay.settle()
        check(hand.overlay.model.selection == 50 && hand.overlay.haptics.filter { $0 == .alignment }.count == 50,
              "resting at the trackpad's edge carries the list to the oldest of 50 entries, ticking each row")
        check(hand.overlay.frame.map { close($0.list!.row(50), $0.list!.highlight) } == true,
              "and the oldest entry is the one under the fingers")
        hand.touch(.ended, 0.38)
        check(hand.recognizer.state == .completed, "lifting commits the oldest entry")
        hand.overlay.wait(T.collapse + 0.0001)
        check(hand.overlay.frame == nil, "and the list collapses away")
    }

    static func recognizerCollapseUnderReduceMotion() {
        var hand = Fingers(back: 3, reduced: true)
        hand.open()
        hand.touch(.moved, 0.38)
        hand.clock()
        hand.touch(.moved, 0.38, 0.59)
        hand.touch(.moved, 0.38, 0.67)
        hand.overlay.settle()
        check(hand.recognizer.selection == 2 && hand.overlay.frame.map { $0.opacity == 1 && close($0.list!.row(2), $0.list!.highlight) } == true,
              "with Reduce Motion the list is fully shown while two pages back is picked")
        hand.touch(.moved, 0.3096, 0.67)
        check(hand.recognizer.state == .tracking && !hand.overlay.model.listOpen && hand.overlay.frame?.list == nil,
              "sliding most of the way back closes the list in the recognizer and the overlay together")
        hand.overlay.settle()
        check(hand.overlay.frame?.opacity == 0, "and the indicator hides below 20% of travel")
        hand.touch(.ended, 0.3096)
        check(hand.commits.isEmpty && hand.outputs.last == .cancel, "so lifting there navigates nowhere")

        var back = Fingers(back: 3, reduced: true)
        back.open()
        back.touch(.moved, 0.38)
        back.clock()
        back.touch(.moved, 0.38, 0.59)
        back.touch(.moved, 0.36, 0.59)
        back.touch(.moved, 0.385, 0.59)
        back.clock()
        back.overlay.settle()
        check(back.overlay.model.listOpen && back.overlay.frame.map { $0.opacity == 1 && close($0.list!.row(0), $0.list!.highlight) } == true,
              "rearming and resting reopens the list on the current page")
        back.touch(.ended, 0.385)
        check(back.commits.isEmpty && back.outputs.last == .cancel, "and lifting at once navigates nowhere")
    }

    static func lifetimes() {
        var idle = Driver()
        check(idle.frame == nil && !idle.model.isAnimating, "nothing draws before a swipe begins")
        idle.send(.progress(HistorySwipeProgress(fraction: 1, stretch: 1)))
        idle.send(.armed(true))
        idle.send(.hold)
        check(idle.frame == nil && idle.haptics.isEmpty, "outputs without a begin draw and play nothing")
        var again = Driver.armed()
        again.send(.cancel)
        again.wait(0.05)
        again.send(.begin(.forward))
        check(again.frame.map { $0.opacity == 1 && $0.scale == 1 && $0.direction == .forward && $0.wash == 0 } == true,
              "a new swipe during a collapse starts fresh")
        var reset = Driver.holding()
        reset.model.reset()
        check(reset.frame == nil && !reset.model.isAnimating, "leaving the window drops the indicator at once")
    }
}
