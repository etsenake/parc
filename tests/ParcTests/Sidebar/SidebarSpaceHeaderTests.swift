import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SidebarSpaceHeaderTests {
    typealias L = SidebarChromeLayout
    typealias H = L.SpaceHeader
    typealias Content = H.Content

    final class FlippedHost: NSView { override var isFlipped: Bool { true } }

    static func space(_ name: String, icon: SidebarGroupIcon? = nil) -> BrowserSpace {
        var space = BrowserSpace(id: UUID(), name: name, symbol: "circle.fill", color: "B9B5D4", profileID: UUID())
        space.customIcon = icon
        if name.hasPrefix("Space "), Int(name.dropFirst(6)) != nil { space.title = nil }
        return space
    }
    static func content(_ spaces: [BrowserSpace], _ active: BrowserSpace?, privateWindow: Bool = false, setting: Bool = false) -> Content {
        H.content(spaces: spaces, activeSpaceID: active?.id, privateWindow: privateWindow, showOnSingleUnnamedSpace: setting)
    }
    static func titled(_ name: String) -> Content { Content(isShown: true, title: name, placeholder: nil, toggleTitle: nil) }
    static func components(_ color: NSColor?) -> [CGFloat]? {
        guard let color = color?.usingColorSpace(.sRGB) else { return nil }
        return [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent].map { ($0 * 1000).rounded() / 1000 }
    }
    static func components(_ color: CGColor?) -> [CGFloat]? { components(color.flatMap { NSColor(cgColor: $0) }) }
    static func pixels(_ view: NSView) -> Data? {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.bitmapData.map { Data(bytes: $0, count: rep.bytesPerRow * rep.pixelsHigh) }
    }
    static let base = ["Rename Space…", "Edit Theme Color…", "New Folder"]
    static let star = NSImage(systemSymbolName: "star", accessibilityDescription: nil)
    static var ellipsis: NSImage? {
        NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
    }

    @Test func aFreshSingleSpaceHasNoHeaderThePlaceholderAndShowSpaceHeader() {
        let first = Self.space("Space 1")
        #expect(Self.content([first], first) == Content(isShown: false, title: "", placeholder: "Space 1", toggleTitle: "Show Space Header"))
    }

    @Test func theSettingShowsItAndTheMenuOffersHideSpaceHeader() {
        let first = Self.space("Space 1")
        #expect(Self.content([first], first, setting: true) == Content(isShown: true, title: "", placeholder: "Space 1", toggleTitle: "Hide Space Header"))
    }

    @Test func aSecondSpaceShowsTheHeaderWithEachPositionsPlaceholderAndNoToggle() {
        let first = Self.space("Space 1"), second = Self.space("Space 2")
        #expect(Self.content([first, second], first) == Content(isShown: true, title: "", placeholder: "Space 1", toggleTitle: nil))
        #expect(Self.content([first, second], second) == Content(isShown: true, title: "", placeholder: "Space 2", toggleTitle: nil))
    }

    @Test func renamingFromSpaceOneTitlesIt() {
        var first = Self.space("Space 1")
        first.name = "Work"
        #expect(Self.content([first], first) == Self.titled("Work"))
    }

    @Test func explicitlyRenamingToSpaceOneKeepsAnAuthoredTitle() {
        var first = Self.space("Space 1")
        first.name = "Work"
        first.name = "Space 1"
        #expect(Self.content([first], first) == Self.titled("Space 1"))
    }

    @Test func anEmptyNameIsUntitled() {
        var first = Self.space("Space 1")
        first.name = "Work"
        first.name = ""
        #expect(Self.content([first], first) == Content(isShown: false, title: "", placeholder: "Space 1", toggleTitle: "Show Space Header"))
    }

    @Test func spaceOneInTheSecondPositionIsATitle() {
        var first = Self.space("Space 1")
        first.name = ""
        first.name = "Space 1"
        #expect(Self.content([Self.space("Space 2"), first], first) == Self.titled("Space 1"))
    }

    @Test func aCustomIconShowsTheHeaderAndDropsTheToggle() {
        let starred = Self.space("Space 1", icon: .symbol("star"))
        #expect(Self.content([starred], starred) == Content(isShown: true, title: "", placeholder: "Space 1", toggleTitle: nil))
    }

    @Test func neverInAPrivateWindow() {
        let first = Self.space("Space 1"), second = Self.space("Space 2"), starred = Self.space("Space 1", icon: .symbol("star"))
        #expect(!Self.content([first, second, starred], starred, privateWindow: true, setting: true).isShown)
        #expect(!Self.content([first], first, privateWindow: true, setting: true).isShown)
    }

    @Test func noActiveSpaceNoHeader() {
        #expect(Self.content([Self.space("Space 1")], nil) == Content(isShown: false, title: "", placeholder: nil, toggleTitle: nil))
    }

    @Test func aControlDoubleClickARenameDoubleClickOrATripleClickLeavesTheNameAlone() {
        #expect(!H.beginsRename(clickCount: 2, modifiers: .control, editing: false))
        #expect(!H.beginsRename(clickCount: 2, modifiers: [], editing: true))
        #expect(!H.beginsRename(clickCount: 3, modifiers: [], editing: false))
    }

    @MainActor final class Header {
        let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 228, height: 400), styleMask: [.borderless], backing: .buffered, defer: true)
        let host = FlippedHost(frame: NSRect(x: 0, y: 0, width: 228, height: 400))
        let header = SidebarSpaceHeaderView()
        let list = NSView()
        var scheduled: [(delay: TimeInterval, body: @MainActor () -> Void)] = []
        var calls: [String] = []

        init(_ content: Content? = nil, icon: Bool = true) {
            let content = content ?? SidebarSpaceHeaderTests.titled("Work")
            let symbol = icon ? SidebarSpaceHeaderTests.star : nil
            window.isReleasedWhenClosed = false
            host.wantsLayer = true
            host.appearance = NSAppearance(named: .aqua)
            window.contentView = host
            host.addSubview(header); host.addSubview(list)
            header.scheduleHoverUpdate = { [weak self] in guard let self else { return }; scheduled.append(($0, $1)) }
            header.frame = NSRect(x: 0, y: H.top(trayHeight: 0, hasFavorites: false), width: 228, height: H.height)
            list.frame = NSRect(x: 8, y: L.tablistTop(trayHeight: 0, spaceHeader: true), width: 212, height: 100)
            header.update(content, symbol: symbol, emoji: nil)
            header.layoutSubtreeIfNeeded()
            header.onRenameSpace = { [weak self] in guard let self else { return }; calls.append("rename") }
            header.onEditTheme = { [weak self] in guard let self else { return }; calls.append("theme") }
            header.onNewFolder = { [weak self] in guard let self else { return }; calls.append("folder") }
            header.onToggleHeader = { [weak self] in guard let self else { return }; calls.append("toggle") }
        }

        deinit { MainActor.assumeIsolated { window.contentView = nil } }

        var field: SidebarMaskedTextField { header.nameField }
        var button: SidebarSpaceHeaderEditButton { header.editButton }
        var symbolView: NSImageView { header.subviews.compactMap { $0 as? NSImageView }.first! }
        var emoji: NSTextField { header.subviews.compactMap { $0 as? NSTextField }.first { $0 !== header.nameField }! }
        var titleHeight: CGFloat { field.intrinsicContentSize.height }

        func runScheduled(_ observe: () -> Void = {}) {
            while !scheduled.isEmpty {
                let pending = scheduled.enumerated().sorted { ($0.element.delay, $0.offset) < ($1.element.delay, $1.offset) }.map(\.element)
                scheduled.removeAll()
                for item in pending { item.body(); observe() }
            }
        }
        func crossing(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.enterExitEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                   context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        }
        func enter() { header.mouseEntered(with: crossing(.mouseEntered)) }
        func exit() { header.mouseExited(with: crossing(.mouseExited)) }
        func showButton() {
            header.canShowHeaderButtonsIfPossible = true
            enter(); runScheduled()
        }
        var click: NSEvent? {
            NSEvent.mouseEvent(with: .rightMouseDown, location: header.convert(NSPoint(x: 100, y: 18), to: nil), modifierFlags: [], timestamp: 0,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
        }
        func press(clickCount: Int, modifiers: NSEvent.ModifierFlags = []) {
            guard let event = NSEvent.mouseEvent(with: .leftMouseDown, location: header.convert(NSPoint(x: 100, y: 18), to: nil),
                                                 modifierFlags: modifiers, timestamp: 0, windowNumber: window.windowNumber,
                                                 context: nil, eventNumber: 0, clickCount: clickCount, pressure: 1) else { return }
            header.mouseDown(with: event)
        }
        func fill() -> [CGFloat]? { button.display(); return SidebarSpaceHeaderTests.components(button.layer?.backgroundColor) }
        var opacityFade: CABasicAnimation? { button.layer?.animation(forKey: "opacity") as? CABasicAnimation }
        var exposed: [NSObject] {
            NSAccessibility.unignoredChildren(from: header.accessibilityChildren() ?? []).compactMap { $0 as? NSObject }
        }
    }

    private static func controlPoints(_ function: CAMediaTimingFunction?) -> [Float]? {
        guard let function else { return nil }
        return (0..<4).flatMap { index -> [Float] in
            var point: [Float] = [0, 0]
            function.getControlPoint(at: index, values: &point)
            return point
        }
    }
    private static func isEditFade(_ fade: CABasicAnimation?) -> Bool {
        fade?.duration == 0.1 && controlPoints(fade?.timingFunction) == controlPoints(CAMediaTimingFunction(name: .easeOut))
    }

    @Test func theHeaderSpansTheSidebarAndTheListFollowsIt() {
        let header = Header()
        #expect(header.header.frame == NSRect(x: 0, y: 90, width: 228, height: 36) && header.list.frame.minY == header.header.frame.maxY)
    }

    @Test func aSymbolIconFillsTheTwentyFourPointSlotAtTheFourteenPointInset() {
        let header = Header()
        let frames = H.frames(width: 228, icon: true, titleHeight: header.titleHeight)
        #expect(!header.symbolView.isHidden && header.symbolView.frame == frames.icon)
        #expect(header.symbolView.frame == NSRect(x: 14, y: 6, width: 24, height: 24))
        #expect(header.emoji.isHidden)
    }

    @Test func theNameSitsBetweenTheIconAndTheEditButtonsSlotCentred() {
        let header = Header()
        let frames = H.frames(width: 228, icon: true, titleHeight: header.titleHeight)
        #expect(header.field.frame == frames.title && header.field.frame.minX == 42 && header.field.frame.maxX == 210)
        #expect(abs(header.field.frame.midY - 18) < 0.001)
    }

    @Test func aTitleIsTheFieldsTextInThirteenPointSemibold() {
        let header = Header()
        #expect(header.field.stringValue == "Work" && header.field.placeholderString == nil)
        #expect(header.field.font == NSFont.systemFont(ofSize: 13, weight: .semibold))
    }

    @Test func theFieldIsAStaticSingleTruncatingLine() {
        let field = Header().field
        #expect(!field.isEditable && !field.isSelectable && !field.isBezeled && field.usesSingleLineMode && field.focusRingType == .none)
        #expect(field.lineBreakMode == .byTruncatingTail && field.alignmentRectInsets.left == 0 && field.alignmentRectInsets.right == 0)
    }

    @Test func aLightThemeUsesTheDarkerForegroundAndTertiaryIcon() {
        let header = Header()
        #expect(Self.components(header.field.textColor) == [0, 0, 0, 0.45])
        #expect(Self.components(header.symbolView.contentTintColor) == [0, 0, 0, 0.3])
    }

    @Test func aDarkThemeUsesWhite() {
        let header = Header()
        header.header.applyStyle(dark: true, tint: nil)
        #expect(Self.components(header.field.textColor) == [1, 1, 1, 0.45] && Self.components(header.symbolView.contentTintColor) == [1, 1, 1, 0.3])
    }

    @Test func aDarkThemeSetsNoAppearanceAndTheHeaderFollowsTheSidebars() {
        let header = Header()
        header.header.applyStyle(dark: true, tint: nil)
        #expect(header.header.appearance == nil && header.header.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua)
        header.host.appearance = NSAppearance(named: .darkAqua)
        #expect(header.header.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
    }

    @Test func theHeadersTintColoursTheIcon() {
        let header = Header()
        header.header.applyStyle(dark: false, tint: .systemRed)
        #expect(header.symbolView.contentTintColor == .systemRed && header.header.appearance == nil)
    }

    @MainActor final class Private {
        let header = SidebarSpaceHeaderView(frame: NSRect(x: 0, y: 0, width: 212, height: 36))
        var indicator: IncognitoProfileIndicatorView { header.incognitoIndicator }
        var icon: NSImageView { indicator.subviews.compactMap { $0 as? NSImageView }.first! }
        var label: NSTextField { indicator.subviews.compactMap { $0 as? NSTextField }.first! }
        init() {
            header.update(SidebarSpaceHeaderTests.titled("Incognito Tabs"), symbol: nil, emoji: nil)
            header.updateIncognitoIndicator(shown: true)
            header.applyStyle(dark: true, tint: nil)
            header.layoutSubtreeIfNeeded()
        }
    }

    @Test func theIncognitoIndicatorReplacesThePrivateTitleLeftAligned() {
        let header = Private()
        #expect(header.header.nameField.isHidden && !header.indicator.isHidden)
        #expect(header.indicator.parcTooltip?.label == "Incognito tabs" && header.indicator.toolTip == nil)
        #expect(header.indicator.frame.minX == 10.5 && abs(header.indicator.frame.midY - 21) < 0.001)
    }

    @Test func theIndicatorCentresItsIconAndLabelWithRecoveredPadding() {
        let header = Private()
        let height = header.label.intrinsicContentSize.height + 8
        #expect(header.indicator.frame.height == height && header.indicator.frame.width == 33 + header.label.intrinsicContentSize.width)
        #expect(header.icon.frame == NSRect(x: 5, y: 4, width: 20, height: height - 8))
        #expect(header.label.frame.minX == 27 && header.label.frame.maxX == header.indicator.bounds.maxX - 6)
        #expect(header.label.frame.midY == header.indicator.bounds.midY)
    }

    @Test func theIndicatorUsesMediumElevenPointTextAndSymbolInTertiaryForeground() {
        let header = Private()
        #expect(header.label.font == NSFont.systemFont(ofSize: 11, weight: .medium))
        #expect(header.icon.symbolConfiguration == NSImage.SymbolConfiguration(pointSize: 11, weight: .medium))
        #expect(header.icon.imageScaling == .scaleNone && header.icon.imageAlignment == .alignCenter)
        #expect(Self.components(header.label.textColor) == [1, 1, 1, 0.3] && Self.components(header.icon.contentTintColor) == [1, 1, 1, 0.3])
    }

    @Test func theDarkIdleIndicatorHasAContinuousGrayCapsule() {
        let header = Private()
        let height = header.label.intrinsicContentSize.height + 8
        #expect(header.indicator.layer?.cornerCurve == .continuous && header.indicator.layer?.cornerRadius == height / 2)
        #expect(Self.components(header.indicator.layer?.backgroundColor) == [0.11, 0.11, 0.11, 0.3])
    }

    @Test func theLightIndicatorUsesTertiaryForegroundAndAGrayCapsule() {
        let header = Private()
        header.header.applyStyle(dark: false, tint: nil)
        #expect(Self.components(header.label.textColor) == [0, 0, 0, 0.3] && Self.components(header.icon.contentTintColor) == [0, 0, 0, 0.3])
        #expect(Self.components(header.indicator.layer?.backgroundColor) == [0.973, 0.973, 0.973, 0.3])
    }

    @Test func theIndicatorIsInformationalTextWithNoPointerOrAccessibilityAction() {
        let indicator = Private().indicator
        #expect(indicator.hitTest(NSPoint(x: 1, y: 1)) == nil)
        #expect(indicator.isAccessibilityElement() && indicator.accessibilityRole() == .staticText)
        #expect(indicator.accessibilityValue() as? String == "Incognito" && indicator.accessibilityChildren()?.isEmpty == true)
        #expect(!indicator.accessibilityPerformPress())
        #expect(!indicator.isAccessibilitySelectorAllowed(#selector(NSAccessibilityProtocol.accessibilityPerformPress)))
    }

    @Test func hidingTheIndicatorRestoresThePrivateTitle() {
        let header = Private()
        header.header.updateIncognitoIndicator(shown: false)
        header.header.layoutSubtreeIfNeeded()
        let field = header.header.nameField
        #expect(!field.isHidden && header.indicator.isHidden && field.stringValue == "Incognito Tabs")
        #expect(field.frame.minX == 14 && abs(field.frame.midY - 21) < 0.001)
    }

    @Test func anEmojiIconIsCentredInTheSameSlot() {
        let header = Header()
        header.header.update(Self.titled("Trips"), symbol: nil, emoji: "🌴")
        header.header.layoutSubtreeIfNeeded()
        let emoji = header.emoji
        #expect(header.symbolView.isHidden && !emoji.isHidden && emoji.stringValue == "🌴")
        #expect(emoji.frame.minX == 14 && emoji.frame.width == 24 && abs(emoji.frame.midY - 18) < 0.001 && header.field.frame.minX == 42)
    }

    @Test func withoutACustomIconTheIconHidesAndTheNameLeads() {
        let header = Header()
        header.header.update(Self.titled("Space 2"), symbol: nil, emoji: nil)
        header.header.layoutSubtreeIfNeeded()
        #expect(header.symbolView.isHidden && header.emoji.isHidden)
        #expect(header.field.frame == H.frames(width: 228, icon: false, titleHeight: header.titleHeight).title)
        #expect(header.field.frame.minX == 14 && header.field.frame.maxX == 210)
    }

    @Test func aLongNameStaysOneTruncatedLineInsideTheSlot() {
        let header = Header()
        header.header.update(Self.titled(String(repeating: "Long Space Name ", count: 6)), symbol: nil, emoji: nil)
        header.header.layoutSubtreeIfNeeded()
        #expect(header.field.frame.maxX == 210 && header.field.frame.height == header.titleHeight)
    }

    private func masked() -> (Header, CAGradientLayer) {
        let header = Header()
        header.header.update(Self.titled(String(repeating: "Long Space Name ", count: 6)), symbol: nil, emoji: nil)
        header.header.layoutSubtreeIfNeeded()
        header.field.needsLayout = true
        header.header.layoutSubtreeIfNeeded()
        return (header, header.field.leadingMask)
    }
    private static let changed = Notification(name: NSText.didChangeNotification, object: NSTextView())

    @Test func theLeadingMaskRunsClearToBlackAndTheHeaderEnablesMasking() {
        let (header, mask) = masked()
        #expect((mask.colors as? [CGColor]) == [NSColor.clear.cgColor, NSColor.black.cgColor])
        #expect(mask.startPoint == CGPoint(x: 0, y: 0.5) && mask.endPoint == CGPoint(x: 1, y: 0.5) && header.field.isMaskingEnabled)
    }

    @Test func layoutGivesTheMaskTheFieldsBoundsAndASixteenPointRamp() {
        let (header, mask) = masked()
        #expect(mask.frame == header.field.bounds && (mask.locations?.map(\.doubleValue) ?? []) == [0, Double(16 / header.field.bounds.width)])
    }

    @Test func theRestingFieldIsNotEditableSoATruncatedNameIsNotMasked() {
        let (header, _) = masked()
        header.field.updateMask(true); header.field.textDidChange(Self.changed)
        #expect(header.field.layer != nil && header.field.layer?.mask == nil)
    }

    @Test func anEditableFieldWithTextThatDoesNotFitMasksItsLeadingEdge() {
        let (header, mask) = masked()
        header.field.isEditable = true
        header.field.textDidChange(Self.changed)
        #expect(header.field.layer?.mask === mask)
    }

    @Test func disablingMaskingRemovesTheMaskAndEnablingItWaitsForTheNextEvaluation() {
        let (header, mask) = masked()
        header.field.isEditable = true
        header.field.textDidChange(Self.changed)
        header.field.isMaskingEnabled = false
        #expect(header.field.layer?.mask == nil)
        header.field.isMaskingEnabled = true
        #expect(header.field.layer?.mask == nil)
        header.field.updateMask(true)
        #expect(header.field.layer?.mask === mask)
    }

    @Test func endingEditingClearsTheMask() {
        let (header, _) = masked()
        header.field.isEditable = true
        header.field.textDidChange(Self.changed)
        header.field.textDidEndEditing(Notification(name: NSText.didEndEditingNotification, object: NSTextView()))
        #expect(header.field.layer?.mask == nil)
    }

    @Test func textThatFitsIsNotMasked() {
        let (header, _) = masked()
        header.field.isEditable = true
        header.header.update(Self.titled("Work"), symbol: nil, emoji: nil)
        header.field.updateMask(true)
        #expect(header.field.layer?.mask == nil)
    }

    private func placeholder() -> (Header, SidebarSpaceHeaderView) {
        var first = Self.space("Space 1")
        first.title = nil
        let header = Header(Self.content([first], first, setting: true), icon: false)
        let reference = SidebarSpaceHeaderView()
        header.host.addSubview(reference)
        reference.frame = NSRect(x: 0, y: 200, width: 228, height: H.height)
        reference.update(Self.titled("Space 1"), symbol: nil, emoji: nil)
        reference.layoutSubtreeIfNeeded()
        return (header, reference)
    }

    @Test func thePlaceholderIsAppKitsInTheSameSlotAsATitle() {
        let (header, reference) = placeholder()
        #expect(header.field.stringValue == "" && header.field.placeholderString == "Space 1" && header.field.placeholderAttributedString == nil)
        #expect(header.field.intrinsicContentSize.height == reference.nameField.intrinsicContentSize.height)
        #expect(header.field.frame == reference.nameField.frame)
    }

    @Test(arguments: [false, true])
    func thePlaceholderDrawsInPlaceholderTextColorNotTheDarkerForeground(_ dark: Bool) {
        let (header, reference) = placeholder()
        header.host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        header.header.applyStyle(dark: dark, tint: nil); reference.applyStyle(dark: dark, tint: nil)
        let name = Self.pixels(reference.nameField)
        reference.nameField.textColor = .placeholderTextColor
        let drawn = Self.pixels(header.field), expected = Self.pixels(reference.nameField)
        #expect(drawn != nil && drawn == expected && drawn != name)
    }

    @Test func anUntitledSpaceReadsAsAnEmptyValueWithThePlaceholder() {
        let (header, _) = placeholder()
        let element = header.exposed.first as? NSCell
        #expect(element?.accessibilityValue() as? String == "" && element?.accessibilityPlaceholderValue() == "Space 1")
    }

    @Test func theHeaderExposesTheNameFieldsCellThenTheRestingEditButtons() {
        let header = Header()
        let children = header.exposed
        #expect(children.count == 2 && children.first === header.field.cell && children.last === header.button.cell)
    }

    @Test func aTitleReadsAsStaticTextWithTheSpaceNameIdentifier() throws {
        let header = Header()
        let name = try #require(header.exposed.first as? NSCell)
        #expect(name.accessibilityRole() == .staticText && name.accessibilityValue() as? String == "Work" && name.accessibilityPlaceholderValue() == nil)
        #expect(name.accessibilityIdentifier() == "sidebarSpaceName" && header.field.accessibilityIdentifier() == "sidebarSpaceName")
    }

    @Test func theEditButtonIsAnAXButtonWithItsIdentifierAndNoLabelOrTooltipOfItsOwn() throws {
        let header = Header()
        let edit = try #require(header.exposed.last as? NSCell)
        let plain = NSButton(frame: .zero)
        plain.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "")
        #expect(edit.accessibilityRole() == .button && edit.accessibilityIdentifier() == "sidebarSpaceEditButton")
        #expect(header.button.accessibilityIdentifier() == "sidebarSpaceEditButton")
        #expect(edit.accessibilityLabel() == plain.cell?.accessibilityLabel() && header.button.toolTip == nil)
    }

    @Test func aShownEmojiIconIsNotAnElement() {
        let header = Header()
        header.header.update(Self.titled("Trips"), symbol: nil, emoji: "🌴")
        #expect(header.exposed.count == 2 && !header.emoji.isAccessibilityElement() && header.emoji.cell?.isAccessibilityElement() == false)
    }

    @Test func theSymbolViewAndTheHeaderAreNotElements() {
        let header = Header()
        #expect(!header.symbolView.isAccessibilityElement() && !header.header.isAccessibilityElement())
    }

    @Test func aTitledSpacesRightClickMenuHasTheSpaceTitlesAndNoToggle() {
        let header = Header()
        let menu = header.click.flatMap { header.header.menu(for: $0) }
        #expect(menu?.items.map(\.title) == Self.base && menu?.items.allSatisfy(\.isEnabled) == true)
        #expect((header.field.cell?.accessibilityCustomActions() ?? []).map(\.name) == Self.base)
    }

    private func untitledShown() -> Header {
        var first = Self.space("Space 1")
        first.title = nil
        let header = Header()
        header.header.update(Self.content([first], first, setting: true), symbol: nil, emoji: nil)
        return header
    }

    @Test func oneUntitledSpaceShownByTheSettingOffersHideSpaceHeaderLastAndEachItemRunsItsAction() {
        let header = untitledShown()
        let menu = header.click.flatMap { header.header.menu(for: $0) }
        #expect(menu?.items.map(\.title) == Self.base + ["Hide Space Header"] && menu?.items.allSatisfy(\.isEnabled) == true)
        for index in 0..<(menu?.items.count ?? 0) { menu?.performActionForItem(at: index) }
        #expect(header.calls == ["rename", "theme", "folder", "toggle"])
    }

    @Test func voiceOverGetsTheSameActionsWhichRunTheSameParcActions() {
        let header = untitledShown()
        let actions = header.field.cell?.accessibilityCustomActions() ?? []
        #expect(actions.map(\.name) == Self.base + ["Hide Space Header"])
        #expect((header.field.accessibilityCustomActions() ?? []).map(\.name) == actions.map(\.name))
        for action in actions { _ = action.handler?() }
        #expect(header.calls == ["rename", "theme", "folder", "toggle"])
    }

    @Test func theToggleLeavesWithTheContentsToggleTitle() {
        let header = untitledShown()
        header.header.update(Self.titled("Work"), symbol: nil, emoji: nil)
        #expect(header.header.makeMenu().items.map(\.title) == Self.base && (header.field.cell?.accessibilityCustomActions() ?? []).count == 3)
    }

    @Test func aSingleClickOnTheNameDoesNotRename() {
        let header = Header(icon: false)
        header.press(clickCount: 1)
        #expect(header.calls.isEmpty)
    }

    @Test func doubleClickingTheNameStartsRename() {
        let header = Header(icon: false)
        header.press(clickCount: 2)
        #expect(header.calls == ["rename"])
    }

    @Test(arguments: [NSEvent.ModifierFlags.command, .shift, .option])
    func aModifiedDoubleClickDoesNotRename(_ modifiers: NSEvent.ModifierFlags) {
        let header = Header(icon: false)
        header.press(clickCount: 2, modifiers: modifiers)
        #expect(header.calls.isEmpty)
    }

    @Test func atRestTheEditButtonIsTheLastViewZeroWidthAtTheTrailingInsetAndClear() {
        let header = Header(icon: false)
        header.header.display()
        let rest = H.frames(width: 228, icon: false, titleHeight: header.titleHeight)
        #expect(!header.header.canShowHeaderButtonsIfPossible && header.header.subviews.last === header.button)
        #expect(!header.button.isHidden && header.button.alphaValue == 0)
        #expect(header.button.frame == rest.editButton && header.button.frame == NSRect(x: 214, y: 6, width: 0, height: 24))
        #expect(header.field.frame == rest.title && header.field.frame.maxX == 210)
    }

    @Test func theEditButtonIsABorderlessMomentaryEllipsis() {
        let button = Header().button
        let momentary = NSButton(frame: .zero)
        momentary.setButtonType(.momentaryChange)
        #expect(button.image?.tiffRepresentation != nil && button.image?.tiffRepresentation == Self.ellipsis?.tiffRepresentation)
        #expect(button.title == "" && !button.isBordered && button.alignment == .center)
        #expect(button.alignmentRectInsets.left == 0 && button.alignmentRectInsets.right == 0)
        #expect(button.alignmentRectInsets.top == 0 && button.alignmentRectInsets.bottom == 0)
        #expect((button.cell as? NSButtonCell)?.highlightsBy == (momentary.cell as? NSButtonCell)?.highlightsBy)
        #expect((button.cell as? NSButtonCell)?.showsStateBy == (momentary.cell as? NSButtonCell)?.showsStateBy)
    }

    @Test func theEditButtonIsGrayA11InALightThemeAimedAtItsAction() {
        let header = Header()
        #expect(Self.components(header.button.contentTintColor) == [0, 0, 0, 0.565])
        #expect(header.button.target === header.header && header.button.action == NSSelectorFromString("didClickEditButton:"))
    }

    @Test func theHeaderAndTheButtonTrackOnlyInTheKeyWindow() {
        let header = Header()
        let options = { (view: NSView) in view.trackingAreas.filter { $0.owner === view && !$0.options.contains(.cursorUpdate) }.map(\.options.rawValue) }
        #expect(options(header.header) == [0x223] && options(header.button) == [0x223] && !header.window.isKeyWindow)
    }

    @Test func hoveredWithoutTheGateTheButtonStaysHidden() {
        let header = Header(icon: false)
        header.enter(); header.runScheduled()
        #expect(header.header.isHovered && header.button.frame.width == 0 && header.button.alphaValue == 0)
    }

    @Test func theGateAloneShowsNothing() {
        let header = Header(icon: false)
        header.header.canShowHeaderButtonsIfPossible = true
        #expect(header.button.frame.width == 0 && header.button.alphaValue == 0)
    }

    @Test func hoveringShowsTheButtonATenthOfASecondLaterNotAtOnce() {
        let header = Header(icon: false)
        header.header.canShowHeaderButtonsIfPossible = true
        header.enter()
        #expect(header.header.isHovered && header.button.frame.width == 0 && header.button.alphaValue == 0)
        #expect(header.scheduled.map(\.delay) == [0.1])
        header.runScheduled()
        #expect(header.button.frame.width == 24 && header.button.alphaValue == 1)
    }

    @Test func theShownButtonSitsAtTheTrailingEdgeAndTheNameEndsFourBeforeIt() {
        let header = Header(icon: false)
        header.showButton()
        let shown = H.frames(width: 228, icon: false, titleHeight: header.titleHeight, editButtonWidth: 24)
        #expect(header.button.frame == shown.editButton && header.button.frame == NSRect(x: 190, y: 6, width: 24, height: 24))
        #expect(header.field.frame == shown.title && header.field.frame.maxX == 186 && !header.button.isHidden)
    }

    @Test func theEllipsisDraws() {
        let header = Header(icon: false)
        header.showButton()
        #expect(Self.pixels(header.button).map { !$0.allSatisfy { $0 == 0 } } == true)
    }

    @Test func hoverOutIsDispatchedNotAppliedInTheExitMessage() {
        let header = Header(icon: false)
        header.showButton()
        header.exit()
        #expect(header.button.frame.width == 24 && header.button.alphaValue == 1)
        #expect(header.scheduled.map(\.delay) == [0])
    }

    @Test func withoutACustomIconTheWidthSnapsToZeroAndTheAlphaFadesOut() {
        let header = Header(icon: false)
        header.showButton()
        header.exit(); header.runScheduled()
        #expect(header.button.frame.width == 0 && header.button.alphaValue == 0 && Self.isEditFade(header.opacityFade))
        #expect(!header.button.isHidden && header.field.frame.maxX == 210)
    }

    @Test func aHoverShorterThanATenthNeverShowsTheButton() {
        let header = Header(icon: false)
        header.header.canShowHeaderButtonsIfPossible = true
        header.enter(); header.exit()
        var flashed = false
        header.runScheduled { flashed = flashed || header.button.frame.width > 0 || header.button.alphaValue > 0 }
        #expect(!flashed && !header.header.isHovered)
    }

    @Test func withAnIconTheButtonShowsAtFullAlphaWithItsWidthWhenTheDelayEnds() {
        let header = Header()
        header.showButton()
        #expect(header.button.frame.width == 24 && header.button.alphaValue == 1)
        #expect(header.button.frame == H.frames(width: 228, icon: true, titleHeight: header.titleHeight, editButtonWidth: 24).editButton)
        #expect(header.field.frame.maxX == 186)
    }

    @Test func withAnIconTheButtonHidesWithoutAFade() {
        let header = Header()
        header.showButton()
        header.exit(); header.runScheduled()
        #expect(header.button.frame.width == 0 && header.button.alphaValue == 0 && header.opacityFade == nil)
    }

    @Test func anUnhoveredButtonIsClearWithSixPointContinuousCorners() {
        let header = Header()
        header.showButton()
        #expect(header.fill() == [0, 0, 0, 0])
        #expect(header.button.layer?.cornerRadius == 6 && header.button.layer?.cornerCurve == .continuous && header.button.layer?.borderWidth == 0)
    }

    @Test func aHoveredButtonFillsWithGrayA4AndKeepsItsTint() {
        let header = Header()
        header.showButton()
        header.button.mouseEntered(with: header.crossing(.mouseEntered))
        #expect(header.button.isHovered && header.header.isHovered && header.fill() == [0, 0, 0, 0.071])
        #expect(Self.components(header.button.contentTintColor) == [0, 0, 0, 0.565])
    }

    @Test func aHoveredButtonInADarkThemeUsesWhite() {
        let header = Header()
        header.showButton()
        header.button.mouseEntered(with: header.crossing(.mouseEntered))
        header.header.applyStyle(dark: true, tint: nil)
        #expect(header.fill() == [1, 1, 1, 0.077] && Self.components(header.button.contentTintColor) == [1, 1, 1, 0.592])
    }

    @Test func aDisabledButtonKeepsTheClearFill() {
        let header = Header()
        header.showButton()
        header.button.mouseEntered(with: header.crossing(.mouseEntered))
        header.button.isEnabled = false
        #expect(header.fill() == [0, 0, 0, 0])
    }

    @Test func leavingTheButtonClearsItsFillAndTheHeaderStaysHovered() {
        let header = Header()
        header.showButton()
        header.button.mouseEntered(with: header.crossing(.mouseEntered))
        header.button.mouseExited(with: header.crossing(.mouseExited))
        #expect(!header.button.isHovered && header.header.isHovered && header.fill() == [0, 0, 0, 0])
    }

    private func editing() -> Header {
        let header = Header(icon: false)
        header.header.canShowHeaderButtonsIfPossible = true
        header.header.isEditing = true
        return header
    }

    @Test func editingShowsDoneAtTheTrailingEdgeWithRoomForItsTitleWithoutHover() {
        let header = editing()
        let doneWidth = header.button.attributedTitle.size().width
        let frames = H.frames(width: 228, icon: false, titleHeight: header.titleHeight,
                              editButtonWidth: H.editButtonWidth(shown: true, editing: true, titleWidth: doneWidth))
        #expect(header.button.frame == frames.editButton && header.button.frame.maxX == 214 && header.button.frame.width >= ceil(doneWidth) + 4)
        #expect(header.field.frame == frames.title && header.field.frame.maxX == header.button.frame.minX - 4)
    }

    @Test func theEditingChangeFadesInInTheSameGroup() {
        let header = editing()
        #expect(header.button.alphaValue == 1 && Self.isEditFade(header.opacityFade))
    }

    @Test func doneReplacesTheEllipsis() throws {
        let header = editing()
        let edit = try #require(header.exposed.last as? NSCell)
        #expect(header.button.image?.tiffRepresentation != Self.ellipsis?.tiffRepresentation && (header.button.image?.size.width ?? 0) <= 1)
        #expect(header.button.title == "Done" && edit.accessibilityLabel() == "Done")
    }

    @Test func thereIsNoHoverFillWhileEditing() {
        let header = editing()
        header.button.mouseEntered(with: header.crossing(.mouseEntered))
        #expect(header.fill() == [0, 0, 0, 0])
    }

    @Test func clickingDoneEndsTheRename() {
        let header = editing()
        header.field.isEditable = true
        let began = header.window.makeFirstResponder(header.field)
        header.button.performClick(nil)
        #expect(began && header.window.firstResponder === header.window)
    }

    @Test func leavingEditingRestoresTheEllipsisAndHidesTheButton() {
        let header = editing()
        header.header.isEditing = false
        #expect(header.button.frame.width == 0 && header.button.title == "")
        #expect(header.button.image?.tiffRepresentation == Self.ellipsis?.tiffRepresentation)
    }

    @Test func theClicksMenuIsTheRightClickMenuAndItsItemsRunTheParcActions() {
        let header = Header(icon: false)
        let clickMenu = header.header.makeMenu()
        #expect(clickMenu.items.map(\.title) == header.click.flatMap { header.header.menu(for: $0) }?.items.map(\.title))
        #expect(clickMenu.items.map(\.title) == Self.base)
        clickMenu.performActionForItem(at: 0)
        #expect(header.calls == ["rename"])
    }

    @Test func resigningKeyClearsTheHoverAndHidesTheButton() {
        let header = Header(icon: false)
        header.showButton()
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: header.window)
        header.runScheduled()
        #expect(!header.header.isHovered && header.button.frame.width == 0)
    }

    @Test func hidingTheHeaderClearsTheHoverAndShownAgainItWaitsForThePointer() {
        let header = Header(icon: false)
        header.showButton()
        header.header.isHidden = true
        header.runScheduled()
        #expect(!header.header.isHovered && header.button.frame.width == 0)
        header.header.isHidden = false
        header.runScheduled()
        #expect(header.button.frame.width == 0 && header.button.alphaValue == 0)
    }

    @Test func pointsOverTheNameIconOrRestingButtonSlotHitTheHeader() {
        let header = Header(icon: false)
        #expect(header.header.hitTest(NSPoint(x: 100, y: 108)) === header.header && header.header.hitTest(NSPoint(x: 20, y: 108)) === header.header)
        #expect(header.header.hitTest(NSPoint(x: 212, y: 108)) === header.header)
    }

    @Test func theShownEditButtonTakesItsOwnClicks() {
        let header = Header(icon: false)
        header.showButton()
        #expect(header.header.hitTest(NSPoint(x: 202, y: 108)) === header.button && header.header.hitTest(NSPoint(x: 100, y: 108)) === header.header)
    }

    @Test func pointsBelowTheHeaderMissIt() {
        #expect(Header(icon: false).header.hitTest(NSPoint(x: 100, y: 130)) == nil)
    }

    @Test func theHeaderIsNoKeyboardStopTheEditButtonIncluded() {
        let header = Header(icon: false)
        #expect(!header.header.acceptsFirstResponder && !header.header.canBecomeKeyView && !header.field.acceptsFirstResponder)
        #expect(!header.button.acceptsFirstResponder && !header.button.canBecomeKeyView && !header.window.isKeyWindow)
    }
}
