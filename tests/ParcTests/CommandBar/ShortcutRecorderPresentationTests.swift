import AppKit
import QuartzCore
import Testing
@testable import Parc

struct ShortcutRecorderPresentationTests {
    @MainActor private final class Window: NSWindow {
        override var isKeyWindow: Bool { true }
        override var isVisible: Bool { true }
    }

    @MainActor private final class Host: NSObject, AppearanceHost {
        @objc dynamic var appearance: NSAppearance?

        func observeAppearance(_ change: @escaping @MainActor () -> Void) -> NSKeyValueObservation {
            observe(\.appearance, options: [.new]) { _, _ in MainActor.assumeIsolated { change() } }
        }
    }

    @MainActor private final class Fixture {
        let window: Window
        let field: ShortcutRecorderView
        let border: CALayer
        let halo: CALayer
        let label: NSTextField

        init(shortcut: KeyboardShortcut = KeyboardShortcut(key: "=", flags: [.control, .shift]),
             appearance: NSAppearance.Name = .aqua, applicationAppearance: NSAppearance.Name? = nil) throws {
            _ = NSApplication.shared
            window = Window(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.titled],
                            backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let host = Host()
            host.appearance = applicationAppearance.flatMap { NSAppearance(named: $0) }
            field = ShortcutRecorderView(frame: NSRect(x: 20, y: 20, width: 66, height: 24), appearanceHost: host)
            window.contentView?.addSubview(field)
            field.shortcut = shortcut
            field.appearance = NSAppearance(named: appearance)
            field.refreshPresentation(reduceMotion: false)
            let sublayers = try #require(field.layer?.sublayers)
            border = sublayers[0]
            halo = sublayers[1]
            label = try #require(field.subviews.compactMap { $0 as? NSTextField }.first)
        }

        func focus() throws {
            try #require(window.makeFirstResponder(field))
            field.refreshPresentation(reduceMotion: false)
        }

        func event() -> NSEvent { CommandBarTestSupport.keyEvent(0, window: window) }

        func matches(_ color: CGColor?, _ expected: NSColor) -> Bool {
            guard let color, let value = NSColor(cgColor: color)?.usingColorSpace(.sRGB),
                  let target = NSColor(cgColor: expected.cgColor(in: field.effectiveAppearance))?.usingColorSpace(.sRGB) else { return false }
            return abs(value.redComponent - target.redComponent) < 0.002 && abs(value.greenComponent - target.greenComponent) < 0.002
                && abs(value.blueComponent - target.blueComponent) < 0.002 && abs(value.alphaComponent - target.alphaComponent) < 0.002
        }

        static func gray(_ value: Double) -> NSColor { NSColor(srgbRed: value, green: value, blue: value, alpha: 1) }
    }

    @Test @MainActor func theFieldDrawsAContinuousSixPointOutlineOverItsBounds() throws {
        let fixture = try Fixture()
        #expect(fixture.border.frame == fixture.field.bounds)
        #expect(fixture.border.cornerRadius == 6)
        #expect(fixture.border.cornerCurve == .continuous)
        #expect(fixture.border.borderWidth == 1)
    }

    @Test(arguments: [(NSAppearance.Name.aqua, 0.93), (NSAppearance.Name.darkAqua, 0.158)])
    @MainActor func anUnfocusedFieldUsesTheAppearancesQuietOutline(name: NSAppearance.Name, gray: Double) throws {
        let fixture = try Fixture(appearance: name)
        #expect(fixture.matches(fixture.border.borderColor, Fixture.gray(gray)))
        #expect(fixture.halo.borderWidth == 0)
        #expect(fixture.halo.animationKeys() == nil)
    }

    @Test @MainActor func aLightUnfocusedFieldIsWhite() throws {
        let fixture = try Fixture()
        #expect(fixture.matches(fixture.border.backgroundColor, .white))
    }

    @Test @MainActor func explicitlyDarkAppearanceUsesATranslucentWhiteFill() throws {
        let fixture = try Fixture(appearance: .darkAqua, applicationAppearance: .darkAqua)
        #expect(fixture.matches(fixture.border.backgroundColor, NSColor.white.withAlphaComponent(0.1)))
    }

    @Test(arguments: [false, true])
    @MainActor func explicitlyDarkAppearanceChangesTheOutlineWithRowSelection(selected: Bool) throws {
        let fixture = try Fixture(appearance: .darkAqua, applicationAppearance: .darkAqua)
        fixture.field.rowSelected = selected
        fixture.field.refreshPresentation(reduceMotion: false)
        let outline = selected ? NSColor.white.withAlphaComponent(0.1) : Fixture.gray(0.243)
        #expect(fixture.matches(fixture.border.borderColor, outline))
    }

    @Test @MainActor func theLabelIsCenteredPassiveContent() throws {
        let fixture = try Fixture()
        #expect(fixture.label.font?.pointSize == 12)
        #expect(fixture.label.alignment == .center)
        #expect(!fixture.label.isSelectable && !fixture.label.isEditable)
        #expect(!fixture.label.isAccessibilityElement() && fixture.label.isAccessibilityHidden())
        #expect(fixture.field.accessibilityChildren()?.isEmpty == true)
    }

    @Test(arguments: [NSEvent.ModifierFlags([.control, .command]), [.control, .option, .shift, .command]])
    @MainActor func aCompleteSpaceChordFitsTheFieldAndIsSpokenAsSpace(flags: NSEvent.ModifierFlags) throws {
        let fixture = try Fixture(shortcut: KeyboardShortcut(key: " ", flags: flags))
        let cell = try #require(fixture.label.cell)
        #expect(fixture.label.stringValue == fixture.field.shortcut?.display)
        #expect(cell.cellSize.width <= fixture.label.frame.width)
        #expect(try #require(fixture.label.font).pointSize >= 8 && fixture.label.font!.pointSize <= 12)
        #expect(fixture.field.frame.width == 66)
        #expect((fixture.field.accessibilityValue() as? String) == fixture.field.shortcut?.spokenDisplay)
        #expect((fixture.field.accessibilityValue() as? String)?.hasSuffix("Space") == true)
    }

    @Test @MainActor func aShortChordRestoresTheTwelvePointLabel() throws {
        let fixture = try Fixture(shortcut: KeyboardShortcut(key: " ", flags: [.control, .option, .shift, .command]))
        fixture.field.shortcut = KeyboardShortcut(key: "=", flags: [.control, .shift])
        fixture.field.refreshPresentation(reduceMotion: false)
        #expect(fixture.label.font?.pointSize == 12)
    }

    @Test @MainActor func hoverAddsOnlyATranslucentAccentOutline() throws {
        let fixture = try Fixture()
        fixture.field.mouseEntered(with: fixture.event())
        fixture.field.refreshPresentation(reduceMotion: false)
        #expect(fixture.matches(fixture.border.borderColor, NSColor.controlAccentColor.withAlphaComponent(0.4)))
    }

    @Test @MainActor func aSelectedRowAloneDoesNotLookFocused() throws {
        let fixture = try Fixture()
        fixture.field.rowSelected = true
        fixture.field.refreshPresentation(reduceMotion: false)
        #expect(fixture.matches(fixture.border.borderColor, Fixture.gray(0.93)))
    }

    @Test @MainActor func focusUsesTheAccentOutlineAndLabel() throws {
        let fixture = try Fixture()
        defer { fixture.field.cancelRecording() }
        try fixture.focus()
        #expect(fixture.matches(fixture.border.borderColor, .controlAccentColor))
        #expect(fixture.matches(fixture.label.textColor?.cgColor(in: fixture.field.effectiveAppearance), .controlAccentColor))
        #expect(fixture.halo.borderWidth == 1)
    }

    @Test @MainActor func focusOwnsExactlyTheFourPulseAnimations() throws {
        let fixture = try Fixture()
        defer { fixture.field.cancelRecording() }
        try fixture.focus()
        #expect(Set(fixture.halo.animationKeys() ?? []) == ["transform.scale.x", "transform.scale.y", "opacity", "cornerRadius"])
    }

    @Test @MainActor func thePulseHasItsDurationExtentAndMatchingFade() throws {
        let fixture = try Fixture()
        defer { fixture.field.cancelRecording() }
        try fixture.focus()
        let pulse = try #require(fixture.halo.animation(forKey: "transform.scale.x") as? CABasicAnimation)
        let fade = try #require(fixture.halo.animation(forKey: "opacity") as? CABasicAnimation)
        #expect(pulse.duration == 1.5)
        #expect(pulse.repeatDuration.isInfinite)
        #expect(pulse.fromValue as? Double == 1)
        #expect(pulse.toValue as? Double == 1.175)
        #expect(fade.fromValue as? Double == 1)
        #expect(fade.toValue as? Double == 0)
        #expect(fade.beginTime == pulse.beginTime)
    }

    @Test @MainActor func refreshingUnchangedPresentationKeepsThePulsePhase() throws {
        let fixture = try Fixture()
        defer { fixture.field.cancelRecording() }
        try fixture.focus()
        let begin = try #require(fixture.halo.animation(forKey: "opacity")?.beginTime)
        fixture.field.refreshPresentation(reduceMotion: false)
        #expect(fixture.halo.animation(forKey: "opacity")?.beginTime == begin)
    }

    @Test @MainActor func aFocusedConflictIsTintedRed() throws {
        let fixture = try Fixture()
        defer { fixture.field.cancelRecording() }
        try fixture.focus()
        fixture.field.isConflicting = true
        fixture.field.refreshPresentation(reduceMotion: false)
        #expect(fixture.matches(fixture.border.borderColor, .systemRed))
        #expect(fixture.matches(fixture.halo.borderColor, .systemRed))
    }

    @Test @MainActor func reduceMotionRemovesTheHaloButKeepsTheFocusOutline() throws {
        let fixture = try Fixture()
        defer { fixture.field.cancelRecording() }
        try fixture.focus()
        fixture.field.refreshPresentation(reduceMotion: true)
        #expect(fixture.halo.animationKeys() == nil)
        #expect(fixture.border.borderWidth == 1)
    }

    @Test @MainActor func resizingUpdatesBothLayers() throws {
        let fixture = try Fixture()
        defer { fixture.field.cancelRecording() }
        try fixture.focus()
        fixture.field.setFrameSize(NSSize(width: 80, height: 24))
        fixture.field.refreshPresentation(reduceMotion: false)
        #expect(fixture.border.frame.width == 80)
        #expect(fixture.halo.frame.width == 80)
    }

    @Test @MainActor func cancellingRetiresThePulseAndTheRecording() throws {
        let fixture = try Fixture()
        try fixture.focus()
        fixture.field.cancelRecording()
        fixture.field.refreshPresentation(reduceMotion: false)
        #expect(fixture.halo.animationKeys() == nil)
        #expect(!fixture.field.isRecording)
    }

    @Test @MainActor func hidingTheFieldCancelsInputAndMotionTogether() throws {
        let fixture = try Fixture()
        try fixture.focus()
        fixture.field.isHidden = true
        #expect(!fixture.field.isRecording)
        #expect(fixture.halo.animationKeys() == nil)
        fixture.field.isHidden = false
        #expect(fixture.window.makeFirstResponder(fixture.field))
        fixture.field.cancelRecording()
    }

    @Test @MainActor func detachingTheFieldRetiresItsPulseAndInput() throws {
        let fixture = try Fixture()
        try fixture.focus()
        fixture.field.removeFromSuperview()
        #expect(!fixture.field.isRecording)
        #expect(fixture.halo.animationKeys() == nil)
    }
}
