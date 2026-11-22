import AppKit
import Testing
@testable import Parc
@testable import ParcKit

@MainActor
struct SidebarAccessibilityTestsFocusTests {
    private typealias ListStopView = SidebarAccessibilityTestsSupport.ListStopView
    private typealias Offscreen = SidebarAccessibilityTestsSupport.Offscreen

    private final class KeyLikeWindow: NSWindow { override var isKeyWindow: Bool { true } }

    @Test func anOffScreenFieldKeepsFocus() {
        let o = Offscreen()
        #expect(o.browser.makeFirstResponder(o.address))
        #expect((o.browser.firstResponder as? NSText)?.delegate === o.address)
    }

    @Test func hiddenTheListTakesNoFocus() {
        let o = Offscreen()
        o.sidebar.presented = false
        _ = o.browser.makeFirstResponder(o.sidebar)
        #expect(o.browser.firstResponder === o.browser)
    }

    @Test func aPresentedSidebarsViewsMayTakeRestoredFocus() {
        let o = Offscreen()
        #expect(SavedFocus.mayReturn(to: o.address, in: o.browser))
        #expect(SavedFocus.mayReturn(to: o.sidebar, in: o.browser))
    }

    @Test func aSidebarThatIsNotPresentedTakesNoRestoredFocus() {
        let o = Offscreen()
        _ = o.browser.makeFirstResponder(o.address)
        let editor = o.browser.firstResponder as? NSTextView
        o.sidebar.presented = false
        #expect(!SavedFocus.mayReturn(to: o.address, in: o.browser))
        #expect(!SavedFocus.mayReturn(to: o.headerToggle, in: o.browser))
        #expect(!SavedFocus.mayReturn(to: o.sidebar, in: o.browser))
        #expect(editor.map { $0.isDescendant(of: o.address) && !SavedFocus.mayReturn(to: $0, in: o.browser) } == true)
    }

    @Test func thePageMayTakeRestoredFocusAndNoOtherWindowMay() {
        let o = Offscreen()
        #expect(SavedFocus.mayReturn(to: o.page, in: o.browser))
        #expect(!SavedFocus.mayReturn(to: o.page, in: nil))
        #expect(!SavedFocus.mayReturn(to: o.page, in: NSWindow()))
    }

    @Test func hidingTheContainerGivesItsFocusToTheWindowAndLeavesBothTrees() {
        let o = Offscreen()
        _ = o.browser.makeFirstResponder(o.address)
        o.container.isHidden = true
        #expect(o.browser.firstResponder === o.browser)
        #expect(!SavedFocus.mayReturn(to: o.address, in: o.browser))
        #expect(!o.listed(o.browser.accessibilityChildren(), o.address))
        #expect(!o.address.canBecomeKeyView)
    }

    @Test func hiddenTheSelectionActionLeavesThePagesFocus() {
        let o = Offscreen()
        o.sidebar.presented = false
        #expect(o.browser.makeFirstResponder(o.page))
        o.sidebar.focusIfPresented()
        #expect((o.browser.firstResponder as? NSText)?.delegate === o.page)
    }

    @Test func presentedTheListStopTakesFocus() {
        let o = Offscreen()
        _ = o.browser.makeFirstResponder(o.page)
        o.sidebar.focusIfPresented()
        #expect(o.browser.firstResponder === o.sidebar)
    }

    @Test func aWindowThatIsNotKeyRevealsNothing() {
        let o = Offscreen()
        var reveals = 0
        #expect(o.sidebar.presentsForEditing(reveal: { reveals += 1 }))
        #expect(reveals == 0)
    }

    @Test func noEditWhileHidden() {
        let o = Offscreen()
        var reveals = 0
        o.sidebar.presented = false
        #expect(!o.sidebar.presentsForEditing(reveal: { reveals += 1 }))
        #expect(reveals == 0)
    }

    @MainActor private final class KeyLike {
        let window = KeyLikeWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 300, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let renamed = ListStopView(frame: NSRect(x: 0, y: 0, width: 228, height: 300))
        var reveals = 0

        init() {
            window.isReleasedWhenClosed = false
            window.contentView?.addSubview(renamed)
        }

        deinit { MainActor.assumeIsolated { window.close() } }
    }

    @Test func inMotionAndStillPresentedTheOwnersRevealRunsAndSettlesItFirst() {
        let k = KeyLike()
        #expect(k.renamed.presentsForEditing(reveal: { k.reveals += 1 }))
        #expect(k.reveals == 1)
    }

    @Test func hiddenTheOwnerFloatsItInAndTheEditBegins() {
        let k = KeyLike()
        k.renamed.presented = false
        #expect(k.renamed.presentsForEditing(reveal: { k.reveals += 1; k.renamed.presented = true }))
        #expect(k.reveals == 1)
    }

    @Test func anOwnerThatCannotRevealItRefusesTheEdit() {
        let k = KeyLike()
        k.renamed.presented = false
        #expect(!k.renamed.presentsForEditing(reveal: { k.reveals += 1 }))
        #expect(k.reveals == 1)
    }

    @Test func withoutAnOwnerItStaysRefused() {
        let k = KeyLike()
        k.renamed.presented = false
        #expect(!k.renamed.presentsForEditing(reveal: nil))
    }
}
