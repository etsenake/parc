import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SidebarSpaceHeaderTestsLayoutTests {
    private typealias Support = SidebarSpaceHeaderTestsSupport
    private typealias H = Support.H
    private typealias Header = Support.Header

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
        #expect(Support.components(header.field.textColor) == [0, 0, 0, 0.45])
        #expect(Support.components(header.symbolView.contentTintColor) == [0, 0, 0, 0.3])
    }

    @Test func aDarkThemeUsesWhite() {
        let header = Header()
        header.header.applyStyle(dark: true, tint: nil)
        #expect(Support.components(header.field.textColor) == [1, 1, 1, 0.45] && Support.components(header.symbolView.contentTintColor) == [1, 1, 1, 0.3])
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

    @MainActor private final class Private {
        let header = SidebarSpaceHeaderView(frame: NSRect(x: 0, y: 0, width: 212, height: 36))
        var indicator: IncognitoProfileIndicatorView { header.incognitoIndicator }
        var icon: NSImageView { indicator.subviews.compactMap { $0 as? NSImageView }.first! }
        var label: NSTextField { indicator.subviews.compactMap { $0 as? NSTextField }.first! }
        init() {
            header.update(Support.titled("Incognito Tabs"), symbol: nil, emoji: nil)
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
        #expect(Support.components(header.label.textColor) == [1, 1, 1, 0.3] && Support.components(header.icon.contentTintColor) == [1, 1, 1, 0.3])
    }

    @Test func theDarkIdleIndicatorHasAContinuousGrayCapsule() {
        let header = Private()
        let height = header.label.intrinsicContentSize.height + 8
        #expect(header.indicator.layer?.cornerCurve == .continuous && header.indicator.layer?.cornerRadius == height / 2)
        #expect(Support.components(header.indicator.layer?.backgroundColor) == [0.11, 0.11, 0.11, 0.3])
    }

    @Test func theLightIndicatorUsesTertiaryForegroundAndAGrayCapsule() {
        let header = Private()
        header.header.applyStyle(dark: false, tint: nil)
        #expect(Support.components(header.label.textColor) == [0, 0, 0, 0.3] && Support.components(header.icon.contentTintColor) == [0, 0, 0, 0.3])
        #expect(Support.components(header.indicator.layer?.backgroundColor) == [0.973, 0.973, 0.973, 0.3])
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
        header.header.update(Support.titled("Trips"), symbol: nil, emoji: "🌴")
        header.header.layoutSubtreeIfNeeded()
        let emoji = header.emoji
        #expect(header.symbolView.isHidden && !emoji.isHidden && emoji.stringValue == "🌴")
        #expect(emoji.frame.minX == 14 && emoji.frame.width == 24 && abs(emoji.frame.midY - 18) < 0.001 && header.field.frame.minX == 42)
    }

    @Test func withoutACustomIconTheIconHidesAndTheNameLeads() {
        let header = Header()
        header.header.update(Support.titled("Space 2"), symbol: nil, emoji: nil)
        header.header.layoutSubtreeIfNeeded()
        #expect(header.symbolView.isHidden && header.emoji.isHidden)
        #expect(header.field.frame == H.frames(width: 228, icon: false, titleHeight: header.titleHeight).title)
        #expect(header.field.frame.minX == 14 && header.field.frame.maxX == 210)
    }

    @Test func aLongNameStaysOneTruncatedLineInsideTheSlot() {
        let header = Header()
        header.header.update(Support.titled(String(repeating: "Long Space Name ", count: 6)), symbol: nil, emoji: nil)
        header.header.layoutSubtreeIfNeeded()
        #expect(header.field.frame.maxX == 210 && header.field.frame.height == header.titleHeight)
    }

    private func masked() -> (Header, CAGradientLayer) {
        let header = Header()
        header.header.update(Support.titled(String(repeating: "Long Space Name ", count: 6)), symbol: nil, emoji: nil)
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
        header.header.update(Support.titled("Work"), symbol: nil, emoji: nil)
        header.field.updateMask(true)
        #expect(header.field.layer?.mask == nil)
    }
}
