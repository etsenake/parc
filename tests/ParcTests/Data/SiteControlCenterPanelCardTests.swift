import AppKit
import ParcCore
import SwiftUI
import Testing
@testable import Parc
@testable import ParcKit
@testable import ParcSidebar

@MainActor
struct SiteControlCenterPanelCardTests {
    private static func extensionItem(_ id: String, pinned: Bool = false) -> SiteControlCenterModel.Extension {
        .init(id: id, name: "Extension " + id, tooltip: "", accessibilityLabel: "", icon: nil, isPinned: pinned, canChangePin: true)
    }

    private static func setting(_ id: String, title: String, subtitle: String, isOn: Bool) -> SiteControlCenterModel.Setting {
        .init(id: id, symbol: "gearshape.fill", symbolSize: 13, symbolWeight: .medium, title: title,
              subtitle: subtitle, isOn: isOn, isEnabled: true)
    }

    private static func borderlessWindow(hosting view: NSView) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -12_000, y: -12_000), size: view.frame.size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        return window
    }

    private static func views<View: NSView>(_ type: View.Type, in view: NSView) -> [View] {
        ((view as? View).map { [$0] } ?? []) + view.subviews.flatMap { views(type, in: $0) }
    }
    private static func fullModel() -> SiteControlCenterModel {
        let model = SiteControlCenterModel()
        model.captureAvailable = true
        model.extensions = [extensionItem("a", pinned: true), extensionItem("b"), extensionItem("c"),
                            extensionItem("d"), extensionItem("e")]
        model.settings = [setting("developerMode", title: "Developer Mode", subtitle: "Off", isOn: false),
                          setting("permission:0:1", title: "Camera", subtitle: "Allowed", isOn: true)]
        model.isSecure = true
        return model
    }

    private static func hostedTooltips() throws -> (NSWindow, [TooltipAnchorView], [String: TooltipConfiguration]) {
        let directory = try #require(Bundle.module.url(forResource: "SiteControlCenter", withExtension: nil))
        let host = NSHostingView(rootView: SiteControlCenterView(model: fullModel())
            .environment(\.siteControlCenterArtwork, SiteControlCenterArtwork.Library(directory: directory)))
        host.frame.size = host.fittingSize
        let window = borderlessWindow(hosting: host)
        let anchors = views(TooltipAnchorView.self, in: host)
        let tooltips = Dictionary(anchors.compactMap { anchor in anchor.parcTooltip.map { ($0.label, $0) } }) { first, _ in first }
        return (window, anchors, tooltips)
    }

    private static func fittingSize(extensions: Int, settings: Bool) -> NSSize {
        let model = SiteControlCenterModel()
        model.extensions = (0..<extensions).map { extensionItem(String($0)) }
        if settings {
            model.settings = [setting("developerMode", title: "Developer Mode", subtitle: "Off", isOn: false)]
            model.isSecure = true
        }
        return NSHostingView(rootView: SiteControlCenterView(model: model)).fittingSize
    }

    @Test func theCardKeepsItsTilesInsideThePlusMenusEdgeInset() {
        #expect(SiteControlCenterMetrics.padding == SidebarPlusMenuView.inset)
        #expect(SiteControlCenterMetrics.width == 232)
        #expect(SiteControlCenterMetrics.button == CGSize(width: 48, height: 32))
        #expect(SiteControlCenterMetrics.extensionIcon == 16)
        #expect(SiteControlCenterMetrics.pin == 14)
    }

    struct CaptureHint: CustomTestStringConvertible, Sendable {
        let testDescription: String
        let button: SiteControlCenterModel.Button
        let hint: String

        static let cases: [Self] = [
            .init(testDescription: "Portion", button: .capture, hint: "Capture a portion of this page"),
            .init(testDescription: "Visible area", button: .captureVisiblePage, hint: "Capture the visible area"),
            .init(testDescription: "Full page", button: .captureFullPage, hint: "Capture the full page"),
        ]
    }

    @Test(arguments: CaptureHint.cases)
    func captureHintsNameTheirAcquisitionMode(_ sample: CaptureHint) {
        #expect(SiteControlCenterModel().help(sample.button) == sample.hint)
    }

    @Test func theHostedCardIsExactlyTheCardWidth() {
        let host = NSHostingView(rootView: SiteControlCenterView(model: Self.fullModel()))
        #expect(host.fittingSize.width == 232)
    }

    @Test func everyItemOfTheCardCarriesATooltip() throws {
        let (window, _, tooltips) = try Self.hostedTooltips()
        defer { window.close() }

        #expect(Set(tooltips.keys) == ["Share", "Capture the visible area", "Capture a portion of this page",
                                       "Capture the full page", "Extension a", "Extension b", "Extension c", "Extension d",
                                       "Extension e", "Unpin", "Add Extension", "Manage Extensions", "All Site Settings",
                                       "Developer Mode", "Camera", "Secure", "More"])
    }

    @Test func theActionKeycapsFollowTheirCommandsLiveBindings() throws {
        let (window, _, tooltips) = try Self.hostedTooltips()
        defer { window.close() }

        #expect(tooltips["Share"]?.shortcut == nil)
        #expect(tooltips["Capture the full page"]?.shortcut == .command("captureFullPage:"))
        #expect(tooltips["Capture a portion of this page"]?.shortcut == .command("capturePage:"))
        #expect(tooltips["Capture the visible area"]?.shortcut == .command("captureVisiblePage:"))
        #expect(SiteControlCenterModel.Button.copyURL.commandID == "copyCurrentURL:")
    }

    @Test func itemTooltipsTakeTheWindowsPaletteBelowTheirItem() throws {
        let (window, _, tooltips) = try Self.hostedTooltips()
        defer { window.close() }

        #expect(!tooltips.isEmpty)
        #expect(tooltips.values.allSatisfy { $0.palette == nil && $0.anchor == .bottomTrailing })
    }

    @Test func ordinaryHitTestsPassThroughEveryTooltipAnchor() throws {
        let (window, anchors, _) = try Self.hostedTooltips()
        defer { window.close() }
        let host = try #require(window.contentView)

        #expect(!anchors.isEmpty)
        for anchor in anchors {
            let centre = anchor.convert(NSPoint(x: anchor.bounds.midX, y: anchor.bounds.midY), to: nil)
            let hit = host.hitTest(host.superview?.convert(centre, from: nil) ?? centre)
            #expect(!(hit is TooltipAnchorView))
        }
    }

    @Test func theShellDrawsAnExtensionsBadgeOnceClearOfItsPin() {
        let badge = ExtensionActionBadge(text: "12", textColor: .white, backgroundColor: .systemBlue)
        let model = SiteControlCenterModel()
        model.extensions = [
            .init(id: "unbadged", name: "Unbadged", tooltip: "", accessibilityLabel: "", icon: nil, isPinned: true,
                  canChangePin: true, badge: badge, badgeText: "12"),
            .init(id: "baked", name: "Baked", tooltip: "", accessibilityLabel: "", icon: nil, isPinned: false,
                  canChangePin: true, badgeText: "3")]
        let host = NSHostingView(rootView: SiteControlCenterView(model: model))
        host.frame.size = host.fittingSize
        let window = Self.borderlessWindow(hosting: host)
        defer { window.close() }

        let drawn = Self.views(ExtensionActionBadgeView.self, in: host)
        let expected = ExtensionActionBadgeMetrics.frame(text: "12", in: NSRect(origin: .zero, size: SiteControlCenterMetrics.button))

        #expect(drawn.count == 1)
        #expect(drawn.first?.badge == badge)
        #expect(drawn.first?.frame.size == expected.size)
        #expect(expected.maxX <= SiteControlCenterMetrics.button.width - SiteControlCenterMetrics.pin + 3)
        #expect(expected.maxY <= SiteControlCenterMetrics.button.height - SiteControlCenterMetrics.pin + 3)
    }

    @Test func settingsAndTheFooterCollapseWhenAbsent() {
        let bare = Self.fittingSize(extensions: 3, settings: false)
        #expect(bare.width == 232)
        #expect(bare.height < Self.fittingSize(extensions: 3, settings: true).height)
    }

    @Test func aFifthItemStartsASecondRowBelowTheFirst() {
        let oneRow = Self.fittingSize(extensions: 3, settings: false)
        let twoRows = Self.fittingSize(extensions: 4, settings: false)
        #expect(twoRows.height == oneRow.height + SiteControlCenterMetrics.button.height + SiteControlCenterMetrics.spacing)
    }

    @Test func theExtensionClickLayerIsTransparentWithoutASecondaryClick() {
        _ = NSApplication.shared
        let click = SiteControlCenterAlternateClick.ClickView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        #expect(click.hitTest(NSPoint(x: 5, y: 5)) == nil)
    }
}
