import AppKit
import QuartzCore
import Testing
@testable import ParcSidebar

@MainActor
struct SidebarPreviewMotionTests {
    final class FlippedHost: NSView { override var isFlipped: Bool { true } }

    final class ExitCommits {
        var pending: [() -> Void] = []
        func commit(_ animations: () -> Void, _ completion: @escaping @Sendable () -> Void) {
            animations()
            pending.append(completion)
        }
        func finish() { let due = pending; pending.removeAll(); due.forEach { $0() } }
    }

    @MainActor final class Stage {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        let host = FlippedHost(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        let exits = ExitCommits()
        let placement = SidebarPreviewFolderCardTests.right
        init() {
            window.isReleasedWhenClosed = false
            host.wantsLayer = true; window.contentView = host
        }
        func surface(reducesMotion: Bool = false, opacity: Float = 1) -> SidebarPreviewSurface {
            let surface = SidebarPreviewSurface(frame: NSRect(x: 224, y: 216, width: 288, height: 200))
            surface.reducesMotion = { reducesMotion }
            let exits = exits
            surface.commitsExit = { exits.commit($0, $1) }
            host.addSubview(surface)
            surface.layer?.opacity = opacity
            CATransaction.flush()
            return surface
        }
        func anchor(in surface: NSView) -> NSPoint { surface.convert(placement.anchor, from: host) }
    }

    private func basic(_ view: NSView, _ key: String) -> CABasicAnimation? { sidebarMotionAnimation(view, key) }
    private func transform(_ value: Any?) -> CATransform3D? { (value as? NSValue)?.caTransform3DValue }
    private func number(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }
    private func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }
    private let easeInOut: [Float] = [0.42, 0, 0.58, 1]

    @Test func theEntranceGrowsAndFadesInForATenthOfASecond() throws {
        let s = Stage(), card = s.surface()
        card.animateIn(from: s.anchor(in: card))
        let grow = try #require(basic(card, "transform")), fade = try #require(basic(card, "opacity"))
        #expect(grow.duration == 0.1 && fade.duration == 0.1)
        #expect(sidebarMotionControlPoints(grow.timingFunction) == easeInOut && sidebarMotionControlPoints(fade.timingFunction) == easeInOut)
        #expect(number(fade.fromValue) == 0 && number(fade.toValue) == 1)
        #expect(transform(grow.toValue).map(CATransform3DIsIdentity) == true)
        let start = try #require(transform(grow.fromValue))
        #expect(near(start.m11, 0.8) && near(start.m22, 0.8))
    }

    @Test func theCardGrowsOutOfTheRowEdge() throws {
        let s = Stage(), card = s.surface()
        let anchor = s.anchor(in: card)
        card.animateIn(from: anchor)
        let start = try #require(transform(basic(card, "transform")?.fromValue))
        card.layer!.transform = start
        let fixed = s.host.layer!.convert(anchor, from: card.layer!)
        let corner = s.host.layer!.convert(CGPoint.zero, from: card.layer!)
        card.layer!.transform = CATransform3DIdentity
        #expect(near(fixed.x, s.placement.anchor.x) && near(fixed.y, s.placement.anchor.y))
        #expect(near(corner.x, 220 + 0.8 * (card.frame.minX - 220)) && near(corner.y, 316 + 0.8 * (card.frame.minY - 316)))
    }

    @Test func repositioningIsImmediateAndAddsNoAnimation() {
        let s = Stage()
        let card = SidebarPreviewCard(title: "Docs", domain: nil, providerURL: nil)
        card.setRows(SidebarPreviewFolderCardTests.rows); card.placement = s.placement
        s.host.addSubview(card); card.place(); CATransaction.flush()
        let before = Set(card.layer?.animationKeys() ?? [])
        let settled = card.frame.minY
        card.placement.row.origin.y += 40; card.place()
        #expect(Set(card.layer?.animationKeys() ?? []) == before)
        #expect(card.frame.minY == settled + 40)
    }

    @Test func anExitingCardTakesNoClicksAndStopsTrackingHover() {
        let s = Stage(), card = s.surface()
        card.updateTrackingAreas()
        card.retire()
        #expect(card.hitTest(NSPoint(x: card.frame.midX, y: card.frame.midY)) == nil)
        #expect(!card.trackingAreas.contains { $0.owner === card })
    }

    @Test func theExitShrinksAndFadesFromThePresentedOpacityAndHoldsItsEnd() throws {
        let s = Stage(), card = s.surface()
        let anchor = s.anchor(in: card)
        card.animateIn(from: anchor)
        let start = try #require(transform(basic(card, "transform")?.fromValue))
        card.layer?.removeAllAnimations(); CATransaction.flush()
        let presented = Double(card.layer?.presentation()?.opacity ?? card.layer?.opacity ?? 0)
        card.retire()
        card.animateOut {}
        let shrink = try #require(basic(card, "transform")), exit = try #require(basic(card, "opacity"))
        #expect(exit.fillMode == .forwards && !exit.isRemovedOnCompletion && shrink.fillMode == .forwards && !shrink.isRemovedOnCompletion)
        #expect(presented > 0 && near(CGFloat(number(exit.fromValue) ?? -1), CGFloat(presented)) && number(exit.toValue) == 0)
        #expect(near(CGFloat(exit.duration), CGFloat(0.1 * presented)))
        #expect(transform(shrink.toValue).map { CATransform3DEqualToTransform($0, start) } == true)
        #expect(sidebarMotionControlPoints(exit.timingFunction) == easeInOut)
    }

    @Test func theCardStaysWhileExitingAndIsRemovedWhenTheExitEnds() {
        let s = Stage(), card = s.surface()
        var removed = false
        card.animateOut { removed = true }
        #expect(card.superview === s.host && !removed)
        s.exits.finish()
        #expect(removed && card.superview == nil)
    }

    @Test func aPartlyFadedCardExitsSooner() {
        let s = Stage(), card = s.surface(opacity: 0.5)
        card.animateOut {}
        #expect(near(CGFloat(basic(card, "opacity")?.duration ?? 0), 0.05))
    }

    @Test func anInvisibleCardIsRemovedImmediately() {
        let s = Stage(), card = s.surface(opacity: 0)
        var removed = false
        card.animateOut { removed = true }
        #expect(removed && card.superview == nil)
    }

    @Test func reduceMotionFadesInWhereTheCardStandsWithoutGrowing() throws {
        let s = Stage(), card = s.surface(reducesMotion: true)
        card.animateIn(from: s.anchor(in: card))
        let fade = try #require(basic(card, "opacity"))
        #expect(Set(card.layer?.animationKeys() ?? []) == ["opacity"])
        #expect(number(fade.fromValue) == 0 && number(fade.toValue) == 1 && fade.duration == 0.1)
        #expect(sidebarMotionControlPoints(fade.timingFunction) == easeInOut)
        #expect(card.layer.map { CATransform3DIsIdentity($0.transform) } == true)
        #expect(card.frame == NSRect(x: 224, y: 216, width: 288, height: 200))
    }

    @Test func reduceMotionFadesOutWithoutShrinking() throws {
        let s = Stage(), card = s.surface(reducesMotion: true)
        card.retire()
        #expect(card.hitTest(NSPoint(x: card.frame.midX, y: card.frame.midY)) == nil)
        let opacity = Double(card.layer?.presentation()?.opacity ?? card.layer?.opacity ?? 0)
        var removed = false
        card.animateOut { removed = true }
        let exit = try #require(basic(card, "opacity"))
        #expect(Set(card.layer?.animationKeys() ?? []) == ["opacity"])
        #expect(opacity > 0 && near(CGFloat(number(exit.fromValue) ?? -1), CGFloat(opacity)) && number(exit.toValue) == 0)
        #expect(exit.fillMode == .forwards && !exit.isRemovedOnCompletion && sidebarMotionControlPoints(exit.timingFunction) == easeInOut)
        #expect(near(CGFloat(exit.duration), CGFloat(0.1 * opacity)))
        #expect(card.superview === s.host && !removed)
        s.exits.finish()
        #expect(removed && card.superview == nil)
    }
}
