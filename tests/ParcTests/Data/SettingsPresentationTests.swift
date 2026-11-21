import AppKit
import Testing
@testable import Parc

@MainActor
struct SettingsPresentationTests {
    @MainActor
    private final class Backdrop: LayoutView {}

    struct Command: Sendable, CustomTestStringConvertible {
        let title: String
        let symbol: String
        var testDescription: String { title }
    }

    nonisolated static let commands = [
        Command(title: "Privacy and Security", symbol: "lock.fill"),
        Command(title: "Passwords", symbol: "key.fill"),
        Command(title: "Credit Cards", symbol: "creditcard.and.123"),
        Command(title: "Notifications", symbol: "bell.fill"),
    ]

    @MainActor
    private final class Fixture {
        let window: NSWindow
        let backdrop = Backdrop(frame: NSRect(x: 0, y: 0, width: SettingsLayout.contentWidth, height: 420))
        let group: SettingsGroupView

        init() {
            _ = NSApplication.shared
            window = NSWindow(contentRect: backdrop.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = backdrop
            group = SettingsGroupView(frame: NSRect(x: SettingsLayout.margin, y: 60, width: SettingsLayout.groupWidth,
                                                    height: SettingsLayout.rowHeight * 4))
            backdrop.addSubview(group)
        }

        deinit {
            MainActor.assumeIsolated { window.close() }
        }

        func command(_ value: Command, at index: Int = 0, color: NSColor = .systemBlue) -> SettingsCommandButton {
            let button = SettingsCommandButton(title: value.title, symbol: value.symbol, color: color)
            button.frame = NSRect(x: 0, y: CGFloat(index) * SettingsLayout.rowHeight,
                                  width: SettingsLayout.groupWidth, height: SettingsLayout.rowHeight)
            group.addSubview(button)
            button.layoutSubtreeIfNeeded()
            return button
        }

        func spaceRow(name: String, detail: String) -> SettingsSpaceButton {
            let profile = SettingsSpaceButton {}
            profile.update(name: name, detail: detail, image: NSImage(systemSymbolName: "star", accessibilityDescription: nil))
            profile.frame = NSRect(x: 0, y: 0, width: SettingsLayout.groupWidth, height: SettingsLayout.rowHeight)
            group.addSubview(profile)
            profile.layoutSubtreeIfNeeded()
            return profile
        }
    }

    @Test func sectionHeadingsUseTheSemiboldHeadingFace() {
        _ = NSApplication.shared
        let heading = SettingsSectionHeading(title: "Your Data and Settings")
        #expect(heading.font == .systemFont(ofSize: 13, weight: .semibold))
    }

    @Test(arguments: commands)
    func aCommandIsOneNamedNativeButton(command: Command) {
        let button = Fixture().command(command)
        #expect(button.accessibilityRole() == .button)
        #expect(button.accessibilityLabel() == command.title)
    }

    @Test(arguments: commands)
    func passiveArtworkAndLabelAreNotDuplicateAccessibilityControls(command: Command) {
        #expect(Fixture().command(command).accessibilityChildren()?.isEmpty ?? true)
    }

    @Test(arguments: commands)
    func everyCommandElementIsContainedInTheRow(command: Command) {
        let button = Fixture().command(command)
        #expect(button.subviews.allSatisfy { button.bounds.contains($0.frame) })
    }

    @Test(arguments: commands)
    func theBadgeFitsTheGroupedRow(command: Command) {
        let button = Fixture().command(command)
        #expect(button.subviews.compactMap { $0 as? SettingsSymbolBadge }.first?.frame.size == NSSize(width: 20, height: 20))
    }

    @Test(arguments: [NSPoint(x: 14, y: 21), NSPoint(x: 80, y: 21), NSPoint(x: SettingsLayout.groupWidth - 16, y: 21)])
    func aCommandRetainsIconTextAndArrowHitOwnership(point: NSPoint) {
        let fixture = Fixture()
        let button = fixture.command(Self.commands[0])
        #expect(button.hitTest(button.convert(point, to: fixture.group)) === button)
    }

    @Test func groupsUseContinuousRoundedCorners() {
        let group = Fixture().group
        #expect(group.layer?.cornerRadius == SettingsLayout.groupRadius)
        #expect(group.layer?.cornerCurve == .continuous)
    }

    @Test func groupsSitOnThePageWithoutAnOutline() {
        #expect(Fixture().group.layer?.borderWidth == 0)
    }

    @Test func anAcceptedClickReachesTheExistingClosureOnce() {
        var activations = 0
        let action = SettingsCommandButton(title: "Native action", symbol: "lock.fill", color: .systemBlue) { activations += 1 }
        action.performClick(nil)
        #expect(activations == 1)
    }

    @Test func aDisabledCommandDoesNotDispatch() {
        var activations = 0
        let action = SettingsCommandButton(title: "Native action", symbol: "lock.fill", color: .systemBlue) { activations += 1 }
        action.isEnabled = false
        action.performClick(nil)
        #expect(activations == 0)
    }

    @Test func longSpaceNamesCannotObscureTheDetail() {
        let profile = Fixture().spaceRow(name: String(repeating: "A very long Space name ", count: 6), detail: "Work")
        #expect(profile.name.frame.maxX <= profile.detail.frame.minX)
    }

    @Test func spaceRowTextStaysInRowBounds() {
        let profile = Fixture().spaceRow(name: String(repeating: "A very long Space name ", count: 6), detail: "Work")
        #expect(profile.bounds.contains(profile.name.frame))
        #expect(profile.bounds.contains(profile.detail.frame))
    }

    @Test func theDetailIsNeverClipped() {
        let profile = Fixture().spaceRow(name: String(repeating: "A very long Space name ", count: 6), detail: "Work")
        #expect(profile.detail.frame.width >= ceil(profile.detail.intrinsicContentSize.width))
    }

    @Test func theSpaceRowNamesItsDetail() {
        let profile = Fixture().spaceRow(name: "Personal", detail: "Work")
        #expect(profile.accessibilityLabel()?.hasSuffix(", Work") == true)
    }

    @Test func theSpaceRowLeadsWithItsIcon() {
        let profile = Fixture().spaceRow(name: "Personal", detail: "Work")
        #expect(!profile.iconImage.isHidden)
        #expect(profile.iconEmoji.isHidden)
        #expect(profile.name.frame.minX > profile.iconImage.frame.maxX)
    }

    @Test func anEmojiIconReplacesTheSymbolAndAnEmptyDetailIsNotSpoken() {
        let profile = Fixture().spaceRow(name: "Plain", detail: "")
        profile.update(name: "Plain", detail: "", emoji: "🌱")
        #expect(profile.accessibilityLabel() == "Plain")
        #expect(profile.iconImage.isHidden)
        #expect(!profile.iconEmoji.isHidden)
    }

    @Test func choosingASpaceRowOpensItOnce() {
        var opened = 0
        let profile = SettingsSpaceButton { opened += 1 }
        profile.performClick(nil)
        #expect(opened == 1)
    }

    @Test func deletionStatesRelabelTheSameButton() {
        let delete = SettingsPillButton(title: "Delete Space…")
        delete.destructive = true
        delete.setLabel("Deleting…")
        #expect(delete.title == "Deleting…")
        #expect(delete.fittingWidth > 0)
    }

    @Test func unavailableContentUsesTheRecoveredOpacity() throws {
        let fixture = Fixture()
        let disabled = fixture.command(Self.commands[0])
        disabled.isEnabled = false
        let bitmap = try #require(disabled.bitmapImageRepForCachingDisplay(in: disabled.bounds))
        disabled.cacheDisplay(in: disabled.bounds, to: bitmap)
        #expect(disabled.subviews.allSatisfy { $0.alphaValue == 0.25 })
    }

    @Test func theSharedGroupPaletteFollowsTheActualEffectiveAppearance() throws {
        let fixture = Fixture()
        var fills: [CGColor] = []
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            fixture.window.appearance = NSAppearance(named: name)
            fixture.group.viewDidChangeEffectiveAppearance()
            fills.append(try #require(fixture.group.layer?.backgroundColor))
        }
        #expect(fills[0] != fills[1])
    }
}
