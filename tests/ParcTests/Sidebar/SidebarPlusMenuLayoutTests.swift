import AppKit
import Testing
@testable import Parc
import ParcCore
@testable import ParcKit
@testable import ParcSidebar

@MainActor
struct SidebarPlusMenuLayoutTests {
    private let rows = SidebarPlusMenuModel.rows(privateBrowsing: false, canCreateEasel: true, canCreateNote: true, canSplit: true)
    private let privateRows = SidebarPlusMenuModel.rows(privateBrowsing: true, canCreateEasel: false, canCreateNote: false, canSplit: false)
    private let neutral = ParcMenuColors(theme: SpaceTheme())

    private func buttons(_ view: NSView) -> [SidebarPlusRowButton] {
        sidebarDescendants(view).compactMap { $0 as? SidebarPlusRowButton }
    }

    private var escape: NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                         characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 53)!
    }

    @Test func theCardIs210By290() {
        let view = SidebarPlusMenuView(rows: rows, colors: neutral) { _ in }
        #expect(view.menuSize == NSSize(width: 210, height: 290))
    }

    @Test func theCardTakesTheAppAppearance() {
        #expect(SidebarPlusMenuView(rows: rows, colors: neutral) { _ in }.appearance == nil)
    }

    @Test func theCardIsAMenuNamedAfterThePlusButton() {
        let view = SidebarPlusMenuView(rows: rows, colors: neutral) { _ in }
        #expect(view.accessibilityRole() == .menu)
        #expect(view.accessibilityLabel() == "New Tab, Folder, or Space")
    }

    @Test func theRowButtonsMatchTheModel() {
        let view = SidebarPlusMenuView(rows: rows, colors: neutral) { _ in }
        #expect(buttons(view).map(\.row.title) == rows.map(\.title))
    }

    @Test func theRowsKeepEightPointInsetsAndSeparatorBands() {
        let view = SidebarPlusMenuView(rows: rows, colors: neutral) { _ in }
        #expect(buttons(view).map(\.frame) == [
            NSRect(x: 8, y: 8, width: 194, height: 40),
            NSRect(x: 8, y: 48, width: 194, height: 40),
            NSRect(x: 8, y: 105, width: 194, height: 40),
            NSRect(x: 8, y: 145, width: 194, height: 40),
            NSRect(x: 8, y: 202, width: 194, height: 40),
            NSRect(x: 8, y: 242, width: 194, height: 40),
        ])
    }

    @Test func onlyNewTabStartsHighlighted() {
        let rowButtons = buttons(SidebarPlusMenuView(rows: rows, colors: neutral) { _ in })
        #expect(rowButtons.last?.emphasized == true)
        #expect(rowButtons.last?.row.action == .tab)
        #expect(rowButtons.filter(\.emphasized).count == 1)
    }

    @Test(arguments: [SidebarPlusAction.note, .tab])
    func clickingAnAvailableRowPerformsIt(action: SidebarPlusAction) throws {
        var chosen: SidebarPlusAction?
        let view = SidebarPlusMenuView(rows: rows, colors: neutral) { chosen = $0 }
        try #require(buttons(view).first { $0.row.action == action }).sendClick()
        #expect(chosen == action)
    }

    @Test func clickingAnUnavailableNewNoteDoesNothing() throws {
        var chosen: SidebarPlusAction?
        let view = SidebarPlusMenuView(rows: privateRows, colors: neutral) { chosen = $0 }
        try #require(buttons(view).first { $0.row.action == .note }).sendClick()
        #expect(chosen == nil)
    }

    @Test func rowsAndEscapeDoNothingWhileClosing() {
        var chosen: SidebarPlusAction?
        var dismissed = false
        let view = SidebarPlusMenuView(rows: rows, colors: neutral, dismiss: { dismissed = true }) { chosen = $0 }
        view.acceptsActions = false
        buttons(view).last?.sendClick()
        view.keyDown(with: escape)
        #expect(chosen == nil)
        #expect(!dismissed)
    }

    @Test func theCardsTrailingEdgeIsFlushWithThePlusButton() {
        let anchor = CGRect(x: 400, y: 80, width: 32, height: 32)
        let placed = SidebarPlusMenuPlacement.windowFrame(anchor: anchor, menu: CGSize(width: 210, height: 290), parentMinX: 0)
        #expect(placed.frame.maxX == anchor.maxX)
    }

    @Test func theCardSits16PointsAboveThePlusButton() {
        let anchor = CGRect(x: 400, y: 80, width: 32, height: 32)
        let placed = SidebarPlusMenuPlacement.windowFrame(anchor: anchor, menu: CGSize(width: 210, height: 290), parentMinX: 0)
        #expect(abs(placed.frame.minY - (anchor.maxY + 16 - 6)) < 0.01)
    }

    @Test func theTailCentreIs19PointsFromTheTrailingEdge() {
        let anchor = CGRect(x: 400, y: 80, width: 32, height: 32)
        let placed = SidebarPlusMenuPlacement.windowFrame(anchor: anchor, menu: CGSize(width: 210, height: 290), parentMinX: 0)
        #expect(abs(placed.tailX - (210 - 19.25)) < 0.01)
    }

    @Test func aClampedCardBeginsAtTheParentEdgeAndItsTailClearsTheCorner() {
        let placed = SidebarPlusMenuPlacement.windowFrame(anchor: CGRect(x: 0, y: 80, width: 1, height: 32),
                                                          menu: CGSize(width: 210, height: 290), parentMinX: 0)
        #expect(placed.frame.minX == 0)
        #expect(abs(placed.tailX - (SidebarPlusMenuPlacement.cornerRadius + SidebarPlusMenuPlacement.tailBase / 2)) < 0.01)
    }

    @Test func theRightTailClampClearsTheCorner() {
        let placed = SidebarPlusMenuPlacement.windowFrame(anchor: CGRect(x: 400, y: 80, width: 1, height: 32),
                                                          menu: CGSize(width: 210, height: 290), parentMinX: 0)
        #expect(abs(placed.tailX - (210 - SidebarPlusMenuPlacement.cornerRadius - SidebarPlusMenuPlacement.tailBase / 2)) < 0.01)
    }

    @Test func theHUDWindowCanBeKeyButNotMain() {
        let window = SidebarPlusMenuWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        #expect(window.canBecomeKey)
        #expect(!window.canBecomeMain)
    }
}

@MainActor
struct SidebarPlusMenuControllerTests {
    @MainActor final class Opened {
        let parent: NSWindow
        let anchor = NSView(frame: NSRect(x: 300, y: 10, width: 32, height: 32))
        let controller = SidebarPlusMenuController()
        var presented: [(parent: NSWindow, panel: SidebarPlusMenuWindow, shown: Bool)] = []
        var transitions: [Bool] = []
        let rows = SidebarPlusMenuModel.rows(privateBrowsing: false, canCreateEasel: true, canCreateNote: true, canSplit: true)

        init(theme: SpaceTheme = SpaceTheme(), styleMask: NSWindow.StyleMask = [.borderless]) {
            parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 500), styleMask: styleMask, backing: .buffered, defer: true)
            parent.isReleasedWhenClosed = false
            parent.contentView?.addSubview(anchor)
            controller.theme = theme
            controller.present = { [weak self] parent, panel in
                guard let self else { return }
                presented.append((parent, panel, SidebarPlusMenuController.isShown(in: parent)))
            }
            controller.onVisibilityChange = { [weak self] in self?.transitions.append($0) }
        }

        func open() { controller.toggle(from: anchor, rows: rows) { _ in } }

        var panel: SidebarPlusMenuWindow? { presented.last?.panel }
        var chrome: SidebarPlusMenuChrome? { panel?.contentView as? SidebarPlusMenuChrome }
        var rowButtons: [SidebarPlusRowButton] {
            chrome.map { sidebarDescendants($0.card).compactMap { $0 as? SidebarPlusRowButton } } ?? []
        }
    }

    private static let purple = SpaceTheme(primaryColor: ThemeColor(hex: "3D2468"), colorCount: 1, appearance: .dark, noise: 0.3)
    private static let blue = SpaceTheme(primaryColor: ThemeColor(hex: "3F9BD6"), colorCount: 2, noise: 0.3)

    private func same(_ a: NSColor, _ b: NSColor, dark: Bool) -> Bool {
        func resolved(_ color: NSColor) -> [CGFloat] {
            var components: [CGFloat] = []
            NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
                let value = color.usingColorSpace(.extendedSRGB)!
                components = [value.redComponent, value.greenComponent, value.blueComponent, value.alphaComponent]
            }
            return components
        }
        return zip(resolved(a), resolved(b)).allSatisfy { abs($0 - $1) < 1e-5 }
    }

    @Test func openingPresentsTheHUDAsAChildOfTheAnchorsWindow() throws {
        let opened = Opened()
        opened.open()
        let presented = try #require(opened.presented.first)
        #expect(opened.presented.count == 1)
        #expect(presented.parent === opened.parent)
        #expect(opened.chrome != nil)
        #expect(SidebarPlusMenuController.isShown(in: opened.parent))
    }

    @Test func theHUDIsRegisteredBeforeItTakesKeyFromItsParent() throws {
        let opened = Opened(styleMask: [.titled, .closable])
        opened.open()
        let presented = try #require(opened.presented.first)
        #expect(presented.shown)
        #expect(opened.transitions == [true])
    }

    @Test func theHUDWindowCarriesTheMenuName() throws {
        let opened = Opened()
        opened.open()
        let panel = try #require(opened.panel)
        #expect(panel.accessibilityLabel() == "New Tab, Folder, or Space")
    }

    @Test func theHUDFollowsTheAppAppearance() throws {
        let opened = Opened(theme: Self.purple)
        opened.open()
        let panel = try #require(opened.panel)
        #expect(panel.appearance == nil)
        let chrome = try #require(opened.chrome)
        #expect(chrome.card.appearance == nil)
        #expect(panel.appearanceSource === NSApp)
    }

    @Test func aDarkPrivateWindowsHUDStillFollowsTheApp() throws {
        let opened = Opened(theme: Self.purple)
        opened.parent.appearance = NSAppearance(named: .darkAqua)
        opened.open()
        let panel = try #require(opened.panel)
        #expect(panel.appearanceSource === NSApp)
        #expect(panel.appearance == nil)
    }

    @Test(arguments: [false, true])
    func theHUDOpensInTheWindowTheme(dark: Bool) throws {
        let opened = Opened(theme: Self.purple)
        opened.open()
        let chrome = try #require(opened.chrome)
        #expect(same(chrome.colors.background, ThemeChromePalette(theme: Self.purple, isDark: dark).backgroundExtra, dark: dark))
    }

    @Test(arguments: [false, true])
    func anOpenHUDRecoloursWithTheWindowTheme(dark: Bool) throws {
        let opened = Opened(theme: Self.purple)
        opened.open()
        opened.controller.theme = Self.blue
        let chrome = try #require(opened.chrome)
        let palette = ThemeChromePalette(theme: Self.blue, isDark: dark)
        #expect(same(chrome.colors.background, palette.backgroundExtra, dark: dark))
        #expect(same(chrome.card.colors.hover, palette.hover, dark: dark))
        #expect(opened.rowButtons.allSatisfy { same($0.colors.subtitle, palette.subtitle, dark: dark) })
    }

    private func awaitsRedraw(_ view: NSView) -> Bool { view.layer?.needsDisplay() ?? view.needsDisplay }

    @Test func anUnchangedThemeDoesNotRedrawTheHUD() throws {
        let opened = Opened(theme: Self.purple)
        opened.open()
        let chrome = try #require(opened.chrome)
        let views: [NSView] = [chrome, chrome.card] + opened.rowButtons
        views.forEach { $0.layer?.displayIfNeeded() }
        try #require(!views.contains(where: awaitsRedraw))
        opened.controller.theme = Self.purple
        #expect(!views.contains(where: awaitsRedraw))
    }

    @Test func aRecolouredHUDRedrawsItsTailCardAndEveryRow() throws {
        let opened = Opened(theme: Self.purple)
        opened.open()
        let chrome = try #require(opened.chrome)
        let views: [NSView] = [chrome, chrome.card] + opened.rowButtons
        views.forEach { $0.layer?.displayIfNeeded() }
        try #require(!views.contains(where: awaitsRedraw))
        opened.controller.theme = Self.blue
        #expect(views.allSatisfy(awaitsRedraw))
    }

    enum ClosePath: CaseIterable, Sendable {
        case dismiss, toggle, escape, row, outsideClick, parentClose
    }

    private func close(_ opened: Opened, by path: ClosePath) throws {
        let chrome = try #require(opened.chrome)
        switch path {
        case .dismiss:
            opened.controller.dismiss()
        case .toggle:
            opened.open()
        case .escape:
            chrome.card.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                       windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                                                       isARepeat: false, keyCode: 53)!)
        case .row:
            opened.rowButtons.last?.sendClick()
        case .outsideClick:
            try #require(opened.panel).resignKey()
        case .parentClose:
            opened.parent.close()
        }
    }

    @Test(arguments: ClosePath.allCases)
    func closingStopsMenuActionsAndHUDInput(path: ClosePath) throws {
        let opened = Opened()
        opened.open()
        try close(opened, by: path)
        let chrome = try #require(opened.chrome)
        let panel = try #require(opened.panel)
        #expect(chrome.card.acceptsActions == false)
        #expect(panel.ignoresMouseEvents)
    }

    @Test(arguments: ClosePath.allCases)
    func closingClearsOwnershipAndAnnouncesEachTransitionOnce(path: ClosePath) throws {
        let opened = Opened()
        opened.open()
        try close(opened, by: path)
        #expect(!SidebarPlusMenuController.isShown(in: opened.parent))
        #expect(opened.transitions == [true, false])
        #expect(opened.presented.count == 1)
    }
}
