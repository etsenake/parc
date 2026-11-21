import AppKit
import SwiftUI
import Testing
@testable import Parc

struct BrowserImportFocusTests {
    @MainActor
    private final class ProbeWindow: NSWindow {
        var shown = true
        var minimized = false
        var testSheet: NSWindow?
        override var isVisible: Bool { shown }
        override var isMiniaturized: Bool { minimized }
        override var attachedSheet: NSWindow? { testSheet }

        init() {
            super.init(contentRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                       styleMask: [.borderless], backing: .buffered, defer: false)
            isReleasedWhenClosed = false
        }
    }

    enum Focus: CaseIterable {
        case noKey, parent, importer, unrelated, unrelatedAfterImporterClosed
        case notRequested, inactive, hidden, minimized, sheet
    }

    @MainActor @Test(arguments: Focus.allCases)
    func focusReturnsOnlyToAnEligibleParentWhenItWillNotStealFocus(_ focus: Focus) {
        _ = NSApplication.shared
        let parent = ProbeWindow()
        let importer = ProbeWindow()
        let other = ProbeWindow()
        parent.shown = focus != .hidden
        parent.minimized = focus == .minimized
        parent.testSheet = focus == .sheet ? other : nil
        let key: NSWindow?
        switch focus {
        case .parent: key = parent
        case .importer: key = importer
        case .unrelated, .unrelatedAfterImporterClosed: key = other
        default: key = nil
        }
        let mayReturn = BrowserImportFocus.mayReturn(requested: focus != .notRequested,
            appIsActive: focus != .inactive, parent: parent,
            importer: focus == .unrelatedAfterImporterClosed ? nil : importer, key: key)

        #expect(mayReturn == ([.noKey, .parent, .importer].contains(focus)))
    }

    private final class FlippedView: NSView { override var isFlipped: Bool { true } }
    private final class FocusableView: NSView {
        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }
    }

    @MainActor @Test func setupKeyViewsFollowReadingOrderAcrossSections() {
        _ = NSApplication.shared
        let accessory = NSView(frame: CGRect(x: 0, y: 0, width: 100, height: 400))
        let importer = FlippedView(frame: CGRect(x: 100, y: 0, width: 300, height: 400))
        let accessoryButton = NSButton(frame: CGRect(x: 0, y: 10, width: 80, height: 20))
        accessory.addSubview(accessoryButton)
        let column = FlippedView(frame: importer.bounds)
        importer.addSubview(column)
        let lower = NSButton(frame: CGRect(x: 0, y: 300, width: 80, height: 20))
        let upper = NSButton(frame: CGRect(x: 0, y: 20, width: 80, height: 20))
        let right = NSButton(frame: CGRect(x: 120, y: 20, width: 80, height: 20))
        let hidden = NSButton(frame: CGRect(x: 0, y: 200, width: 80, height: 20))
        hidden.isHidden = true
        let disabled = NSButton(frame: CGRect(x: 0, y: 250, width: 80, height: 20))
        disabled.isEnabled = false
        let label = NSTextField(wrappingLabelWithString: "Status")
        label.frame = CGRect(x: 0, y: 100, width: 80, height: 20)
        let field = NSTextField(frame: CGRect(x: 0, y: 150, width: 80, height: 20))
        let host = NSHostingView(rootView: Button("A") {})
        host.frame = CGRect(x: 0, y: 60, width: 200, height: 30)
        let focusable = FocusableView(frame: CGRect(x: 0, y: 350, width: 200, height: 40))
        let nested = NSButton(frame: CGRect(x: 0, y: 5, width: 50, height: 20))
        focusable.addSubview(nested)
        [lower, right, upper, hidden, disabled, label, field, host, focusable].forEach(column.addSubview)

        let order = BrowserImportFocus.keyViews(in: [accessory, importer])

        let expected: [NSView] = [accessoryButton, upper, right, host, field, hidden, disabled, lower, focusable, nested]
        #expect(order.elementsEqual(expected, by: ===))
    }

    @MainActor @Test func emptySetupOffersNoKeyViews() {
        #expect(BrowserImportFocus.keyViews(in: []).isEmpty)
    }
}
