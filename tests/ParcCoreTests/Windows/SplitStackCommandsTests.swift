import Foundation
import Testing
@testable import ParcCore

struct SplitStackCommandsTests {
    private static func close(_ left: [Double], _ right: [Double]) -> Bool {
        left.count == right.count && zip(left, right).allSatisfy { abs($0 - $1) < 1e-9 }
    }

    private static func layout(_ sizes: [Int], orientation: SplitOrientation = .horizontal) -> BrowserSplitLayout {
        let ids = (0..<sizes.reduce(0, +)).map { _ in UUID() }
        let even = sizes.map { Array(repeating: 1 / Double($0), count: $0) }
        let shape = BrowserSplitLayout.shape(orientation: orientation, sizes: sizes,
                                             factors: Array(repeating: 1 / Double(sizes.count), count: sizes.count), stackFactors: even)
        return BrowserSplitLayout(id: UUID(), spaceID: UUID(), tabIDs: ids, orientation: shape.orientation,
                                  widthFactors: shape.widthFactors, stacks: shape.stacks)
    }

    struct Position: Sendable, CustomTestStringConvertible {
        let count: Int
        let index: Int
        var testDescription: String { "pane \(index) of \(count)" }
        var inside: Bool { (0..<count).contains(index) }
        var candidates: [BrowserSplitLayout?] { [nil, count > 0 ? SplitStackCommandsTests.layout(Array(repeating: 1, count: count)) : nil] }
        static let all = (0...5).flatMap { count in (-1...5).map { Position(count: count, index: $0) } }
    }

    @Test(arguments: Position.all)
    func flatMovePreviousKeepsTodaysRule(_ p: Position) {
        #expect(p.candidates.allSatisfy { SplitPaneOperation.movePrevious.isEnabled(index: p.index, count: p.count, layout: $0) == (p.inside && p.count > 1 && p.index > 0) })
    }

    @Test(arguments: Position.all)
    func flatMoveNextKeepsTodaysRule(_ p: Position) {
        #expect(p.candidates.allSatisfy { SplitPaneOperation.moveNext.isEnabled(index: p.index, count: p.count, layout: $0) == (p.inside && p.count > 1 && p.index < p.count - 1) })
    }

    @Test(arguments: Position.all)
    func flatAddKeepsTheFourPaneLimit(_ p: Position) {
        #expect(p.candidates.allSatisfy { SplitPaneOperation.addAfter.isEnabled(index: p.index, count: p.count, layout: $0) == (p.inside && p.count < 4) })
    }

    @Test(arguments: Position.all)
    func flatSeparateKeepsTodaysRule(_ p: Position) {
        #expect(p.candidates.allSatisfy { SplitPaneOperation.separate.isEnabled(index: p.index, count: p.count, layout: $0) == (p.inside && p.count > 1) })
    }

    @Test(arguments: Position.all)
    func splitThisPaneNeedsRoomForOneMorePane(_ p: Position) {
        #expect(p.candidates.allSatisfy { SplitPaneOperation.stackAfter.isEnabled(index: p.index, count: p.count, layout: $0) == (p.inside && (2...3).contains(p.count)) })
    }

    @Test(arguments: Position.all)
    func aFlatPaneHasNoStackToMoveIn(_ p: Position) {
        #expect(p.candidates.allSatisfy {
            !SplitPaneOperation.stackPrevious.isEnabled(index: p.index, count: p.count, layout: $0)
                && !SplitPaneOperation.stackNext.isEnabled(index: p.index, count: p.count, layout: $0)
        })
    }

    struct StackedPane: Sendable, CustomTestStringConvertible {
        let sizes: [Int]
        let index: Int
        var testDescription: String { "pane \(index) of \(sizes)" }
        var split: BrowserSplitLayout { SplitStackCommandsTests.layout(sizes) }
        static let all = [[1, 2], [2, 1], [2, 2], [3, 1], [1, 3], [2, 1, 1], [1, 2, 1], [1, 1, 2], [1, 1], [1, 1, 1, 1]].flatMap { sizes in
            (0..<sizes.reduce(0, +)).map { StackedPane(sizes: sizes, index: $0) }
        }
    }

    @Test(arguments: StackedPane.all)
    func moveLeftMatchesTheStoresSlotMove(_ p: StackedPane) {
        let split = p.split
        #expect(SplitPaneOperation.movePrevious.isEnabled(index: p.index, count: split.tabIDs.count, layout: split)
                == (split.movingSlot(of: split.tabIDs[p.index], by: -1) != nil))
    }

    @Test(arguments: StackedPane.all)
    func moveRightMatchesTheStoresSlotMove(_ p: StackedPane) {
        let split = p.split
        #expect(SplitPaneOperation.moveNext.isEnabled(index: p.index, count: split.tabIDs.count, layout: split)
                == (split.movingSlot(of: split.tabIDs[p.index], by: 1) != nil))
    }

    @Test(arguments: StackedPane.all)
    func moveUpMatchesTheStoresStackMove(_ p: StackedPane) {
        let split = p.split
        #expect(SplitPaneOperation.stackPrevious.isEnabled(index: p.index, count: split.tabIDs.count, layout: split)
                == (split.movingWithinStack(split.tabIDs[p.index], by: -1) != nil))
    }

    @Test(arguments: StackedPane.all)
    func moveDownMatchesTheStoresStackMove(_ p: StackedPane) {
        let split = p.split
        #expect(SplitPaneOperation.stackNext.isEnabled(index: p.index, count: split.tabIDs.count, layout: split)
                == (split.movingWithinStack(split.tabIDs[p.index], by: 1) != nil))
    }

    @Test(arguments: StackedPane.all)
    func splitThisPaneIsOfferedOnEveryPaneUntilTheSplitHoldsFour(_ p: StackedPane) {
        let split = p.split
        #expect(SplitPaneOperation.stackBefore.isEnabled(index: p.index, count: split.tabIDs.count, layout: split) == (split.tabIDs.count < 4))
    }

    @Test func theMainRowMoveFollowsSlots() {
        let trio = Self.layout([1, 2])
        #expect(SplitPaneOperation.moveNext.isEnabled(index: 0, count: 3, layout: trio))
        #expect(!SplitPaneOperation.moveNext.isEnabled(index: 1, count: 3, layout: trio))
        #expect(SplitPaneOperation.movePrevious.isEnabled(index: 2, count: 3, layout: trio))
    }

    @Test func aStackMoveNeedsANeighbourInThatDirection() {
        let trio = Self.layout([1, 2])
        #expect(SplitPaneOperation.stackNext.isEnabled(index: 1, count: 3, layout: trio))
        #expect(!SplitPaneOperation.stackPrevious.isEnabled(index: 1, count: 3, layout: trio))
        #expect(SplitPaneOperation.stackPrevious.isEnabled(index: 2, count: 3, layout: trio))
        #expect(!SplitPaneOperation.stackNext.isEnabled(index: 2, count: 3, layout: trio))
    }

    @Test func aLayoutThatDoesNotMatchThePanesFallsBackToFlatRules() {
        let trio = Self.layout([1, 2])
        #expect(!SplitPaneOperation.stackNext.isEnabled(index: 1, count: 4, layout: trio))
        #expect(SplitPaneOperation.moveNext.isEnabled(index: 1, count: 4, layout: trio))
    }

    @MainActor private final class Fixture {
        let root: URL
        let store: BrowserStore

        init(_ name: String) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-split-stack-commands-\(name)-" + UUID().uuidString)
            store = try BrowserStore(directory: root, now: { Date(timeIntervalSince1970: 1_800_000_000) })
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func pair() -> (a: UUID, b: UUID, flat: BrowserSplitLayout) {
            let a = store.open("https://a.test"), b = store.open("https://b.test")
            store.setSplit([a, b])
            return (a, b, store.activeSplitLayout!)
        }

        func stackedBelow() -> (a: UUID, b: UUID, id: UUID, flat: BrowserSplitLayout, below: SplitPaneInsertion) {
            let (a, b, flat) = pair()
            let below = SplitPaneInsertion(paneID: a, operation: .stackAfter, state: store.state)!
            let id = UUID()
            _ = store.insertSplitPane(below, tabID: id, navigationURL: URL(string: "https://new.test/"), creation: nil, savedHomeIDs: [:], documents: [:])
            return (a, b, id, flat, below)
        }

        func fourPanes() {
            let b = stackedBelow().b
            _ = store.insertSplitPane(SplitPaneInsertion(paneID: b, operation: .stackBefore, state: store.state)!, tabID: UUID(),
                                      navigationURL: URL(string: "https://fourth.test/"), creation: nil, savedHomeIDs: [:], documents: [:])
        }
    }

    @MainActor @Test func aSingleUnsplitPageHasNoStackToAddTo() throws {
        let f = try Fixture("single")
        let a = f.store.open("https://a.test")
        #expect(SplitPaneInsertion(paneID: a, operation: .stackAfter, state: f.store.state) == nil)
        #expect(SplitPaneInsertion(paneID: a, operation: .stackBefore, state: f.store.state) == nil)
    }

    @MainActor @Test func aSinglePageKeepsTodaysAddItemsToStartASplit() throws {
        let f = try Fixture("single")
        let a = f.store.open("https://a.test")
        #expect(SplitPaneInsertion(paneID: a, operation: .addBelow, state: f.store.state) != nil)
    }

    @MainActor @Test func addBelowThisPaneIsTheStoresStackedInsertion() throws {
        let f = try Fixture("targets")
        let (a, _, _) = f.pair()
        let below = SplitPaneInsertion(paneID: a, operation: .stackAfter, state: f.store.state)
        #expect(below != nil)
        #expect(below == SplitPaneInsertion(paneID: a, stackingAfter: true, state: f.store.state))
    }

    @MainActor @Test func addBelowTargetsThePanesOwnSlotAfterIt() throws {
        let f = try Fixture("targets")
        let (a, _, flat) = f.pair()
        let below = SplitPaneInsertion(paneID: a, operation: .stackAfter, state: f.store.state)
        #expect(below?.target == .stack(0, after: true))
        #expect(below?.index == 1)
        #expect(below?.orientation == .horizontal)
        #expect(below?.layout == flat)
        #expect(below?.paneID == a)
    }

    @MainActor @Test func addAboveTargetsThePanesOwnSlotBeforeIt() throws {
        let f = try Fixture("targets")
        let (_, b, _) = f.pair()
        let above = SplitPaneInsertion(paneID: b, operation: .stackBefore, state: f.store.state)
        #expect(above?.target == .stack(1, after: false))
        #expect(above?.index == 1)
    }

    @MainActor @Test func thePendingPanePreviewsInsideThePanesSlot() throws {
        let f = try Fixture("targets")
        let (a, b, _) = f.pair()
        let below = SplitPaneInsertion(paneID: a, operation: .stackAfter, state: f.store.state)
        let above = SplitPaneInsertion(paneID: b, operation: .stackBefore, state: f.store.state)
        #expect(below?.previewLayout?.stacks?.slotSizes == [2, 1])
        #expect(above?.previewLayout?.stacks?.slotSizes == [1, 2])
        #expect(below?.previewLayout?.orientation == .horizontal)
    }

    @MainActor @Test func addRightStillAddsAFullLengthPaneWithAFlatPreview() throws {
        let f = try Fixture("targets")
        let (a, _, _) = f.pair()
        let mainRow = try #require(SplitPaneInsertion(paneID: a, operation: .addAfter, state: f.store.state))
        #expect(mainRow.target == .insert(1))
        #expect(mainRow.previewLayout == nil)
        #expect(Self.close(mainRow.previewFactors, [1.0 / 3, 1.0 / 3, 1.0 / 3]))
    }

    @MainActor @Test(arguments: [true, false])
    func stackedPreviewFactorsAreThePreviewsValidFlatRow(_ below: Bool) throws {
        let f = try Fixture("targets")
        let (a, b, _) = f.pair()
        let request = try #require(below ? SplitPaneInsertion(paneID: a, operation: .stackAfter, state: f.store.state)
                                         : SplitPaneInsertion(paneID: b, operation: .stackBefore, state: f.store.state))
        let preview = try #require(request.previewLayout)
        #expect(Self.close(request.previewFactors, preview.widthFactors))
        #expect(request.previewFactors.count == 3)
        #expect(abs(request.previewFactors.reduce(0, +) - 1) < 1e-9)
    }

    @MainActor @Test func addBelowThisPaneCommits() throws {
        let f = try Fixture("targets")
        let (a, _, _) = f.pair()
        let below = try #require(SplitPaneInsertion(paneID: a, operation: .stackAfter, state: f.store.state))
        #expect(f.store.insertSplitPane(below, tabID: UUID(), navigationURL: URL(string: "https://new.test/"), creation: nil, savedHomeIDs: [:], documents: [:]))
    }

    @MainActor @Test func theNewPaneLandsBelowThePaneInsideItsColumn() throws {
        let f = try Fixture("targets")
        let s = f.stackedBelow()
        let committed = try #require(f.store.activeSplitLayout)
        #expect(committed.id == s.flat.id)
        #expect(committed.tabIDs == [s.a, s.id, s.b])
        #expect(committed.stacks?.slotSizes == [2, 1])
    }

    @MainActor @Test func thePendingPanePreviewedExactlyTheCommittedShape() throws {
        let f = try Fixture("targets")
        let s = f.stackedBelow()
        let committed = try #require(f.store.activeSplitLayout)
        #expect(Self.close(s.below.previewFactors, committed.widthFactors))
        #expect(s.below.previewLayout?.stacks == committed.stacks)
    }

    @MainActor @Test func onAPaneAlreadyInAStackTheSameItemsAddToThatStack() throws {
        let f = try Fixture("targets")
        let s = f.stackedBelow()
        let again = SplitPaneInsertion(paneID: s.id, operation: .stackAfter, state: f.store.state)
        #expect(again?.target == .stack(1, after: true))
        #expect(again?.previewLayout?.stacks?.slotSizes == [3, 1])
    }

    @MainActor @Test func aCrossDirectionAddStaysRefusedOnAStackedSplit() throws {
        let f = try Fixture("targets")
        let s = f.stackedBelow()
        #expect(SplitPaneInsertion(paneID: s.a, operation: .addBelow, state: f.store.state) == nil)
    }

    @MainActor @Test func addAboveOnTheLoneColumnCommits() throws {
        let f = try Fixture("targets")
        let s = f.stackedBelow()
        let above = try #require(SplitPaneInsertion(paneID: s.b, operation: .stackBefore, state: f.store.state))
        #expect(f.store.insertSplitPane(above, tabID: UUID(), navigationURL: URL(string: "https://fourth.test/"), creation: nil, savedHomeIDs: [:], documents: [:]))
        #expect(f.store.activeSplitLayout?.stacks?.slotSizes == [2, 2])
    }

    @MainActor @Test(arguments: 0..<4)
    func splitThisPaneRefusesAtFourPanes(_ index: Int) throws {
        let f = try Fixture("targets")
        f.fourPanes()
        let pane = f.store.state.selectedTabIDs[index]
        #expect(SplitPaneInsertion(paneID: pane, operation: .stackAfter, state: f.store.state) == nil)
        #expect(SplitPaneInsertion(paneID: pane, operation: .stackBefore, state: f.store.state) == nil)
    }

    struct StartCase: Sendable, CustomTestStringConvertible {
        let count: Int
        let isSplit: Bool
        var testDescription: String { "\(count) panes, split \(isSplit)" }
        static let all = (0...5).flatMap { count in [false, true].map { StartCase(count: count, isSplit: $0) } }
    }

    @Test(arguments: StartCase.all)
    func splitThisPaneStartsASplitOnlyOnASingleUnsplitPage(_ c: StartCase) {
        #expect(SplitPaneOperation.stackAfter.startsSplitView(paneCount: c.count, isSplit: c.isSplit) == (c.count == 1 && !c.isSplit))
    }

    @Test(arguments: StartCase.all, 0..<SplitPaneOperation.allCases.count)
    func onlySplitThisPaneIsRedirected(_ c: StartCase, _ operationIndex: Int) {
        let operation = SplitPaneOperation.allCases[operationIndex]
        guard operation != .stackAfter else { return }
        #expect(!operation.startsSplitView(paneCount: c.count, isSplit: c.isSplit))
    }

    @MainActor @Test func onASinglePageSplitThisPaneRunsAsAddSplitView() throws {
        let f = try Fixture("single-page")
        let a = f.store.open("https://a.test")
        #expect(f.store.state.selectedTabIDs == [a])
        #expect(f.store.activeSplitLayout == nil)
        #expect(SplitPaneOperation.stackAfter.startsSplitView(paneCount: f.store.state.selectedTabIDs.count, isSplit: f.store.activeSplitLayout != nil))
    }

    @MainActor @Test func itOpensAddSplitViewsPendingPaneRightOfThePage() throws {
        let f = try Fixture("single-page")
        let a = f.store.open("https://a.test")
        let started = try #require(SplitPaneInsertion(paneID: a, operation: .addAfter, state: f.store.state))
        #expect(started.target == .insert(1))
        #expect(started.orientation == .horizontal)
        #expect(started.layout == nil)
        #expect(started.previewLayout == nil)
        #expect(Self.close(started.previewFactors, [0.5, 0.5]))
    }

    @MainActor private func startedSplit(_ f: Fixture) throws -> (a: UUID, id: UUID) {
        let a = f.store.open("https://a.test")
        let started = try #require(SplitPaneInsertion(paneID: a, operation: .addAfter, state: f.store.state))
        let id = UUID()
        _ = f.store.insertSplitPane(started, tabID: id, navigationURL: URL(string: "https://new.test/"), creation: nil, savedHomeIDs: [:], documents: [:])
        return (a, id)
    }

    @MainActor @Test func theNewSplitViewCommitsLikeAddSplitViews() throws {
        let f = try Fixture("single-page")
        let (a, id) = try startedSplit(f)
        #expect(f.store.activeSplitLayout?.tabIDs == [a, id])
    }

    @MainActor @Test func thePageAndNewPaneSitSideBySideWithNoStack() throws {
        let f = try Fixture("single-page")
        _ = try startedSplit(f)
        #expect(f.store.activeSplitLayout?.orientation == .horizontal)
        #expect(f.store.activeSplitLayout?.stacks == nil)
    }

    @MainActor @Test func onceThereIsASplitSplitThisPaneStacksAgain() throws {
        let f = try Fixture("single-page")
        _ = try startedSplit(f)
        #expect(!SplitPaneOperation.stackAfter.startsSplitView(paneCount: f.store.state.selectedTabIDs.count, isSplit: f.store.activeSplitLayout != nil))
    }

    @MainActor @Test(arguments: [0, 1])
    func inTheNewSplitSplitThisPaneAddsBelowThePaneInFocus(_ index: Int) throws {
        let f = try Fixture("single-page")
        let (a, id) = try startedSplit(f)
        let below = SplitPaneInsertion(paneID: [a, id][index], operation: .stackAfter, state: f.store.state)
        #expect(below?.target == .stack(index, after: true))
        #expect(below?.previewLayout?.stacks?.slotSizes == (index == 0 ? [2, 1] : [1, 2]))
    }

    @MainActor private func reading(_ f: Fixture) -> (a: UUID, b: UUID, c: UUID, id: UUID) {
        let a = f.store.open("https://a.test"), b = f.store.open("https://b.test"), c = f.store.open("https://c.test")
        f.store.setSplit([a, b, c])
        let id = UUID()
        _ = f.store.insertSplitPane(SplitPaneInsertion(paneID: c, operation: .stackBefore, state: f.store.state)!, tabID: id,
                                    navigationURL: URL(string: "https://new.test/"), creation: nil, savedHomeIDs: [:], documents: [:])
        return (a, b, c, id)
    }

    @MainActor @Test func addAboveThisPaneCommitsOnTheLastColumn() throws {
        let f = try Fixture("reading")
        let p = reading(f)
        #expect(f.store.state.selectedTabIDs == [p.a, p.b, p.id, p.c])
        #expect(f.store.activeSplitLayout?.stacks?.slotSizes == [1, 1, 2])
        #expect(f.store.state.selectedTabIDs == f.store.activeSplitLayout?.tabIDs)
    }

    @MainActor @Test func moveDownWithinTheStackCommitsAndKeepsReadingOrder() throws {
        let f = try Fixture("reading")
        let p = reading(f)
        let split = try #require(f.store.activeSplitLayout)
        #expect(SplitPaneOperation.stackNext.isEnabled(index: 2, count: 4, layout: split))
        #expect(f.store.moveSplitPaneWithinStack(p.id, offset: 1, expected: split))
        #expect(f.store.state.selectedTabIDs == [p.a, p.b, p.c, p.id])
        #expect(f.store.activeSplitLayout?.stacks?.slotSizes == [1, 1, 2])
        #expect(f.store.state.selectedTabIDs == f.store.activeSplitLayout?.tabIDs)
    }

    @MainActor private func afterMovingDown(_ f: Fixture) throws -> (p: (a: UUID, b: UUID, c: UUID, id: UUID), split: BrowserSplitLayout) {
        let p = reading(f)
        _ = f.store.moveSplitPaneWithinStack(p.id, offset: 1, expected: f.store.activeSplitLayout!)
        return (p, try #require(f.store.activeSplitLayout))
    }

    @MainActor @Test func theLastColumnCannotMoveFurtherRight() throws {
        let f = try Fixture("reading")
        let (p, split) = try afterMovingDown(f)
        #expect(!SplitPaneOperation.moveNext.isEnabled(index: 3, count: 4, layout: split))
        #expect(!f.store.moveSplitPane(p.id, offset: 1, expected: split))
    }

    @MainActor @Test func moveLeftMovesTheWholeColumnAndKeepsReadingOrder() throws {
        let f = try Fixture("reading")
        let (p, split) = try afterMovingDown(f)
        #expect(SplitPaneOperation.movePrevious.isEnabled(index: 3, count: 4, layout: split))
        #expect(f.store.moveSplitPane(p.id, offset: -1, expected: split))
        #expect(f.store.state.selectedTabIDs == [p.a, p.c, p.id, p.b])
        #expect(f.store.activeSplitLayout?.stacks?.slotSizes == [1, 2, 1])
        #expect(f.store.state.selectedTabIDs == f.store.activeSplitLayout?.tabIDs)
    }

    @MainActor private func sideways(_ f: Fixture) throws -> (a: UUID, b: UUID, id: UUID, right: SplitPaneInsertion) {
        let a = f.store.open("https://a.test"), b = f.store.open("https://b.test")
        f.store.setSplit([a, b])
        f.store.setSplitLayout(orientation: .vertical, widthFactors: [0.5, 0.5])
        let right = try #require(SplitPaneInsertion(paneID: b, operation: .stackAfter, state: f.store.state))
        return (a, b, UUID(), right)
    }

    @MainActor @Test func inATopAndBottomSplitAddRightDividesThePanesRow() throws {
        let f = try Fixture("vertical")
        let s = try sideways(f)
        #expect(s.right.orientation == .vertical)
        #expect(s.right.target == .stack(1, after: true))
        #expect(s.right.previewLayout?.orientation == .vertical)
        #expect(s.right.previewLayout?.stacks?.slotSizes == [1, 2])
    }

    @MainActor @Test func theNewPaneSitsRightOfThePaneInsideItsRow() throws {
        let f = try Fixture("vertical")
        let s = try sideways(f)
        #expect(f.store.insertSplitPane(s.right, tabID: s.id, navigationURL: URL(string: "https://new.test/"), creation: nil, savedHomeIDs: [:], documents: [:]))
        let split = try #require(f.store.activeSplitLayout)
        #expect(split.orientation == .vertical)
        #expect(split.tabIDs == [s.a, s.b, s.id])
        #expect(split.stacks?.slotSizes == [1, 2])
    }

    @MainActor @Test func sidewaysMovesAreOfferedOnlyWhereANeighbourExists() throws {
        let f = try Fixture("vertical")
        let s = try sideways(f)
        _ = f.store.insertSplitPane(s.right, tabID: s.id, navigationURL: URL(string: "https://new.test/"), creation: nil, savedHomeIDs: [:], documents: [:])
        let split = try #require(f.store.activeSplitLayout)
        #expect(SplitPaneOperation.stackPrevious.isEnabled(index: 2, count: 3, layout: split))
        #expect(!SplitPaneOperation.stackNext.isEnabled(index: 2, count: 3, layout: split))
        #expect(SplitPaneOperation.movePrevious.isEnabled(index: 2, count: 3, layout: split))
        #expect(!SplitPaneOperation.moveNext.isEnabled(index: 2, count: 3, layout: split))
    }
}
