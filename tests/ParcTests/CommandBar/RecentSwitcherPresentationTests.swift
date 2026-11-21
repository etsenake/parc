import AppKit
import Testing
@testable import Parc

struct RecentSwitcherPresentationTests {
    @MainActor private final class Window: NSWindow {
        override var isVisible: Bool { true }
    }

    @MainActor private final class Publication {
        var job: DispatchWorkItem?
    }

    @MainActor private struct Fixture {
        let content: RecentTabSwitcherView
        let window: Window
        let queue = Publication()
        let items: [RecentTabSwitcherView.Item]

        init() {
            _ = NSApplication.shared
            let frame = CGRect(x: 0, y: 0, width: 850, height: 478)
            window = Window(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            content = RecentTabSwitcherView(frame: frame, schedulePublication: { [queue] in queue.job = $0 })
            window.contentView = content
            items = ["one", "two", "three"].map { title in
                RecentTabSwitcherView.Item(id: title, title: title, spaceName: "Space", vertical: false,
                                          components: [.init(id: UUID(), title: title)])
            }
            content.canInteract = { true }
            content.setItems(items, focused: 1)
        }

        var frames: [String: CGRect] {
            ["one": CGRect(x: 16, y: 16, width: 170, height: 158),
             "two": CGRect(x: 200, y: 16, width: 170, height: 158),
             "three": CGRect(x: 600, y: 16, width: 170, height: 158)]
        }
    }

    @Test(arguments: [(1200.0, 940.5), (600.0, 520.0)])
    @MainActor func theSwitcherIsCenteredAndCapsItsContentWidth(width: Double, expected: Double) {
        let parent = NSRect(x: 50, y: 70, width: width, height: 800)
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 1000)
        let frame = RecentTabSwitcherView.panelFrame(itemCount: 5, parent: parent, screen: screen)
        let shadow = RecentTabSwitcherView.Metrics.shadow
        let content = CGRect(x: frame.minX + shadow.left, y: frame.minY + shadow.bottom,
                             width: frame.width - shadow.left - shadow.right,
                             height: frame.height - shadow.top - shadow.bottom)
        #expect(abs(content.width - CGFloat(expected)) < 0.001)
        #expect(content.height == 190)
        #expect(content.midX == parent.midX)
        #expect(content.midY == parent.midY)
    }

    @Test(arguments: [([2, 1], true), ([1, 1], false), ([0, 3], false)])
    @MainActor func stackedPreviewSlotsRequireTheirActualPaneCount(sizes: [Int], valid: Bool) {
        let ids = [UUID(), UUID(), UUID()]
        let item = RecentTabSwitcherView.Item(id: "stacked", title: "Stacked", spaceName: "Space",
            vertical: false, components: ids.map { .init(id: $0, title: "Pane") }, slotSizes: sizes)
        #expect(item.slots?.map { $0.map(\.id) } == (valid ? [[ids[0], ids[1]], [ids[2]]] : nil))
    }

    @Test @MainActor func focusingAnotherPreviewKeepsTheNativeResponder() {
        let fixture = Fixture()
        let responder = fixture.window.firstResponder
        fixture.content.focus(2)
        #expect(fixture.content.focusedID == "three")
        #expect(fixture.window.firstResponder === responder)
        #expect(!fixture.content.acceptsFirstResponder)
    }

    @Test @MainActor func aPointerChoiceUsesTheCurrentIndexOfItsOriginalItem() {
        let fixture = Fixture()
        fixture.content.setItems([fixture.items[2], fixture.items[0]], focused: 1)
        var selected: [Int] = []
        fixture.content.onChoose = { selected.append($0) }
        fixture.content.choose("three")
        fixture.content.choose("two")
        #expect(selected == [0])
    }

    @Test(arguments: ["hidden", "unavailable", "retired", "detached"])
    @MainActor func staleSwitcherSurfacesCannotDispatch(reason: String) {
        let fixture = Fixture()
        var selected: Int?
        fixture.content.onChoose = { selected = $0 }
        switch reason {
        case "hidden": fixture.content.isHidden = true
        case "unavailable": fixture.content.canInteract = { false }
        case "retired": fixture.content.retire()
        default: fixture.window.contentView = nil
        }
        fixture.content.choose("one")
        #expect(selected == nil)
    }

    @Test @MainActor func visibilityUsesOnlyCardsIntersectingTheViewport() throws {
        let fixture = Fixture()
        fixture.content.publish(frames: fixture.frames)
        let job = try #require(fixture.queue.job)
        job.perform()
        #expect(fixture.content.visibleItemIndexes == [0, 1])
    }

    @Test @MainActor func publishingIdenticalFramesDoesNotRepeatVisibility() throws {
        let fixture = Fixture()
        var notifications = 0
        fixture.content.onVisibleItemsChanged = { notifications += 1 }
        fixture.content.publish(frames: fixture.frames)
        try #require(fixture.queue.job).perform()
        fixture.content.publish(frames: fixture.frames)
        try #require(fixture.queue.job).perform()
        #expect(notifications == 1)
    }

    @Test @MainActor func detachingTheSwitcherCancelsItsPendingFramePublication() throws {
        let fixture = Fixture()
        fixture.content.publish(frames: fixture.frames)
        let old = try #require(fixture.queue.job)
        fixture.window.contentView = nil
        old.perform()
        #expect(fixture.content.itemFrames.isEmpty)
    }
}

extension RecentSwitcherPresentationTests {
    @Test(arguments: [false, true])
    @MainActor func aReserveCardOnlyPublishesAVisiblePreviewAfterPromotion(promoted: Bool) throws {
        let fixture = Fixture()
        var items = fixture.items
        items[1].isHidden = !promoted
        fixture.content.setItems(items, focused: 0)
        fixture.content.publish(frames: fixture.frames)
        let job = try #require(fixture.queue.job)
        job.perform()
        #expect(fixture.content.itemFrames["two"] == fixture.frames["two"])
        #expect(fixture.content.visibleItemIndexes == (promoted ? [0, 1] : [0]))
    }

    @Test(arguments: [false, true])
    @MainActor func onlyAPromotedReserveCardCanDispatchPointerInput(promoted: Bool) {
        let fixture = Fixture()
        var items = fixture.items
        items[1].isHidden = !promoted
        fixture.content.setItems(items, focused: 0)
        var hovered: [Int] = [], chosen: [Int] = []
        fixture.content.onHover = { hovered.append($0) }
        fixture.content.onChoose = { chosen.append($0) }
        fixture.content.hover("two")
        fixture.content.choose("two")
        let expected = promoted ? [1] : []
        #expect(hovered == expected)
        #expect(chosen == expected)
    }
}
