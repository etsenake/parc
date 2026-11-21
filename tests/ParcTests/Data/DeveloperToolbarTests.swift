import AppKit
import Testing
@testable import Parc

struct DeveloperToolbarTests {
    private func layout(_ width: CGFloat, blocked: Bool = false) -> DeveloperToolbarLayout.Frames {
        DeveloperToolbarLayout.frames(in: CGRect(x: 0, y: 0, width: width, height: 40),
                                      blockedTitleRoom: blocked ? 60 : nil)
    }

    @Test func aWideToolbarLeavesRoomForAllItsControls() {
        let wide = layout(900)

        #expect(wide.siteInfo == CGRect(x: 8, y: 6, width: 28, height: 28))
        #expect(wide.hiddenTrailing.allSatisfy { !$0 })
        #expect(wide.trailing.allSatisfy { $0.size == CGSize(width: 28, height: 28) })
        #expect(wide.trailing.last?.maxX == 895)
        #expect(wide.address.minX == 44)
        #expect(wide.address.height == 40)
        #expect(wide.address.maxX <= wide.trailing[0].minX)
    }

    @Test(arguments: [900, 200])
    func captureAndConsoleKeepTheirDividerOnlyWhileBothFit(_ width: Int) {
        let frames = layout(CGFloat(width))
        let bothVisible = !frames.hiddenTrailing[2] && !frames.hiddenTrailing[3]

        if bothVisible {
            #expect(frames.divider.size == CGSize(width: 1.5, height: 20))
            #expect(frames.divider.minX - frames.trailing[2].maxX == 7.5)
            #expect(frames.trailing[3].minX - frames.divider.maxX == 7.5)
        } else {
            #expect(frames.divider.isEmpty)
        }
    }

    @Test func controlsCollapseFromTheInsideToLeaveRoomForTheAddress() {
        let narrow = layout(200)

        #expect(narrow.siteInfo.width == 28)
        #expect(narrow.address.width + 0.5 >= DeveloperToolbarLayout.addressMinWidth)
        #expect(narrow.hiddenTrailing[0])
        #expect(!narrow.hiddenTrailing[7])
        #expect(narrow.trailing[7].width == 28)
    }

    @Test func aVeryNarrowToolbarKeepsTheLeadingSiteControl() {
        let frames = layout(80)

        #expect(frames.siteInfo.origin == CGPoint(x: 8, y: 6))
        #expect(frames.hiddenTrailing.filter { !$0 }.count <= 1)
    }

    @Test(arguments: [(false, 0.3), (true, 0.02)])
    func theStripeOverlayFollowsTheAppearance(_ isDark: Bool, _ alpha: Double) {
        #expect(DeveloperToolbarLayout.stripeForegroundAlpha(isDark: isDark) == CGFloat(alpha))
    }

    @Test func stripesRepeatWithoutGapsBeyondTheirSpecifiedSpacing() throws {
        let origins = DeveloperToolbarLayout.stripeOrigins(width: 90, height: 40)
        let first = try #require(origins.first)
        let second = try #require(origins.dropFirst().first)

        #expect(second - first == DeveloperToolbarLayout.stripeBarWidth + DeveloperToolbarLayout.stripeBarSpacing)
        #expect(origins.last.map { $0 + DeveloperToolbarLayout.stripeBarWidth >= 90 } == true)
    }

    @Test func theBlockedSignUsesAddressRoomWhenTheToolbarIsWide() throws {
        let plain = layout(900)
        let signed = layout(900, blocked: true)
        let sign = try #require(signed.blocked)

        #expect(plain.blocked == nil)
        #expect(signed.hiddenTrailing == plain.hiddenTrailing)
        #expect(signed.trailing[7] == plain.trailing[7])
        #expect(signed.trailing[6] == plain.trailing[6])
        #expect(sign.size == CGSize(width: 28, height: 28))
        #expect(sign.maxX == signed.trailing[6].minX)
        #expect(sign.minX == signed.trailing[5].maxX)
        #expect(signed.address.width == plain.address.width - sign.width)
    }

    @Test(arguments: [80, 200, 370, 520])
    func aBlockedSignOnlyUsesAvailableRoomOrTheSiteControlsSlot(_ width: Int) {
        let plain = layout(CGFloat(width))
        let signed = layout(CGFloat(width), blocked: true)

        #expect(signed.hiddenTrailing.enumerated().allSatisfy { index, hidden in
            index == 6 || hidden == plain.hiddenTrailing[index]
        })
        guard let sign = signed.blocked else {
            #expect(signed == plain)
            return
        }
        #expect(signed.address.width + 0.5 >= 60)
        #expect(sign.minX >= signed.address.maxX)
        #expect(sign.maxX <= CGFloat(width) - 5)
        if signed.hiddenTrailing[6] && !plain.hiddenTrailing[6] {
            #expect(sign == plain.trailing[6])
            #expect(signed.address == plain.address)
        }
    }

    @MainActor
    private final class InertWindow: NSWindow {
        override var isKeyWindow: Bool { true }
        override var canBecomeKey: Bool { true }
    }

    @MainActor @Test func theFirstEditSelectsTheAddressOnTheScheduledTurn() throws {
        _ = NSApplication.shared
        let window = InertWindow(contentRect: CGRect(x: 0, y: 0, width: 240, height: 48),
                                 styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let field = NSTextField(frame: CGRect(x: 8, y: 8, width: 200, height: 22))
        field.stringValue = "https://localhost/"
        window.contentView?.addSubview(field)
        #expect(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor())
        editor.selectedRange = NSRange(location: 3, length: 0)
        var next: (@MainActor () -> Void)?

        DeveloperToolbarLayout.scheduleFirstEditSelection(field) { next = $0 }
        #expect(editor.selectedRange == NSRange(location: 3, length: 0))
        let select = try #require(next)
        select()

        #expect(editor.selectedRange == NSRange(location: 0, length: field.stringValue.utf16.count))
    }

    @Test(arguments: [(0, 0, true), (0, 40, false), (40, 40, true), (40, 40, false)])
    func paneChromeIsCurrentWhenItsFramesMatchItsVisibleStrips(_ barHeight: Int, _ expectedHeight: Int, _ matches: Bool) {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let frame = CGRect(x: 0, y: 0, width: 800, height: barHeight)
        let browser = CGRect(x: 0, y: 0, width: 800, height: 0)
        let content = CGRect(x: 0, y: barHeight, width: !matches && barHeight == expectedHeight ? 790 : 800,
                             height: 600 - barHeight)

        #expect(DeveloperChromeGeometry.paneIsCurrent(bounds: bounds, developerHeight: CGFloat(expectedHeight),
            browserHeight: 0, developerFrame: frame, browserFrame: browser, contentFrame: content) == matches)
    }

    @Test(arguments: [(0, 0, true), (0, 40, false), (40, 40, true)])
    func peekChromeIsCurrentWhenItsFramesMatchItsVisibleStrip(_ barHeight: Int, _ expectedHeight: Int, _ matches: Bool) {
        let card = CGRect(x: 100, y: 12, width: 800, height: 676)
        let frame = CGRect(x: 0, y: 0, width: 800, height: barHeight)
        let browser = CGRect(x: 0, y: 0, width: 800, height: 0)
        let content = CGRect(x: 0, y: barHeight, width: 800, height: 676 - barHeight)

        #expect(DeveloperChromeGeometry.peekIsCurrent(card: card, developerHeight: CGFloat(expectedHeight),
            browserHeight: 0, developerFrame: frame, browserFrame: browser, contentFrame: content) == matches)
    }
}
