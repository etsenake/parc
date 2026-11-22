import AppKit
import Testing
@testable import ParcSidebar

struct MiniPlayerMotionTests {
    @MainActor private struct Fixture {
        let window: NSWindow
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let deck = NSView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let card = NSView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        let back = NSView(frame: CGRect(x: 5, y: 5, width: 45, height: 45))
        let companion = NSView(frame: CGRect(x: 100, y: 0, width: 50, height: 50))
        let unrelated = NSView(frame: CGRect(x: 0, y: 100, width: 50, height: 50))
        let motion = MiniPlayerMotion()

        init() {
            _ = NSApplication.shared
            window = NSWindow(contentRect: root.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            [root, deck, card, back, companion, unrelated].forEach { $0.wantsLayer = true }
            deck.addSubview(back)
            deck.addSubview(card)
            root.addSubview(deck)
            root.addSubview(companion)
            root.addSubview(unrelated)
            window.contentView = root
        }

        func animate(reduceMotion: Bool = false) {
            motion.layout(in: root, deck: deck, companion: companion, animated: true, reduceMotion: reduceMotion) {
                card.frame = CGRect(x: 10, y: 15, width: 75, height: 70)
                back.alphaValue = 0.4
                companion.frame.origin.x = 110
                unrelated.frame.origin.x = 10
            }
        }

        func addIndependentAnimation(to view: NSView) {
            let independent = CABasicAnimation(keyPath: "opacity")
            independent.fromValue = 0.2
            independent.toValue = 1
            independent.duration = 10
            view.layer?.add(independent, forKey: "unrelated")
        }
    }

    @MainActor @Test func movingTheCardAndCompanionUsesTheLayoutSpring() throws {
        let fixture = Fixture()
        fixture.animate()
        let spring = try #require(fixture.card.layer?.animation(forKey: "parc.media.position") as? CASpringAnimation)
        let omega = 2 * Double.pi / 0.25
        #expect(abs(spring.stiffness - omega * omega) < 0.01 && abs(spring.damping - 1.8 * omega) < 0.01)
        #expect(fixture.companion.layer?.animation(forKey: "parc.media.position") != nil)
    }

    @MainActor @Test func rearrangingTheDeckDoesNotAnimateOtherViews() {
        let fixture = Fixture()
        fixture.animate()
        #expect(fixture.unrelated.layer?.animation(forKey: "parc.media.position") == nil)
    }

    @MainActor @Test func onlyACardWhoseOpacityChangedFades() {
        let fixture = Fixture()
        fixture.animate()
        #expect(fixture.card.layer?.animation(forKey: "parc.media.opacity") == nil)
        #expect(fixture.back.layer?.animation(forKey: "parc.media.opacity") != nil)
    }

    @MainActor @Test func reducedMotionAppliesTheFrameWithoutStartingASpring() {
        let fixture = Fixture()
        fixture.animate(reduceMotion: true)
        #expect(fixture.card.frame == CGRect(x: 10, y: 15, width: 75, height: 70))
        #expect(fixture.card.layer?.animation(forKey: "parc.media.position") == nil)
    }

    @MainActor @Test func settlingRemovesDeckAnimationsEvenAfterDetachment() {
        let fixture = Fixture()
        fixture.animate()
        fixture.deck.removeFromSuperview()
        fixture.motion.settle()
        #expect(fixture.card.layer?.animation(forKey: "parc.media.position") == nil)
        #expect(fixture.companion.layer?.animation(forKey: "parc.media.position") == nil)
        #expect(fixture.back.layer?.animation(forKey: "parc.media.opacity") == nil)
    }

    @MainActor @Test func settlingLeavesIndependentlyOwnedAnimationsAlone() {
        let fixture = Fixture()
        fixture.addIndependentAnimation(to: fixture.card)
        fixture.addIndependentAnimation(to: fixture.unrelated)
        fixture.animate()
        fixture.motion.settle()
        #expect(fixture.card.layer?.animation(forKey: "unrelated") != nil)
        #expect(fixture.unrelated.layer?.animation(forKey: "unrelated") != nil)
    }
}
