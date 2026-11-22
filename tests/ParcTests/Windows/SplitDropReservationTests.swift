import AppKit
import ParcCore
import QuartzCore
import Testing
@testable import Parc

@MainActor private final class ReservedHost: NSView { override var isFlipped: Bool { true } }

@MainActor private final class Scene {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1810, height: 700), styleMask: .borderless, backing: .buffered, defer: false)
    let host = ReservedHost(frame: NSRect(x: 0, y: 0, width: 1810, height: 700))
    let split: ParcSplitView
    let first = SplitDropReservedPane(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
    let second = SplitDropReservedPane(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
    let ink = NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.6, alpha: 1)
    let originalFrames: [NSRect]
    var third: SplitDropReservedPane?
    var columnFrames: [NSRect] = []
    var editing: [Bool] = []

    var panes: [SplitDropReservedPane] { [first, second] + (third.map { [$0] } ?? []) }
    var allowAll: (SplitDropTarget, SplitOrientation) -> Bool { { _, _ in true } }
    var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    init() {
        window.isReleasedWhenClosed = false
        window.contentView = host
        split = ParcSplitView(frame: host.bounds)
        host.addSubview(split)
        split.addArrangedSubview(first)
        split.addArrangedSubview(second)
        split.configure(orientation: .horizontal, factors: [0.75, 0.25])
        split.constrain(to: host)
        originalFrames = split.arrangedSubviews.map(\.frame)
        split.onInteractivePaneEditing = { [weak self] in self?.editing.append($0) }
    }

    func addColumn() {
        let pane = SplitDropReservedPane(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        third = pane
        split.addArrangedSubview(pane)
        let column = BrowserSplitStacks(slotSizes: [2, 1], slotFactors: [0.5, 0.5], stackFactors: [[0.5, 0.5], [1]])
        split.configure(orientation: .horizontal, factors: column.flattenedFactors, stacks: column)
        host.layoutSubtreeIfNeeded()
        columnFrames = split.arrangedSubviews.map(\.frame)
    }

    func lease() -> ParcSplitView.DropReservation {
        let lease = immediate(split.prepareDropReservation(in: host, contents: panes.map(\.body))!)
        lease.setInsertionColor { [ink] in ink }
        return lease
    }

    func region() -> NSView? { split.subviews.first { view in !panes.contains { $0 === view } } }

    func leftEdge(_ lease: ParcSplitView.DropReservation) -> SplitDropGeometry.Proposal {
        lease.proposal(at: NSPoint(x: 1, y: 200), canPropose: allowAll)!
    }

    func leave(_ lease: ParcSplitView.DropReservation) -> SplitDropGeometry.Proposal? {
        lease.proposal(at: NSPoint(x: -20, y: -20), canPropose: allowAll)
    }
}

@MainActor struct SplitDropReservationTests {
    @Test func onePresentationLeaseAdmitsOnlyTheExactOriginalSurfaces() {
        let scene = Scene()
        let lease = scene.lease()
        #expect(lease.isCurrent)
        #expect(scene.split.prepareDropReservation(in: scene.host, contents: scene.panes.map(\.body)) == nil)
    }

    @Test func aReservedInsertionKeepsItsIdentityAndTheWholePaneSlotIncludingTheHeader() {
        let scene = Scene()
        let insert = scene.leftEdge(scene.lease())
        #expect(insert.0 == .insert(0))
        #expect(insert.1 == .horizontal)
        #expect(insert.2.minY == 0)
        #expect(insert.2.height == 700)
    }

    @Test func theIncomingPaneIsTheSplitsWidthOverOneMorePane() {
        let scene = Scene()
        let lease = scene.lease()
        _ = scene.leftEdge(lease)
        #expect(lease.incomingPaneSize == NSSize(width: scene.split.bounds.width / 3, height: scene.split.bounds.height))
    }

    @Test func aNewInsertionSlotHasNoExistingDropRegion() {
        let scene = Scene()
        let lease = scene.lease()
        _ = scene.leftEdge(lease)
        #expect(!lease.reusedRegion)
    }

    @Test func thePaneHighlightFollowsFromTheLayersPreviousBoundsOverTwoTenths() {
        let scene = Scene()
        _ = scene.leftEdge(scene.lease())
        if !scene.reduceMotion {
            #expect(scene.first.followed.contains { $0.duration == 0.2 && $0.previous != scene.first.layer?.bounds })
        }
    }

    @Test func presentationNeverInsertsAPageIntoTheOriginalArrangedOwners() {
        let scene = Scene()
        _ = scene.leftEdge(scene.lease())
        #expect(scene.split.arrangedSubviews.count == 2)
        #expect(scene.split.arrangedSubviews[0] === scene.first)
        #expect(scene.split.arrangedSubviews[1] === scene.second)
    }

    @Test func theIncomingRegionGetsAThirdWhileOriginalsKeepTheirThreeToOneRatio() {
        let scene = Scene()
        let insert = scene.leftEdge(scene.lease())
        #expect(abs(insert.2.width - 597) <= 1)
        #expect(abs(scene.first.frame.width - 895) <= 1)
        #expect(abs(scene.second.frame.width - 298) <= 1)
    }

    @Test func reservedLayoutKeepsBothTenPointGaps() {
        let scene = Scene()
        let insert = scene.leftEdge(scene.lease())
        #expect(scene.first.frame.minX == insert.2.maxX + 10)
        #expect(scene.second.frame.minX == scene.first.frame.maxX + 10)
    }

    @Test func theReservedRegionRendersTheBorderOnTheOriginalContentGeometry() throws {
        let scene = Scene()
        let insert = scene.leftEdge(scene.lease())
        let region = try #require(scene.region())
        #expect(region.frame == insert.2)
        #expect(region.layer?.borderWidth == 2)
        #expect(region.layer?.cornerRadius == 6)
        #expect(region.layer?.backgroundColor == nil)
        #expect(region.layer?.opacity == 1)
    }

    @Test func theReservedRegionIsAPassivePresentation() throws {
        let scene = Scene()
        _ = scene.leftEdge(scene.lease())
        let region = try #require(scene.region())
        #expect(!region.isAccessibilityElement())
        #expect(region.accessibilityChildren()?.isEmpty == true)
        #expect(region.hitTest(.zero) == nil)
        #expect(!region.acceptsFirstResponder)
    }

    @Test func theBorderExpandsOverTwoTenthsWithEaseOutWhateverTheMotionSetting() throws {
        let scene = Scene()
        _ = scene.leftEdge(scene.lease())
        let motion = try #require(scene.region()?.layer?.animation(forKey: "Split drop region") as? CAAnimationGroup)
        #expect(motion.duration == 0.2)
        #expect(motion.timingFunction == CAMediaTimingFunction(name: .easeOut))
    }

    @Test func theBorderGrowsFromACollapsedZeroAxisToTheExactReservedSize() throws {
        let scene = Scene()
        _ = scene.leftEdge(scene.lease())
        let region = try #require(scene.region())
        let motion = try #require(region.layer?.animation(forKey: "Split drop region") as? CAAnimationGroup)
        let bounds = motion.animations?.compactMap { $0 as? CABasicAnimation }.first { $0.keyPath == "bounds" }
        #expect((bounds?.fromValue as? NSValue)?.rectValue.width == 0)
        #expect((bounds?.toValue as? NSValue)?.rectValue == region.layer?.bounds)
    }

    @Test func theBorderAlphaGoesFromCollapsedZeroToExpandedOne() throws {
        let scene = Scene()
        _ = scene.leftEdge(scene.lease())
        let motion = try #require(scene.region()?.layer?.animation(forKey: "Split drop region") as? CAAnimationGroup)
        let alpha = motion.animations?.compactMap { $0 as? CABasicAnimation }.first { $0.keyPath == "opacity" }
        #expect((alpha?.fromValue as? NSNumber)?.doubleValue == 0)
        #expect((alpha?.toValue as? NSNumber)?.doubleValue == 1)
    }

    @Test func theRegionResolvesTheOriginalWindowsHalfOpacityInk() throws {
        let scene = Scene()
        _ = scene.leftEdge(scene.lease())
        let region = try #require(scene.region())
        let border = try #require(region.layer?.borderColor)
        let ink = try #require(NSColor(cgColor: border)?.usingColorSpace(.deviceRGB))
        #expect(abs(ink.alphaComponent - 0.5) < 0.001)
    }

    @Test func theOriginalPaneLayerReceivesTheAttributedPositionAndBoundsTransition() throws {
        let scene = Scene()
        _ = scene.leftEdge(scene.lease())
        let movement = try #require(scene.first.layer?.animation(forKey: "Split reserved layout") as? CAAnimationGroup)
        #expect(movement.duration == 0.2)
        #expect(movement.animations?.count == 2)
        #expect(movement.timingFunction == CAMediaTimingFunction(name: .easeOut))
    }

    @Test func theReservationAnimatesTowardAlreadyAuthoritativeGeometry() throws {
        let scene = Scene()
        _ = scene.leftEdge(scene.lease())
        let movement = try #require(scene.first.layer?.animation(forKey: "Split reserved layout") as? CAAnimationGroup)
        let bounds = movement.animations?.first { ($0 as? CABasicAnimation)?.keyPath == "bounds" } as? CABasicAnimation
        #expect((bounds?.toValue as? NSValue)?.rectValue == scene.first.layer?.bounds)
    }

    @Test func controlledGeometryStaysAdmittedAndExposesNoDivider() {
        let scene = Scene()
        let lease = scene.lease()
        _ = scene.leftEdge(lease)
        #expect(lease.isCurrent)
        #expect(!scene.split.isAccessibilityElement())
        #expect((scene.split.accessibilitySplitters() ?? []).isEmpty)
    }

    @Test func thePointerInItsOwnReservedRegionKeepsTheProposalAndRegion() {
        let scene = Scene()
        let lease = scene.lease()
        let insert = scene.leftEdge(lease)
        let held = lease.proposal(at: NSPoint(x: insert.2.midX, y: insert.2.midY), canPropose: scene.allowAll)!
        #expect(held.0 == insert.0)
        #expect(held.2 == insert.2)
        #expect(lease.reusedRegion)
    }

    @Test func retargetingReordersTheSameReservedRegion() throws {
        let scene = Scene()
        let lease = scene.lease()
        _ = scene.leftEdge(lease)
        let region = try #require(scene.region())
        let moved = lease.proposal(at: NSPoint(x: scene.second.frame.maxX - 1, y: 200), canPropose: scene.allowAll)!
        #expect(moved.0 == .insert(2))
        #expect(scene.split.subviews.contains { $0 === region })
        #expect(!lease.reusedRegion)
    }

    @Test func leavingRestoresTheOriginalFramesWithoutAModelTransaction() {
        let scene = Scene()
        let lease = scene.lease()
        _ = scene.leftEdge(lease)
        #expect(scene.leave(lease) == nil)
        #expect(scene.split.arrangedSubviews.map(\.frame) == scene.originalFrames)
    }

    @Test func aCollapsedBorderNeverRemainsAValidDropRegion() {
        let scene = Scene()
        let lease = scene.lease()
        let insert = scene.leftEdge(lease)
        _ = scene.leave(lease)
        #expect(lease.isCurrent)
        #expect(!lease.containsReservedPoint(NSPoint(x: insert.2.midX, y: insert.2.midY)))
    }

    @Test func aNormalExitSynchronouslyPublishesTheCollapsedBorder() throws {
        let scene = Scene()
        let lease = scene.lease()
        _ = scene.leftEdge(lease)
        let region = try #require(scene.region())
        _ = scene.leave(lease)
        #expect(region.layer?.opacity == 0)
        #expect(region.frame.width == 0)
    }

    @Test func onlyThePassiveBorderRemainsDuringItsExitTransition() throws {
        let scene = Scene()
        let lease = scene.lease()
        _ = scene.leftEdge(lease)
        let region = try #require(scene.region())
        _ = scene.leave(lease)
        #expect(region.superview === scene.split)
        #expect(region.layer?.animation(forKey: "Split drop region") != nil)
        #expect(scene.first.layer?.animation(forKey: "Split reserved layout") != nil)
    }

    @Test func reenteringReusesTheRetiringRegionAndSupersedesItsTransition() throws {
        let scene = Scene()
        let lease = scene.lease()
        _ = scene.leftEdge(lease)
        let region = try #require(scene.region())
        _ = lease.proposal(at: NSPoint(x: scene.second.frame.maxX - 1, y: 200), canPropose: scene.allowAll)
        _ = scene.leave(lease)
        _ = scene.leftEdge(lease)
        #expect(scene.split.subviews.contains { $0 === region })
        #expect(region.layer?.opacity == 1)
        #expect(!lease.reusedRegion)
    }

    @Test func returningToTheCollapsingRegionAtTheSameSlotReusesItWithoutFeedback() {
        let scene = Scene()
        let lease = scene.lease()
        _ = scene.leftEdge(lease)
        _ = scene.leave(lease)
        _ = scene.leftEdge(lease)
        _ = scene.leave(lease)
        _ = scene.leftEdge(lease)
        #expect(lease.reusedRegion == !scene.reduceMotion)
    }

    @Test func aReenteredRegionSurvivesItsOldCollapseCompletion() throws {
        let scene = Scene()
        var complete: (@MainActor () -> Void)?
        scene.split.registerDropRegionCompletion = { complete = $0 }
        let lease = scene.lease()
        _ = scene.leftEdge(lease)
        let region = try #require(scene.region())
        _ = scene.leave(lease)
        let finishCollapse = try #require(complete)
        _ = scene.leftEdge(lease)

        finishCollapse()

        #expect(region.superview === scene.split)
        #expect(region.layer?.opacity == 1)
    }

    @Test func clearingSynchronouslyRemovesTheBorderAndItsAnimation() throws {
        let scene = Scene()
        let lease = scene.lease()
        _ = scene.leftEdge(lease)
        let region = try #require(scene.region())
        lease.clear()
        #expect(region.superview == nil)
        #expect(region.layer?.animation(forKey: "Split drop region") == nil)
    }

    @Test func clearingRestoresGeometryAndEndsMotionWhileKeepingValidationAlive() {
        let scene = Scene()
        let lease = scene.lease()
        _ = scene.leftEdge(lease)
        lease.clear()
        #expect(lease.isCurrent)
        #expect(scene.split.arrangedSubviews.map(\.frame) == scene.originalFrames)
        #expect(scene.first.layer?.animation(forKey: "Split reserved layout") == nil)
    }

    @Test func aLeaseAloneIsNotInteractivePaneEditing() {
        let scene = Scene()
        _ = scene.lease()
        #expect(scene.editing.isEmpty)
        #expect(!scene.split.isInteractivePaneEditing)
    }

    @Test func theFirstAdmittedEntryBeginsEditing() {
        let scene = Scene()
        let lease = scene.lease()
        #expect(lease.beginInteractivePaneEdit() != nil)
        #expect(scene.editing == [true])
        #expect(scene.split.isInteractivePaneEditing)
    }

    @Test func leavingThePaneAreaKeepsEditingUntilTheDragEnds() {
        let scene = Scene()
        let lease = scene.lease()
        _ = lease.beginInteractivePaneEdit()
        _ = scene.leave(lease)
        #expect(scene.editing == [true])
        #expect(scene.split.isInteractivePaneEditing)
    }

    @Test func clearingPaneMotionAlsoCancelsThePaneHighlightsPathTransition() {
        let scene = Scene()
        let lease = scene.lease()
        _ = scene.leftEdge(lease)
        lease.clear()
        #expect(scene.panes.contains { $0.cancelled > 0 })
    }

    @Test func endingALeaseIsOneShotAndRetainsTheOriginalOwners() {
        let scene = Scene()
        let lease = scene.lease()
        lease.end()
        lease.end()
        #expect(lease.ended)
        #expect(!lease.isCurrent)
        #expect(scene.split.subviews.count == 2)
    }

    @Test func theDragsEditOutlivesItsLeaseAndEndsOnlyOnItsOwnTerminalEnd() {
        let scene = Scene()
        let lease = scene.lease()
        let edit = lease.beginInteractivePaneEdit()
        lease.end()
        #expect(scene.editing == [true])
        #expect(scene.split.isInteractivePaneEditing)
        #expect(lease.beginInteractivePaneEdit() == nil)
        edit?.end()
        edit?.end()
        #expect(scene.editing == [true, false])
        #expect(!scene.split.isInteractivePaneEditing)
    }

    @Test func aRefusedInsertionKeepsTheGenuineReplacementWithoutReservingLayout() {
        let scene = Scene()
        let lease = scene.lease()
        let replace = lease.proposal(at: NSPoint(x: 1, y: 200), canPropose: { target, _ in
            if case .replace = target { return true }
            return false
        })!
        #expect(replace.0 == .replace(0))
        #expect(scene.split.arrangedSubviews.map(\.frame) == scene.originalFrames)
        #expect(!lease.reusedRegion)
    }

    @Test func aPointerOverAPaneHeaderTargetsThatPanesEdge() {
        let scene = Scene()
        let lease = scene.lease()
        let header = lease.proposal(at: NSPoint(x: 1, y: 20), canPropose: scene.allowAll)
        #expect(header?.0 == .insert(0))
        #expect(header?.2.minY == 0)
        #expect(header?.2.height == 700)
        lease.end()
        #expect(scene.split.arrangedSubviews.map(\.frame) == scene.originalFrames)
    }

    @MainActor private struct Stack {
        let scene: Scene
        let lease: ParcSplitView.DropReservation
        let point: NSPoint
        let proposal: SplitDropGeometry.Proposal
        let frames: [NSRect]
        let region: NSView

        init() {
            let scene = Scene()
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

    @Test func returningToTheCollapsingStackRegionReusesItWithoutFeedback() {
        let stack = Stack()
        _ = stack.scene.leave(stack.lease)
        _ = stack.lease.proposal(at: stack.point, canPropose: stack.scene.allowAll)
        #expect(stack.lease.reusedRegion == !stack.scene.reduceMotion)
    }

    @Test func endingAStackReservationRestoresTheFlatSplit() {
        let stack = Stack()
        stack.lease.end()
        #expect(stack.scene.split.arrangedSubviews.map(\.frame) == stack.scene.originalFrames)
        #expect(stack.scene.split.subviews.count == 2)
        #expect(stack.scene.split.isVertical)
    }

    @Test func aStackedPanesBottomBandReservesRoomInsideItsOwnStack() {
        let scene = Scene()
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
        lease.end()
        #expect(scene.split.arrangedSubviews.map(\.frame) == scene.columnFrames)
        #expect(scene.split.subviews.count == 3)
    }

    @Test func aStaleLeaseRetiresWhenTheOwnerConfiguresAnAuthoritativeLayoutButKeepsTheDragsEdit() {
        let scene = Scene()
        let lease = scene.lease()
        _ = lease.beginInteractivePaneEdit()
        _ = scene.leftEdge(lease)
        scene.split.configure(orientation: .vertical, factors: [0.5, 0.5])
        #expect(scene.editing == [true])
        #expect(scene.split.isInteractivePaneEditing)
        #expect(lease.ended)
        #expect(!lease.isCurrent)
        #expect(scene.split.subviews.count == 2)
        #expect(!scene.split.isVertical)
        lease.end()
        #expect(!scene.split.isVertical)
        #expect(scene.first.layer?.animation(forKey: "Split reserved layout") == nil)
    }

    @Test func aNewDragsEditReplacesAnUnterminatedOneWithoutAGap() {
        let scene = Scene()
        let stale = scene.lease()
        let staleEdit = stale.beginInteractivePaneEdit()
        scene.split.configure(orientation: .vertical, factors: [0.5, 0.5])
        let next = scene.lease()
        let nextEdit = next.beginInteractivePaneEdit()
        #expect(staleEdit?.ended == true)
        #expect(nextEdit?.ended == false)
        #expect(scene.editing == [true])
        staleEdit?.end()
        #expect(scene.editing == [true])
        #expect(scene.split.isInteractivePaneEditing)
        nextEdit?.end()
        #expect(scene.editing == [true, false])
    }

    @Test func anIncomingPaneAtATopAndBottomSplitsTopEdgeIsTheSplitWideAndAThirdHigh() {
        let scene = Scene()
        scene.split.configure(orientation: .vertical, factors: [0.5, 0.5])
        let lease = scene.lease()
        let topEdge = lease.proposal(at: NSPoint(x: 200, y: 41), canPropose: scene.allowAll)
        #expect(topEdge?.0 == .insert(0))
        #expect(topEdge?.1 == .vertical)
        #expect(lease.incomingPaneSize == NSSize(width: scene.split.bounds.width, height: scene.split.bounds.height / 3))
    }

    @Test func anOutsideHostResizeIsNeverAcceptedAsOwnedPreviewGeometry() {
        let scene = Scene()
        let lease = scene.lease()
        scene.host.frame.size.width += 30
        #expect(!lease.isCurrent)
    }

    @Test func anAdmissionCallbackThatRetiresTheLeaseCannotAttachAnOrphanRegion() {
        let scene = Scene()
        scene.split.configure(orientation: .vertical, factors: [0.5, 0.5])
        let lease = scene.lease()
        let proposal = lease.proposal(at: NSPoint(x: 200, y: 41), canPropose: { _, _ in
            scene.split.configure(orientation: .horizontal, factors: [0.75, 0.25])
            return true
        })
        #expect(proposal == nil)
        #expect(lease.ended)
        #expect(scene.split.subviews.count == 2)
    }

    @Test func cancellingRetiresTheLeaseSynchronouslyBeforePassivePresentationFinishes() {
        let scene = Scene()
        let lease = scene.lease()
        let before = scene.split.arrangedSubviews.map(\.frame)
        _ = scene.leftEdge(lease)
        lease.end(animated: true)
        #expect(lease.ended)
        #expect(!lease.isCurrent)
        #expect(scene.split.arrangedSubviews.map(\.frame) == before)
    }

    @Test func thePassiveCollapseCompletionRemovesItsOwnRegion() throws {
        let scene = Scene()
        var complete: (@MainActor () -> Void)?
        scene.split.registerDropRegionCompletion = { complete = $0 }
        let lease = scene.lease()
        _ = scene.leftEdge(lease)
        let region = try #require(scene.region())
        lease.end(animated: true)
        try #require(region.superview === scene.split)
        let finishCollapse = try #require(complete)

        finishCollapse()

        #expect(region.superview == nil)
        #expect(scene.split.subviews == scene.panes)
    }

    @Test func theOriginalWindowResigningKeyClearsTheTerminalBorderAndTransition() {
        let scene = Scene()
        let lease = scene.lease()
        _ = scene.leftEdge(lease)
        lease.end(animated: true)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: scene.window)
        #expect(scene.first.layer?.animation(forKey: "Split reserved layout") == nil)
        #expect(scene.split.subviews.count == 2)
    }

    @Test func hidingTheSplitRevokesTheGestureAndBorderPresentationAtOnce() {
        let scene = Scene()
        let lease = scene.lease()
        _ = scene.leftEdge(lease)
        scene.split.isHidden = true
        #expect(lease.ended)
        #expect(scene.split.subviews.count == 2)
        #expect(scene.first.layer?.animation(forKey: "Split reserved layout") == nil)
    }

    @MainActor private final class IntentRig {
        let scene = Scene()
        let lease: ParcSplitView.DropReservation
        var now: TimeInterval = 100
        var due = 0
        let seat: NSPoint

        init() {
            scene.addColumn()
            lease = scene.split.prepareDropReservation(in: scene.host, contents: scene.panes.map(\.body))!
            lease.setInsertionColor { [ink = scene.ink] in ink }
            seat = NSPoint(x: scene.columnFrames[2].midX, y: scene.columnFrames[2].maxY - 10)
            lease.clock = { [weak self] in self?.now ?? 0 }
            lease.onIntentDue = { [weak self] in self?.due += 1 }
        }

        func sweep(from start: NSPoint, to end: NSPoint, steps: Int = 40, each: (SplitDropGeometry.Proposal?) -> Void = { _ in }) {
            for step in 1...steps {
                let progress = CGFloat(step) / CGFloat(steps)
                now += 0.008
                each(lease.proposal(at: NSPoint(x: start.x + (end.x - start.x) * progress, y: start.y + (end.y - start.y) * progress),
                                    canPropose: scene.allowAll))
            }
        }

        func settleOnSeat() -> SplitDropGeometry.Proposal? {
            sweep(from: NSPoint(x: 1, y: 200), to: seat)
            now += 0.05
            return lease.proposal(at: seat, canPropose: scene.allowAll)
        }
    }

    @Test func aFastSweepToTheLoneColumnsBottomBandOpensNothingAndMovesNoPane() {
        let rig = IntentRig()
        var opened = false
        rig.sweep(from: NSPoint(x: 1, y: 200), to: rig.seat) { _ in
            opened = opened || rig.lease.shownTarget != nil || rig.lease.appeared
                || rig.scene.split.arrangedSubviews.map(\.frame) != rig.scene.columnFrames
        }
        #expect(!opened)
        #expect(rig.scene.split.subviews.count == 3)
    }

    @Test func theSeatUnderThePointerWaitsDueOneSampleWindowAfterTheLastMovement() {
        let rig = IntentRig()
        rig.sweep(from: NSPoint(x: 1, y: 200), to: rig.seat)
        #expect(rig.lease.hoverIntent.isPending)
        #expect(rig.lease.hoverIntent.deadline == rig.now + 0.05)
    }

    @Test func externalDropIntentRechecksTheStationaryPointerAtItsDeadline() throws {
        let scene = Scene()
        let lease = try #require(scene.split.prepareDropReservation(in: scene.host, contents: scene.panes.map(\.body)))
        let edge = scene.host.convert(NSPoint(x: 1, y: 200), to: nil)
        let drag = SplitDropDragInfo(window: scene.window, location: edge)
        drag.writeURL("https://intent.invalid")
        var now: TimeInterval = 100
        var timers: [Timer] = []
        lease.clock = { now }
        lease.intentFireDate = { Date(timeIntervalSinceReferenceDate: now + $0) }
        lease.scheduleIntentTimer = { timers.append($0) }
        let session = try #require(ExternalSplitDropSession(host: scene.host, info: drag, frames: scene.originalFrames,
            orientation: .horizontal, reservation: lease, validate: { lease.isCurrent }, insertionColor: { .black },
            canPropose: scene.allowAll, commit: { _, _ in false }))
        session.targets.performFeedback = {}
        var targets: [SplitDropTarget?] = []
        session.targets.onChange = { targets.append($0) }

        #expect(session.update(drag) == .copy)
        #expect(targets.isEmpty)
        let deadline = now + 0.05
        let timer = try #require(timers.first)
        #expect(timer.fireDate == Date(timeIntervalSinceReferenceDate: deadline))
        now = deadline
        timer.fire()

        #expect(targets == [.insert(0)])
        #expect(timers.count == 1)
        #expect(!timer.isValid)
    }

    @Test func aReleaseBeforeTheSeatAppearsDropsIntoTheSeatAndMovesNothingFirst() {
        let rig = IntentRig()
        rig.sweep(from: NSPoint(x: 1, y: 200), to: rig.seat)
        let early = rig.lease.proposal(at: rig.seat, canPropose: rig.scene.allowAll, presenting: false)
        #expect(early?.0 == .stack(2, after: true))
        #expect(early?.1 == .horizontal)
        #expect(rig.scene.split.arrangedSubviews.map(\.frame) == rig.scene.columnFrames)
    }

    @Test func onceThePointerSettlesTheSeatOpensAndAsksForItsHaptic() {
        let rig = IntentRig()
        let settled = rig.settleOnSeat()
        #expect(settled?.0 == .stack(2, after: true))
        #expect(rig.lease.shownTarget == .stack(2, after: true))
        #expect(rig.lease.appeared)
        #expect(rig.scene.split.arrangedSubviews.map(\.frame) != rig.scene.columnFrames)
    }

    @Test func sweepingOnTowardTheLeftEdgeKeepsTheOpenSeatWithNoCollapse() throws {
        let rig = IntentRig()
        _ = rig.settleOnSeat()
        let seatFrames = rig.scene.split.arrangedSubviews.map(\.frame)
        let region = try #require(rig.scene.region())
        var collapsed = false
        rig.sweep(from: rig.seat, to: NSPoint(x: 1, y: 200)) { proposal in
            collapsed = collapsed || rig.lease.shownTarget != .stack(2, after: true) || rig.lease.appeared
                || rig.scene.split.arrangedSubviews.map(\.frame) != seatFrames || region.superview !== rig.scene.split
                || region.layer?.opacity != 1 || proposal == nil
        }
        #expect(!collapsed)
    }

    @Test func settlingOnTheLeftEdgeMovesTheSameRegionStraightFromTheSeat() throws {
        let rig = IntentRig()
        let seatRect = try #require(rig.settleOnSeat()).2
        let region = try #require(rig.scene.region())
        rig.sweep(from: rig.seat, to: NSPoint(x: 1, y: 200))
        rig.now += 0.05
        let edge = rig.lease.proposal(at: NSPoint(x: 1, y: 200), canPropose: rig.scene.allowAll)
        let move = region.layer?.animation(forKey: "Split drop region") as? CAAnimationGroup
        let bounds = move?.animations?.compactMap { $0 as? CABasicAnimation }.first { $0.keyPath == "bounds" }
        #expect(edge?.0 == .insert(0))
        #expect(rig.lease.shownTarget == .insert(0))
        #expect(rig.lease.appeared)
        #expect(region.superview === rig.scene.split)
        #expect(region.layer?.opacity == 1)
        #expect((bounds?.fromValue as? NSValue)?.rectValue.size == seatRect.size)
    }

    @Test func leavingTheSplitClearsThePreviewAtOnce() {
        let rig = IntentRig()
        _ = rig.settleOnSeat()
        #expect(rig.lease.proposal(at: NSPoint(x: -20, y: -20), canPropose: rig.scene.allowAll) == nil)
        #expect(rig.lease.shownTarget == nil)
        #expect(rig.scene.split.arrangedSubviews.map(\.frame) == rig.scene.columnFrames)
    }

    @Test func endingTheIntentLeaseRestoresTheStackedFramesAndForgetsTheIntent() {
        let rig = IntentRig()
        _ = rig.settleOnSeat()
        rig.lease.end()
        #expect(rig.scene.split.arrangedSubviews.map(\.frame) == rig.scene.columnFrames)
        #expect(rig.scene.split.subviews.count == 3)
        #expect(!rig.lease.hoverIntent.isPending)
    }
}
