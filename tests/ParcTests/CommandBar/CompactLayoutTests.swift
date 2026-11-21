import AppKit
import Testing
@testable import Parc

struct CompactLayoutTests {
    private typealias Layout = CommandBarCompactLayout

    @Test(arguments: [
        (false, 1200.0, 1440.0, 450.0), (true, 1200, 1440, 350),
        (true, 300, 1440, 284), (false, 420, 1440, 404), (false, 1200, 400, 384), (true, 12, 1440, 0),
    ])
    func theEditorFitsItsWindowAndScreen(popup: Bool, windowWidth: Double, screenWidth: Double, expected: Double) {
        let window = CGRect(x: 0, y: 0, width: windowWidth, height: 500)
        let screen = CGRect(x: 0, y: 0, width: screenWidth, height: 800)
        #expect(Layout.width(popup: popup, window: window, screen: screen) == CGFloat(expected))
    }

    @Test(arguments: [(140.0, 140.0), (800.0, 642.0), (101.0, 108.0)])
    func theEditorSlidesInsideItsWindow(anchor: Double, expected: Double) {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let window = CGRect(x: 100, y: 80, width: 1000, height: 800)
        #expect(Layout.originX(anchor: anchor, width: 450, window: window, screen: screen) == CGFloat(expected))
    }

    @Test(arguments: [36.0, 31.0])
    func theInputRowKeepsTheAddressPillBaseline(pillHeight: Double) {
        let anchor = CGRect(x: 120, y: 640, width: 222, height: pillHeight)
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let y = Layout.originY(anchor: anchor, height: 309, lift: Layout.lift(anchorHeight: anchor.height), screen: screen)
        let panelTop = y + 309
        let icon = Layout.iconFrame(centre: Layout.headerCentre)
        let text = Layout.inputFrame(width: 450, centre: Layout.headerCentre)
        #expect(panelTop - icon.midY == anchor.midY)
        #expect(panelTop - text.minY - Layout.textLineHeight / 2 == anchor.midY)
    }

    @Test @MainActor func theHeaderUsesTheSameIconAndTitleColumnsAsResults() throws {
        _ = NSApplication.shared
        let title = "Example page"
        let icon = try #require(NSImage(systemSymbolName: "clock", accessibilityDescription: nil))
        let row = CommandResultCell(title: title, detail: "", accessory: "", isTab: false, icon: icon, enabled: true)
        row.frame = NSRect(x: 0, y: 0, width: 450 - 2 * Layout.listInset, height: 50)
        row.layoutSubtreeIfNeeded()
        let label = try #require(CommandBarTestSupport.labels(in: row).first { $0.stringValue == title })
        let image = try #require(row.subviews.compactMap { $0 as? NSImageView }.first)
        #expect(Layout.textX == Layout.listInset + label.frame.minX)
        #expect(Layout.iconX == Layout.listInset + image.frame.minX)
        #expect(Layout.iconSize == image.frame.width)
    }

    @MainActor private final class Window: NSWindow {
        override var isKeyWindow: Bool { true }
    }

    @MainActor private final class Fixture {
        let window: Window
        let content: NSView
        let anchor = NSView(frame: NSRect(x: 14, y: 310, width: 200, height: 36))
        let pillIcon = SidebarAddressSearchIcon(frame: NSRect(x: 9, y: 11, width: 14, height: 14))
        let bar: CommandBar

        init(compact: Bool, reduceMotion: Bool, width: CGFloat = 600) throws {
            _ = NSApplication.shared
            let owner = Window(contentRect: NSRect(x: 100, y: 100, width: width, height: 500),
                               styleMask: .borderless, backing: .buffered, defer: false)
            owner.isReleasedWhenClosed = false
            let content = try #require(owner.contentView)
            content.addSubview(anchor)
            anchor.addSubview(pillIcon)
            window = owner
            self.content = content
            let defaults = try #require(UserDefaults(suiteName: "Parc.CompactLayoutTests." + UUID().uuidString))
            bar = CommandBar(parent: owner, tabs: [], history: [], currentURL: nil, profilePath: "", page: nil,
                sidebarAnchor: compact ? anchor : nil, addressOnly: compact,
                shortcuts: KeyboardShortcuts(mainMenu: { nil }, observesKeyboardLayout: false),
                privacyDefaults: defaults, makeOmnibox: { _, _, _ in nil }, loadFavicon: { _, _, _ in },
                reduceMotion: { reduceMotion })
            bar.present()
            content.layoutSubtreeIfNeeded()
        }

        func surface() throws -> PopoverBackgroundView {
            try #require(content.subviews.last?.subviews.compactMap { $0 as? PopoverBackgroundView }.first)
        }

        func input() throws -> CommandBarInputField {
            try #require(try surface().subviews.compactMap { $0 as? CommandBarInputField }.first)
        }
    }

    @Test(arguments: [(true, 450.0), (false, 552.0)])
    @MainActor func anAddressAnchorSelectsTheCompactSurface(compact: Bool, expected: Double) throws {
        let fixture = try Fixture(compact: compact, reduceMotion: true)
        defer { fixture.bar.dismiss(restoreFocus: false) }
        let surface = try fixture.surface()
        #expect(surface.frame.width == CGFloat(expected))
    }

    @Test @MainActor func theAttachedEditorStaysInsideItsOriginalWindow() throws {
        let fixture = try Fixture(compact: true, reduceMotion: true, width: 300)
        defer { fixture.bar.dismiss(restoreFocus: false) }
        let surface = try fixture.surface()
        #expect(fixture.content.bounds.contains(surface.frame))
        #expect(surface.frame.width == 284)
    }

    @Test(arguments: [false, true])
    @MainActor func thePillGlidesOnlySidewaysWhenMotionIsAllowed(reduceMotion: Bool) throws {
        let fixture = try Fixture(compact: true, reduceMotion: reduceMotion)
        defer { fixture.bar.dismiss(restoreFocus: false) }
        let input = try fixture.input()
        let animation = input.layer?.animation(forKey: "pillGlide") as? CABasicAnimation
        if reduceMotion {
            #expect(animation == nil)
        } else {
            let animation = try #require(animation)
            #expect(animation.keyPath == "transform.translation.x")
            #expect(animation.toValue as? Double == 0)
            #expect(animation.duration == 0.15)
        }
    }

    @Test @MainActor func theHeaderFollowsChangesInScrollerWidth() throws {
        let fixture = try Fixture(compact: true, reduceMotion: true)
        defer { fixture.bar.dismiss(restoreFocus: false) }
        let surface = try fixture.surface()
        let scroll = try #require(surface.subviews.compactMap { $0 as? CommandResultsScrollView }.first)
        let input = try fixture.input()
        scroll.scrollerStyle = .overlay
        scroll.tile()
        surface.layoutSubtreeIfNeeded()
        let noReserve = input.frame
        scroll.scrollerStyle = .legacy
        scroll.tile()
        surface.layoutSubtreeIfNeeded()
        #expect(scroll.scrollerReserve > 0)
        #expect(input.frame.minX == noReserve.minX)
        #expect(input.frame.maxX == noReserve.maxX - scroll.scrollerReserve)
    }
}

extension CompactLayoutTests {
    @Test @MainActor func theKeyboardAddressCommandHasNoCompactEditorAnchor() {
        #expect(CommandBarAddressSource.keyboard.anchor == nil)
    }

    @Test(arguments: [false, true])
    @MainActor func pressingAddressChromeProvidesThatControlsAnchor(popup: Bool) throws {
        _ = NSApplication.shared
        let sidebar = SidebarView(frame: .zero)
        let popupChrome = PopupChromeView(frame: .zero)
        var anchors: [NSView] = []
        let focus: (CommandBarAddressSource) -> Void = { source in
            if let anchor = source.anchor { anchors.append(anchor) }
        }
        CommandBarAddressSource.connect(sidebar, focus: focus)
        CommandBarAddressSource.connect(popupChrome, focus: focus)
        let expected = popup ? popupChrome.addressAnchor : sidebar.addressEditorAnchor
        let button = try #require(expected as? ActionButton)
        let press = try #require(button.actionBlock)
        press()
        #expect(anchors == [expected])
    }

    @Test(arguments: [false, true])
    @MainActor func aClickSelectsThePaneUsedByAddressEditing(clickTrailing: Bool) throws {
        let window = CommandBarTestSupport.borderlessWindow(width: 600)
        let content = try #require(window.contentView)
        let leading = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 250))
        let trailing = NSView(frame: NSRect(x: 300, y: 0, width: 280, height: 250))
        content.addSubview(leading)
        content.addSubview(trailing)
        let first = UUID(), second = UUID()
        let clicked = clickTrailing ? trailing : leading
        let point = clicked.convert(NSPoint(x: 40, y: 40), to: nil)
        var focused: UUID? = clickTrailing ? first : second
        WindowPaneFocus.visitHits(at: point, panes: [first: leading, second: trailing],
                                  isRendered: { $0 == first || $0 == second }) { focused = $0 }
        let target = WindowPaneFocus.currentTab(fullscreen: nil, focused: focused, selection: [first, second])
        #expect(target == (clickTrailing ? second : first))
    }
}
