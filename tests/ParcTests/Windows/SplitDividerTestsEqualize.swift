import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SplitDividerTestsEqualize {
    private typealias SplitScaleWindow = SplitDividerTestsSupport.SplitScaleWindow

    @MainActor private final class Rig {
        let directory: URL
        let store: BrowserStore
        let ids: [UUID]
        let original: BrowserSplitLayout
        let originalState: BrowserState
        let window = SplitScaleWindow.make()
        let view: ParcSplitView
        var calls = 0

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-dividers-" + UUID().uuidString)
            let opened = try BrowserStore(directory: directory)
            store = opened
            ids = (0..<4).map { opened.open("https://\($0).invalid") }
            store.setSplit(ids)
            _ = store.setSplitLayout(orientation: .horizontal, widthFactors: [1, 2, 3, 4])
            original = store.activeSplitLayout!
            originalState = store.state
            view = ParcSplitView(frame: NSRect(x: 0, y: 0, width: 1200, height: 1200))
            window.contentView!.addSubview(view)
            for _ in ids { view.addArrangedSubview(NSView()) }
            view.configure(orientation: .horizontal, factors: original.widthFactors)
            storeOwner()
        }

        deinit {
            let directory = directory
            MainActor.assumeIsolated { window.close() }
            try? FileManager.default.removeItem(at: directory)
        }

        func storeOwner() {
            view.prepareDividerResize = { [weak self] in
                guard let self else { return nil }
                let captured = store.activeSplitLayout!
                return { [weak self] factors in
                    guard let self else { return false }
                    calls += 1
                    return store.resizeSplit(expected: captured, widthFactors: factors)
                }
            }
        }

        func doubleClick(_ divider: Int) {
            let pane = view.arrangedSubviews[divider]
            let local = view.isVertical ? NSPoint(x: pane.frame.maxX + 3, y: 200) : NSPoint(x: 200, y: pane.frame.maxY + 3)
            let event = NSEvent.mouseEvent(with: .leftMouseDown, location: view.convert(local, to: nil), modifierFlags: [], timestamp: 0,
                                           windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 2, pressure: 1)!
            view.mouseDown(with: event)
        }

        func grips() -> [CALayer] { (view.layer?.sublayers ?? []).filter { $0.name == "Split divider grip" } }

        func layoutAnimations() -> [CAAnimationGroup] {
            (view.arrangedSubviews.compactMap(\.layer) + grips()).compactMap { $0.animation(forKey: "Split divider equalization") as? CAAnimationGroup }
        }

        func goVertical() {
            _ = store.setSplitLayout(orientation: .vertical, widthFactors: [1, 2, 3, 4])
            view.configure(orientation: .vertical, factors: store.activeSplitLayout!.widthFactors)
        }
    }

    @Test func anAcceptedDoubleClickUsesTheRecoveredDurationAndEaseOutCurve() throws {
        let rig = try Rig()
        rig.doubleClick(1)
        let animation = rig.layoutAnimations().first
        #expect(animation?.duration == 0.2)
        #expect(animation?.timingFunction == CAMediaTimingFunction(name: .easeOut))
    }

    @Test func theMotionTransformsOnlyLiveGeometry() throws {
        let rig = try Rig()
        rig.doubleClick(1)
        #expect(rig.layoutAnimations().first?.animations?.compactMap { ($0 as? CABasicAnimation)?.keyPath } == ["position", "bounds"])
    }

    @Test func keyLossRetiresOwnedMotionWithoutReversingAcceptedDurableState() throws {
        let rig = try Rig()
        rig.doubleClick(1)
        let durable = rig.store.activeSplitLayout
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: rig.window)
        #expect(rig.layoutAnimations().isEmpty)
        #expect(rig.store.activeSplitLayout == durable)
    }

    @Test func aNativeDoubleClickEqualizesOnlyTheAdjacentPair() throws {
        let rig = try Rig()
        rig.doubleClick(1)
        #expect(rig.calls == 1)
        #expect(SplitDividerTestsSupport.near(rig.store.activeSplitLayout!.widthFactors, [0.1, 0.25, 0.25, 0.4]))
    }

    @Test func nativeEqualizationDiffersByAtMostOneRoundedPoint() throws {
        let rig = try Rig()
        rig.doubleClick(1)
        #expect(abs(rig.view.arrangedSubviews[1].frame.width - rig.view.arrangedSubviews[2].frame.width) <= 1)
    }

    @Test func aGeometryOperationLeavesPageRecordsAndSelectionUntouched() throws {
        let rig = try Rig()
        rig.doubleClick(1)
        #expect(rig.store.state.selectedTabIDs == rig.ids)
        #expect(rig.store.state.tabs == rig.originalState.tabs)
    }

    @Test func theOriginalGroupAndAnchorIdentityAreRetained() throws {
        let rig = try Rig()
        rig.doubleClick(1)
        let changed = rig.store.activeSplitLayout!
        #expect(changed.id == rig.original.id)
        #expect(changed.sidebarAnchorID == rig.original.sidebarAnchorID)
        #expect(changed.tabIDs == rig.ids)
    }

    @Test func theExactLayoutIsDurableBeforePublication() throws {
        let rig = try Rig()
        rig.doubleClick(1)
        let loaded = try BrowserStore(directory: rig.directory)
        #expect(loaded.activeSplitLayout == rig.store.activeSplitLayout)
    }

    @Test func aStaleOriginalRatioReceiptCannotRetarget() throws {
        let rig = try Rig()
        rig.doubleClick(1)
        #expect(!rig.store.resizeSplit(expected: rig.original, widthFactors: [1, 1, 1, 1]))
    }

    @Test func anUnavailableNativeOwnerLeavesTheDividerUnchanged() throws {
        let rig = try Rig()
        let frames = rig.view.arrangedSubviews.map(\.frame)
        let layout = rig.store.activeSplitLayout
        rig.view.prepareDividerResize = { nil }
        rig.doubleClick(2)
        #expect(rig.view.arrangedSubviews.map(\.frame) == frames)
        #expect(rig.store.activeSplitLayout == layout)
    }

    @Test func aRefusedCompletionRestoresTheOriginalGeometryAndNeverStartsMotion() throws {
        let rig = try Rig()
        let frames = rig.view.arrangedSubviews.map(\.frame)
        rig.view.prepareDividerResize = { { _ in false } }
        rig.doubleClick(2)
        #expect(rig.view.arrangedSubviews.map(\.frame) == frames)
        #expect(rig.layoutAnimations().isEmpty)
    }

    @Test func aSynchronousOrientationChangeCannotAnimateOrOverwriteTheNewLayout() throws {
        let rig = try Rig()
        rig.view.prepareDividerResize = { [weak rig] in { _ in
            rig?.view.configure(orientation: .vertical, factors: [1, 1, 1, 1]); return true
        } }
        rig.doubleClick(2)
        #expect(!rig.view.isVertical)
        #expect(rig.layoutAnimations().isEmpty)
    }

    @Test func aVerticalLayoutKeepsAHorizontalGripOnEachActualDivider() throws {
        let rig = try Rig()
        rig.goVertical()
        #expect(rig.grips().allSatisfy { $0.frame.size == NSSize(width: 24, height: 2) })
    }

    @Test func theVerticalGripUsesCurrentDividerAndViewportCoordinates() throws {
        let rig = try Rig()
        rig.goVertical()
        #expect(rig.grips()[0].frame.midY == rig.view.arrangedSubviews[0].frame.maxY + rig.view.dividerThickness / 2)
        #expect(rig.grips()[0].frame.midX == rig.view.bounds.midX)
    }

    @Test func aVerticalPairOperationPreservesTheOtherPanesShares() throws {
        let rig = try Rig()
        rig.goVertical()
        rig.doubleClick(0)
        #expect(SplitDividerTestsSupport.near(rig.store.activeSplitLayout!.widthFactors, [0.15, 0.15, 0.3, 0.4]))
    }

    @Test func nativeVerticalFramesEqualizeAdjacentHeights() throws {
        let rig = try Rig()
        rig.goVertical()
        rig.doubleClick(0)
        #expect(abs(rig.view.arrangedSubviews[0].frame.height - rig.view.arrangedSubviews[1].frame.height) <= 1)
    }

    private func failDisk(_ rig: Rig) throws {
        try rig.store.save()
        try FileManager.default.removeItem(at: rig.directory)
        try Data().write(to: rig.directory)
    }

    private func recoverDisk(_ rig: Rig) throws {
        try FileManager.default.removeItem(at: rig.directory)
        try FileManager.default.createDirectory(at: rig.directory, withIntermediateDirectories: true)
    }

    @Test func aRealDiskFailureRefusesGeometryPublication() throws {
        let rig = try Rig()
        let layout = rig.store.activeSplitLayout!
        try failDisk(rig)
        #expect(!rig.store.resizeSplit(expected: layout, widthFactors: [1, 1, 1, 1]))
        try recoverDisk(rig)
    }

    @Test func aFailedSaveRetainsTheCompleteGroupAndSelection() throws {
        let rig = try Rig()
        let layout = rig.store.activeSplitLayout!, state = rig.store.state
        try failDisk(rig)
        _ = rig.store.resizeSplit(expected: layout, widthFactors: [1, 1, 1, 1])
        #expect(rig.store.state == state)
        #expect(rig.store.persistenceError != nil)
        try recoverDisk(rig)
    }

    @Test func theOriginalReceiptRetriesAfterStorageRecovers() throws {
        let rig = try Rig()
        let layout = rig.store.activeSplitLayout!
        try failDisk(rig)
        _ = rig.store.resizeSplit(expected: layout, widthFactors: [1, 1, 1, 1])
        try recoverDisk(rig)
        #expect(rig.store.resizeSplit(expected: layout, widthFactors: [1, 1, 1, 1]))
        #expect(rig.store.state.tabs == rig.originalState.tabs)
        #expect(rig.store.state.selectedTabIDs == rig.ids)
    }

    @Test func invalidFactorsCannotCorruptTheOriginalGeometry() throws {
        let rig = try Rig()
        let current = rig.store.activeSplitLayout!, state = rig.store.state
        #expect(!rig.store.resizeSplit(expected: current, widthFactors: [0, 1, 1, 1]))
        #expect(rig.store.state == state)
    }

    @Test func aSelectionChangeDuringADividerOperationRefusesStaleCompletion() throws {
        let rig = try Rig()
        let current = rig.store.activeSplitLayout!
        _ = rig.store.open("https://different-selection.invalid")
        let selected = rig.store.state
        #expect(!rig.store.resizeSplit(expected: current, widthFactors: [1, 1, 1, 1]))
        #expect(rig.store.state == selected)
    }
}
