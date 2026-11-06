import AppKit

/// Inert AppKit checks for the onboarding theme-step editor chrome.
/// No browser, engine, imports or user profile.
@main
struct OnboardingThemeStepTests {
    @MainActor static var assertions = 0
    @MainActor static func expect(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
        assertions += 1
        guard condition() else { fatalError("Line \(line): \(message)") }
    }
    @MainActor static func near(_ a: CGFloat, _ b: CGFloat, _ message: String, line: Int = #line) {
        expect(abs(a - b) < 0.001, "\(message) (\(a) vs \(b))", line: line)
    }

    @MainActor static func main() {
        _ = NSApplication.shared
        layoutConstants()
        chromeGeometryAndShadow()
        popoverClearShadowAndHitRegion()
        wrapPopoverMaterial()
        setupEmptyStateAndSidebar()
        colorPadSquare()
        spaceNameField()
        lightDarkFieldAndCard()
        reduceMotionAppearance()
        print("PASS: onboarding theme-step chrome, wrap material, pad, empty state, space name, light/dark and Reduce Motion (\(assertions) assertions)")
    }

    @MainActor static func layoutConstants() {
        near(OnboardingThemeEditorLayout.editorSize.width, 356, "Stock editor width")
        near(OnboardingThemeEditorLayout.editorSize.height, 508, "Stock editor height")
        near(OnboardingThemeEditorLayout.scale, 0.83, "NewSetupView case 5 scale")
        near(OnboardingThemeEditorLayout.visualSize.width, 356 * 0.83, "Scaled visual width")
        near(OnboardingThemeEditorLayout.visualSize.height, 508 * 0.83, "Scaled visual height")
        near(OnboardingThemeEditorLayout.cornerRadius, 16, "Setup clip corner")
        near(OnboardingThemeEditorLayout.shadowRadius, 30, "Setup shadow radius")
        near(OnboardingThemeEditorLayout.shadowOffsetY, 7, "Setup shadow y")
        expect(OnboardingThemeEditorLayout.shadowOpacity == 0.25, "Setup shadow opacity")
        expect(OnboardingThemeEditorLayout.emptyStateText == "Click to pick a color",
               "Unboxing empty-state copy")
        expect(OnboardingThemeEditorLayout.wrapMaterial == .popover,
               "Wrap uses typed material 6")
        expect(OnboardingThemeEditorLayout.wrapMaterialState == .followsWindowActiveState,
               "Wrap follows window active state")
        expect(OnboardingThemeEditorLayout.wrapBlendingMode == .withinWindow,
               "Wrap blends within the window")
        expect(!OnboardingThemeEditorLayout.wrapMaterialEmphasized,
               "Wrap material is not emphasized")
        near(OnboardingThemeEditorLayout.colorPadSize, 340, "Lazy 340-point color pad")
        near(SpaceThemeEditorView.colorPadSide, 340, "Stock editor pad is the same 340 square")
        expect(OnboardingThemeEditorLayout.appearDuration == 0.1, "easeInOut appear duration")
        let bounds = NSRect(x: 0, y: 0, width: 610, height: 548)
        let frame = OnboardingThemeEditorLayout.frame(in: bounds)
        near(frame.midX, bounds.midX, "Editor centered horizontally")
        near(frame.midY, bounds.midY, "Editor centered vertically")
        expect(bounds.contains(frame), "Scaled editor fits the 610×548 content column")
    }

    @MainActor static func chromeGeometryAndShadow() {
        let editor = SpaceThemeEditorView(theme: SpaceTheme(), performHapticFeedback: {})
        let chrome = OnboardingThemeEditorChrome(editor: editor)
        expect(editor.presentation == .setup, "Chrome selects setup presentation")
        expect(editor.superview === chrome.popoverBackground, "Editor sits in the clear-shadow wrap")
        expect(chrome.popoverBackground.superview === chrome.composition, "Wrap sits in the parent shadow host")
        expect(chrome.composition.superview === chrome, "Shadow host stays inside chrome")
        let column = NSRect(x: 0, y: 0, width: 610, height: 548)
        chrome.applyFrame(in: column)
        near(chrome.frame.width, column.width, "Chrome fills the content column")
        near(chrome.frame.height, column.height, "Chrome fills the content column height")
        near(chrome.composition.bounds.width, 356, "Unscaled composition bounds width")
        near(chrome.composition.bounds.height, 508, "Unscaled composition bounds height")
        near(chrome.composition.frame.width, 356 * 0.83, "Composition frame is the 0.83 visual width")
        near(chrome.composition.frame.height, 508 * 0.83, "Composition frame is the 0.83 visual height")
        near(chrome.composition.frame.midX, column.midX, "UnitPoint.center horizontal")
        near(chrome.composition.frame.midY, column.midY, "UnitPoint.center vertical")
        near(editor.frame.width, 356, "Editor keeps its 356×508 layout")
        near(editor.frame.height, 508, "Editor keeps its 356×508 layout")
        near(chrome.composition.layer?.cornerRadius ?? 0, 16, "Continuous 16-point chrome corner")
        expect(chrome.composition.layer?.cornerCurve == .continuous, "Continuous corner curve")
        near(CGFloat(chrome.composition.layer?.shadowOpacity ?? -1), 0.25, "Parent owns black 0.25 shadow")
        near(chrome.composition.layer?.shadowRadius ?? 0, 30, "Shadow radius 30")
        near(chrome.composition.layer?.shadowOffset.height ?? 0, 7, "Shadow y 7")
        expect(chrome.composition.layer?.masksToBounds == false, "Shadow is not clipped")
        expect(chrome.composition.layer?.shadowPath != nil, "Shadow path paints without a chrome fill")
        near(chrome.composition.layer?.shadowPath?.boundingBox.width ?? 0, 356,
             "Shadow path follows the unscaled editor")
        near(chrome.composition.layer?.shadowPath?.boundingBox.height ?? 0, 508,
             "Shadow path follows the unscaled editor")
        expect(editor.layer?.masksToBounds == true, "Editor clip does not supply the chrome shadow")
        near(editor.layer?.cornerRadius ?? 0, 16, "Setup editor clips at 16")
    }

    @MainActor static func popoverClearShadowAndHitRegion() {
        let editor = SpaceThemeEditorView(theme: SpaceTheme(), performHapticFeedback: {})
        let chrome = OnboardingThemeEditorChrome(editor: editor)
        let column = NSRect(x: 0, y: 0, width: 610, height: 548)
        chrome.applyFrame(in: column)
        expect(chrome.popoverBackground.layer?.shadowOpacity == 0, "Wrap shadow opacity is clear")
        near(chrome.popoverBackground.layer?.shadowRadius ?? -1, 0, "Wrap shadow radius is zero")
        near(chrome.popoverBackground.layer?.shadowOffset.width ?? -1, 0, "Wrap shadow x is zero")
        near(chrome.popoverBackground.layer?.shadowOffset.height ?? -1, 0, "Wrap shadow y is zero")
        expect(chrome.popoverBackground.layer?.shadowPath == nil, "Wrap does not paint a shadow path")
        expect(chrome.popoverBackground.layer?.masksToBounds == true, "Wrap clips the popover fill")
        near(chrome.popoverBackground.layer?.cornerRadius ?? 0, 16, "Wrap uses setup corner 16")
        expect(chrome.popoverBackground.layer?.cornerCurve == .continuous, "Wrap corner is continuous")
        expect(editor.layer?.shadowOpacity == 0, "Editor does not own the drop shadow")
        expect(chrome.hitRegion.superview === chrome, "MouseDownView lives in the chrome")
        expect(chrome.subviews.first === chrome.hitRegion, "Hit region stays behind the scaled editor")
        near(chrome.hitRegion.frame.width, column.width, "Hit region fills the column width")
        near(chrome.hitRegion.frame.height, column.height, "Hit region fills the column height")
        let padding = NSPoint(x: 8, y: 8)
        expect(chrome.hitTest(padding) === chrome.hitRegion, "Column padding hits MouseDownView")
        let center = NSPoint(x: chrome.composition.frame.midX, y: chrome.composition.frame.midY)
        let editorHit = chrome.hitTest(center)
        expect(editorHit !== chrome.hitRegion, "Scaled editor remains the center hit target")
        expect(editorHit != nil, "Scaled editor remains hittable")
    }

    @MainActor static func editorMaterial(_ editor: SpaceThemeEditorView) -> NSVisualEffectView? {
        editor.subviews.compactMap { $0 as? NSVisualEffectView }.first
    }

    @MainActor static func wrapPopoverMaterial() {
        let editor = SpaceThemeEditorView(theme: SpaceTheme(), performHapticFeedback: {})
        let chrome = OnboardingThemeEditorChrome(editor: editor)
        let column = NSRect(x: 0, y: 0, width: 610, height: 548)
        chrome.applyFrame(in: column)
        chrome.layoutSubtreeIfNeeded()
        let wrap = chrome.popoverBackground
        expect(wrap.translucency.superview === wrap, "Translucency lives in the wrap")
        expect(wrap.subviews.first === wrap.translucency, "Translucency stays behind the editor")
        expect(editor.superview === wrap, "Editor stays in the wrap")
        near(wrap.translucency.frame.width, 356, "Translucency fills the unscaled wrap width")
        near(wrap.translucency.frame.height, 508, "Translucency fills the unscaled wrap height")
        expect(wrap.translucency.material == .popover, "Wrap material is popover")
        expect(wrap.translucency.state == .followsWindowActiveState, "Wrap follows window active state")
        expect(wrap.translucency.blendingMode == .withinWindow, "Wrap blends within the window")
        expect(!wrap.translucency.isEmphasized, "Wrap material is not emphasized")
        near(wrap.translucency.layer?.cornerRadius ?? 0, 16, "Wrap material clips at 16")
        expect(wrap.translucency.layer?.cornerCurve == .continuous, "Wrap material corner is continuous")
        let setupMaterial = editorMaterial(editor)
        expect(setupMaterial != nil, "Stock editor still owns its visual effect view")
        expect(setupMaterial?.isHidden == true, "Setup hides the editor's own popover material")
        let sidebar = SpaceThemeEditorView(theme: SpaceTheme(), performHapticFeedback: {})
        let stock = editorMaterial(sidebar)
        expect(stock != nil, "Sidebar editor keeps its visual effect view")
        expect(stock?.isHidden == false, "Sidebar material stays visible")
        expect(stock?.material == .popover, "Sidebar material stays popover")
        expect(stock?.blendingMode == .withinWindow, "Sidebar still blends within the window")
        near(sidebar.layer?.cornerRadius ?? 0, 12, "Sidebar corner remains 12")
        near(sidebar.frame.width, 356, "Sidebar editor stays 356 wide")
        near(sidebar.frame.height, 508, "Sidebar editor stays 508 tall")
        sidebar.presentation = .setup
        expect(editorMaterial(sidebar)?.isHidden == true, "Switching to setup hides the stock material")
        sidebar.presentation = .sidebar
        expect(editorMaterial(sidebar)?.isHidden == false, "Returning to sidebar restores the stock material")
        near(sidebar.layer?.cornerRadius ?? 0, 12, "Returning to sidebar restores corner 12")
    }

    @MainActor static func setupEmptyStateAndSidebar() {
        let blank = SpaceThemeEditorView(theme: SpaceTheme(), performHapticFeedback: {})
        expect(blank.presentation == .sidebar, "Stock editor stays sidebar presentation")
        expect(blank.emptyStatePrompt == "Tap to pick a color for this space",
               "Sidebar keeps its recovered empty-state copy")
        expect(blank.emptyStatePrompt != "Click to pick a color",
               "Sidebar does not use Unboxing empty-state copy")
        near(blank.layer?.cornerRadius ?? 0, 12, "Sidebar corner remains 12")
        near(blank.frame.width, 356, "Sidebar editor stays 356 wide")
        near(blank.frame.height, 508, "Sidebar editor stays 508 tall")
        blank.presentation = .setup
        expect(blank.emptyStatePrompt == "Click to pick a color", "Setup shows unboxing empty-state copy")
        near(blank.layer?.cornerRadius ?? 0, 16, "Setup corner is 16")
        var theme = SpaceTheme.singleColor(ThemeColor(hex: "4C6688")!)
        theme.intensity = 0.2
        let colored = SpaceThemeEditorView(theme: theme, performHapticFeedback: {})
        colored.presentation = .setup
        expect(colored.emptyStatePrompt == nil, "A chosen color hides the empty-state copy")
        colored.presentation = .sidebar
        expect(colored.emptyStatePrompt == nil, "A chosen color also hides the sidebar empty-state copy")
    }

    @MainActor static func colorPadSquare() {
        func colorPadFrame(_ editor: SpaceThemeEditorView) -> NSRect {
            let pads = editor.subviews.filter { $0.accessibilityLabel() == "Theme color pad" }
            expect(pads.count == 1, "The editor hosts one accessible theme color pad")
            return pads.first?.frame ?? .zero
        }
        let sidebar = SpaceThemeEditorView(theme: SpaceTheme(), performHapticFeedback: {})
        sidebar.layoutSubtreeIfNeeded()
        let sidebarPad = colorPadFrame(sidebar)
        near(sidebarPad.width, 340, "Sidebar pad width is the recovered 340 square")
        near(sidebarPad.height, 340, "Sidebar pad height is the recovered 340 square")
        near(sidebarPad.minX, 8, "Pad keeps the 8-point inset")
        near(sidebarPad.minY, 8, "Pad keeps the 8-point inset")
        let editor = SpaceThemeEditorView(theme: SpaceTheme(), performHapticFeedback: {})
        let chrome = OnboardingThemeEditorChrome(editor: editor)
        chrome.applyFrame(in: NSRect(x: 0, y: 0, width: 610, height: 548))
        chrome.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()
        let setupPad = colorPadFrame(editor)
        near(setupPad.width, 340, "Setup pad width is the recovered 340 square")
        near(setupPad.height, 340, "Setup pad height is the recovered 340 square")
        near(editor.frame.width, 356, "340 pad does not change the 356 editor")
    }

    @MainActor static func spaceNameField() {
        let name = OnboardingSpaceNameField(frame: NSRect(x: 0, y: 0, width: 257, height: 36))
        name.layoutSubtreeIfNeeded()
        expect(name.field.placeholderString == "Space name", "Placeholder is Space name")
        expect(name.field.accessibilityLabel() == "Space name", "Accessible Space name")
        expect(name.field.focusRingType == .none, "No focus ring")
        expect(!name.field.isBordered && !name.field.drawsBackground, "Borderless field in setup chrome")
        expect(name.field.superview === name, "Field stays inside the named chrome")
        expect(name.bounds.contains(name.field.frame), "Field inset inside 36-point row")
    }

    @MainActor static func lightDarkFieldAndCard() {
        let name = OnboardingSpaceNameField(frame: NSRect(x: 0, y: 0, width: 257, height: 36))
        let card = OnboardingSetupCard(frame: NSRect(origin: .zero, size: OnboardingSetupLayout.size))
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            name.appearance = NSAppearance(named: appearance)
            name.viewDidChangeEffectiveAppearance()
            name.updateColors()
            expect(name.layer?.backgroundColor != nil, "Name field fill for \(appearance.rawValue)")
            card.appearance = NSAppearance(named: appearance)
            card.viewDidChangeEffectiveAppearance()
            card.themeBackground = NSColor(srgbRed: 0.2, green: 0.3, blue: 0.8, alpha: 1)
            expect(card.chrome.layer?.backgroundColor == card.themeBackground?.cgColor,
                   "Themed card fill for \(appearance.rawValue)")
        }
        card.themeBackground = nil
    }

    @MainActor static func reduceMotionAppearance() {
        expect(OnboardingThemeEditorLayout.shouldAnimateAppearance(alreadyVisible: false),
               "First attach plays the appear")
        expect(!OnboardingThemeEditorLayout.shouldAnimateAppearance(alreadyVisible: true),
               "A chrome still in the column skips the appear after render teardown")
        let editor = SpaceThemeEditorView(theme: SpaceTheme(), performHapticFeedback: {})
        let chrome = OnboardingThemeEditorChrome(editor: editor)
        let column = NSRect(x: 0, y: 0, width: 610, height: 548)
        chrome.prepareAppearance(reduceMotion: true, in: column)
        expect(chrome.composition.alphaValue == 1, "Reduce Motion does not hide the editor")
        chrome.playAppearance(reduceMotion: true, in: column)
        expect(chrome.composition.alphaValue == 1, "Reduce Motion keeps the settled 0.83 composition")
        near(chrome.composition.frame.width, 356 * 0.83, "Reduce Motion still applies the 0.83 frame")
        near(chrome.composition.frame.height, 508 * 0.83, "Reduce Motion still applies the 0.83 frame")
        near(chrome.composition.bounds.width, 356, "Reduce Motion keeps unscaled editor bounds")
        chrome.prepareAppearance(reduceMotion: false)
        expect(chrome.composition.alphaValue == 0, "Ordinary appear starts from opacity 0")
        chrome.playAppearance(reduceMotion: false)
    }
}
