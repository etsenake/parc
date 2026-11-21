import AppKit
import Testing
@testable import Parc

@MainActor
struct SidebarDockStripTests {
    final class RecordingButton: NSButton {
        var alphaSets: [(value: CGFloat, duration: TimeInterval)] = []
        var moves = 0
        override var alphaValue: CGFloat { didSet { alphaSets.append((alphaValue, NSAnimationContext.current.duration)) } }
        override func viewWillMove(toSuperview newSuperview: NSView?) { super.viewWillMove(toSuperview: newSuperview); moves += 1 }
    }

    @MainActor final class Dock {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.borderless], backing: .buffered, defer: true)
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        let strip = SidebarDockStrip(frame: SidebarChromeLayout.dockStrip(width: 228, height: 50))
        var three: [NSButton] = []

        init(animated: Bool = false, count: Int = 3, selected: Int? = 1) {
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.addSubview(strip)
            strip.reduceMotion = { !animated }
            strip.dark = false
            three = Self.buttons(count)
            strip.items = three; strip.selectedIndex = selected
            strip.layoutSubtreeIfNeeded()
        }

        deinit { MainActor.assumeIsolated { window.contentView = nil } }

        static func buttons(_ count: Int, from start: Int = 0) -> [NSButton] {
            (start..<start + count).map { index in
                let button = RecordingButton(frame: .zero)
                button.wantsLayer = true
                button.isBordered = false; button.image = NSImage(systemSymbolName: "circle", accessibilityDescription: nil)
                button.imagePosition = .imageOnly
                SidebarAccessibility.configureSpace(button, name: "Space \(index)")
                return button
            }
        }
        func sets(_ buttons: [NSButton]) -> [[(value: CGFloat, duration: TimeInterval)]] { buttons.map { ($0 as! RecordingButton).alphaSets } }
        func reset(_ buttons: [NSButton]) { for button in buttons { (button as! RecordingButton).alphaSets.removeAll() } }
        func parts(_ name: String) -> [NSView] { strip.documentView!.subviews.filter { $0.identifier?.rawValue == name } }
        var backgrounds: [NSView] { parts("SidebarDockItemBackground") }
        var dots: [NSView] { parts("SidebarDockItemPageIndicator") }
        func hover(_ index: Int?) {
            let item = index.map { strip.layoutState.items[$0] }
            strip.updateHover(atWindowPoint: item.map { strip.documentView!.convert(NSPoint(x: $0.midX, y: $0.midY), to: nil) })
        }
        var titles: [String] { Self.titles(strip.accessibilityChildren()) }
        static func titles(_ children: [Any]?) -> [String] {
            (children ?? []).compactMap { ($0 as AnyObject as? NSAccessibilityProtocol)?.accessibilityTitle() ?? nil }
        }
        var regular: SidebarChromeLayout.DockLayout { SidebarChromeLayout.dockLayout(width: 148, height: 50, count: 3, focused: 1) }
    }

    private static let light = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.5)
    private static let red = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), blue = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
    private static func near(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 0.5 && abs(a.maxX - b.maxX) <= 0.5 && abs(a.minY - b.minY) <= 0.5 && abs(a.maxY - b.maxY) <= 0.5
    }

    @Test func theStripHasZeroTwoZeroTwoInsets() {
        let dock = Dock()
        #expect(dock.strip.contentInsets.left == 2 && dock.strip.contentInsets.right == 2 && dock.strip.contentInsets.top == 0)
    }

    @Test func theStripHasNoElasticityOrBackground() {
        let dock = Dock()
        #expect(dock.strip.horizontalScrollElasticity == .none && dock.strip.verticalScrollElasticity == .none && !dock.strip.drawsBackground)
    }

    @Test func theStripSpansFortyToWidthMinusForty() {
        #expect(Dock().strip.frame == NSRect(x: 40, y: 0, width: 148, height: 50))
    }

    @Test func theStripUsesTheRecoveredLayout() {
        let dock = Dock()
        #expect(dock.strip.layoutState == dock.regular && !dock.regular.compact)
    }

    @Test func buttonsTakeTheirItemFrames() {
        let dock = Dock()
        #expect(zip(dock.three, dock.regular.items).allSatisfy { Self.near($0.frame, $1) })
    }

    @Test func theSelectedIconIsFullAndOthersAtTheLightRestingAlpha() {
        #expect(Dock().three.map(\.alphaValue) == [0.5, 1, 0.5])
    }

    @Test func iconsTakeForegroundSecondaryWithoutASpaceColour() {
        #expect(Dock().three.allSatisfy { $0.contentTintColor == Self.light })
    }

    @Test func darkUsesItsRestingAlpha() {
        let dock = Dock()
        dock.strip.dark = true
        #expect(dock.three.map(\.alphaValue) == [0.35, 1, 0.35])
    }

    private func iconless() -> Dock {
        let dock = Dock()
        dock.strip.activeTints = [.systemGreen, .systemGreen, .systemGreen]
        dock.strip.iconlessButtons = [ObjectIdentifier(dock.three[1])]
        return dock
    }

    @Test func aSelectedIconlessSpaceUsesTheEightPointDot() {
        let dock = iconless()
        #expect(dock.three[1].alphaValue == 0 && dock.dots[1].alphaValue == 1 && dock.dots[1].frame.width == 8)
    }

    @Test func theIconlessDotKeepsTheSecondaryForegroundRatherThanTheAccent() {
        #expect(iconless().dots[1].layer?.backgroundColor == Self.light.cgColor)
    }

    @Test func theIconlessDotKeepsTheSpacesHitTarget() {
        let dock = iconless()
        #expect(dock.strip.documentView!.hitTest(NSPoint(x: dock.three[1].frame.midX, y: dock.three[1].frame.midY)) === dock.three[1])
    }

    @Test func theIconlessPresentationKeepsTheSpaceAccessibilityOwner() {
        #expect(iconless().titles == ["Space 0", "Space 1", "Space 2"])
    }

    @Test func spacesAreOrderedLeftToRight() {
        let dock = Dock()
        #expect(dock.titles == ["Space 0", "Space 1", "Space 2"])
        #expect(Dock.titles(dock.strip.documentView!.accessibilityChildren()) == ["Space 0", "Space 1", "Space 2"])
    }

    @Test func backgroundsAndDotsAreNotExposed() {
        #expect(Dock().strip.accessibilityChildren()?.count == 3)
    }

    private func withCreate() -> (Dock, NSButton) {
        let dock = Dock()
        let create = Dock.buttons(1, from: 9)[0]
        create.setAccessibilityLabel("Create Space")
        SidebarAccessibility.configureSpace(create, name: "Create Space")
        dock.strip.items = dock.three + [create]; dock.strip.selectedIndex = 3; dock.strip.layoutSubtreeIfNeeded()
        return (dock, create)
    }

    @Test func theCreationButtonComesLastAndItemsRunLeftToRight() {
        let (dock, _) = withCreate()
        #expect(dock.titles == ["Space 0", "Space 1", "Space 2", "Create Space"])
        #expect(zip(dock.strip.items, dock.strip.items.dropFirst()).allSatisfy { $0.frame.maxX <= $1.frame.minX + 0.5 })
    }

    @Test func aReorderUpdatesTheOrderWithoutRemovingAButton() {
        let (dock, create) = withCreate()
        let all = dock.three + [create]
        let moves = all.map { ($0 as! RecordingButton).moves }
        dock.strip.items = [dock.three[2], dock.three[0], dock.three[1], create]
        #expect(dock.titles == ["Space 2", "Space 0", "Space 1", "Create Space"])
        #expect(all.map { ($0 as! RecordingButton).moves } == moves && moves.allSatisfy { $0 > 0 })
    }

    @Test func theCreationButtonLeavesWithItsItem() {
        let (dock, create) = withCreate()
        dock.strip.items = [dock.three[2], dock.three[0], dock.three[1], create]
        dock.strip.items = dock.three; dock.strip.selectedIndex = 1; dock.strip.layoutSubtreeIfNeeded()
        #expect(create.superview == nil)
        #expect(dock.titles == ["Space 0", "Space 1", "Space 2"])
        #expect(zip(dock.three, dock.regular.items).allSatisfy { Self.near($0.frame, $1) })
    }

    @Test func eachItemHasABackground() {
        let dock = Dock()
        #expect(dock.backgrounds.count == 3 && zip(dock.backgrounds, dock.regular.items).allSatisfy { Self.near($0.frame, $1) })
    }

    @Test func backgroundsHaveSixPointContinuousCorners() {
        #expect(Dock().backgrounds.allSatisfy { $0.layer?.cornerRadius == 6 && $0.layer?.cornerCurve == .continuous })
    }

    @Test func dockItemsTakeNoKeyboardFocus() {
        let (dock, create) = withCreate()
        #expect(dock.three.allSatisfy { !$0.acceptsFirstResponder } && !create.acceptsFirstResponder)
    }

    @Test func aHoveredItemIsHighlightedAndItsBackgroundShows() {
        let dock = Dock()
        dock.hover(0)
        #expect(abs(dock.three[0].alphaValue - 0.7) < 0.001 && dock.three[1].alphaValue == 1)
        #expect(abs(dock.backgrounds[0].alphaValue - 1) < 0.001 && dock.backgrounds[1].alphaValue < 0.001)
    }

    @Test func anIdenticalHoverDoesNotRearrange() {
        let dock = Dock()
        dock.hover(0)
        dock.reset(dock.three)
        dock.hover(0)
        #expect(dock.sets(dock.three).allSatisfy(\.isEmpty) && abs(dock.backgrounds[0].alphaValue - 1) < 0.001)
    }

    @Test func backgroundsStayOnTheirItemsAndCrossFade() {
        let dock = Dock()
        dock.hover(0)
        dock.hover(2)
        #expect(zip(dock.backgrounds, dock.regular.items).allSatisfy { Self.near($0.frame, $1) })
        #expect(dock.backgrounds[0].alphaValue < 0.001 && abs(dock.backgrounds[2].alphaValue - 1) < 0.001)
    }

    @Test func leavingClearsTheHighlightAndARepeatedClearDoesNotRearrange() {
        let dock = Dock()
        dock.hover(2)
        dock.hover(nil)
        #expect(dock.backgrounds.allSatisfy { $0.alphaValue < 0.001 } && dock.three[0].alphaValue == 0.5)
        dock.reset(dock.three)
        dock.hover(nil)
        #expect(dock.sets(dock.three).allSatisfy { $0.isEmpty })
    }

    @Test func hidingTheSidebarClearsTheHoverAndShowingItInAWindowThatIsNotKeyHoversNothing() {
        let dock = Dock()
        dock.hover(0)
        dock.host.isHidden = true
        #expect(dock.backgrounds.allSatisfy { $0.alphaValue < 0.001 } && dock.three[0].alphaValue == 0.5)
        dock.host.isHidden = false
        #expect(dock.backgrounds.allSatisfy { $0.alphaValue < 0.001 })
    }

    @Test func aDockLeavingWithAnUnhiddenSidebarClearsTheHoverAndItsReturnHoversNothing() {
        let dock = Dock()
        dock.hover(0)
        dock.strip.setPresented(false)
        #expect(!dock.strip.isHiddenOrHasHiddenAncestor)
        #expect(dock.backgrounds.allSatisfy { $0.alphaValue < 0.001 } && dock.three[0].alphaValue == 0.5)
        dock.strip.setPresented(true)
        #expect(dock.backgrounds.allSatisfy { $0.alphaValue < 0.001 })
    }

    @Test func theSelectedSpaceTakesItsColourAndIdleOnesKeepForegroundSecondary() {
        let dock = Dock()
        dock.strip.activeTints = [nil, Self.red, Self.blue]
        #expect(dock.three[0].contentTintColor == Self.light && dock.three[1].contentTintColor == Self.red)
        #expect(dock.three[2].contentTintColor == Self.light)
    }

    @Test func aHighlightedSpaceTakesItsColourWhichLeavesWithTheHighlight() {
        let dock = Dock()
        dock.strip.activeTints = [nil, Self.red, Self.blue]
        dock.hover(2)
        #expect(dock.three[2].contentTintColor == Self.blue && abs(dock.three[2].alphaValue - 0.7) < 0.001)
        dock.hover(nil)
        #expect(dock.three[2].contentTintColor == Self.light)
    }

    @Test func aSwitchSetsOnlyTheTwoChangingIcons() {
        let dock = Dock()
        dock.reset(dock.three)
        dock.strip.selectedIndex = 2
        let sets = dock.sets(dock.three)
        #expect(sets[2].map(\.value) == [1] && sets[1].map(\.value) == [0.5] && sets[0].isEmpty)
    }

    @Test func theSwitchAnimates() {
        let dock = Dock(animated: true)
        dock.reset(dock.three)
        dock.strip.selectedIndex = 2
        #expect(!dock.sets(dock.three).joined().isEmpty && dock.sets(dock.three).joined().allSatisfy { $0.duration > 0 })
    }

    @Test func theSameItemsALayoutPassAndAnUnchangedStyleDoNotSnap() {
        let dock = Dock()
        dock.strip.activeTints = [nil, Self.red, Self.blue]
        dock.reset(dock.three)
        dock.strip.items = Array(dock.three); dock.strip.activeTints = [nil, Self.red, Self.blue]; dock.strip.dark = false
        dock.strip.needsLayout = true; dock.strip.layoutSubtreeIfNeeded()
        #expect(dock.sets(dock.three).allSatisfy { $0.isEmpty })
    }

    @Test func aNewItemTakesItsStyleDirectlyWithoutSnappingTheOthers() {
        let dock = Dock(animated: true)
        dock.strip.selectedIndex = 0
        dock.reset(dock.three)
        let extra = Dock.buttons(1, from: 3)[0]
        dock.strip.items = dock.three + [extra]; dock.strip.layoutSubtreeIfNeeded()
        #expect(dock.sets(dock.three).allSatisfy { $0.isEmpty })
        #expect(dock.sets([extra])[0].last.map { $0.value == 0.5 && $0.duration == 0 } == true)
    }

    @Test func theSwitchSettlesAndTheExtraItemLeaves() {
        let dock = Dock()
        dock.strip.selectedIndex = 0
        let extra = Dock.buttons(1, from: 3)[0]
        dock.strip.items = dock.three + [extra]; dock.strip.layoutSubtreeIfNeeded()
        #expect(dock.three.map(\.alphaValue) == [1, 0.5, 0.5] && extra.alphaValue == 0.5)
        dock.strip.items = dock.three; dock.strip.layoutSubtreeIfNeeded()
        #expect(extra.superview == nil && zip(dock.three, dock.regular.items).allSatisfy { Self.near($0.frame, $1) })
    }

    @Test func theSelectionFollowsItsItem() {
        let dock = Dock()
        dock.strip.selectedIndex = 2
        dock.reset(dock.three)
        dock.strip.items = Array(dock.three.dropFirst()); dock.strip.layoutSubtreeIfNeeded()
        #expect(dock.strip.selectedIndex == 1 && dock.sets([dock.three[2]])[0].isEmpty)
    }

    @Test func theOwnersMatchingIndexRestylesNothing() {
        let dock = Dock()
        dock.strip.selectedIndex = 2
        dock.reset(dock.three)
        dock.strip.items = Array(dock.three.dropFirst()); dock.strip.layoutSubtreeIfNeeded()
        dock.strip.selectedIndex = 1
        #expect(dock.sets([dock.three[2]])[0].isEmpty && dock.three[2].alphaValue == 1)
    }

    @Test func aRemovedSelectionLeavesNone() {
        let dock = Dock()
        dock.strip.selectedIndex = 2
        dock.strip.items = Array(dock.three.dropFirst())
        dock.strip.items = [dock.three[1]]
        #expect(dock.strip.selectedIndex == nil)
    }

    @Test func theSuccessorOfARemovedSelectionCrossFades() {
        let dock = Dock(animated: true)
        dock.strip.selectedIndex = 2
        dock.strip.items = Array(dock.three.dropFirst())
        dock.strip.items = [dock.three[1]]
        dock.reset(dock.three)
        dock.strip.selectedIndex = 0
        let sets = dock.sets([dock.three[1]])[0]
        #expect(sets.map(\.value) == [1] && sets.allSatisfy { $0.duration > 0 })
    }

    private func compact() -> (Dock, [NSButton]) {
        let dock = Dock()
        let eight = Dock.buttons(8)
        dock.strip.items = eight; dock.strip.selectedIndex = 3
        dock.strip.layoutSubtreeIfNeeded()
        return (dock, eight)
    }

    @Test func replacedItemsLeaveTheStrip() {
        let (dock, _) = compact()
        #expect(dock.three.allSatisfy { $0.superview == nil })
    }

    @Test func eightSpacesUseTheDotStyleWithTheFocusedSelection() {
        let (dock, eight) = compact()
        let layout = dock.strip.layoutState
        #expect(layout.compact && layout.items[3].width == 22)
        #expect(zip(eight, layout.items).allSatisfy { Self.near($0.frame, $1) })
    }

    @Test func onlyTheSelectedIconIsDrawnInTheDotStyle() {
        let (_, eight) = compact()
        #expect(eight.enumerated().allSatisfy { $0.offset == 3 ? $0.element.alphaValue == 1 : $0.element.alphaValue == 0 })
    }

    @Test func eachItemHasADotAndABackground() {
        let (dock, _) = compact()
        #expect(dock.dots.count == 8 && dock.backgrounds.count == 8)
    }

    @Test(arguments: 0..<8)
    func eachDotIsACentredFourPointDotAtHalfExceptTheSelectedOnesHidden(_ index: Int) {
        let (dock, _) = compact()
        let dot = dock.dots[index], item = dock.strip.layoutState.items[index]
        if index == 3 {
            #expect(dot.alphaValue == 0 && dot.frame.width == 8)
        } else {
            #expect(dot.alphaValue == 0.5 && dot.frame.size == CGSize(width: 4, height: 4))
            #expect(abs(dot.frame.midX - item.midX) <= 0.5 && abs(dot.frame.midY - item.midY) <= 0.5 && dot.layer?.cornerRadius == 2)
        }
    }

    @Test func theDotStyleHasNoHoverBackground() {
        #expect(compact().0.backgrounds.allSatisfy { $0.alphaValue == 0 })
    }

    @Test func theDotNeverTakesTheSpacesClick() {
        let (dock, eight) = compact()
        let item = dock.strip.layoutState.items[0]
        let center = dock.strip.convert(NSPoint(x: item.midX, y: item.midY), from: dock.strip.documentView)
        #expect(dock.host.hitTest(dock.strip.convert(center, to: dock.host)) === eight[0])
    }

    @Test func dotsKeepTheSpaceButtonsAccessibleInOrder() {
        let (dock, eight) = compact()
        #expect(eight.allSatisfy { !$0.isHidden && $0.cell?.accessibilityRoleDescription() == "Space" })
        #expect(dock.titles == (0..<8).map { "Space \($0)" })
    }

    private func overflowing() -> (Dock, [NSButton]) {
        let dock = Dock()
        let many = Dock.buttons(30)
        dock.strip.items = many; dock.strip.selectedIndex = nil; dock.strip.layoutSubtreeIfNeeded()
        dock.strip.selectedIndex = 29
        return (dock, many)
    }

    @Test func thirtySpacesOverflowTheStrip() {
        let (dock, _) = overflowing()
        #expect(dock.strip.layoutState.contentWidth > 144 && dock.strip.documentView!.frame.width == dock.strip.layoutState.contentWidth)
        #expect(dock.strip.overflows)
    }

    @Test func theLastSelectionScrollsToTheEnd() {
        let (dock, _) = overflowing()
        #expect(abs(dock.strip.contentView.bounds.minX - (dock.strip.layoutState.contentWidth + 2 - 148)) < 0.5)
    }

    @Test func aLaterSelectionScrollsBackToTheLeadingInset() {
        let (dock, _) = overflowing()
        dock.strip.selectedIndex = 0
        #expect(abs(dock.strip.contentView.bounds.minX + 2) < 0.5)
    }

    @Test func aMiddleSelectionIsCentred() {
        let (dock, _) = overflowing()
        dock.strip.selectedIndex = 0
        dock.strip.selectedIndex = 15
        #expect(abs(dock.strip.contentView.bounds.midX - dock.strip.layoutState.items[15].midX) <= 0.5)
    }

    @Test func anItemScrolledOutOfTheStripIsNotHovered() {
        let (dock, many) = overflowing()
        dock.strip.selectedIndex = 15
        dock.hover(0)
        #expect(many[0].alphaValue == 0)
    }

    @Test func aVisibleCompactItemShowsItsIconWhileHovered() {
        let (dock, many) = overflowing()
        dock.strip.selectedIndex = 15
        dock.hover(14)
        #expect(abs(many[14].alphaValue - 0.7) < 0.001)
    }

    private static func sideways() -> NSEvent {
        NSEvent(cgEvent: CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 0, wheel2: -3, wheel3: 0)!)!
    }

    @Test func anOverflowingStripKeepsTheSwipeForItsOwnScrolling() {
        let (dock, _) = overflowing()
        dock.strip.selectedIndex = 15
        var offered = 0
        dock.strip.offerScroll = { _ in offered += 1; return true }
        dock.strip.scrollWheel(with: Self.sideways())
        #expect(offered == 0)
    }

    @Test func aStripThatFitsHandsTheSwipeToThePager() {
        let dock = Dock()
        var offered = 0
        dock.strip.offerScroll = { _ in offered += 1; return true }
        let resting = dock.strip.contentView.bounds.origin
        #expect(!dock.strip.overflows)
        dock.strip.scrollWheel(with: Self.sideways())
        #expect(offered == 1 && dock.strip.contentView.bounds.origin == resting)
    }
}
