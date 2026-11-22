import AppKit
import Testing
@testable import ParcCore
@testable import ParcSidebar
@testable import ParcOnboarding

struct OnboardingKeyboardTests {
    @MainActor private final class Window: NSWindow {
        var testParent: NSWindow?
        var testSheet: NSWindow?
        override var sheetParent: NSWindow? { testParent }
        override var attachedSheet: NSWindow? { testSheet }

        init() {
            _ = NSApplication.shared
            super.init(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                       styleMask: .borderless, backing: .buffered, defer: false)
            isReleasedWhenClosed = false
        }
    }

    enum KeyOwner: CaseIterable {
        case setup, setupSheet, browser, browserSheet, noKey, noSetup
    }

    @Test(arguments: KeyOwner.allCases)
    @MainActor func closeSetupBelongsToTheOriginalSetupWindow(owner: KeyOwner) {
        let setup = Window(), browser = Window(), sheet = Window()
        let key: NSWindow?
        switch owner {
        case .setup, .noSetup: key = setup
        case .setupSheet: sheet.testParent = setup; key = sheet
        case .browser: key = browser
        case .browserSheet: sheet.testParent = browser; key = sheet
        case .noKey: key = nil
        }
        #expect(OnboardingCloseCommand.owns(setup: owner == .noSetup ? nil : setup, key: key)
                == (owner == .setup || owner == .setupSheet))
    }

    @Test(arguments: [false, true])
    @MainActor func aSheetBlocksCloseSetup(hasSheet: Bool) {
        let setup = Window()
        setup.testSheet = hasSheet ? Window() : nil
        #expect(OnboardingCloseCommand.isAvailable(setup: setup) == !hasSheet)
    }

    @Test @MainActor func aMissingSetupWindowIsUnavailable() {
        #expect(!OnboardingCloseCommand.isAvailable(setup: nil))
    }

    @Test @MainActor func themeEditorTabOrderReachesTheNextSetupControl() {
        _ = NSApplication.shared
        let editor = SpaceThemeEditorView(theme: SpaceTheme(), performHapticFeedback: {})
        let following = NSView()
        editor.chainKeyViews(to: following)
        var visited = Set<ObjectIdentifier>()
        var current: NSView? = editor.firstKeyView
        while let view = current, view !== following, visited.insert(ObjectIdentifier(view)).inserted {
            #expect(view.isDescendant(of: editor) && view !== editor)
            #expect(view is NSControl || view.acceptsFirstResponder)
            current = view.nextKeyView
        }
        #expect(current === following)
    }

    @Test @MainActor func chainingTheSetupEditorKeepsTheSidebarEditorsOwnOrder() {
        _ = NSApplication.shared
        let sidebar = SpaceThemeEditorView(theme: SpaceTheme(), performHapticFeedback: {})
        let editor = SpaceThemeEditorView(theme: SpaceTheme(), performHapticFeedback: {})
        let views = [sidebar] + sidebar.subviews.flatMap { [$0] + $0.subviews }
        let links = views.map { $0.nextKeyView.map(ObjectIdentifier.init) }
        editor.chainKeyViews(to: NSView())
        #expect(views.map { $0.nextKeyView.map(ObjectIdentifier.init) } == links)
    }
}
