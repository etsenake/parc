import AppKit

@MainActor private final class InertWindow: NSWindow {
    var key = true
    override var isKeyWindow: Bool { key }
    override var canBecomeKey: Bool { true }
}

@main
struct DeveloperToolbarTests {
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor
    static func runChecks() {
        _ = NSApplication.shared
        var assertions = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            assertions += 1
            precondition(condition(), message)
        }

        expect(DeveloperToolbarLayout.height == 40, "Recovered panel height 40")
        expect(DeveloperToolbarLayout.leadingInset == 8, "Recovered leading inset 8")
        expect(DeveloperToolbarLayout.trailingInset == 5, "Recovered trailing inset 5")
        expect(DeveloperToolbarLayout.buttonSize == 28, "Recovered control size 28")
        expect(DeveloperToolbarLayout.stripeDegrees == -45, "Recovered stripe rotation -45")
        expect(DeveloperToolbarLayout.stripeBarWidth == 15, "Recovered barWidth 15")
        expect(DeveloperToolbarLayout.stripeBarSpacing == 15, "Recovered barSpacing 15")
        expect(DeveloperToolbarLayout.stripeForegroundAlpha(isDark: false) == 0.3,
               "Light stripe overlay is white at 0.3")
        expect(DeveloperToolbarLayout.stripeForegroundAlpha(isDark: true) == 0.02,
               "Dark stripe overlay is white at 0.02")
        expect(DeveloperToolbarLayout.dividerWidth == 1.5 && DeveloperToolbarLayout.dividerHeight == 20
                && DeveloperToolbarLayout.dividerPadding == 7.5,
               "Recovered 1.5×20 divider with 7.5 padding")

        let wide = DeveloperToolbarLayout.frames(in: NSRect(x: 0, y: 0, width: 900, height: 40))
        expect(wide.siteInfo == NSRect(x: 8, y: 6, width: 28, height: 28),
               "Site Settings sits 8 in and vertically centered")
        expect(wide.hiddenTrailing.allSatisfy { !$0 }, "A wide strip keeps every trailing control")
        expect(wide.trailing.count == 8 && wide.trailing.allSatisfy { $0.width == 28 && $0.height == 28 },
               "Trailing controls stay 28×28")
        expect(abs(wide.trailing[7].maxX - (900 - 5)) < 0.01, "Split sits 5 points from the trailing edge")
        expect(wide.divider.width == 1.5 && wide.divider.height == 20,
               "Capture and Console keep the recovered divider")
        expect(abs(wide.trailing[2].maxX + 7.5 - wide.divider.minX) < 0.01
                && abs(wide.divider.maxX + 7.5 - wide.trailing[3].minX) < 0.01,
               "Divider sits between Capture and Console with 7.5-point padding")
        expect(wide.address.minX == 8 + 28 + 8 && wide.address.height == 40
                && wide.address.maxX <= wide.trailing[0].minX,
               "Address fills the center stack at full strip height")

        let origins = DeveloperToolbarLayout.stripeOrigins(width: 90, height: 40)
        expect(origins.count >= 3, "Stripe origins cover the strip plus slant overrun")
        if origins.count >= 2 {
            expect(abs((origins[1] - origins[0]) - 30) < 0.01, "Stripe period is barWidth + barSpacing")
        }

        let narrow = DeveloperToolbarLayout.frames(in: NSRect(x: 0, y: 0, width: 200, height: 40))
        expect(narrow.siteInfo.width == 28, "Narrow layout keeps the 28-point lock")
        expect(narrow.address.width + 0.5 >= DeveloperToolbarLayout.addressMinWidth,
               "Address keeps a hittable width after trailing collapse")
        expect(narrow.hiddenTrailing.contains(true), "Trailing controls yield before shrinking below the floor")
        expect(narrow.hiddenTrailing[0] && !narrow.hiddenTrailing[7],
               "Copy (inner) hides before Split (outer) remains")
        expect(narrow.trailing[7].width == 28, "Visible Split stays 28 points; it is not compacted to 24")
        expect(!narrow.hiddenTrailing.allSatisfy { $0 } || narrow.address.width >= 20,
               "Collapse stops once the address has room or only the lock remains")
        if !narrow.hiddenTrailing[2] && !narrow.hiddenTrailing[3] {
            expect(abs(narrow.trailing[2].maxX + 7.5 - narrow.divider.minX) < 0.01
                    && abs(narrow.divider.maxX + 7.5 - narrow.trailing[3].minX) < 0.01,
                   "Visible Capture and Console still sandwich the divider")
        } else {
            expect(narrow.divider.width < 0.5, "Divider hides when Capture or Console yields")
        }

        expect(wide.blocked == nil, "No blocked sign without blocked content")
        let signed = DeveloperToolbarLayout.frames(in: NSRect(x: 0, y: 0, width: 900, height: 40), blockedTitleRoom: 60)
        expect(signed.hiddenTrailing.allSatisfy { !$0 } && signed.trailing[7] == wide.trailing[7]
                && signed.trailing[6] == wide.trailing[6],
               "The blocked sign leaves Extensions and Split in place")
        expect(signed.blocked.map { abs($0.maxX - signed.trailing[6].minX) < 0.01 && $0.size == NSSize(width: 28, height: 28) } == true,
               "The blocked sign sits right before the Site Control Center button")
        expect(signed.blocked.map { abs(signed.trailing[5].maxX - $0.minX) < 0.01 } == true,
               "Inspect Element sits right before the blocked sign")
        expect(abs(signed.address.width - (wide.address.width - 28)) < 0.01, "The blocked sign takes its width from the address")
        for width in stride(from: CGFloat(60), through: 520, by: 1) {
            let bounds = NSRect(x: 0, y: 0, width: width, height: 40)
            let plain = DeveloperToolbarLayout.frames(in: bounds)
            let frames = DeveloperToolbarLayout.frames(in: bounds, blockedTitleRoom: 60)
            expect(frames.hiddenTrailing.enumerated().allSatisfy { $0.offset == 6 || $0.element == plain.hiddenTrailing[$0.offset] },
                   "The blocked sign never hides another trailing control at \(width)")
            guard let blocked = frames.blocked else {
                expect(frames == plain, "Without room, the strip lays out as if nothing was blocked at \(width)")
                continue
            }
            expect(frames.address.width + 0.5 >= 60, "The blocked sign leaves the address 60 points at \(width)")
            expect(blocked.maxX <= width - 5 + 0.01 && blocked.minX >= frames.address.maxX - 0.01,
                   "The blocked sign stays between the address and the trailing edge at \(width)")
            if frames.hiddenTrailing[6] && !plain.hiddenTrailing[6] {
                expect(blocked == plain.trailing[6] && frames.address == plain.address,
                       "A narrow strip gives the blocked sign the Site Control Center button's place at \(width)")
            }
        }

        let squeezed = DeveloperToolbarLayout.frames(in: NSRect(x: 0, y: 0, width: 80, height: 40))
        expect(squeezed.siteInfo.origin == NSPoint(x: 8, y: 6), "The lock remains at the recovered origin")
        expect(squeezed.hiddenTrailing.filter { !$0 }.count <= 1,
               "A very narrow strip hides the inner trailing cluster")

        let window = InertWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 48),
                                 styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let field = NSTextField(frame: NSRect(x: 8, y: 8, width: 200, height: 22))
        field.stringValue = "https://localhost/"
        window.contentView?.addSubview(field)
        expect(window.makeFirstResponder(field), "Inert window can focus the address field")
        DeveloperToolbarLayout.scheduleFirstEditSelection(field)
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        let selected = field.currentEditor()?.selectedRange
        expect(selected?.location == 0 && selected?.length == field.stringValue.utf16.count,
               "First-edit selects the whole address on the next main-queue turn")
        window.close()

        let paneBounds = NSRect(x: 0, y: 0, width: 800, height: 600)
        let zeroBar = NSRect(x: 0, y: 0, width: 800, height: 0)
        let hiddenCurrent = DeveloperChromeGeometry.paneIsCurrent(
            bounds: paneBounds, developerHeight: 0, browserHeight: 0,
            developerFrame: zeroBar, browserFrame: zeroBar,
            contentFrame: paneBounds)
        expect(hiddenCurrent, "hidden pane strips with full-bleed content are current")
        expect(!DeveloperChromeGeometry.paneIsCurrent(
            bounds: paneBounds, developerHeight: 0, browserHeight: 0,
            developerFrame: .zero, browserFrame: .zero,
            contentFrame: paneBounds),
               "unlaid-out zero frames are not current (first attach still flushes)")
        let shownDev = DeveloperToolbarLayout.height
        let shownBar: CGFloat = 32
        let header = max(shownDev, shownBar)
        let afterShow = DeveloperChromeGeometry.paneIsCurrent(
            bounds: paneBounds, developerHeight: shownDev, browserHeight: 0,
            developerFrame: zeroBar, browserFrame: zeroBar,
            contentFrame: paneBounds)
        expect(!afterShow, "newly shown developer strip is not current until laid out")
        let laidOut = DeveloperChromeGeometry.paneIsCurrent(
            bounds: paneBounds, developerHeight: shownDev, browserHeight: shownBar,
            developerFrame: NSRect(x: 0, y: 0, width: 800, height: shownDev),
            browserFrame: NSRect(x: 0, y: 0, width: 800, height: shownBar),
            contentFrame: NSRect(x: 0, y: header, width: 800, height: 600 - header))
        expect(laidOut, "matching pane strip and content frames are current")
        let moved = DeveloperChromeGeometry.paneIsCurrent(
            bounds: paneBounds, developerHeight: shownDev, browserHeight: shownBar,
            developerFrame: NSRect(x: 0, y: 0, width: 800, height: shownDev),
            browserFrame: NSRect(x: 0, y: 0, width: 800, height: shownBar),
            contentFrame: NSRect(x: 0, y: header, width: 790, height: 600 - header))
        expect(!moved, "a content frame change is not current")

        let card = NSRect(x: 100, y: 12, width: 800, height: 676)
        let peekZero = NSRect(x: 0, y: 0, width: card.width, height: 0)
        let peekHidden = DeveloperChromeGeometry.peekIsCurrent(
            card: card, developerHeight: 0, browserHeight: 0,
            developerFrame: peekZero, browserFrame: peekZero,
            contentFrame: NSRect(x: 0, y: 0, width: card.width, height: card.height))
        expect(peekHidden, "hidden peek strips with full-card content are current")
        let peekShown = DeveloperChromeGeometry.peekIsCurrent(
            card: card, developerHeight: shownDev, browserHeight: 0,
            developerFrame: peekZero, browserFrame: peekZero,
            contentFrame: NSRect(x: 0, y: 0, width: card.width, height: card.height))
        expect(!peekShown, "newly shown peek developer strip is not current until laid out")
        let peekLaidOut = DeveloperChromeGeometry.peekIsCurrent(
            card: card, developerHeight: shownDev, browserHeight: 0,
            developerFrame: NSRect(x: 0, y: 0, width: card.width, height: shownDev),
            browserFrame: peekZero,
            contentFrame: NSRect(x: 0, y: shownDev, width: card.width, height: card.height - shownDev))
        expect(peekLaidOut, "matching peek strip and content frames are current")

        print("DeveloperToolbar: \(assertions) assertions passed")
    }
}
