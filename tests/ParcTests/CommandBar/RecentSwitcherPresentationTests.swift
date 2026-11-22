import AppKit
import Testing
@testable import Parc

struct RecentSwitcherPresentationTests {
    enum Preview: CaseIterable { case note, easel, incognito }

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

        init(count: Int = 3, viewportWidth: CGFloat = 562, cold: Bool = false) {
            _ = NSApplication.shared
            let frame = CGRect(x: 0, y: 0, width: viewportWidth + 288, height: 478)
            window = Window(contentRect: cold ? .zero : frame, styleMask: .borderless, backing: .buffered, defer: cold)
            window.isReleasedWhenClosed = false
            content = RecentTabSwitcherView(frame: cold ? .zero : frame,
                                            schedulePublication: { [queue] in queue.job = $0 }, reduceMotion: { true })
            window.contentView = content
            items = ["one", "two", "three", "four", "five", "reserve"].prefix(count).map { title in
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

        func layout() {
            content.layoutSubtreeIfNeeded()
            queue.job?.perform()
            queue.job = nil
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

    @Test @MainActor func theDefaultArtworkFolderIsInTheApplicationBundle() {
        let artwork = RecentSwitcherArtwork()
        #expect(artwork.directory == Bundle.main.resourceURL?.appendingPathComponent("RecentSwitcher", isDirectory: true))
    }

    @Test(arguments: Preview.allCases)
    @MainActor func bundledPreviewArtworkDecodesAsATemplate(preview: Preview) throws {
        let resources = try #require(Bundle.module.resourceURL).appendingPathComponent("CommandBarFixtures", isDirectory: true)
        let artwork = RecentSwitcherArtwork(resources: resources)
        let image = switch preview {
        case .note: artwork.note
        case .easel: artwork.easel
        case .incognito: artwork.incognito
        }
        let template = try #require(image)
        #expect(template.isValid && template.isTemplate)
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
    @MainActor private func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }

    @Test @MainActor func theHostLaysOutFiveCardsAtTheOriginalSizeAndPadding() throws {
        let fixture = Fixture(count: 5, viewportWidth: 940.5)
        fixture.layout()
        let view = fixture.content
        #expect(view.contentRect == CGRect(x: 144, y: 120, width: view.bounds.width - 288, height: 190))
        #expect(!view.acceptsFirstResponder)
        #expect(view.itemFrames.count == 5)
        let card = try #require(view.itemFrames[fixture.items[0].id])
        #expect(abs(card.width - 181.7) < 0.01)
        #expect(card.height == 158)
        #expect(card.origin == CGPoint(x: 16, y: 16))
    }

    @Test @MainActor func theHostPublishesVisibilityFromItsLaidOutViewport() {
        let fixture = Fixture(count: 5, viewportWidth: 940.5)
        var publications = [Set<Int>]()
        fixture.content.onVisibleItemsChanged = { [weak content = fixture.content] in
            if let content { publications.append(content.visibleItemIndexes) }
        }
        fixture.layout()
        #expect(publications == [Set(0..<5)])
    }

    @Test(arguments: [false, true])
    @MainActor func keepingTheSameHostedCardsDoesNotRepublishVisibility(changesFocus: Bool) throws {
        let fixture = Fixture(count: 5, viewportWidth: 940.5)
        let view = fixture.content
        view.configure(isDark: false, focus: .systemPurple, hover: .systemGray, maxContrast: .black, cutout: .white)
        fixture.layout()
        try #require(view.visibleItemIndexes == Set(0..<5))
        let frames = view.itemFrames
        view.onVisibleItemsChanged = { Issue.record("The same visible cards were published again") }
        view.configure(isDark: false, focus: .systemPurple, hover: .systemGray, maxContrast: .black, cutout: .white)
        view.setItems(fixture.items, focused: 1)
        let index = changesFocus ? 3 : 1
        view.focus(index)
        fixture.layout()
        #expect(view.focusedID == fixture.items[index].id)
        #expect(view.itemFrames == frames)
        #expect(view.visibleItemIndexes == Set(0..<5))
    }

    @Test @MainActor func theHostBuildsTheNativePopoverMaterial() throws {
        let fixture = Fixture()
        fixture.layout()
        let material = try #require(descendants(of: fixture.content).compactMap { $0 as? NSVisualEffectView }.first)
        #expect(material.material == .popover)
        #expect(material.state == .followsWindowActiveState)
        #expect(material.blendingMode == .withinWindow)
        #expect(!material.isEmphasized)
    }

    @Test @MainActor func theNarrowHostedRowDoesNotShowAHorizontalScroller() throws {
        let fixture = Fixture(count: 5, viewportWidth: 520)
        fixture.layout()
        let scroll = try #require(descendants(of: fixture.content).compactMap { $0 as? NSScrollView }.first)
        #expect(!scroll.hasHorizontalScroller)
    }

    @Test @MainActor func theColdHostPublishesCardsAfterItGetsItsPanelSize() {
        let fixture = Fixture(count: 5, viewportWidth: 0, cold: true)
        fixture.window.setContentSize(NSSize(width: 1228.5, height: 478))
        fixture.layout()
        #expect(fixture.content.bounds.size == fixture.window.frame.size)
        #expect(abs(fixture.content.contentRect.width - 940.5) <= 1)
        #expect(fixture.content.contentRect.height == 190)
        #expect(fixture.content.itemFrames.count == 5)
        #expect(fixture.content.visibleItemIndexes == Set(0..<5))
    }

    @Test @MainActor func aHostedReserveJoinsVisibilityOnlyWhenPromoted() {
        let fixture = Fixture(count: 6, viewportWidth: 940.5)
        var items = fixture.items
        items[5].isHidden = true
        fixture.content.setItems(items, focused: 1)
        fixture.layout()
        #expect(fixture.content.itemFrames.count == 6)
        #expect(fixture.content.visibleItemIndexes == Set(0..<5))
        items[5].isHidden = false
        fixture.content.setItems(Array(items.dropFirst()), focused: 4)
        fixture.layout()
        #expect(fixture.content.itemFrames.count == 5)
        #expect(fixture.content.visibleItemIndexes == Set(0..<5))
        #expect(fixture.content.focusedID == items[5].id)
    }

    @Test @MainActor func theDocumentAndPrivatePreviewPDFsDecodeAsTemplates() throws {
        let resources = try #require(Bundle.module.resourceURL)
        let artwork = RecentSwitcherArtwork(resources: resources)
        #expect(artwork.directory?.path == Bundle.module.url(forResource: "RecentSwitcher", withExtension: nil)?.path)
        #expect(artwork.note?.isTemplate == true)
        #expect(artwork.easel?.isTemplate == true)
        #expect(artwork.incognito?.isTemplate == true)
    }

    @Test @MainActor func theHostedPreviewVariantsKeepTheSameCardSize() throws {
        let fixture = Fixture(count: 5, viewportWidth: 940.5)
        let artwork = RecentSwitcherArtwork(resources: Bundle.module.resourceURL)
        let picture = NSImage(size: NSSize(width: 240, height: 180), flipped: false) { rect in
            NSColor.systemBlue.setFill()
            rect.fill()
            return true
        }
        var items = fixture.items
        items[0].components[0].template = .init(image: try #require(artwork.note), title: "A two-line note title")
        items[1].components[0].image = picture
        items[1].components.append(.init(id: UUID(), title: "Second pane", image: picture))
        items[1].customInfo = .init(icon: NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil), title: "Named split")
        items[2].components.append(.init(id: UUID(), title: "Empty pane"))
        items[2].customInfo = .init(icon: nil, title: "Counted split")
        items[3].components[0].image = picture
        items[3].overlay = .init(id: UUID(), title: "Peek", image: picture)
        items[4].components[0].template = .init(image: try #require(artwork.incognito), title: nil)
        items[4].components[0].isRecordingMedia = true
        fixture.content.setItems(items, focused: 1)
        fixture.layout()
        try #require(fixture.content.itemFrames.count == 5)
        #expect(fixture.content.itemFrames.values.allSatisfy { abs($0.width - 181.7) < 0.01 && $0.height == 158 })
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

extension RecentSwitcherPresentationTests {
    @Test @MainActor func fiveCardsKeepTheOriginalPanelSizeAndCardMetrics() {
        let parent = NSRect(x: 50, y: 70, width: 1200, height: 800)
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 1000)
        let frame = RecentTabSwitcherView.panelFrame(itemCount: 5, parent: parent, screen: screen)
        #expect(abs(RecentTabSwitcherView.Metrics.cardWidth - 181.7) < 0.0001)
        #expect(frame.height == 478)
        #expect(abs(frame.width - 1228.5) < 0.0001)
        #expect(frame.minX + 144 + 940.5 / 2 == parent.midX)
        #expect(frame.minY + 168 + 95 == parent.midY)
    }

    @Test @MainActor func aNarrowParentScrollsHorizontally() {
        let frame = RecentTabSwitcherView.panelFrame(itemCount: 5, parent: NSRect(x: 0, y: 0, width: 600, height: 700),
                                                     screen: NSRect(x: 0, y: 0, width: 1440, height: 1000))
        #expect(frame.width - 288 == 520)
    }

    @Test @MainActor func aSinglePaneItemDrawsFlat() {
        let fixture = Fixture()
        #expect(fixture.items[0].slots == nil)
    }

    @Test @MainActor func hoveringAndChoosingMapTheOriginalIdentityToItsCurrentItem() {
        let fixture = Fixture()
        var hovered: [Int] = [], chosen: [Int] = []
        fixture.content.onHover = { hovered.append($0) }
        fixture.content.onChoose = { chosen.append($0) }
        fixture.content.hover("three")
        fixture.content.choose("three")
        fixture.content.choose("retired")
        #expect(hovered == [2] && chosen == [2])
    }

    @Test @MainActor func anOwnerThatRefusesInteractionBlocksHoverAndChoice() {
        let fixture = Fixture()
        var hovered: [Int] = [], chosen: [Int] = []
        fixture.content.onHover = { hovered.append($0) }
        fixture.content.onChoose = { chosen.append($0) }
        fixture.content.canInteract = { false }
        fixture.content.choose("one")
        fixture.content.hover("one")
        #expect(hovered.isEmpty && chosen.isEmpty)
    }

    @Test @MainActor func aRemovedItemCannotBeChosen() {
        let fixture = Fixture()
        var chosen: [Int] = []
        fixture.content.onChoose = { chosen.append($0) }
        fixture.content.setItems([fixture.items[2], fixture.items[1]], focused: 1)
        fixture.content.choose("one")
        #expect(chosen.isEmpty)
    }

    @Test @MainActor func aHiddenReserveRefusesHoverChoiceAndFocus() {
        let fixture = Fixture()
        var items = fixture.items
        items[2].isHidden = true
        fixture.content.setItems(items, focused: 1)
        var hovered: [Int] = [], chosen: [Int] = []
        fixture.content.onHover = { hovered.append($0) }
        fixture.content.onChoose = { chosen.append($0) }
        fixture.content.hover("three")
        fixture.content.choose("three")
        fixture.content.focus(2)
        #expect(hovered.isEmpty && chosen.isEmpty)
        #expect(fixture.content.focusedID == nil)
    }

    @Test @MainActor func aPromotedReserveTakesTheFocusAndDispatchesItsPosition() {
        let fixture = Fixture()
        var items = fixture.items
        items[2].isHidden = true
        fixture.content.setItems(items, focused: 1)
        items[2].isHidden = false
        fixture.content.setItems(items, focused: 2)
        var chosen: [Int] = []
        fixture.content.onChoose = { chosen.append($0) }
        fixture.content.choose("three")
        #expect(fixture.content.focusedID == "three")
        #expect(chosen == [2])
    }

    @Test @MainActor func retiringRevokesCallbacksAndFurtherMutation() {
        let fixture = Fixture()
        var chosen: [Int] = []
        fixture.content.onChoose = { chosen.append($0) }
        let focused = fixture.content.focusedID
        fixture.content.retire()
        fixture.content.choose("one")
        fixture.content.focus(0)
        #expect(chosen.isEmpty)
        #expect(fixture.content.focusedID == focused)
        #expect(fixture.content.canInteract == nil && fixture.content.onChoose == nil)
    }
}
