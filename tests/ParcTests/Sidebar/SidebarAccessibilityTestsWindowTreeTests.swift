import AppKit
import Testing
@testable import Parc
@testable import ParcKit
@testable import ParcSidebar

@MainActor
struct SidebarAccessibilityTestsWindowTreeTests {
    private typealias Region = SidebarAccessibilityTestsSupport.Region

    @Test func theResizeStripIsNotAnAccessibilityElementAndIsAbsentFromTheTree() {
        let r = Region()
        let container = NSView(frame: r.root.bounds)
        container.setAccessibilityElement(true)
        container.setAccessibilityRole(.group)
        let strip = SidebarResizeRegionView(frame: SidebarResizeRegionView.frame(trailing: NSRect(x: 0, y: 0, width: 228, height: 400), in: r.root.bounds))
        let toggle = NSButton(title: "Hide sidebar", target: nil, action: nil)
        container.addSubview(strip)
        container.addSubview(toggle)
        r.root.addSubview(container)
        let children = container.accessibilityChildren() as? [NSObject] ?? []
        #expect(!strip.isAccessibilityElement())
        #expect([nil, .unknown].contains(strip.accessibilityRole()))
        #expect(!children.contains { $0 === strip })
        #expect(children.contains { $0 === toggle || $0 === toggle.cell })
        #expect(strip.accessibilityHitTest(NSPoint(x: strip.frame.midX, y: strip.frame.midY)).map { $0 as AnyObject !== strip } ?? true)
    }

    @MainActor private final class Header {
        let browser = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 900, height: 600),
                               styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        let sidebar = NSView(frame: NSRect(x: 0, y: 0, width: 228, height: 600))
        let address = ActionButton("Address", symbol: "magnifyingglass")
        let lights = WindowStandardButtons()
        let back = ActionButton(SidebarAccessibility.goBack, symbol: "arrow.left")
        let forward = ActionButton(SidebarAccessibility.goForward, symbol: "arrow.right")
        let reload = ActionButton(SidebarAccessibility.reload, symbol: "arrow.clockwise")
        let footer = ActionButton("Space actions", symbol: "ellipsis")
        let headerToggle = ActionButton(SidebarAccessibility.hideSidebar, symbol: "sidebar.left")

        init() {
            browser.isReleasedWhenClosed = false
            let surface = NSView(frame: sidebar.bounds)
            surface.addSubview(address)
            sidebar.addSubview(surface)
            for view in [lights, back, forward, reload, footer, headerToggle] { sidebar.addSubview(view) }
            browser.contentView?.addSubview(sidebar)
        }

        deinit { MainActor.assumeIsolated { browser.close() } }

        func owner(_ element: Any) -> NSView? { (element as? NSView) ?? (element as? NSCell)?.controlView }
        var header: [NSView] { [lights, headerToggle, back, forward, reload] }
    }

    @Test func appKitAloneListsTheContentSurfaceFirst() {
        let h = Header()
        #expect((h.sidebar.accessibilityChildren() ?? []).first.flatMap(h.owner) === h.address)
    }

    @Test func reorderingKeepsEveryElement() {
        let h = Header()
        let natural = h.sidebar.accessibilityChildren() ?? []
        let ordered = SidebarAccessibility.headerFirst(natural, header: h.header)
        #expect(h.lights.buttons.count == 3)
        #expect(ordered.count == natural.count)
    }

    @Test func lightsToggleBackForwardReloadThenTheRestInSubviewOrder() {
        let h = Header()
        let ordered = SidebarAccessibility.headerFirst(h.sidebar.accessibilityChildren() ?? [], header: h.header)
        #expect(ordered.compactMap(h.owner) == h.lights.buttons + [h.headerToggle, h.back, h.forward, h.reload, h.address, h.footer])
    }

    @Test func theTreeOpensWithAXCloseButtonAndAXMinimizeButton() {
        let h = Header()
        let ordered = SidebarAccessibility.headerFirst(h.sidebar.accessibilityChildren() ?? [], header: h.header)
        #expect(ordered.prefix(2).compactMap { $0 as? NSCell }.map { $0.accessibilitySubrole() } == [.closeButton, .minimizeButton])
    }

    @Test func theTrafficLightsAreNoKeyboardStops() {
        let h = Header()
        #expect(h.lights.buttons.allSatisfy { $0.refusesFirstResponder && !$0.acceptsFirstResponder && !$0.canBecomeKeyView })
        #expect(SidebarAccessibility.keyViews(in: [h.lights], space: h.sidebar).isEmpty)
    }

    @Test func withoutItsLightsTheHeaderLeadsWithTheToggle() {
        let h = Header()
        _ = h.lights.buttons
        h.lights.isHidden = true
        let ordered = SidebarAccessibility.headerFirst(h.sidebar.accessibilityChildren() ?? [], header: h.header)
        #expect(ordered.first.flatMap(h.owner) === h.headerToggle)
    }

    @Test func aNarrowHeaderOrdersItsVisibleControlsByFrame() {
        let h = Header()
        h.back.frame.origin.x = 70
        h.forward.frame.origin.x = 104
        h.headerToggle.frame.origin.x = 138
        h.reload.isHidden = true
        #expect(SidebarAccessibility.laidOut([h.headerToggle, h.back, h.forward, h.reload]) == [h.back, h.forward, h.headerToggle])
    }

    @Test func aNarrowHeadersTreeFollowsTheFrames() {
        let h = Header()
        h.back.frame.origin.x = 70
        h.forward.frame.origin.x = 104
        h.headerToggle.frame.origin.x = 138
        h.reload.isHidden = true
        let narrow = SidebarAccessibility.laidOut([h.headerToggle, h.back, h.forward, h.reload])
        let tree = SidebarAccessibility.headerFirst(h.sidebar.accessibilityChildren() ?? [], header: [h.lights] + narrow)
        #expect(Array(tree.compactMap(h.owner).prefix(6)) == h.lights.buttons + [h.back, h.forward, h.headerToggle])
    }

    @Test func theBackPointerRecordsTheLastViewLinked() {
        let (first, second, member) = (NSView(), NSView(), NSView())
        first.nextKeyView = member
        second.nextKeyView = member
        #expect(member.previousKeyView === second)
    }

    @Test func theBackPointerSurvivesWhenItsViewLinksElsewhere() {
        let (first, second, member, elsewhere) = (NSView(), NSView(), NSView(), NSView())
        first.nextKeyView = member
        second.nextKeyView = member
        second.nextKeyView = elsewhere
        #expect(member.previousKeyView === second)
        #expect(first.nextKeyView === member)
    }
}
