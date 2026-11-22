import AppKit
import ParcCore
import QuartzCore
import Testing
@testable import Parc

@MainActor
struct SplitDropReservationStacksTests {
    @MainActor private struct Stack {
        let scene: SplitDropReservationSupport.Scene
        let lease: ParcSplitView.DropReservation
        let point: NSPoint
        let proposal: SplitDropGeometry.Proposal
        let frames: [NSRect]
        let region: NSView

        init() {
            let scene = SplitDropReservationSupport.Scene()
            self.scene = scene
            lease = scene.lease()
            point = NSPoint(x: scene.originalFrames[0].midX, y: scene.originalFrames[0].maxY - 10)
            proposal = lease.proposal(at: point, canPropose: scene.allowAll)!
            let shape = BrowserSplitStacks(slotSizes: [2, 1], slotFactors: BrowserSplitLayout.normalized([0.75, 0.25], count: 2)!,
                                           stackFactors: [[0.5, 0.5], [1]])
            frames = SplitStackGeometry.paneFrames(size: scene.split.bounds.size, orientation: .horizontal, stacks: shape,
                thickness: scene.split.dividerThickness, minimum: 220, scale: scene.window.backingScaleFactor)
            region = scene.region()!
        }
    }

    @Test func aPanesBottomBandReservesARegionInsideItsColumnAndStaysAdmitted() {
        let stack = Stack()
        #expect(stack.proposal.0 == .stack(0, after: true))
        #expect(stack.proposal.1 == .horizontal)
        #expect(!stack.lease.reusedRegion)
        #expect(stack.lease.isCurrent)
    }

    @Test func aFlatSplitPreviewsTheStackedShapeTheCommitWouldProduce() {
        let stack = Stack()
        #expect(stack.scene.first.frame == stack.frames[0])
        #expect(stack.region.frame == stack.frames[1])
        #expect(stack.proposal.2 == stack.frames[1])
        #expect(stack.scene.second.frame == stack.frames[2])
    }

    @Test func onlyTheStackedColumnDivides() {
        let stack = Stack()
        let original = stack.scene.originalFrames[0]
        #expect(stack.region.frame.minX == original.minX)
        #expect(stack.region.frame.maxX == original.maxX)
        #expect(stack.scene.second.frame.height == stack.scene.split.bounds.height)
    }

    @Test func aStackedIncomingPaneIsItsColumnWideAndHalfTheSplitHigh() {
        let stack = Stack()
        #expect(stack.lease.incomingPaneSize == NSSize(width: stack.scene.originalFrames[0].width, height: stack.scene.split.bounds.height / 2))
    }

    @Test func aStackReservationHidesEveryDivider() {
        #expect((Stack().scene.split.accessibilitySplitters() ?? []).isEmpty)
    }

    @Test func theStackRegionGrowsFromAZeroHeightLineAcrossOnlyItsColumn() throws {
        let stack = Stack()
        let motion = try #require(stack.region.layer?.animation(forKey: "Split drop region") as? CAAnimationGroup)
        let start = motion.animations?.compactMap { $0 as? CABasicAnimation }.first { $0.keyPath == "bounds" }
        #expect(motion.duration == 0.2)
        #expect((start?.fromValue as? NSValue)?.rectValue.size == NSSize(width: stack.scene.originalFrames[0].width, height: 0))
        #expect(stack.scene.first.layer?.animation(forKey: "Split reserved layout") != nil)
    }

    @Test func thePointerInItsOwnStackedRegionKeepsTheProposal() {
        let stack = Stack()
        let held = stack.lease.proposal(at: NSPoint(x: stack.proposal.2.midX, y: stack.proposal.2.midY), canPropose: stack.scene.allowAll)!
        #expect(held.0 == stack.proposal.0)
        #expect(held.2 == stack.proposal.2)
        #expect(stack.lease.reusedRegion)
    }

    @Test func reclassifyingToTheSameStackTargetReusesTheRegionWithoutRelayout() {
        let stack = Stack()
        let repeated = stack.lease.proposal(at: NSPoint(x: stack.frames[0].midX, y: stack.frames[0].maxY - 5), canPropose: stack.scene.allowAll)!
        #expect(repeated.0 == stack.proposal.0)
        #expect(stack.lease.reusedRegion)
        #expect(stack.scene.first.frame == stack.frames[0])
    }

    @Test func aMainRowSlotAtTheSameReadingIndexIsADifferentReservation() {
        let stack = Stack()
        let mainRow = stack.lease.proposal(at: NSPoint(x: stack.frames[0].maxX - 5, y: 100), canPropose: stack.scene.allowAll)!
        #expect(mainRow.0 == .insert(1))
        #expect(!stack.lease.reusedRegion)
        #expect(stack.scene.first.frame.height == stack.scene.split.bounds.height)
        #expect(stack.region.frame.height == stack.scene.split.bounds.height)
        #expect(stack.lease.incomingPaneSize == NSSize(width: stack.scene.split.bounds.width / 3, height: stack.scene.split.bounds.height))
    }

    @Test func movingFromAMainRowSlotBackToTheStackIsANewRegion() {
        let stack = Stack()
        _ = stack.lease.proposal(at: NSPoint(x: stack.frames[0].maxX - 5, y: 100), canPropose: stack.scene.allowAll)
        let back = stack.lease.proposal(at: NSPoint(x: stack.scene.first.frame.midX, y: stack.scene.first.frame.maxY - 10), canPropose: stack.scene.allowAll)!
        #expect(back.0 == stack.proposal.0)
        #expect(!stack.lease.reusedRegion)
        #expect(stack.scene.first.frame == stack.frames[0])
    }

    @Test func leavingAStackRestoresTheFlatFramesAndCollapsesTheRegionAcrossItsColumn() {
        let stack = Stack()
        let original = stack.scene.originalFrames[0]
        #expect(stack.scene.leave(stack.lease) == nil)
        #expect(stack.scene.split.arrangedSubviews.map(\.frame) == stack.scene.originalFrames)
        #expect(stack.region.frame == NSRect(x: original.minX, y: original.maxY, width: original.width, height: 0))
        #expect(stack.region.layer?.opacity == 0)
        #expect(stack.lease.incomingPaneSize == NSSize(width: stack.scene.split.bounds.width / 3, height: stack.scene.split.bounds.height))
    }

    @Test(arguments: [false, true])
    func returningToTheSameStackOnlyAsksForFeedbackAfterCollapseCompletes(collapseCompleted: Bool) throws {
        let stack = Stack()
        var complete: (@MainActor () -> Void)?
        stack.scene.split.registerDropRegionCompletion = { complete = $0 }
        _ = stack.scene.leave(stack.lease)
        let finishCollapse = try #require(complete)
        if collapseCompleted { finishCollapse() }
        _ = stack.lease.proposal(at: stack.point, canPropose: stack.scene.allowAll)
        #expect(stack.lease.reusedRegion == !collapseCompleted)
        #expect(stack.lease.appeared == collapseCompleted)
    }

    @Test func endingAStackReservationRestoresTheFlatSplit() {
        let stack = Stack()
        stack.lease.end()
        #expect(stack.scene.split.arrangedSubviews.map(\.frame) == stack.scene.originalFrames)
        #expect(stack.scene.split.subviews.count == 2)
        #expect(stack.scene.split.isVertical)
    }

    @Test func aStackedPanesBottomBandReservesRoomInsideItsOwnStack() {
        let scene = SplitDropReservationSupport.Scene()
        scene.addColumn()
        let lease = scene.lease()
        let grow = lease.proposal(at: NSPoint(x: scene.columnFrames[1].midX, y: scene.columnFrames[1].maxY - 10), canPropose: scene.allowAll)!
        let grown = SplitStackGeometry.paneFrames(size: scene.split.bounds.size, orientation: .horizontal,
            stacks: BrowserSplitStacks(slotSizes: [3, 1], slotFactors: [0.5, 0.5], stackFactors: [[1.0 / 3, 1.0 / 3, 1.0 / 3], [1]]),
            thickness: scene.split.dividerThickness, minimum: 220, scale: scene.window.backingScaleFactor)
        #expect(grow.0 == .stack(1, after: true))
        #expect(grow.1 == .horizontal)
        #expect(!lease.reusedRegion)
        #expect(lease.isCurrent)
        #expect([scene.first.frame, scene.second.frame, grow.2, scene.third!.frame] == grown)
        #expect(lease.incomingPaneSize == NSSize(width: scene.columnFrames[1].width, height: scene.split.bounds.height / 3))
        #expect((scene.split.accessibilitySplitters() ?? []).isEmpty)
    }

    @Test func endingAReservationWithinAStackRestoresItsFrames() {
        let scene = SplitDropReservationSupport.Scene()
        scene.addColumn()
        let lease = scene.lease()
        _ = lease.proposal(at: NSPoint(x: scene.columnFrames[1].midX, y: scene.columnFrames[1].maxY - 10), canPropose: scene.allowAll)!
        lease.end()
        #expect(scene.split.arrangedSubviews.map(\.frame) == scene.columnFrames)
        #expect(scene.split.subviews.count == 3)
    }
}
