import Foundation
import Testing
@testable import ParcCore

struct EaselStampModelTests {
    @Test(arguments: EaselStampDesign.allCases)
    func builtInFacesRoundTripThroughAnObject(_ design: EaselStampDesign) {
        let face = EaselStampFace.design(design)
        #expect(EaselStampFace(item: EaselStampTestsSupport.stamp(face)) == face, "\(design.title) survives a trip through the object")
    }

    @Test(arguments: EaselStampDesign.allCases)
    func builtInFacesRoundTripThroughRecents(_ design: EaselStampDesign) {
        let face = EaselStampFace.design(design)
        #expect(EaselStampFace(token: face.token) == face, "\(design.title) survives a trip through recents")
    }

    @Test(arguments: EaselStampDesign.allCases)
    func builtInFacesStoreTheirNameWithoutText(_ design: EaselStampDesign) {
        let face = EaselStampFace.design(design)
        #expect(face.stamp == design.rawValue && face.text.isEmpty, "Built-in stamps store their name and no text")
    }

    @Test(arguments: EaselStampDesign.allCases)
    func builtInFacesHaveAnAccessibleStampName(_ design: EaselStampDesign) {
        let face = EaselStampFace.design(design)
        #expect(face.accessibilityLabel() == design.title + " stamp", "\(design.title) reads as a stamp")
    }

    @Test
    func thumbsUpHasASpokenName() {
        #expect(EaselStampFace.design(.thumbsUp).accessibilityLabel() == "Thumbs up stamp", "VoiceOver hears Thumbs up stamp")
    }

    @Test
    func emojiFacesStoreTheirEmojiAsText() {
        let party = EaselStampFace.emoji("🎉")
        #expect(EaselStampFace(item: EaselStampTestsSupport.stamp(party)) == party && party.text == "🎉" && party.stamp == nil, "Emoji stamps keep the emoji as text")
    }

    @Test
    func emojiFacesUseTheNameOrEmojiInTheirSpokenLabel() {
        let party = EaselStampFace.emoji("🎉")
        #expect(party.accessibilityLabel(emojiName: "party popper") == "Party popper stamp", "Emoji stamps read their name")
        #expect(party.accessibilityLabel() == "🎉 stamp", "An unnamed emoji still reads as a stamp")
    }

    @Test
    func iconFacesStoreAPrefixedSymbolName() {
        let cloud = EaselStampFace.icon("cloud")
        #expect(cloud.text == "icon:cloud" && EaselStampFace(text: "icon:cloud") == cloud, "Icons store a prefixed symbol name")
    }

    @Test
    func iconFacesHaveReadableNames() {
        let cloud = EaselStampFace.icon("cloud")
        #expect(cloud.accessibilityLabel() == "Cloud icon", "Icons read as icons")
        #expect(EaselStampFace.icon("server.rack.fill").title() == "Server rack", "Unknown symbols get a readable name")
    }

    @Test
    func iconAndEmojiRecentTokensRoundTrip() {
        let party = EaselStampFace.emoji("🎉")
        let cloud = EaselStampFace.icon("cloud")
        #expect(EaselStampFace(token: "icon:cloud") == cloud && EaselStampFace(token: "emoji:🎉") == party, "Tokens decode")
    }

    @Test(arguments: ["", "stamp", "stamp:", "stamp:wave", "emoji:hi", "icon:Cloud", "icon:..", "logo:cloud", ":cloud"])
    func malformedRecentTokensAreRefused(_ bad: String) {
        #expect(EaselStampFace(token: bad) == nil, "Token \(bad) is refused")
    }

    @Test
    func replacingAStampFaceClearsThePreviousOne() {
        var item = EaselStampTestsSupport.stamp(.design(.heart))
        EaselStampFace.icon("bolt").apply(to: &item)
        #expect(item.stamp == nil && item.text == "icon:bolt", "Changing a face clears the old one")
        EaselStampFace.design(.star).apply(to: &item)
        #expect(item.stamp == "star" && item.text.isEmpty, "And back again")
    }

    @Test(arguments: ["🎉", "👍🏽", "❤️", "1️⃣", "#️⃣", "🇨🇦", "👩‍👩‍👧‍👦", "🏳️‍🌈", "😀", "☝🏽", "©️", "☺️"])
    func aSingleEmojiCanBeUsedAsAStamp(_ good: String) {
        #expect(EaselStampFace.isEmoji(good), "\(good) is an emoji")
    }

    @Test(arguments: ["", "a", "1", "ab", "🎉🎉", " ", "\n", "🎉 ", "™", "❤", "☺", "A\u{FE0F}", "1\u{FE0F}", "x\u{FE0F}\u{20E3}",
                    "\u{20E3}", "👩‍👩‍👧‍👦x"])
    func onlyASingleEmojiCountsAsAnEmojiStamp(_ bad: String) {
        #expect(!EaselStampFace.isEmoji(bad), "\(bad.debugDescription) is not a single emoji")
    }

    @Test
    func choosingEmojiAddsTheirMissingPresentationSelector() {
        #expect(EaselStampFace(emoji: "❤") == .emoji("❤️") && EaselStampFace(emoji: "☺") == .emoji("☺️"), "Bare text-style emoji get their emoji look when picked")
        #expect(EaselStampFace(emoji: "🎉") == .emoji("🎉") && EaselStampFace(emoji: "☝🏽") == .emoji("☝🏽")
               && EaselStampFace(emoji: "❤️") == .emoji("❤️"), "Emoji that already look right stay as they are")
    }

    @Test(arguments: ["", "A", "1", "hi", "🎉🎉", "\u{FE0F}"])
    func malformedEmojiCannotBecomeAStamp(_ bad: String) {
        #expect(EaselStampFace(emoji: bad) == nil, "\(bad.debugDescription) never becomes an emoji stamp")
    }

    @Test
    func savedEmojiStampsRequireTheirPresentationSelector() {
        #expect(EaselStampFace(text: "❤") == nil && EaselStampFace(token: "emoji:❤") == nil, "Saved stamps must already be tidy")
    }

    @Test(arguments: ["cloud", "server.rack", "chevron.left.forwardslash.chevron.right", "cylinder.split.1x2"])
    func validSymbolNamesCanBeUsedAsStamps(_ good: String) {
        #expect(EaselStampFace.isSymbolName(good), "\(good) is a symbol name")
    }

    @Test(arguments: ["", "Cloud", "cloud fill", ".cloud", "cloud.", "cloud..fill", "../etc", String(repeating: "a", count: 97)])
    func invalidSymbolNamesAreRefused(_ bad: String) {
        #expect(!EaselStampFace.isSymbolName(bad), "\(bad.debugDescription) is not a symbol name")
    }

    @MainActor @Test
    func allThreeStampFaceKindsCanBeSaved() {
        let plain = EaselStampTestsSupport.item(.rectangle, 10, 10, 100, 100)
        #expect(EaselStampTestsSupport.accepts([plain, EaselStampTestsSupport.stamp(.design(.heart)), EaselStampTestsSupport.stamp(.emoji("🎉")), EaselStampTestsSupport.stamp(.icon("cloud"))]), "Every face saves")
    }

    @MainActor @Test
    func aNonStampCannotSaveAStampFace() {
        let plain = EaselStampTestsSupport.item(.rectangle, 10, 10, 100, 100)
        var wrongKind = plain; wrongKind.stamp = "heart"
        #expect(!EaselStampTestsSupport.accepts([wrongKind]), "A stamp face on a rectangle is refused")
    }

    @MainActor @Test
    func invalidStampFacesAreRefused() {
        var unknown = EaselStampTestsSupport.stamp(.design(.heart)); unknown.stamp = "wave"
        #expect(!EaselStampTestsSupport.accepts([unknown]), "Unknown built-in stamps are refused")
        var both = EaselStampTestsSupport.stamp(.design(.heart)); both.text = "🎉"
        #expect(!EaselStampTestsSupport.accepts([both]), "A built-in stamp with emoji text is refused")
        var empty = EaselStampTestsSupport.stamp(.emoji("🎉")); empty.text = ""
        #expect(!EaselStampTestsSupport.accepts([empty]), "A stamp needs a face")
        var words = EaselStampTestsSupport.stamp(.emoji("🎉")); words.text = "hello"
        #expect(!EaselStampTestsSupport.accepts([words]), "Plain words are not a stamp")
        var path = EaselStampTestsSupport.stamp(.icon("cloud")); path.text = "icon:../../etc"
        #expect(!EaselStampTestsSupport.accepts([path]), "Odd symbol names are refused")
    }

    @MainActor @Test
    func stampsCannotSaveStrokePoints() {
        var stroked = EaselStampTestsSupport.stamp(.design(.star)); stroked.points = [EaselPoint(x: 0, y: 0), EaselPoint(x: 1, y: 1)]
        #expect(!EaselStampTestsSupport.accepts([stroked]), "Stamps carry no stroke points")
    }

    @MainActor @Test
    func stampsCannotSaveLinks() {
        var linked = EaselStampTestsSupport.stamp(.design(.star)); linked.url = "https://example.com"
        #expect(!EaselStampTestsSupport.accepts([linked]), "Stamps carry no links")
    }

    @MainActor @Test
    func stampsCannotSaveTextStyles() {
        var styled = EaselStampTestsSupport.stamp(.design(.star)); styled.textStyle = EaselTextStyle()
        #expect(!EaselStampTestsSupport.accepts([styled]), "Stamps carry no text style")
    }

    @MainActor @Test
    func aTiltedAttachedStampCanBeSaved() {
        let plain = EaselStampTestsSupport.item(.rectangle, 10, 10, 100, 100)
        var tilted = EaselStampTestsSupport.stamp(.design(.star)); tilted.rotation = -7.5; tilted.attachedTo = plain.id
        #expect(EaselStampTestsSupport.accepts([plain, tilted]), "Tilted, attached stamps save")
    }

    @Test
    func objectsWithoutStampsLeaveTheFieldOut() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let plain = EaselStampTestsSupport.item(.rectangle, 0, 0, 10, 10)
        guard let plainJSON = try? encoder.encode(plain), let plainText = String(data: plainJSON, encoding: .utf8) else {
            Issue.record("Plain objects encode")
            return
        }
        #expect(!plainText.contains("\"stamp\""), "Objects without stamps leave the field out")
    }

    @Test
    func stampKindAndFaceRoundTrip() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let heart = EaselStampTestsSupport.stamp(.design(.heart))
        guard let heartJSON = try? encoder.encode(heart), let heartText = String(data: heartJSON, encoding: .utf8),
              let decoded = try? JSONDecoder().decode(EaselItem.self, from: heartJSON) else { Issue.record("Stamps encode"); return }
        #expect(heartText.contains("\"stamp\":\"heart\"") && heartText.contains("\"kind\":\"stamp\""), "Stamps save their kind and face")
        #expect(decoded == heart, "Stamps decode unchanged")
    }

    @Test
    func olderObjectsOpenWithoutAStampField() {
        let legacy = Data("{\"id\":\"\(UUID().uuidString)\",\"kind\":\"rectangle\",\"frame\":{\"x\":0,\"y\":0,\"width\":5,\"height\":5},\"zIndex\":0,\"text\":\"\",\"color\":\"#252525\",\"points\":[]}".utf8)
        #expect((try? JSONDecoder().decode(EaselItem.self, from: legacy))?.stamp == nil, "Older objects open without a stamp")
    }

    @Test func aGenerousIconSet() {
        let all = EaselStampIcons.all
        #expect(all.count >= 80, "A generous icon set")
        #expect(Set(all.map(\.symbol)).count == all.count, "Each icon appears once")
        #expect(Set(all.map { $0.title.lowercased() }).count == all.count, "Icon names are unique for VoiceOver")
        #expect(all.allSatisfy { EaselStampFace.isSymbolName($0.symbol) && !$0.title.isEmpty }, "Icons have valid symbols and names")
        #expect(EaselStampIcons.sections.allSatisfy { !$0.icons.isEmpty && !$0.title.isEmpty }, "Sections are named and filled")
        for (query, symbol) in [("database", "cylinder.split.1x2"), ("server", "server.rack"), ("user", "person"), ("mail", "envelope"),
                                ("credit", "creditcard"), ("auth", "person.badge.key"), ("settings", "gearshape"), ("wifi", "wifi"),
                                ("location", "mappin.and.ellipse"), ("chat", "bubble.left"), ("package", "shippingbox")] {
            #expect(EaselStampIcons.search(query).contains { $0.symbol == symbol }, "Searching \(query) finds \(symbol)")
        }
        #expect(EaselStampIcons.search("Cl").first?.symbol == "cloud", "Name matches come first")
        #expect(EaselStampIcons.search("  ").count == all.count && EaselStampIcons.search("zzzz").isEmpty, "Blank searches show everything")
        #expect(EaselStampIcons.icon(named: "cloud")?.title == "Cloud" && EaselStampIcons.icon(named: "nope") == nil, "Icons look up by symbol")
    }

    @Test @MainActor func onlyIconStampsTakeAColour() throws {
        var cloud = EaselStampTestsSupport.stamp(.icon("cloud"))
        let party = EaselStampTestsSupport.stamp(.emoji("🎉")), heart = EaselStampTestsSupport.stamp(.design(.heart))
        #expect(EaselStyleFamily.of(cloud) == .icons && EaselStyleFamily.of(party) == nil && EaselStyleFamily.of(heart) == nil, "Only icon stamps take a colour")
        #expect(EaselSelectionToolbarPlan.groups(for: [EaselToolbarSubject(cloud)], editingText: false, locked: false) == [[.color], [.more]], "A selected icon gets the style button")
        #expect(EaselSelectionToolbarPlan.groups(for: [EaselToolbarSubject(party)], editingText: false, locked: false) == [[.more]], "Emoji and built-in stamps stay colourless")
        let palette = try #require(EaselPalette.colors(for: .ink).first(where: { $0 != .automatic }), "No ink palette")
        #expect(EaselStyle.apply(.color(.palette(palette)), to: &cloud) && cloud.color == EaselPalette.stored(palette, role: .ink), "The style button recolours icons with palette colours")
        #expect(EaselStyle.colorChoice(of: cloud) == .palette(palette), "The picker shows the icon's palette colour")
        var art = EaselVectorArt()
        art.images[cloud.id] = EaselVectorImage(data: Data([0x89, 0x50, 0x4E, 0x47]), mimeType: "image/png")
        #expect(EaselVectorExport.element(cloud, art: art).contains("fill:var(--"), "Recoloured icons export their palette colour for light and dark")
        var mixed = party
        #expect(!EaselStyle.apply(.color(.palette(palette)), to: &mixed) && mixed == party, "Recolouring a mixed selection leaves emoji alone")
        #expect(EaselStampTestsSupport.accepts([cloud]), "Recoloured icons still save")
    }
}
