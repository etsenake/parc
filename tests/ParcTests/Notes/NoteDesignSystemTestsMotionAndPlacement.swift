import AppKit
import Testing
@testable import ParcCore
@testable import ParcNotes

@MainActor
struct NoteDesignSystemTestsMotionAndPlacement {
    private init() { NoteEditorFixtures.registerFonts() }

    @Test func stiffnessFollowsResponse() {
        let omega = 2 * Double.pi / 0.15
        #expect(abs(NoteSpring.highlight.stiffness - omega * omega) < 0.001)
    }

    @Test func dampingFollowsRatio() {
        let omega = 2 * Double.pi / 0.15
        #expect(abs(NoteSpring.highlight.dampingCoefficient - 2 * 0.825 * omega) < 0.001)
    }

    @Test func aSpringStartsAtZero() {
        #expect(NoteSpring.highlight.progress(at: 0) == 0)
    }

    @Test func aSpringSettlesAtOne() {
        #expect(abs(NoteSpring.highlight.progress(at: 2) - 1) < 0.001)
    }

    @Test func theBouncyToggleOvershoots() {
        #expect(NoteSpring.toggle.progress(at: 0.12) > 1)
    }

    @Test func aSpringsDurationSettles() {
        let animation = NoteAnimation.spring("opacity", .press, from: 0, to: 1)
        #expect(animation.duration == animation.settlingDuration)
        #expect(animation.duration > 0)
    }

    @Test func theModelValueLandsImmediately() {
        let layer = CALayer()
        NoteAnimation.spring(layer, "opacity", to: Float(0.5), spring: .highlight)
        #expect(abs(layer.opacity - 0.5) < 0.0001)
    }

    @Test func aNewerGenerationRetiresTheOlderToken() {
        let layer = CALayer()
        let first = NoteAnimation.advanceGeneration(of: layer, key: "k")
        let second = NoteAnimation.advanceGeneration(of: layer, key: "k")
        #expect(!first.isCurrent)
        #expect(second.isCurrent)
    }

    @Test func centredLayersLiftAboutTheirMiddle() {
        let centred = CALayer()
        centred.bounds = CGRect(x: 0, y: 0, width: 100, height: 40)
        NoteAnimation.lift(centred, lifted: true)
        #expect(centred.transform.m11 == NoteAnimation.liftScale)
        #expect(centred.transform.m41 == 0)
    }

    private func corneredLayer() -> CALayer {
        let cornered = CALayer()
        cornered.anchorPoint = .zero
        cornered.bounds = CGRect(x: 0, y: 0, width: 100, height: 40)
        return cornered
    }

    @Test func viewLayersLiftAboutTheirMiddleToo() {
        let cornered = corneredLayer()
        NoteAnimation.lift(cornered, lifted: true)
        #expect(abs(cornered.transform.m41 + 50 * (NoteAnimation.liftScale - 1)) < 0.0001)
    }

    @Test func droppingSettlesBackToRest() {
        let cornered = corneredLayer()
        NoteAnimation.lift(cornered, lifted: true)
        NoteAnimation.lift(cornered, lifted: false)
        #expect(CATransform3DIsIdentity(cornered.transform))
    }

    private let visible = NSRect(x: 0, y: 0, width: 600, height: 400)

    private func place(_ anchor: NSRect, _ size: NSSize, _ preferred: NoteFloatingPanel.Edge = .below, in area: NSRect? = nil) -> (frame: NSRect, edge: NoteFloatingPanel.Edge) {
        NoteFloatingPanel.placement(anchor: anchor, size: size, preferred: preferred, visible: area ?? visible)
    }

    @Test func aPanelFitsBelowTheAnchorWithAGap() {
        let below = place(NSRect(x: 100, y: 50, width: 10, height: 20), NSSize(width: 200, height: 150))
        #expect(below.edge == .below)
        #expect(below.frame.minY == 76)
        #expect(below.frame.minX == 100)
    }

    @Test func aPanelFlipsAboveWhenTheBottomIsCrowded() {
        let flipped = place(NSRect(x: 100, y: 330, width: 10, height: 20), NSSize(width: 200, height: 150))
        #expect(flipped.edge == .above)
        #expect(flipped.frame.maxY == 324)
    }

    @Test func aPanelClampsInsideTheVisibleRect() {
        #expect(place(NSRect(x: 560, y: 50, width: 10, height: 20), NSSize(width: 200, height: 100)).frame.maxX == 592)
    }

    @Test func tallContentShrinksToTheRoom() {
        let squeezed = place(NSRect(x: 10, y: 180, width: 10, height: 20), NSSize(width: 200, height: 900))
        #expect(squeezed.frame.maxY <= 392)
        #expect(squeezed.frame.height >= NoteFloatingPanel.minimumVisibleHeight)
    }

    @Test func submenusFlipToTheLeadingSide() {
        let side = place(NSRect(x: 500, y: 100, width: 80, height: 34), NSSize(width: 200, height: 100), .trailing)
        #expect(side.edge == .leading)
        #expect(side.frame.maxX == 494)
    }

    @Test func placementFollowsAScrolledDocumentsVisibleRect() {
        let scrolled = place(NSRect(x: 100, y: 1050, width: 10, height: 20), NSSize(width: 200, height: 150),
                             in: NSRect(x: 0, y: 1000, width: 600, height: 400))
        #expect(scrolled.edge == .below)
        #expect(scrolled.frame.minY == 1076)
    }
}
