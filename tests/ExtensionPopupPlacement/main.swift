import AppKit

var assertions = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    assertions += 1
    precondition(condition(), message)
}
func frame(_ origin: CGPoint, _ size: CGSize) -> CGRect { CGRect(origin: origin, size: size) }

let screen = CGRect(x: 0, y: 0, width: 1512, height: 944)
let window = screen
let popup = CGSize(width: 600, height: 400)
let gap = ExtensionPopupPlacement.gap

let pill = CGRect(x: 8, y: 860, width: 224, height: 34)
let sidebarButton = CGRect(x: 150, y: 863, width: 28, height: 28)
let fromSidebar = frame(ExtensionPopupPlacement.origin(size: popup, control: sidebarButton, bar: pill,
                                                       window: window, screen: screen), popup)
check(!fromSidebar.intersects(pill), "a sidebar popup no longer covers the URL bar or the button that opened it")
check(fromSidebar.maxY == pill.minY - gap, "a sidebar popup hangs just below the URL bar")
check(fromSidebar.minX == window.minX + ExtensionPopupPlacement.margin && fromSidebar.maxX > sidebarButton.maxX,
      "a sidebar popup slides inside the window and stays under the button that opened it")

for sidebarWidth in [CGFloat(240), 0] {
    let toolbar = CGRect(x: sidebarWidth + 8, y: 904, width: window.width - sidebarWidth - 16, height: 32)
    let button = CGRect(x: toolbar.maxX - 104, y: 908, width: 32, height: 24)
    let placed = frame(ExtensionPopupPlacement.origin(size: popup, control: button, bar: toolbar,
                                                      window: window, screen: screen), popup)
    check(!placed.intersects(toolbar), "a toolbar popup never covers its toolbar, sidebar width \(sidebarWidth)")
    check(placed.maxY == toolbar.minY - gap && placed.maxX == button.maxX,
          "a toolbar popup sits just below the clicked button, sidebar width \(sidebarWidth)")
    check(placed.minX > sidebarWidth, "a toolbar popup opens beside its button, not around the sidebar")
}

let split = window.midY
let topBar = CGRect(x: 248, y: 904, width: 1256, height: 32)
let topButton = CGRect(x: 1400, y: 908, width: 32, height: 24)
let bottomBar = CGRect(x: 248, y: split - 36, width: 1256, height: 32)
let bottomButton = CGRect(x: 1400, y: split - 32, width: 32, height: 24)
let top = frame(ExtensionPopupPlacement.origin(size: popup, control: topButton, bar: topBar,
                                               window: window, screen: screen), popup)
let bottom = frame(ExtensionPopupPlacement.origin(size: popup, control: bottomButton, bar: bottomBar,
                                                  window: window, screen: screen), popup)
check(top.maxY == topBar.minY - gap, "the top pane's popup opens below the top pane's toolbar")
check(top.minY > bottomBar.maxY, "the top pane's popup stays above the lower pane's toolbar")
check(bottom.maxY == bottomBar.minY - gap, "the lower pane's popup opens below the lower pane's toolbar")
check(bottom.maxY < split, "the lower pane's popup stays in the lower pane")

let shortBar = CGRect(x: 248, y: 260, width: 1256, height: 32)
let shortButton = CGRect(x: 1400, y: 264, width: 32, height: 24)
let flipped = frame(ExtensionPopupPlacement.origin(size: popup, control: shortButton, bar: shortBar,
                                                   window: window, screen: screen), popup)
check(flipped.minY == shortBar.maxY + gap && flipped.maxX == shortButton.maxX,
      "with no room below, a popup flips up just above its toolbar instead of covering it")

let lowWindow = CGRect(x: 0, y: 0, width: 1512, height: 600)
let lowPill = CGRect(x: 8, y: 516, width: 224, height: 34)
let lowButton = CGRect(x: 150, y: 519, width: 28, height: 28)
let tall = CGSize(width: 600, height: 510)
let beside = frame(ExtensionPopupPlacement.origin(size: tall, control: lowButton, bar: lowPill,
                                                  window: lowWindow, screen: screen), tall)
check(!beside.intersects(lowPill) && beside.minX == lowPill.maxX + gap && beside.maxY == lowPill.maxY,
      "with no room above or below, a sidebar popup opens beside the URL bar, level with it")
check(lowWindow.contains(beside), "a popup that fits the window stays inside it")

let lowerSplitBar = CGRect(x: 248, y: 436, width: 1256, height: 32)
let lowerSplitButton = CGRect(x: 1400, y: 440, width: 32, height: 24)
let crowded = frame(ExtensionPopupPlacement.origin(size: tall, control: lowerSplitButton, bar: lowerSplitBar,
                                                   window: window, screen: screen), tall)
check(!crowded.intersects(lowerSplitButton) && crowded.maxX == lowerSplitButton.minX - gap,
      "a popup too tall for either side of a full-width toolbar keeps its button uncovered")
check(window.insetBy(dx: 8, dy: 8).contains(crowded), "a crowded popup still stays inside the window")

let smallWindow = CGRect(x: 300, y: 300, width: 700, height: 400)
let smallBar = CGRect(x: 308, y: 660, width: 684, height: 32)
let smallButton = CGRect(x: 900, y: 664, width: 32, height: 24)
let spilled = frame(ExtensionPopupPlacement.origin(size: popup, control: smallButton, bar: smallBar,
                                                   window: smallWindow, screen: screen), popup)
check(spilled.maxY == smallBar.minY - gap && spilled.maxX == smallButton.maxX,
      "a popup taller than its window still hangs below the button, running past the window's edge")
check(screen.contains(spilled), "a popup that leaves its window stays on screen")

let tiny = CGRect(x: 0, y: 0, width: 620, height: 540)
let tinyBar = CGRect(x: 8, y: 500, width: 604, height: 32)
let tinyButton = CGRect(x: 570, y: 504, width: 32, height: 24)
let pinned = frame(ExtensionPopupPlacement.origin(size: tall, control: tinyButton, bar: tinyBar,
                                                  window: tiny, screen: tiny), tall)
check(tiny.insetBy(dx: 8, dy: 8).contains(pinned), "when nothing fits beside its button, a popup still stays on screen")

let nearEdge = CGRect(x: 1476, y: 908, width: 32, height: 24)
let edgeBar = CGRect(x: 8, y: 904, width: 1504, height: 32)
let right = frame(ExtensionPopupPlacement.origin(size: popup, control: nearEdge, bar: edgeBar,
                                                 window: window, screen: screen), popup)
check(right.maxX == window.maxX - ExtensionPopupPlacement.margin && right.maxY == edgeBar.minY - gap,
      "a popup from a button near the window's edge slides back inside it")

let page = CGRect(x: 248, y: 8, width: 1256, height: 928)
let pageAnchor = ExtensionPopupPlacement.pageAnchor(page)
let fallback = frame(ExtensionPopupPlacement.origin(size: popup, control: pageAnchor, bar: pageAnchor,
                                                    window: window, screen: nil), popup)
check(fallback.maxX == page.maxX - ExtensionPopupPlacement.pageInset && fallback.maxY == page.maxY - gap,
      "with no visible control a popup hangs from the top trailing corner of the page")

let shortWindow = CGRect(x: 0, y: 200, width: 760, height: 620)
let shortPill = CGRect(x: 8, y: 736, width: 224, height: 34)
let shortPillButton = CGRect(x: 150, y: 739, width: 28, height: 28)
let square = CGSize(width: 600, height: 600)
let hanging = frame(ExtensionPopupPlacement.origin(size: square, control: shortPillButton, bar: shortPill,
                                                   window: shortWindow, screen: screen), square)
check(!hanging.intersects(shortPill) && hanging.maxY == shortPill.minY - gap && screen.contains(hanging),
      "a popup that fits the window only by covering the URL bar hangs below the bar onto the screen instead")

let shortSplit = CGRect(x: 0, y: 300, width: 1512, height: 644)
let shortLowerBar = CGRect(x: 248, y: 586, width: 1256, height: 32)
let shortLowerButton = CGRect(x: 1400, y: 590, width: 32, height: 24)
let flippedUp = frame(ExtensionPopupPlacement.origin(size: CGSize(width: 600, height: 300), control: shortLowerButton,
                                                     bar: shortLowerBar, window: shortSplit, screen: screen),
                      CGSize(width: 600, height: 300))
check(flippedUp.minY == shortLowerBar.maxY + gap && shortSplit.contains(flippedUp),
      "with no room below inside the window, a lower pane's popup flips up and stays inside the window")

final class Flipped: NSView { override var isFlipped: Bool { true } }

@MainActor func viewChecks() {
    let root = Flipped(frame: window)
    func add(_ rect: CGRect, to parent: NSView) -> NSView {
        let view = Flipped(frame: rect); parent.addSubview(view); return view
    }
    func onScreen(_ view: NSView) -> CGRect {
        let rect = root.convert(view.bounds, from: view)
        return CGRect(x: rect.minX, y: root.bounds.height - rect.maxY, width: rect.width, height: rect.height)
    }
    func place(_ anchor: (control: NSView, bar: NSView)?) -> CGRect {
        guard let anchor else { return .null }
        return frame(ExtensionPopupPlacement.origin(size: popup, control: onScreen(anchor.control), bar: onScreen(anchor.bar),
                                                    window: window, screen: screen), popup)
    }
    let shows = { (view: NSView) in !view.isHiddenOrHasHiddenAncestor }
    let sidebar = add(CGRect(x: 0, y: 0, width: 240, height: 944), to: root)
    let urlBar = add(CGRect(x: 8, y: 50, width: 224, height: 34), to: sidebar)
    let sidebarPins = add(CGRect(x: 150, y: 53, width: 28, height: 28), to: sidebar)
    let sidebarPin = add(sidebarPins.bounds, to: sidebarPins)
    let pageActions = add(CGRect(x: 202, y: 53, width: 25, height: 28), to: sidebar)
    let upper = add(CGRect(x: 248, y: 8, width: 1256, height: 464), to: root)
    let lower = add(CGRect(x: 248, y: 476, width: 1256, height: 460), to: root)
    let upperBar = add(CGRect(x: 0, y: 0, width: 1256, height: 32), to: upper)
    let lowerBar = add(CGRect(x: 0, y: 0, width: 1256, height: 32), to: lower)
    let upperPin = add(CGRect(x: 1152, y: 4, width: 32, height: 24), to: upperBar)
    let lowerPin = add(CGRect(x: 1152, y: 4, width: 32, height: 24), to: lowerBar)
    let upperInfo = add(CGRect(x: 1190, y: 2, width: 28, height: 28), to: upperBar)
    let sidebarArea = ExtensionPopupArea(owner: sidebar, bar: urlBar, controls: [sidebarPin, pageActions])
    let upperArea = ExtensionPopupArea(owner: upperBar, bar: upperBar, controls: [upperPin, upperInfo])
    let lowerArea = ExtensionPopupArea(owner: lowerBar, bar: lowerBar, controls: [lowerPin])
    let owners = [sidebarArea, upperArea, lowerArea]

    let fromLower = ExtensionPopupPlacement.anchor(clicked: lowerPin, owners: owners, defaults: [sidebarArea, upperArea], shows: shows)
    check(fromLower?.control === lowerPin && fromLower?.bar === lowerBar,
          "a click in a pane's toolbar anchors there even while the sidebar shows the URL bar")
    let lowerPopup = place(fromLower)
    check(lowerPopup.maxY == onScreen(lowerBar).minY - gap && lowerPopup.maxY < onScreen(upper).minY,
          "the lower pane's popup opens below the lower pane's toolbar, not over the upper pane")
    let fromUpper = ExtensionPopupPlacement.anchor(clicked: upperPin, owners: owners, defaults: [lowerArea], shows: shows)
    check(fromUpper?.bar === upperBar, "a click in the upper pane anchors to the upper pane even when the lower one is selected")
    let upperPopup = place(fromUpper)
    check(upperPopup.maxY == onScreen(upperBar).minY - gap && upperPopup.minY > onScreen(lowerBar).maxY,
          "the upper pane's popup opens below the upper pane's toolbar, not over the lower pane")
    let fromSidebar = ExtensionPopupPlacement.anchor(clicked: sidebarPin, owners: owners, defaults: [upperArea], shows: shows)
    check(fromSidebar?.bar === urlBar && !place(fromSidebar).intersects(onScreen(urlBar)),
          "a click in the sidebar opens below its URL bar without covering it")

    let shortcut = ExtensionPopupPlacement.anchor(clicked: nil, owners: owners, defaults: [sidebarArea, upperArea], shows: shows)
    check(shortcut?.control === sidebarPin && shortcut?.bar === urlBar, "a shortcut opens below the extension's own pinned button")
    let unpinned = ExtensionPopupPlacement.anchor(clicked: nil, owners: owners, defaults: [
        ExtensionPopupArea(owner: sidebar, bar: urlBar, controls: [nil, pageActions]), upperArea], shows: shows)
    check(unpinned?.control === pageActions, "an unpinned extension opens below the Site Control Center button")
    upperBar.isHidden = true
    let hiddenBar = ExtensionPopupPlacement.anchor(clicked: upperPin, owners: owners, defaults: [lowerArea], shows: shows)
    check(hiddenBar?.bar === lowerBar, "a click whose toolbar has since hidden falls back to the selected address area")
    upperBar.isHidden = false
    let page = add(CGRect(x: 0, y: 32, width: 1256, height: 400), to: upper)
    let fromPage = ExtensionPopupPlacement.anchor(clicked: page, owners: owners, defaults: [upperArea], shows: shows)
    check(fromPage?.control === upperPin, "a Site Control Center shown from the page itself falls back to the toolbar")
    check(ExtensionPopupPlacement.anchor(clicked: nil, owners: owners, defaults: [], shows: shows) == nil,
          "with no address area the popup falls back to the page corner")

    var source = ExtensionPopupSource(identifier: "a", control: upperPin)
    let first = NSObject(), second = NSObject()
    check(source.control(for: "b", popup: first) == nil, "another extension's popup never takes a click meant for this one")
    check(source.control(for: "a", popup: first) === upperPin, "the popup a click opens is placed from that click's button")
    check(source.control(for: "a", popup: first) === upperPin, "that popup keeps its button as it resizes")
    check(source.claimed && source.control(for: "a", popup: second) == nil,
          "a later popup from the command bar, a shortcut or the extension itself doesn't reuse an old click")
    var unopened = ExtensionPopupSource(identifier: "a", control: upperPin)
    check(!unopened.claimed, "a click stays unclaimed until its own popup asks for it")
    check(unopened.control(for: "a", popup: second) === upperPin && unopened.claimed, "the asking popup claims the click")
}
MainActor.assumeIsolated { viewChecks() }

print("ExtensionPopupPlacement: \(assertions) assertions passed")
