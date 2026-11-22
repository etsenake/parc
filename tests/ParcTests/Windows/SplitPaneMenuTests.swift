import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SplitPaneMenuTests {
    @MainActor private final class Dispatch {
        var performed: [SplitPaneOperation] = []
        var available = true
    }

    private static func invoke(_ item: NSMenuItem) {
        _ = (item.target as? NSObject)?.perform(item.action, with: item)
    }

    private static func rows(_ menu: NSMenu) -> [String] { menu.items.filter { !$0.isSeparatorItem }.map(\.title) }

    private static func make(_ dispatch: Dispatch, orientation: SplitOrientation = .horizontal, index: Int = 0, count: Int = 2,
                             layout: BrowserSplitLayout? = nil, artwork: ((String) -> NSImage?)? = nil) -> NSMenu {
        SplitPaneMenu.make(orientation: orientation, index: index, count: count, layout: layout, artwork: artwork) { operation in
            { if dispatch.available { dispatch.performed.append(operation) } }
        }
    }

    private static func stackedLayout(_ orientation: SplitOrientation) -> BrowserSplitLayout {
        let shape = BrowserSplitLayout.shape(orientation: orientation, sizes: [1, 2], factors: [0.5, 0.5], stackFactors: [[1], [0.5, 0.5]])
        return BrowserSplitLayout(id: UUID(), spaceID: UUID(), tabIDs: [UUID(), UUID(), UUID()], orientation: shape.orientation,
                                  widthFactors: shape.widthFactors, stacks: shape.stacks)
    }

    @Test func theMenuOwnsExplicitAvailability() {
        let menu = Self.make(Dispatch())
        #expect(!menu.autoenablesItems)
        #expect(menu.title == "Split View Controls Menu")
    }

    @Test func aHorizontalSplitMatchesTheInstalledPaneControlList() {
        #expect(Self.rows(Self.make(Dispatch())) == ["Move Left", "Move Right", "Add Right Split", "Add Left Split", "Add Above This Pane",
                                                     "Add Below This Pane", "Separate Tab from Split", "Convert to Vertical Split View",
                                                     "Copy Links"])
    }

    @Test func aBoundaryMoveIsDisabled() {
        let menu = Self.make(Dispatch())
        #expect(menu.items[0].isEnabled == false)
        #expect(menu.items[1].isEnabled)
    }

    @Test func menuSectionsAreSeparators() {
        #expect(Self.make(Dispatch()).items.filter(\.isSeparatorItem).count == 3)
    }

    @Test func eachItemKeepsItsActionOwner() {
        let item = Self.make(Dispatch()).items[1]
        #expect(item.target != nil)
        #expect(item.representedObject != nil)
        #expect(item.action != nil)
    }

    @Test func dispatchPreservesTheExactOperation() {
        let dispatch = Dispatch()
        Self.invoke(Self.make(dispatch).items[1])
        #expect(dispatch.performed == [.moveNext])
    }

    @Test func theOwnerCanRejectAnActionAfterTheMenuWasPrepared() {
        let dispatch = Dispatch()
        let menu = Self.make(dispatch)
        dispatch.available = false
        Self.invoke(menu.items[1])
        #expect(dispatch.performed.isEmpty)
    }

    @Test func aFourPaneMenuHasNoFifthPaneAction() {
        let full = Self.make(Dispatch(), orientation: .vertical, index: 3, count: 4)
        #expect(full.items.filter { $0.title.hasPrefix("Add ") }.allSatisfy { !$0.isEnabled })
    }

    @Test func theLastVerticalPaneOnlyMovesUp() {
        let full = Self.make(Dispatch(), orientation: .vertical, index: 3, count: 4)
        #expect(full.items[0].title == "Move Up" && full.items[0].isEnabled)
        #expect(!full.items[1].isEnabled)
    }

    @Test func aTopAndBottomSplitOffersSidewaysStackedAdds() {
        #expect(Self.rows(Self.make(Dispatch(), orientation: .vertical, index: 3, count: 4))
                == ["Move Up", "Move Down", "Add Top Split", "Add Bottom Split", "Add Left of This Pane", "Add Right of This Pane",
                    "Separate Tab from Split", "Convert to Horizontal Split View", "Copy Links"])
    }

    @Test func convertSitsAboveCopyLinks() {
        let full = Self.make(Dispatch(), orientation: .vertical, index: 3, count: 4)
        #expect(full.items[9].title == "Convert to Horizontal Split View")
        #expect(full.items.last?.title == "Copy Links")
    }

    @Test func aPaneInAStackAlsoMovesWithinIt() {
        let stacked = Self.make(Dispatch(), index: 2, count: 3, layout: Self.stackedLayout(.horizontal))
        #expect(Self.rows(stacked) == ["Move Left", "Move Right", "Move Up", "Move Down", "Add Right Split", "Add Left Split",
                                       "Add Above This Pane", "Add Below This Pane", "Separate Tab from Split",
                                       "Convert to Vertical Split View", "Copy Links"])
    }

    @Test func movesNeedANeighbour() {
        let stacked = Self.make(Dispatch(), index: 2, count: 3, layout: Self.stackedLayout(.horizontal))
        #expect(stacked.items[0].isEnabled && !stacked.items[1].isEnabled)
        #expect(stacked.items[2].isEnabled && !stacked.items[3].isEnabled)
    }

    @Test func threePanesLeaveRoomForOneMore() {
        let stacked = Self.make(Dispatch(), index: 2, count: 3, layout: Self.stackedLayout(.horizontal))
        #expect(stacked.items.filter { $0.title.hasPrefix("Add ") }.allSatisfy { $0.isEnabled })
    }

    @Test func stackRowsDispatchTheirExactOperations() {
        let dispatch = Dispatch()
        let stacked = Self.make(dispatch, index: 2, count: 3, layout: Self.stackedLayout(.horizontal))
        for item in stacked.items where ["Move Left", "Move Up", "Add Above This Pane", "Add Below This Pane"].contains(item.title) {
            Self.invoke(item)
        }
        #expect(dispatch.performed == [.movePrevious, .stackPrevious, .stackBefore, .stackAfter])
    }

    @Test func aPaneAloneInItsSlotShowsNoStackMoves() {
        let lone = Self.make(Dispatch(), index: 0, count: 3, layout: Self.stackedLayout(.horizontal))
        #expect(!lone.items.contains { $0.title == "Move Up" || $0.title == "Move Down" })
        #expect(!lone.items[0].isEnabled && lone.items[1].isEnabled)
    }

    @Test func inATopAndBottomSplitAStackedPaneMovesLeftAndRight() {
        let sideways = Self.make(Dispatch(), orientation: .vertical, index: 1, count: 3, layout: Self.stackedLayout(.vertical))
        #expect(Self.rows(sideways).prefix(4) == ["Move Up", "Move Down", "Move Left", "Move Right"])
        #expect(sideways.items[0].isEnabled && !sideways.items[1].isEnabled)
        #expect(!sideways.items[2].isEnabled && sideways.items[3].isEnabled)
    }

    @Test func copyLinksFollowsTheOwnersLiveRefusal() {
        let dispatch = Dispatch()
        let menu = Self.make(dispatch)
        let copyLinks = menu.items.last!
        dispatch.available = false
        Self.invoke(copyLinks)
        #expect(copyLinks.isEnabled)
        #expect(dispatch.performed.isEmpty)
    }

    @Test func copyLinksDispatchesTheSplitsCopyOperation() {
        let dispatch = Dispatch()
        Self.invoke(Self.make(dispatch).items.last!)
        #expect(dispatch.performed == [.copyLinks])
    }

    @Test func withNoWebPageToCopyOnlyCopyLinksIsDisabled() {
        let linkless = SplitPaneMenu.make(orientation: .horizontal, index: 0, count: 2) { operation in
            operation == .copyLinks ? nil : {}
        }
        #expect(linkless.items.last?.title == "Copy Links")
        #expect(linkless.items.last?.isEnabled == false)
        #expect(linkless.items[1].isEnabled)
    }

    @Test func aSolePaneExposesBothOriginalOrientationSections() {
        let single = Self.make(Dispatch(), orientation: .vertical, index: 0, count: 1)
        #expect(single.items.map(\.title) == ["Add Left Split", "Add Right Split", "", "Add Top Split", "Add Bottom Split"])
        #expect(single.items.filter { !$0.isSeparatorItem }.allSatisfy { $0.isEnabled })
    }

    @Test func soleRowsDispatchTheirBeforeAfterAndOrientationIdentities() {
        let dispatch = Dispatch()
        let single = Self.make(dispatch, orientation: .vertical, index: 0, count: 1)
        for item in single.items where !item.isSeparatorItem { Self.invoke(item) }
        #expect(dispatch.performed == [.addBefore, .addAfter, .addAbove, .addBelow])
    }

    @Test(arguments: [0, 5])
    func noMenuMaterializesOutsideTheContentBounds(_ count: Int) {
        let invalid = SplitPaneMenu.make(orientation: .horizontal, index: 0, count: count) { _ in
            Issue.record("an invalid menu dispatched")
            return nil
        }
        #expect(invalid.items.isEmpty)
    }

    @Test func aRefusedOwnerLeavesNoEnabledAction() {
        let refused = SplitPaneMenu.make(orientation: .horizontal, index: 1, count: 3) { _ in nil }
        #expect(refused.items.allSatisfy { $0.isSeparatorItem || !$0.isEnabled })
    }
}

@MainActor
struct SplitPaneMenuArtworkTests {
    private static var artwork: URL? {
        Bundle.module.url(forResource: "SplitViews", withExtension: nil)?.appendingPathComponent("SplitPaneMenu", isDirectory: true)
    }

    private static func pixels(_ image: NSImage, _ appearance: NSAppearance.Name) -> Data {
        let size = image.size
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance { image.draw(in: NSRect(origin: .zero, size: size)) }
        NSGraphicsContext.restoreGraphicsState()
        return Data(bytes: bitmap.bitmapData!, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }

    private static func rendition(_ file: String) throws -> NSImage {
        let directory = try #require(artwork)
        return try #require(NSImage(contentsOf: directory.appendingPathComponent(file + "@2x.png")))
    }

    private static func menu(_ orientation: SplitOrientation, index: Int, count: Int, layout: BrowserSplitLayout? = nil) -> NSMenu {
        let directory = artwork
        return SplitPaneMenu.make(orientation: orientation, index: index, count: count, layout: layout,
                                  artwork: { SplitPaneMenuArtwork.image($0, in: directory) }) { _ in {} }
    }

    private static func shows(_ menu: NSMenu, _ names: [String?]) throws -> Bool {
        guard menu.items.count == names.count else { return false }
        for (item, name) in zip(menu.items, names) {
            guard let name else {
                if !item.isSeparatorItem { return false }
                continue
            }
            guard let image = item.image else { return false }
            if #available(macOS 27, *), item.preferredImageVisibility != .visible { return false }
            let light = try rendition(name), dark = try rendition(name + "-dark")
            let matches = image.size == light.size && pixels(image, .aqua) == pixels(light, .aqua)
                && pixels(image, .darkAqua) == pixels(dark, .darkAqua) && pixels(image, .aqua) != pixels(image, .darkAqua)
            if !matches { return false }
        }
        return true
    }

    @Test func aHorizontalSplitsItemsShowTheirArtworkLightOrDarkByAppearance() throws {
        let menu = Self.menu(.horizontal, index: 0, count: 2)
        #expect(try Self.shows(menu, ["icon-split-move-left", "icon-split-move-right", nil, "icon-split-add-right", "icon-split-add-left",
                                      "icon-split-stack-add-top", "icon-split-stack-add-bottom", nil,
                                      "icon-separate-from-split", "icon-split-vertical", nil, "icon-split-copy-links-horizontal"]))
    }

    @Test func aVerticalSplitTakesTheVerticalSeparateConvertAndCopyLinksArtwork() throws {
        let menu = Self.menu(.vertical, index: 3, count: 4)
        #expect(try Self.shows(menu, ["icon-split-move-top", "icon-split-move-bottom", nil, "icon-split-add-top", "icon-split-add-bottom",
                                      "icon-split-stack-add-left", "icon-split-stack-add-right", nil,
                                      "icon-separate-from-split-menu-bottom", "icon-split-horizontal", nil,
                                      "icon-split-copy-links-vertical"]))
    }

    @Test func stackMovesShareTheMatchingMoveArtwork() throws {
        let shape = BrowserSplitLayout.shape(orientation: .horizontal, sizes: [1, 2], factors: [0.5, 0.5], stackFactors: [[1], [0.5, 0.5]])
        let layout = BrowserSplitLayout(id: UUID(), spaceID: UUID(), tabIDs: [UUID(), UUID(), UUID()], orientation: .horizontal,
                                        widthFactors: shape.widthFactors, stacks: shape.stacks)
        let menu = Self.menu(.horizontal, index: 2, count: 3, layout: layout)
        #expect(try Self.shows(menu, ["icon-split-move-left", "icon-split-move-right", "icon-split-move-top", "icon-split-move-bottom", nil,
                                      "icon-split-add-right", "icon-split-add-left", "icon-split-stack-add-top",
                                      "icon-split-stack-add-bottom", nil, "icon-separate-from-split", "icon-split-vertical", nil,
                                      "icon-split-copy-links-horizontal"]))
    }

    @Test func aSolePanesAddRowsShowTheirArtwork() throws {
        let menu = Self.menu(.vertical, index: 0, count: 1)
        #expect(try Self.shows(menu, ["icon-split-add-left", "icon-split-add-right", nil, "icon-split-add-top", "icon-split-add-bottom"]))
    }

    @Test func artworkDrawsAtItsCatalogSizes() {
        let sizes = Self.menu(.horizontal, index: 0, count: 2).items.compactMap(\.image).map(\.size)
        let eighteen = NSSize(width: 18, height: 18)
        #expect(sizes == [eighteen, eighteen, eighteen, eighteen, eighteen, eighteen, eighteen, NSSize(width: 22, height: 22), eighteen])
    }

    @Test func aMissingDirectoryYieldsNoImage() {
        #expect(SplitPaneMenuArtwork.image("icon-split-move-left", in: nil) == nil)
    }

    @Test func aMissingDarkRenditionYieldsNoImage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-split-artwork-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try #require(Self.artwork)
        try FileManager.default.copyItem(at: source.appendingPathComponent("icon-split-move-left.png"),
                                         to: directory.appendingPathComponent("icon-split-move-left.png"))
        #expect(SplitPaneMenuArtwork.image("icon-split-move-left", in: directory) == nil)
    }
}

@MainActor
struct SplitPaneLinksTests {
    private static let links = [FolderLinks.Link(tabID: UUID(), title: "Fish & <Chips>", url: "https://one.invalid/a?b=1&c=2"),
                                FolderLinks.Link(tabID: UUID(), title: "", url: "https://two.invalid/")]

    private func scratchPasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("parc-split-links-" + UUID().uuidString))
    }

    @Test func copyLinksWritesThePasteboard() {
        let pasteboard = scratchPasteboard()
        defer { pasteboard.releaseGlobally() }
        #expect(LinkPasteboard.write(Self.links, format: .plain, to: pasteboard))
    }

    @Test func plainTextTargetsGetOneBareAddressPerLineInOrder() {
        let pasteboard = scratchPasteboard()
        defer { pasteboard.releaseGlobally() }
        _ = LinkPasteboard.write(Self.links, format: .plain, to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "https://one.invalid/a?b=1&c=2\nhttps://two.invalid/")
    }

    @Test func richTextTargetsGetEachTitleLinkedToItsAddress() {
        let pasteboard = scratchPasteboard()
        defer { pasteboard.releaseGlobally() }
        _ = LinkPasteboard.write(Self.links, format: .plain, to: pasteboard)
        #expect(pasteboard.string(forType: .html) == "<meta charset=\"utf-8\"><a href=\"https://one.invalid/a?b=1&amp;c=2\">Fish &amp; &lt;Chips&gt;</a><br>\n"
                + "<a href=\"https://two.invalid/\">https://two.invalid/</a>")
    }

    @Test func markdownCopiesStayMarkdownOnly() {
        let pasteboard = scratchPasteboard()
        defer { pasteboard.releaseGlobally() }
        #expect(LinkPasteboard.write(Self.links, format: .markdown, to: pasteboard))
        #expect(pasteboard.types?.contains(.html) == false)
        #expect(pasteboard.string(forType: .string)?.hasPrefix("[Fish & \\<Chips>](<https://one.invalid/a?b=1&c=2>)") == true)
    }

    @Test func nothingToCopyLeavesThePasteboardAlone() {
        let pasteboard = scratchPasteboard()
        defer { pasteboard.releaseGlobally() }
        _ = LinkPasteboard.write(Self.links, format: .plain, to: pasteboard)
        let count = pasteboard.changeCount
        #expect(!LinkPasteboard.write([], format: .plain, to: pasteboard))
        #expect(pasteboard.changeCount == count)
    }
}

@MainActor
struct SplitPaneInsertionSessionTests {
    @MainActor private struct Fixture {
        let directory: URL
        let store: BrowserStore
        let session: SplitPaneInsertionSession
        let owner = Owner()
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        let before: BrowserState

        final class Owner { var valid = true }

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-pane-menu-" + UUID().uuidString)
            store = try BrowserStore(directory: directory)
            let id = store.open("https://original.invalid")
            let request = try #require(SplitPaneInsertion(paneID: id, operation: .addAfter, state: store.state))
            let owner = owner
            before = store.state
            session = SplitPaneInsertionSession(request: request, candidateIDs: [id]) { owner.valid }
            session.placeholder.frame = host.bounds
            host.addSubview(session.placeholder)
            session.placeholder.layoutSubtreeIfNeeded()
        }

        func cleanUp() { try? FileManager.default.removeItem(at: directory) }
    }

    @Test func aValidDraftOwnsOnePresentation() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        #expect(fixture.session.isValid)
        #expect(fixture.session.placeholder.superview === fixture.host)
    }

    @Test func theTemporaryPaneHasAnAccessibilityLabel() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        #expect(fixture.session.placeholder.accessibilityLabel() == "New split pane")
    }

    @Test func thePlaceholderDrawsNoInventedLabelOrControl() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        #expect(fixture.session.placeholder.subviews.isEmpty)
    }

    @Test(arguments: [(NSAppearance.Name.aqua, 0.666), (NSAppearance.Name.darkAqua, 0.1)])
    func theFillResolvesWhiteAtTheAppearancesAlpha(_ name: NSAppearance.Name, _ alpha: Double) throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let pending = fixture.session.placeholder
        pending.appearance = NSAppearance(named: name)
        pending.updateLayer()
        let fill = try #require(pending.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))?.usingColorSpace(.sRGB))
        #expect(fill.redComponent == 1 && fill.greenComponent == 1 && fill.blueComponent == 1)
        #expect(abs(fill.alphaComponent - alpha) < 0.0001)
    }

    @Test func thePlaceholderOwnsTheHighlightBorderLayer() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let pending = fixture.session.placeholder
        #expect(pending.layer?.sublayers?.contains(pending.splitHighlight.layer) == true)
    }

    @Test func presentingNeverCreatesASavedPage() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        #expect(fixture.store.state == fixture.before)
    }

    @Test func invalidatingTheOwnerRevokesTheTemporaryPane() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.owner.valid = false
        #expect(!fixture.session.isValid)
    }

    @Test func cancellationRemovesThePlaceholder() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.session.cancel()
        #expect(fixture.session.cancelled)
        #expect(fixture.session.placeholder.superview == nil)
    }

    @Test func aReturningOwnerCannotReviveACancelledPresentation() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.owner.valid = false
        fixture.session.cancel()
        fixture.owner.valid = true
        #expect(!fixture.session.isValid)
    }

    @Test func repeatedCancellationNeverChangesTheContentRecords() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.session.cancel()
        fixture.session.cancel()
        #expect(fixture.store.state == fixture.before)
    }
}

@MainActor
struct SplitPaneHighlightTests {
    @MainActor private struct Fixture {
        let window: NSWindow
        let paneView: NSView
        let highlight = SplitPaneHighlight()
        var shape: CAShapeLayer { highlight.layer }

        init() {
            _ = NSApplication.shared
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            paneView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
            window.contentView = paneView
            highlight.attach(to: paneView)
            CATransaction.flush()
        }

        func takeTransitions() -> [String: CFTimeInterval] {
            defer { shape.removeAllAnimations() }
            return Dictionary(uniqueKeysWithValues: (shape.animationKeys() ?? []).compactMap { key in
                shape.animation(forKey: key).map { (key, $0.duration) }
            })
        }

        func isRecovered(_ transitions: [String: CFTimeInterval]) -> Bool {
            transitions["opacity"] != nil && transitions.values.allSatisfy { abs($0 - 0.11) < 1e-9 }
        }
    }

    @Test func theLayerHasNoFillRoundJoinAndCapHighZAndStartsHidden() {
        let shape = Fixture().shape
        #expect(shape.fillColor == nil)
        #expect(shape.lineJoin == .round && shape.lineCap == .round)
        #expect(shape.zPosition == 8 && shape.opacity == 0)
    }

    @Test func theBorderStrokesTheFullContentBounds() {
        let fixture = Fixture()
        fixture.highlight.layout(bounds: fixture.paneView.bounds, cornerRadius: 6)
        #expect(fixture.shape.frame == fixture.paneView.bounds)
        #expect(fixture.shape.path?.boundingBox == CGRect(x: 0, y: 0, width: 300, height: 200))
    }

    @Test func theStrokeColorAppliesWithoutAnImplicitTransition() {
        let fixture = Fixture()
        fixture.highlight.color = NSColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 1)
        #expect(fixture.shape.strokeColor != nil)
        #expect(fixture.shape.animationKeys()?.isEmpty != false)
    }

    @Test func focusedMultiPaneContentShowsTheTwoPointBorder() {
        #expect(SplitPaneHighlightState.resolve(isProposedDropTarget: false, isFocused: true, paneCount: 2, dragEditActive: false)
                == SplitPaneHighlightState(display: true, width: 2))
    }

    @Test func aProposedReplacementShowsTheThreePointBorderDuringADrag() {
        #expect(SplitPaneHighlightState.resolve(isProposedDropTarget: true, isFocused: false, paneCount: 2, dragEditActive: true)
                == SplitPaneHighlightState(display: true, width: 3))
    }

    @Test func aDragEditHidesTheFocusBorder() {
        #expect(!SplitPaneHighlightState.resolve(isProposedDropTarget: false, isFocused: true, paneCount: 2, dragEditActive: true).display)
    }

    @Test func aSingleContentShowsNoFocusBorder() {
        #expect(!SplitPaneHighlightState.resolve(isProposedDropTarget: false, isFocused: true, paneCount: 1, dragEditActive: false).display)
    }

    @Test func theFirstPublishedStateAppliesImmediately() {
        let fixture = Fixture()
        fixture.highlight.update(display: false, width: 2)
        #expect(fixture.shape.opacity == 0 && fixture.shape.lineWidth == 4)
        #expect(fixture.takeTransitions().isEmpty)
    }

    @Test func theVisibleWidthIsHalfTheDoubledStrokeAndOpacityIsOne() {
        let fixture = Fixture()
        fixture.highlight.update(display: false, width: 2)
        fixture.highlight.update(display: true, width: 3)
        #expect(fixture.shape.opacity == 1 && fixture.shape.lineWidth == 6)
    }

    @Test func aDisplayedStateChangeUsesTheElevenHundredthsTransition() {
        let fixture = Fixture()
        fixture.highlight.update(display: false, width: 2)
        _ = fixture.takeTransitions()
        fixture.highlight.update(display: true, width: 3)
        #expect(fixture.isRecovered(fixture.takeTransitions()))
    }

    @Test func aWidthOnlyChangeAppliesWithoutATransition() {
        let fixture = Fixture()
        fixture.highlight.update(display: true, width: 3)
        _ = fixture.takeTransitions()
        fixture.highlight.update(display: true, width: 2)
        #expect(fixture.shape.lineWidth == 4)
        #expect(fixture.takeTransitions().isEmpty)
    }

    @Test func hidingUsesTheSameTransition() {
        let fixture = Fixture()
        fixture.highlight.update(display: true, width: 2)
        _ = fixture.takeTransitions()
        fixture.highlight.update(display: false, width: 2)
        #expect(fixture.shape.opacity == 0)
        #expect(fixture.isRecovered(fixture.takeTransitions()))
    }

    @Test func aHiddenHostUpdatesImmediately() {
        let fixture = Fixture()
        fixture.highlight.update(display: false, width: 2)
        _ = fixture.takeTransitions()
        fixture.paneView.isHidden = true
        fixture.highlight.update(display: true, width: 2)
        #expect(fixture.shape.opacity == 1)
        #expect(fixture.takeTransitions().isEmpty)
    }

    @Test func thePathFollowsTheHostsBoundsTransitionFromItsPreviousSize() throws {
        let fixture = Fixture()
        fixture.highlight.layout(bounds: fixture.paneView.bounds, cornerRadius: 6)
        let animation = CABasicAnimation(keyPath: "bounds")
        animation.duration = 0.2
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        fixture.highlight.followLayout(from: CGRect(x: 0, y: 0, width: 200, height: 200), animation: animation)
        let follow = try #require(fixture.shape.animation(forKey: "Split pane highlight layout") as? CABasicAnimation)
        #expect(follow.keyPath == "path")
        #expect(follow.duration == 0.2)
        #expect((follow.fromValue as! CGPath).boundingBox.width == 200)
    }

    @Test func cancellingTheHostTransitionRemovesThePathTransition() {
        let fixture = Fixture()
        fixture.highlight.layout(bounds: fixture.paneView.bounds, cornerRadius: 6)
        fixture.highlight.followLayout(from: CGRect(x: 0, y: 0, width: 200, height: 200), animation: CABasicAnimation(keyPath: "bounds"))
        #expect(fixture.shape.animation(forKey: "Split pane highlight layout") != nil)
        fixture.highlight.cancelFollow()
        #expect(fixture.shape.animation(forKey: "Split pane highlight layout") == nil)
    }
}
