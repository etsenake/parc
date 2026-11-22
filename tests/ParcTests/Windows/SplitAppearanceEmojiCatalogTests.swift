import AppKit
import CoreText
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcSidebar

@MainActor
struct SplitAppearanceEmojiCatalogTests {
    private static let emoji = SidebarEmojiModel.load(from: Bundle.module.resourceURL)

    @Test func theBundledEmojiListLoadsInCategoryOrder() {
        #expect(Self.emoji.emojis.count > 1800)
        #expect(Self.emoji.emojis.first?.emoji == "😀")
    }

    @Test func thereAreEightCategoriesInCaseOrder() {
        let starts = Self.emoji.categoryStarts.compactMap { $0 }
        #expect(starts.count == 8)
        #expect(starts == starts.sorted())
    }

    @Test func activitiesPrecedeTravel() {
        let starts = Self.emoji.categoryStarts.compactMap { $0 }
        #expect(Self.emoji.emojis[starts[4]].category == 4)
        #expect(Self.emoji.emojis[starts[3]].category == 3)
    }

    @Test func flagsComeLast() {
        let starts = Self.emoji.categoryStarts.compactMap { $0 }
        #expect(Self.emoji.emojis[starts[7]].emoji.unicodeScalars.first!.value >= 0x1F3C1)
    }

    @Test func theFilterIsCaseInsensitiveWithSpacesAsWildcards() {
        #expect(Self.emoji.filtered("grinning").emojis.first?.emoji == "😀")
        #expect(Self.emoji.filtered("GRIN face").emojis.contains { $0.emoji == "😀" })
    }

    @Test func anInvalidPatternMatchesOnlyByEmoji() {
        #expect(Self.emoji.filtered("(").emojis.isEmpty)
        #expect(Self.emoji.filtered("😀").emojis.contains { $0.emoji == "😀" })
    }

    struct SkinToneCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let base: String
        let expected: String

        static let all = [
            Self(testDescription: "single emoji", base: "👋", expected: "👋🏽"),
            Self(testDescription: "joined emoji", base: "🧑‍💻", expected: "🧑🏽‍💻"),
        ]
    }

    @Test(arguments: SkinToneCase.all)
    func aSkinToneModifierFollowsTheFirstScalar(_ sample: SkinToneCase) {
        #expect(SidebarEmojiModel.applying("\u{1F3FD}", to: sample.base) == sample.expected)
    }

    @Test func aNewSkinToneReplacesTheOldOne() {
        #expect(SidebarEmojiModel.applying("\u{1F3FB}", to: "👋🏽") == "👋🏻")
    }

    @Test func theBaseEmojiHasSixVersionsIncludingFiveSkinTones() {
        #expect(SidebarEmojiModel.variants(of: "👋").count == 6)
    }

    @Test func aTonedChoiceMarksItsBaseCell() {
        #expect(Self.emoji.index(containing: "👋🏽") == Self.emoji.emojis.firstIndex { $0.emoji == "👋" })
    }

    @Test func theEmojiPageHasNoPlaceholderBeforeTypingAndEightCategoryButtons() {
        _ = NSApplication.shared
        let page = SidebarEmojiPickerView(selectedEmoji: nil, source: Self.emoji)
        #expect(page.searchField.placeholderString == nil)
        #expect(page.categoryBar.arrangedSubviews.count == 8)
    }

    @Test func searchWaitsForItsDebounce() {
        _ = NSApplication.shared
        let page = SidebarEmojiPickerView(selectedEmoji: nil, source: Self.emoji)
        page.searchField.stringValue = "pizza"
        page.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        #expect(page.searchField.placeholderString == nil)
        #expect(page.model.emojis.count == Self.emoji.emojis.count)
    }

    @Test func theDebouncedQueryFiltersTheGrid() {
        _ = NSApplication.shared
        let page = SidebarEmojiPickerView(selectedEmoji: nil, source: Self.emoji)
        page.searchField.stringValue = "pizza"
        page.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        page.applyQuery()
        #expect(page.model.emojis.contains { $0.emoji == "🍕" })
        #expect(page.model.emojis.count < 20)
    }

    @Test func anEmptiedSearchShowsSearchAndEveryEmoji() {
        _ = NSApplication.shared
        let page = SidebarEmojiPickerView(selectedEmoji: nil, source: Self.emoji)
        page.searchField.stringValue = "pizza"
        page.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        page.applyQuery()
        page.searchField.stringValue = ""
        page.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        page.applyQuery()
        #expect(page.searchField.placeholderString == "Search")
        #expect(page.model.emojis.count == Self.emoji.emojis.count)
    }

    @Test func aToneLessEmojiSelectsAtOnce() throws {
        _ = NSApplication.shared
        let page = SidebarEmojiPickerView(selectedEmoji: nil, source: Self.emoji)
        var picked: [String] = []
        page.onEmojiSelected = { picked.append($0) }
        let pizza = try #require(Self.emoji.emojis.firstIndex { $0.emoji == "🍕" })
        page.collectionView(page.collectionView, didSelectItemsAt: [IndexPath(item: pizza, section: 0)])
        #expect(picked == ["🍕"])
        #expect(page.selectedEmoji == "🍕")
        #expect(page.skinTonePopover == nil)
    }

    @Test func emojiCellsAreTwentyEightPoints() {
        _ = NSApplication.shared
        let page = SidebarEmojiPickerView(selectedEmoji: nil, source: Self.emoji)
        let size = page.collectionView(page.collectionView, layout: page.collectionView.collectionViewLayout!,
                                       sizeForItemAt: IndexPath(item: 0, section: 0))
        #expect(size == NSSize(width: 28, height: 28))
    }
}
