import CoreGraphics
import Foundation
import Testing
@testable import ParcCore

struct ArcSidebarImportParsingTests {
    private typealias Support = ArcSidebarImportTestsSupport

    struct ProfileDirectory: Sendable, CustomTestStringConvertible {
        let directory: String
        let expected: ArcSidebarImport.ProfileKey
        var testDescription: String { directory }
    }

    @Test(arguments: [
        ProfileDirectory(directory: "Default", expected: .standard),
        ProfileDirectory(directory: "Profile 1", expected: Support.profileOne),
    ])
    func profileDirectoriesResolveToTheirArcProfile(_ entry: ProfileDirectory) {
        #expect(ArcSidebarImport.profileKey(directory: entry.directory) == entry.expected)
    }

    @Test func profilesListStandardFirstThenSpacesThenFavorites() throws {
        let arc = try Support.loadArc()
        #expect(arc.profiles == [.standard, Support.profileOne, Support.profileTwo])
    }

    @Test func spacesKeepArcsOrderAndSkipOnesWithoutAProfile() throws {
        let arc = try Support.loadArc()
        #expect(arc.spaces.map(\.title) == ["Work", nil, "Side", "Plain", "Odd"])
        #expect(arc.spaces.map(\.profile) == [.standard, .standard, Support.profileOne, .standard, .standard])
    }

    @Test func refusedAndBrokenItemsAreCounted() throws {
        let arc = try Support.loadArc()
        #expect(arc.skippedItemCount == 9)
    }

    @Test func thePinnedTreeKeepsSupportedItemsAndTheirMetadata() throws {
        let arc = try Support.loadArc()
        let work = arc.spaces[0]
        let expected: [Support.Item] = [
            .tab(Support.Tab(title: "Alpha docs", url: "https://docs.example.test/a", customTitle: "Renamed alpha", isMuted: true)),
            .folder(title: "Projects", icon: .icon(.star), children: [
                .tab(Support.Tab(title: "example.test", url: "https://example.test/b")),
                .folder(title: "Imported folder", icon: nil, children: [.tab(Support.Tab(title: "Gamma", url: "https://example.test/c"))])
            ]),
            .split(title: "Compare", icon: .emoji("\u{1F9EA}"), tabs: [Support.Tab(title: "Delta", url: "https://example.test/d"),
                   Support.Tab(title: "Epsilon", url: "https://example.test/e")], orientation: .vertical, widthFactors: [0.3, 0.7]),
            .tab(Support.Tab(title: "Settings", url: "parc://settings"))
        ]
        #expect(Support.roundingFactors(work.pinned) == expected)
    }

    @Test func aSpaceKeepsItsRecognizedSymbol() throws {
        let arc = try Support.loadArc()
        let work = arc.spaces[0]
        #expect(work.icon == .icon(.planet))
    }

    @Test func splitWidthFactorsFollowTheirTabIDs() throws {
        let arc = try Support.loadArc()
        guard case let .split(_, _, _, _, factors) = arc.spaces[0].pinned[2] else {
            Issue.record("The third pinned item is a split")
            return
        }
        #expect(Support.close(factors[0], 0.3) && Support.close(factors[1], 0.7))
    }

    @Test func singleColorThemeKeepsTextureNoiseAndIntensity() throws {
        let single = try #require(try Support.loadArc().spaces[0].theme)
        #expect(single.colorCount == 1 && single.wheel == .complimentary && single.texture == .grain)
        #expect(Support.close(single.noise, 0.8) && Support.close(single.intensity, 1))
        #expect(single.appearance == .automatic)
    }

    @Test func outOfGamutColorIsCarriedInDisplayP3() throws {
        let single = try #require(try Support.loadArc().spaces[0].theme)
        let primary = try #require(single.primaryColor)
        #expect(primary.colorSpace == .displayP3)
        let extended = try #require(CGColorSpace(name: CGColorSpace.extendedSRGB))
        let displayP3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let source = try #require(CGColor(colorSpace: extended, components: [1.0699, -0.143, 0.2, 1]))
        let converted = try #require(source.converted(to: displayP3, intent: .defaultIntent, options: nil))
        let system = try #require(converted.components)
        #expect(Support.close(primary.red, Double(system[0]), 1e-3) && Support.close(primary.green, Double(system[1]), 1e-3)
                && Support.close(primary.blue, Double(system[2]), 1e-3))
    }

    @Test func aThreeColorThemeUsesItsAnalogousPalette() throws {
        let ideas = try Support.loadArc().spaces[1]
        #expect(ideas.theme?.colorCount == 3 && ideas.theme?.wheel == .analogous && ideas.theme?.texture == .sand)
        #expect(ideas.theme?.primaryColor == ThemeColor(red: 0.2, green: 0.4, blue: 0.8))
    }

    @Test func theV2EmojiUsesItsSingleCharacter() throws {
        let ideas = try Support.loadArc().spaces[1]
        #expect(ideas.icon == .emoji("\u{1F680}"))
    }

    @Test func reversedContainerLabelsStillFindPinned() throws {
        let ideas = try Support.loadArc().spaces[1]
        #expect(ideas.pinned == [.tab(Support.Tab(title: "Golf", url: "https://example.test/g"))])
    }

    @Test func aTwoColorThemeKeepsItsComplementaryPaletteAndTexture() throws {
        let side = try Support.loadArc().spaces[2]
        #expect(side.theme?.colorCount == 2 && side.theme?.wheel == .complimentary && side.theme?.texture == .tweed
                && side.theme.map { Support.close($0.noise, 0.25) && Support.close($0.intensity, 0.5) } == true)
    }

    @Test func aLegacyEmojiUsesItsUnicodeScalar() throws {
        let side = try Support.loadArc().spaces[2]
        #expect(side.icon == .emoji("\u{1F600}"))
    }

    @Test func newContainerIDsAloneLocateThePinnedContainer() throws {
        let actual = try Support.loadArc().spaces[2].pinned.count
        #expect(actual == 1)
    }

    @Test func unknownIconIsDroppedAndMissingThemeIsArcsUnthemedSpace() throws {
        let plain = try Support.loadArc().spaces[3]
        #expect(plain.icon == nil && plain.theme == SpaceTheme() && plain.pinned.isEmpty)
    }

    @Test func unknownStyleFallsBackToParcsDefaultTheme() throws {
        let actual = try Support.loadArc().spaces[4].theme
        #expect(actual == nil)
    }

    @Test func standardFavoritesHoldTabsAndSplitsButSkipFolders() throws {
        let favorites = try #require(try Support.loadArc().favorites[.standard])
        #expect(favorites.count == 14)
        #expect(favorites[1] == .split(title: nil, icon: nil, tabs: [Support.Tab(title: "Left", url: "https://left.example.test/"),
               Support.Tab(title: "Right", url: "https://right.example.test/")], orientation: .horizontal, widthFactors: [0.5, 0.5]))
    }

    @Test func customProfileFavoritesAreRead() throws {
        let actual = try Support.loadArc().favorites[Support.profileTwo]
        #expect(actual == [.tab(Support.Tab(title: "Calendar", url: "https://calendar.example.test/"))])
    }

    @Test(arguments: ["not json", "[]", #"{"sidebar":{"containers":[{"global":{}}]}}"#])
    func aFileWithoutArcsSidebarShapeFails(bad: String) {
        #expect(throws: (any Error).self) { try ArcSidebarImport(data: Data(bad.utf8)) }
    }

    @Test func nestingIsBoundedAt128() throws {
        var deep: [Any] = []
        for level in 0..<200 {
            let child = level < 199 ? ["F\(level + 1)"] : []
            deep += ["F\(level)", ["id": "F\(level)", "title": "L\(level)", "childrenIds": child, "data": ["list": [:]]]]
        }
        let deepArc = try ArcSidebarImport(data: Support.document(items: deep, pinned: ["F0"]))
        var depth = 0
        var level = deepArc.spaces[0].pinned
        while case let .folder(_, _, children)? = level.first { depth += 1; level = children }
        #expect(depth == ArcSidebarImport.maximumDepth && deepArc.skippedItemCount == 1)
    }

    @Test func itemCountIsBoundedAt50000IncludingTheContainer() throws {
        var many: [Any] = []
        var ids: [String] = []
        for index in 0...ArcSidebarImport.maximumItems {
            ids.append("T\(index)")
            many += ["T\(index)", ["id": "T\(index)", "data": ["tab": ["savedURL": "https://example.test/\(index)", "savedTitle": "T"]]]]
        }
        let manyArc = try ArcSidebarImport(data: Support.document(items: many, pinned: ids))
        #expect(manyArc.spaces[0].pinned.count == ArcSidebarImport.maximumItems - 1 && manyArc.skippedItemCount == 4)
    }
}
