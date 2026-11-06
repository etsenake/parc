import AppKit

/// SidebarView's flipped content surface, holding the header and a stand-in
/// for the list where SidebarView.layout() puts them.
final class FlippedHost: NSView { override var isFlipped: Bool { true } }

// The production Space header in an off-screen window that is never made
// key: SidebarChromeLayout.SpaceHeader.content on Space fixtures, frames
// against the model, the name field's font, colour, placeholder and
// configuration, its MaskedTextField fade, the icon slot, the edit button
// (frames, alpha, colours, hover fill, the hover delay on the main queue, the
// key-window gate, editing and its menu), accessibility, the context menu and
// its actions, hit testing and keyboard focus. Hover arrives as AppKit's
// entered and exited messages; no pointer input, and menus are captured
// rather than shown.
@main
struct SidebarSpaceHeaderTests {
    static var failures = 0, count = 0
    static func check(_ condition: Bool, _ message: String) {
        count += 1
        if !condition { failures += 1; print("FAIL: \(message)") }
    }
    static func components(_ color: NSColor?) -> [CGFloat]? {
        guard let color = color?.usingColorSpace(.sRGB) else { return nil }
        return [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent].map { ($0 * 1000).rounded() / 1000 }
    }
    static func components(_ color: CGColor?) -> [CGFloat]? { components(color.flatMap { NSColor(cgColor: $0) }) }
    @MainActor static func settle(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
    /// Runs the main run loop until `condition` holds or `seconds` pass.
    @MainActor static func wait(upTo seconds: Double, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while !condition(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
        return condition()
    }
    static func space(_ name: String, icon: SidebarGroupIcon? = nil) -> BrowserSpace {
        var space = BrowserSpace(id: UUID(), name: name, symbol: "circle.fill", color: "B9B5D4", profileID: UUID())
        space.customIcon = icon
        if name.hasPrefix("Space "), Int(name.dropFirst(6)) != nil { space.title = nil }
        return space
    }
    /// A view's pixels as AppKit draws them.
    @MainActor static func pixels(_ view: NSView) -> Data? {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.bitmapData.map { Data(bytes: $0, count: rep.bytesPerRow * rep.pixelsHigh) }
    }

    @MainActor static func main() {
        _ = NSApplication.shared
        typealias L = SidebarChromeLayout
        typealias H = L.SpaceHeader
        typealias Content = H.Content

        // The render-side decision SidebarView calls, on Space fixtures.
        func content(_ spaces: [BrowserSpace], _ active: BrowserSpace?, privateWindow: Bool = false, setting: Bool = false) -> Content {
            H.content(spaces: spaces, activeSpaceID: active?.id, privateWindow: privateWindow, showOnSingleUnnamedSpace: setting)
        }
        var first = space("Space 1")
        check(content([first], first) == Content(isShown: false, title: "", placeholder: "Space 1", toggleTitle: "Show Space Header"),
              "a fresh single Space: no header, the placeholder, Show Space Header")
        check(content([first], first, setting: true) == Content(isShown: true, title: "", placeholder: "Space 1", toggleTitle: "Hide Space Header"),
              "the setting shows it and the menu offers Hide Space Header")
        let second = space("Space 2")
        check(content([first, second], first) == Content(isShown: true, title: "", placeholder: "Space 1", toggleTitle: nil)
              && content([first, second], second) == Content(isShown: true, title: "", placeholder: "Space 2", toggleTitle: nil),
              "adding a Space shows the header with each position's placeholder and no toggle")
        check(content([first], first) == Content(isShown: false, title: "", placeholder: "Space 1", toggleTitle: "Show Space Header"),
              "removing it hides the header again")
        first.name = "Work"
        check(content([first], first) == Content(isShown: true, title: "Work", placeholder: nil, toggleTitle: nil),
              "renaming from Space 1 titles it: shown with the name and no placeholder")
        first.name = "Space 1"
        check(content([first], first) == Content(isShown: true, title: "Space 1", placeholder: nil, toggleTitle: nil),
              "explicitly renaming to Space 1 keeps an authored title")
        first.name = ""
        check(content([first], first) == Content(isShown: false, title: "", placeholder: "Space 1", toggleTitle: "Show Space Header"),
              "an empty name is untitled")
        first.name = "Space 1"
        check(content([second, first], first) == Content(isShown: true, title: "Space 1", placeholder: nil, toggleTitle: nil),
              "\"Space 1\" in the second position is a title")
        let starred = space("Space 1", icon: .symbol("star"))
        check(content([starred], starred) == Content(isShown: true, title: "", placeholder: "Space 1", toggleTitle: nil),
              "a custom icon shows the header and drops the toggle")
        check(!content([first, second, starred], starred, privateWindow: true, setting: true).isShown
              && !content([first], first, privateWindow: true, setting: true).isShown,
              "never in a private window, whatever the Spaces or the setting")
        check(content([first], nil) == Content(isShown: false, title: "", placeholder: nil, toggleTitle: nil), "no active Space, no header")


        let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 228, height: 400), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        let host = FlippedHost(frame: NSRect(x: 0, y: 0, width: 228, height: 400))
        host.wantsLayer = true
        window.contentView = host
        let header = SidebarSpaceHeaderView()
        let list = NSView()
        host.addSubview(header); host.addSubview(list)

        // Two Spaces with a dismissed, empty tray, laid out as SidebarView does.
        header.frame = NSRect(x: 0, y: H.top(trayHeight: 0, hasFavorites: false), width: 228, height: H.height)
        list.frame = NSRect(x: 8, y: L.tablistTop(trayHeight: 0, spaceHeader: true), width: 212, height: 100)
        check(header.frame == NSRect(x: 0, y: 90, width: 228, height: 36) && list.frame.minY == header.frame.maxY,
              "the header spans the sidebar at 90…126 and the list follows it")

        let titled = { (name: String) in Content(isShown: true, title: name, placeholder: nil, toggleTitle: nil) }
        let star = NSImage(systemSymbolName: "star", accessibilityDescription: nil)
        header.update(titled("Work"), symbol: star, emoji: nil)
        header.layoutSubtreeIfNeeded()
        let field = header.nameField
        let images = header.subviews.compactMap { $0 as? NSImageView }
        let emoji = header.subviews.compactMap { $0 as? NSTextField }.first { $0 !== field }
        guard let symbolView = images.first, let emoji else { print("FAIL: the header has no icon views"); exit(1) }
        let titleHeight = field.intrinsicContentSize.height
        let frames = H.frames(width: 228, icon: true, titleHeight: titleHeight)
        check(!symbolView.isHidden && symbolView.frame == frames.icon && symbolView.frame == NSRect(x: 14, y: 6, width: 24, height: 24),
              "a symbol icon fills the 24-point slot at the 14-point inset")
        check(emoji.isHidden, "no emoji with a symbol icon")
        check(field.frame == frames.title && field.frame.minX == 42 && field.frame.maxX == 210 && abs(field.frame.midY - 18) < 0.001,
              "the name 4 after the icon, 4 before the edit button's slot, centred in the 36-point header")
        check(field.stringValue == "Work" && field.placeholderString == nil && field.font == NSFont.systemFont(ofSize: 13, weight: .semibold),
              "a title is the field's text in FontSet.sectionHeader: 13-point semibold")
        check(!field.isEditable && !field.isSelectable && !field.isBezeled && field.usesSingleLineMode && field.focusRingType == .none
              && field.lineBreakMode == .byTruncatingTail && field.alignmentRectInsets.left == 0 && field.alignmentRectInsets.right == 0,
              "the field configuration: not editable or selectable, no focus ring, single line, tail truncation, no alignment insets")
        check(components(field.textColor) == [0, 0, 0, 0.45], "SidebarForegroundDarker in a light theme")
        check(components(symbolView.contentTintColor) == [0, 0, 0, 0.3], "ForegroundTertiary icon tint without a Space colour")
        header.applyStyle(dark: true, tint: nil)
        check(components(field.textColor) == [1, 1, 1, 0.45] && components(symbolView.contentTintColor) == [1, 1, 1, 0.3]
              && header.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua, "dark theme")
        header.applyStyle(dark: false, tint: .systemRed)
        check(symbolView.contentTintColor == .systemRed && header.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua,
              "the header's tint colours the icon")

        let privateHeader = SidebarSpaceHeaderView(frame: NSRect(x: 0, y: 0, width: 212, height: 36))
        privateHeader.update(titled("Incognito Tabs"), symbol: nil, emoji: nil)
        privateHeader.updateIncognitoIndicator(shown: true)
        privateHeader.applyStyle(dark: true, tint: nil)
        privateHeader.layoutSubtreeIfNeeded()
        check(privateHeader.nameField.isHidden && privateHeader.profileButton.isHidden && !privateHeader.incognitoIndicator.isHidden
              && privateHeader.incognitoIndicator.parcTooltip?.label == "Incognito tabs" && privateHeader.incognitoIndicator.toolTip == nil
              && privateHeader.incognitoIndicator.frame.minX == 10.5 && abs(privateHeader.incognitoIndicator.frame.midY - 21) < 0.001,
              "multiple Profiles replace the private title with the left-aligned incognito indicator")
        let indicator = privateHeader.incognitoIndicator
        guard let indicatorIcon = indicator.subviews.compactMap({ $0 as? NSImageView }).first,
              let indicatorLabel = indicator.subviews.compactMap({ $0 as? NSTextField }).first else {
            print("FAIL: the incognito indicator has no icon or label"); exit(1)
        }
        let indicatorHeight = indicatorLabel.intrinsicContentSize.height + 8
        check(indicator.frame.height == indicatorHeight && indicator.frame.width == 33 + indicatorLabel.intrinsicContentSize.width
              && indicatorIcon.frame == NSRect(x: 5, y: 4, width: 20, height: indicatorHeight - 8)
              && indicatorLabel.frame.minX == 27 && indicatorLabel.frame.maxX == indicator.bounds.maxX - 6
              && indicatorLabel.frame.midY == indicator.bounds.midY,
              "the full-size indicator centers its 20-point icon and label with recovered padding and gap")
        check(indicatorLabel.font == NSFont.systemFont(ofSize: 11, weight: .medium)
              && indicatorIcon.symbolConfiguration == NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
              && indicatorIcon.imageScaling == .scaleNone && indicatorIcon.imageAlignment == .alignCenter
              && components(indicatorLabel.textColor) == [1, 1, 1, 0.3]
              && components(indicatorIcon.contentTintColor) == [1, 1, 1, 0.3],
              "the indicator uses medium 11-point text and symbol with tertiary foreground")
        check(indicator.layer?.cornerCurve == .continuous && indicator.layer?.cornerRadius == indicatorHeight / 2
              && components(indicator.layer?.backgroundColor) == [0.11, 0.11, 0.11, 0.3],
              "the dark idle indicator has a continuous Gray2 capsule")
        privateHeader.applyStyle(dark: false, tint: nil)
        check(components(indicatorLabel.textColor) == [0, 0, 0, 0.3]
              && components(indicatorIcon.contentTintColor) == [0, 0, 0, 0.3]
              && components(indicator.layer?.backgroundColor) == [0.973, 0.973, 0.973, 0.3],
              "the light indicator uses tertiary foreground and Gray2 capsule")
        check(privateHeader.incognitoIndicator.hitTest(NSPoint(x: 1, y: 1)) == nil
              && privateHeader.incognitoIndicator.isAccessibilityElement()
              && privateHeader.incognitoIndicator.accessibilityRole() == .staticText
              && privateHeader.incognitoIndicator.accessibilityValue() as? String == "Incognito"
              && privateHeader.incognitoIndicator.accessibilityChildren()?.isEmpty == true
              && !privateHeader.incognitoIndicator.accessibilityPerformPress()
              && !privateHeader.incognitoIndicator.isAccessibilitySelectorAllowed(#selector(NSAccessibilityProtocol.accessibilityPerformPress)),
              "the incognito indicator exposes informational text and no pointer or accessibility action")
        privateHeader.updateIncognitoIndicator(shown: false)
        privateHeader.layoutSubtreeIfNeeded()
        check(!privateHeader.nameField.isHidden && privateHeader.incognitoIndicator.isHidden
              && privateHeader.nameField.stringValue == "Incognito Tabs" && privateHeader.nameField.frame.minX == 14
              && abs(privateHeader.nameField.frame.midY - 21) < 0.001,
              "one Profile restores the private title")

        header.update(titled("Trips"), symbol: nil, emoji: "🌴")
        header.layoutSubtreeIfNeeded()
        check(symbolView.isHidden && !emoji.isHidden && emoji.stringValue == "🌴" && emoji.frame.minX == 14 && emoji.frame.width == 24
              && abs(emoji.frame.midY - 18) < 0.001 && field.frame.minX == 42, "an emoji icon is centred in the same slot")

        header.update(titled("Space 2"), symbol: nil, emoji: nil)
        header.layoutSubtreeIfNeeded()
        check(symbolView.isHidden && emoji.isHidden && field.frame == H.frames(width: 228, icon: false, titleHeight: titleHeight).title
              && field.frame.minX == 14 && field.frame.maxX == 210, "without a custom icon Parc hides the icon and the name leads")
        header.update(titled(String(repeating: "Long Space Name ", count: 6)), symbol: nil, emoji: nil)
        header.layoutSubtreeIfNeeded()
        check(field.frame.maxX == 210 && field.frame.height == titleHeight, "a long name stays one truncated line inside the slot")

        //
        // editable field whose text runs past an edge.
        let mask = field.leadingMask
        check((mask.colors as? [CGColor]) == [NSColor.clear.cgColor, NSColor.black.cgColor]
              && mask.startPoint == CGPoint(x: 0, y: 0.5) && mask.endPoint == CGPoint(x: 1, y: 0.5) && field.isMaskingEnabled,
              "leadingMask runs clear to black across the field, and the header enables masking")
        field.needsLayout = true
        header.layoutSubtreeIfNeeded()
        check(mask.frame == field.bounds && (mask.locations?.map(\.doubleValue) ?? []) == [0, Double(16 / field.bounds.width)],
              "layout gives the mask the field's bounds and a 16-point ramp")
        // AppKit's handlers forward the notification's field editor.
        let editor = NSTextView()
        let changed = Notification(name: NSText.didChangeNotification, object: editor)
        field.updateMask(true); field.textDidChange(changed)
        check(field.layer != nil && field.layer?.mask == nil, "the resting header's field is not editable, so a truncated name is not masked")
        field.isEditable = true
        field.textDidChange(changed)
        check(field.layer?.mask === mask, "editable with text that does not fit, the field masks its leading edge")
        field.isMaskingEnabled = false
        check(field.layer?.mask == nil, "disabling masking removes the mask")
        field.isMaskingEnabled = true
        check(field.layer?.mask == nil, "enabling it again waits for the next text change setter does")
        field.updateMask(true)
        check(field.layer?.mask === mask, "the mask follows the next evaluation")
        field.textDidEndEditing(Notification(name: NSText.didEndEditingNotification, object: editor))
        check(field.layer?.mask == nil, "ending editing clears it")
        header.update(titled("Work"), symbol: nil, emoji: nil)
        field.updateMask(true)
        check(field.layer?.mask == nil, "text that fits is not masked")
        field.isEditable = false

        first.title = nil
        //
        // AppKit's placeholder colour with an empty accessibility value.
        header.update(content([first], first, setting: true), symbol: nil, emoji: nil)
        header.layoutSubtreeIfNeeded()
        let reference = SidebarSpaceHeaderView()
        host.addSubview(reference)
        reference.frame = NSRect(x: 0, y: 200, width: 228, height: H.height)
        reference.update(titled("Space 1"), symbol: nil, emoji: nil)
        reference.layoutSubtreeIfNeeded()
        check(field.stringValue == "" && field.placeholderString == "Space 1" && field.placeholderAttributedString == nil
              && field.intrinsicContentSize.height == titleHeight && field.frame == reference.nameField.frame,
              "the placeholder is AppKit's, in the same slot as a title")
        for dark in [false, true] {
            header.applyStyle(dark: dark, tint: nil); reference.applyStyle(dark: dark, tint: nil)
            let name = pixels(reference.nameField)
            reference.nameField.textColor = .placeholderTextColor
            let placeholder = pixels(field), expected = pixels(reference.nameField)
            check(placeholder != nil && placeholder == expected && placeholder != name,
                  "\(dark ? "dark" : "light"): the placeholder draws in placeholderTextColor, not SidebarForegroundDarker")
        }
        header.applyStyle(dark: false, tint: nil)
        reference.removeFromSuperview()

        // Accessibility: AppKit exposes the name field's cell as a static
        //
        // icon views (shown or hidden) and the header itself are not elements.
        func exposed() -> [NSObject] {
            NSAccessibility.unignoredChildren(from: header.accessibilityChildren() ?? []).compactMap { $0 as? NSObject }
        }
        let placeholderElement = exposed().first as? NSCell
        check(placeholderElement?.accessibilityValue() as? String == "" && placeholderElement?.accessibilityPlaceholderValue() == "Space 1",
              "an untitled Space reads as an empty value with the Space N placeholder")
        header.update(titled("Work"), symbol: star, emoji: nil)
        let children = exposed()
        let name = children.first as? NSCell
        //
        // hides it [C].
        let editElement = children.last as? NSCell
        check(children.count == 2 && name === field.cell && editElement === header.editButton.cell,
              "two elements: the name field's cell, then the resting edit button's")
        check(name?.accessibilityRole() == .staticText && name?.accessibilityValue() as? String == "Work"
              && name?.accessibilityPlaceholderValue() == nil, "a title reads as static text")
        check(name?.accessibilityIdentifier() == "sidebarSpaceName" && field.accessibilityIdentifier() == "sidebarSpaceName",
              "the sidebarSpaceName identifier on the exposed element")
        // No label of its own: AppKit's reading of the "ellipsis" symbol with
        //
        let plainButton = NSButton(frame: .zero)
        plainButton.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "")
        check(editElement?.accessibilityRole() == .button && editElement?.accessibilityIdentifier() == "sidebarSpaceEditButton"
              && header.editButton.accessibilityIdentifier() == "sidebarSpaceEditButton"
              && editElement?.accessibilityLabel() == plainButton.cell?.accessibilityLabel() && header.editButton.toolTip == nil,
              "the edit button: an AXButton with the sidebarSpaceEditButton identifier and no label or tooltip of its own")
        header.update(titled("Trips"), symbol: nil, emoji: "🌴")
        check(exposed().count == 2 && !emoji.isAccessibilityElement() && emoji.cell?.isAccessibilityElement() == false,
              "a shown emoji icon is not an element")
        header.update(titled("Work"), symbol: star, emoji: nil)
        check(!symbolView.isAccessibilityElement() && !header.isAccessibilityElement(), "the symbol view and the header are not elements")

        //
        // has, then the header toggle while the content offers it.
        var calls: [String] = []
        header.onRenameSpace = { calls.append("rename") }
        header.onEditTheme = { calls.append("theme") }
        header.onNewFolder = { calls.append("folder") }
        header.onToggleHeader = { calls.append("toggle") }
        let click = NSEvent.mouseEvent(with: .rightMouseDown, location: header.convert(NSPoint(x: 100, y: 18), to: nil),
                                       modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                       eventNumber: 0, clickCount: 1, pressure: 1)
        let base = ["Rename Space…", "Edit Theme Color…", "New Folder"]
        var menu = click.flatMap { header.menu(for: $0) }
        check(menu?.items.map(\.title) == base && menu?.items.allSatisfy(\.isEnabled) == true
              && (field.cell?.accessibilityCustomActions() ?? []).map(\.name) == base,
              "a titled Space's right-click menu has the titles and no header toggle")
        header.update(content([first], first, setting: true), symbol: nil, emoji: nil)
        menu = click.flatMap { header.menu(for: $0) }
        check(menu?.items.map(\.title) == base + ["Hide Space Header"] && menu?.items.allSatisfy(\.isEnabled) == true,
              "one untitled Space shown by the setting offers Hide Space Header last")
        for index in 0..<(menu?.items.count ?? 0) { menu?.performActionForItem(at: index) }
        check(calls == ["rename", "theme", "folder", "toggle"], "each item runs its Parc action")
        let actions = field.cell?.accessibilityCustomActions() ?? []
        check(actions.map(\.name) == base + ["Hide Space Header"]
              && (field.accessibilityCustomActions() ?? []).map(\.name) == actions.map(\.name), "the same actions for VoiceOver")
        calls.removeAll()
        for action in actions { _ = action.handler?() }
        check(calls == ["rename", "theme", "folder", "toggle"], "custom actions run the same Parc actions")
        header.update(titled("Work"), symbol: nil, emoji: nil)
        check(header.makeMenu().items.map(\.title) == base && (field.cell?.accessibilityCustomActions() ?? []).count == 3,
              "the toggle leaves with the content's toggle title")

        //
        let button = header.editButton
        header.layoutSubtreeIfNeeded()
        // Drawn once, AppKit animates the button's layer, so a fade is its
        // "opacity" animation [C].
        header.display()
        func opacityFade() -> CABasicAnimation? { button.layer?.animation(forKey: "opacity") as? CABasicAnimation }
        func controlPoints(_ function: CAMediaTimingFunction?) -> [Float]? {
            guard let function else { return nil }
            return (0..<4).flatMap { index -> [Float] in
                var point: [Float] = [0, 0]
                function.getControlPoint(at: index, values: &point)
                return point
            }
        }
        func isArcFade(_ fade: CABasicAnimation?) -> Bool {
            fade?.duration == 0.1 && controlPoints(fade?.timingFunction) == controlPoints(CAMediaTimingFunction(name: .easeOut))
        }
        let restFrames = H.frames(width: 228, icon: false, titleHeight: titleHeight)
        check(!header.canShowHeaderButtonsIfPossible && header.subviews.last === button && !button.isHidden && button.alphaValue == 0
              && button.frame == restFrames.editButton && button.frame == NSRect(x: 214, y: 6, width: 0, height: 24)
              && field.frame == restFrames.title && field.frame.maxX == 210,
              "at rest: the stack's last view, zero width at the trailing inset, alpha 0 and not hidden; the gate starts false")
        let ellipsis = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        let momentary = NSButton(frame: .zero)
        momentary.setButtonType(.momentaryChange)
        check(button.image?.tiffRepresentation != nil && button.image?.tiffRepresentation == ellipsis?.tiffRepresentation
              && button.title == "" && !button.isBordered && button.alignment == .center && button.alignmentRectInsets.left == 0 && button.alignmentRectInsets.right == 0
              && button.alignmentRectInsets.top == 0 && button.alignmentRectInsets.bottom == 0
              && (button.cell as? NSButtonCell)?.highlightsBy == (momentary.cell as? NSButtonCell)?.highlightsBy
              && (button.cell as? NSButtonCell)?.showsStateBy == (momentary.cell as? NSButtonCell)?.showsStateBy,
              "an ellipsis at 13 points semibold, no title, borderless momentary change, centred, no alignment insets")
        check(components(button.contentTintColor) == [0, 0, 0, 0.565], "GrayA11 in a light theme")
        check(button.target === header && button.action == NSSelectorFromString("didClickEditButton:"), "aimed at didClickEditButton:")
        let areaOptions = { (view: NSView) in view.trackingAreas.filter { $0.owner === view }.map(\.options.rawValue) }
        check(areaOptions(header) == [0x223] && areaOptions(button) == [0x223] && !window.isKeyWindow,
              "the header and the button track entered/exited, moved, in the visible rect and only in the key window (0x223)")

        // The gate: hovering shows nothing while canShowHeaderButtonsIfPossible is false.
        func crossing(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.enterExitEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                   context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        }
        header.mouseEntered(with: crossing(.mouseEntered))
        settle(0.3)
        check(header.isHovered && button.frame.width == 0 && button.alphaValue == 0, "hovered without the gate: still hidden")
        header.mouseExited(with: crossing(.mouseExited))
        settle(0.05)
        header.canShowHeaderButtonsIfPossible = true
        check(button.frame.width == 0 && button.alphaValue == 0, "the gate alone shows nothing")

        // Hover-in waits 0.1 s on the main queue, then shows and fades in.
        header.mouseEntered(with: crossing(.mouseEntered))
        check(header.isHovered && button.frame.width == 0 && button.alphaValue == 0, "hovering re-evaluates later, not at once")
        let start = Date()
        let appeared = wait(upTo: 2) { button.frame.width == 24 }
        let elapsed = Date().timeIntervalSince(start)
        check(appeared && elapsed >= 0.095, "the button shows 0.1 s after the header is hovered (after \(elapsed) s)")
        check(wait(upTo: 2) { button.alphaValue == 1 }, "and fades in to alpha 1")
        let shownFrames = H.frames(width: 228, icon: false, titleHeight: titleHeight, editButtonWidth: 24)
        check(button.frame == shownFrames.editButton && button.frame == NSRect(x: 190, y: 6, width: 24, height: 24)
              && field.frame == shownFrames.title && field.frame.maxX == 186 && !button.isHidden,
              "shown: 190…214, 24 × 24 and centred; the name ends 4 before it")
        check(pixels(button).map { !$0.allSatisfy { $0 == 0 } } == true, "the ellipsis draws")
        // The pointer leaving re-evaluates on the next main-queue turn; a
        // block queued after the exit sees that re-evaluation's result.
        settle(0.3)
        header.mouseExited(with: crossing(.mouseExited))
        check(button.frame.width == 24 && button.alphaValue == 1, "hover-out is dispatched, not applied in the exit message")
        var after: (width: CGFloat, alpha: CGFloat, fade: CABasicAnimation?) = (-1, -1, nil)
        DispatchQueue.main.async { after = (button.frame.width, button.alphaValue, opacityFade()) }
        settle(0.05)
        check(after.width == 0 && after.alpha == 0 && isArcFade(after.fade) && !button.isHidden && field.frame.maxX == 210,
              "then, without a custom icon, the width snaps to 0 and the alpha fades out in the 0.1 s ease-out group")
        // A pointer that leaves within 0.1 s shows nothing: the delayed
        // re-evaluation reads the hover again.
        header.mouseEntered(with: crossing(.mouseEntered))
        header.mouseExited(with: crossing(.mouseExited))
        var flashed = false
        _ = wait(upTo: 0.3) { flashed = flashed || button.frame.width > 0 || button.alphaValue > 0; return false }
        check(!flashed && !header.isHovered, "a hover shorter than 0.1 s never shows the button")
        //
        // lands with the width.
        header.update(titled("Work"), symbol: star, emoji: nil)
        header.layoutSubtreeIfNeeded()
        header.mouseEntered(with: crossing(.mouseEntered))
        check(wait(upTo: 2) { button.frame.width == 24 } && button.alphaValue == 1
              && button.frame == H.frames(width: 228, icon: true, titleHeight: titleHeight, editButtonWidth: 24).editButton
              && field.frame.maxX == 186, "with an icon: shown at alpha 1 with its width when the delay ends")
        settle(0.3)
        header.mouseExited(with: crossing(.mouseExited))
        DispatchQueue.main.async { after = (button.frame.width, button.alphaValue, opacityFade()) }
        settle(0.05)
        check(after.width == 0 && after.alpha == 0 && after.fade == nil, "and hidden without a fade")
        header.mouseEntered(with: crossing(.mouseEntered))
        _ = wait(upTo: 2) { button.frame.width == 24 }

        // The button's own hover fill: GrayA4, radius 6, continuous corners.
        func fill() -> [CGFloat]? { button.display(); return components(button.layer?.backgroundColor) }
        check(fill() == [0, 0, 0, 0] && button.layer?.cornerRadius == 6 && button.layer?.cornerCurve == .continuous
              && button.layer?.borderWidth == 0, "unhovered: clear, with the radius 6 continuous corners")
        button.mouseEntered(with: crossing(.mouseEntered))
        check(button.isHovered && header.isHovered && fill() == [0, 0, 0, 0.071], "hovered: GrayA4 on the button itself (light)")
        check(components(button.contentTintColor) == [0, 0, 0, 0.565], "the tint stays GrayA11 while hovered")
        header.applyStyle(dark: true, tint: nil)
        check(fill() == [1, 1, 1, 0.077] && components(button.contentTintColor) == [1, 1, 1, 0.592], "dark: GrayA4 and GrayA11 in white")
        header.applyStyle(dark: false, tint: nil)
        button.isEnabled = false
        check(fill() == [0, 0, 0, 0], "a disabled button keeps the clear fill")
        button.isEnabled = true
        button.mouseExited(with: crossing(.mouseExited))
        check(!button.isHovered && header.isHovered && fill() == [0, 0, 0, 0], "leaving the button clears its fill, the header stays hovered")

        //
        //
        header.update(titled("Work"), symbol: nil, emoji: nil)
        header.mouseExited(with: crossing(.mouseExited))
        _ = wait(upTo: 2) { button.frame.width == 0 && button.alphaValue == 0 }
        header.isEditing = true
        let editingFrames = H.frames(width: 228, icon: false, titleHeight: titleHeight, editButtonWidth: 30)
        check(button.frame == editingFrames.editButton && button.frame == NSRect(x: 184, y: 6, width: 30, height: 24)
              && field.frame == editingFrames.title && field.frame.maxX == 180, "editing: 184…214 and the name ends at 180, without hover")
        check(button.alphaValue == 1 && isArcFade(opacityFade()), "the editing change fades in, in the group")
        // AppKit keeps a 1 × 1 placeholder for the cleared image [C].
        check(button.image?.tiffRepresentation != ellipsis?.tiffRepresentation && (button.image?.size.width ?? 0) <= 1
              && button.title == "Done" && editElement?.accessibilityLabel() == "Done", "\"Done\" replaces the ellipsis")
        button.mouseEntered(with: crossing(.mouseEntered))
        check(fill() == [0, 0, 0, 0], "no hover fill while editing")
        button.mouseExited(with: crossing(.mouseExited))
        // Done ends the rename: makeFirstResponder(nil).
        field.isEditable = true
        let began = window.makeFirstResponder(field)
        button.performClick(nil)
        check(began && window.firstResponder === window, "clicking Done ends the rename")
        field.isEditable = false
        header.isEditing = false
        check(button.frame.width == 0 && button.title == "" && button.image?.tiffRepresentation == ellipsis?.tiffRepresentation,
              "leaving editing restores the ellipsis and hides the button again")
        _ = wait(upTo: 2) { button.alphaValue == 0 }

        // A click pops up makeMenu(), the same Space menu as right-click (the
        // popUpContextMenu call itself is a source check; no menu is shown here).
        calls.removeAll()
        let clickMenu = header.makeMenu()
        check(clickMenu.items.map(\.title) == click.flatMap { header.menu(for: $0) }?.items.map(\.title)
              && clickMenu.items.map(\.title) == base, "the click's menu is the right-click menu")
        clickMenu.performActionForItem(at: 0)
        check(calls == ["rename"], "its items run the Parc actions")

        // Hover only in the key window: resigning key (or hiding) clears it.
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        check(!header.isHovered && wait(upTo: 0.5) { button.frame.width == 0 }, "resigning key clears the hover and hides the button")
        header.mouseEntered(with: crossing(.mouseEntered))
        _ = wait(upTo: 2) { button.frame.width == 24 }
        header.isHidden = true
        check(!header.isHovered && wait(upTo: 0.5) { button.frame.width == 0 }, "hiding the header clears the hover")
        header.isHidden = false
        settle(0.2)
        check(button.frame.width == 0 && button.alphaValue == 0, "shown again it waits for the pointer")

        // Pointer and keyboard: the header takes its own events and no focus.
        // hitTest takes points in the superview's (the flipped host's) space.
        check(header.hitTest(NSPoint(x: 100, y: 108)) === header && header.hitTest(NSPoint(x: 20, y: 108)) === header,
              "points over the name or icon hit the header")
        check(header.hitTest(NSPoint(x: 212, y: 108)) === header, "the resting edit button's slot hits the header")
        header.mouseEntered(with: crossing(.mouseEntered))
        _ = wait(upTo: 2) { button.frame.width == 24 }
        check(header.hitTest(NSPoint(x: 202, y: 108)) === button && header.hitTest(NSPoint(x: 100, y: 108)) === header,
              "the shown edit button takes its own clicks")
        header.mouseExited(with: crossing(.mouseExited))
        _ = wait(upTo: 0.5) { button.frame.width == 0 }
        check(header.hitTest(NSPoint(x: 100, y: 130)) == nil, "points below it miss the header")
        check(!header.acceptsFirstResponder && !header.canBecomeKeyView && !field.acceptsFirstResponder
              && !button.acceptsFirstResponder && !button.canBecomeKeyView && !window.isKeyWindow,
              "no keyboard stop, the edit button included; the window is never key")

        print("SidebarSpaceHeader: \(count) assertions, \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
