import Foundation
import Testing
@testable import ParcCore

struct NoteUnsplashTestsCreditTests {
    private typealias Fixture = NoteUnsplashTestsSupport

    @Test
    func theCreditNamesAndLinksThePhotographer() throws {
        let credit = NoteUnsplash.credit(for: try Fixture.photo())
        #expect(credit == NoteMediaCredit(name: "Jane \"JJ\" Doe", link: "https://unsplash.com/@jane"), "the credit names and links the photographer")
    }

    @Test
    func theCreditSentenceNamesUnsplash() throws {
        let credit = NoteUnsplash.credit(for: try Fixture.photo())
        #expect(credit.sentence == "Photo by Jane \"JJ\" Doe on Unsplash", "the credit reads like Unsplash asks")
    }

    @Test
    func theProfileLinkCarriesReferralTags() throws {
        let credit = NoteUnsplash.credit(for: try Fixture.photo())
        let profile = Fixture.query(credit.profileURL)
        #expect(profile["utm_source"] == "parc" && profile["utm_medium"] == "referral", "profile links carry Unsplash's referral tags")
    }

    @Test
    func theProviderLinkCarriesReferralTags() throws {
        let credit = NoteUnsplash.credit(for: try Fixture.photo())
        #expect(credit.provider?.name == "Unsplash" && Fixture.query(credit.provider?.url)["utm_medium"] == "referral", "Unsplash itself is linked with referral tags")
    }

    @Test
    func anExistingReferralTagIsPreserved() {
        let tagged = NoteMediaCredit.referral(URL(string: "https://unsplash.com/@jane?utm_source=other")!)
        #expect(Fixture.query(tagged)["utm_source"] == "other" && Fixture.query(tagged)["utm_medium"] == "referral", "existing tags are kept")
    }

    @Test
    func aNonUnsplashCreditUsesAPlainSentenceAndLink() {
        let elsewhere = NoteMediaCredit(name: "Sam", link: "https://example.com/sam")
        #expect(elsewhere.provider == nil && elsewhere.sentence == "Photo by Sam", "other sites get a plain credit")
        #expect(elsewhere.profileURL?.absoluteString == "https://example.com/sam", "other links aren't tagged")
    }

    @Test
    func onlyWebCreditLinksAreClickable() {
        #expect(NoteMediaCredit(name: "Sam", link: "javascript:alert(1)").profileURL == nil, "only web links are clickable")
    }

    @Test
    func aCreditNeedsAName() {
        let blank: String? = "  "
        let nameless = NoteMediaCredit(name: blank, link: "https://unsplash.com/@x")
        #expect(nameless == nil, "a credit needs a name")
    }

    @Test
    func aBlankCreditLinkIsDropped() {
        #expect(NoteMediaCredit(name: " Sam ", link: " ").link == nil, "blank links are dropped")
    }

    private func creditedImagePage() -> NotePage {
        var block = NoteBlock(.image)
        block.props.source = "Attachments/Photo%20by%20Jane.jpg"
        block.props.alt = "A mountain lake"
        block.props.credit = NoteMediaCredit(name: "Jane \"JJ\" <Doe> -->", link: "https://unsplash.com/@jane")
        return NotePage(blocks: [block, NoteBlock.paragraph(NoteText("After"))])
    }

    private func creditedCoverPage() -> NotePage {
        var page = NotePage(blocks: [NoteBlock.paragraph(NoteText("Body"))])
        page.settings.cover = NoteCover(source: "Attachments/Photo by Jane.jpg", position: 0.3,
                                        credit: NoteMediaCredit(name: "1999", link: "https://unsplash.com/@jane"))
        return page
    }

    @Test
    func theImageCreditIsEscapedInItsParcComment() {
        let page = creditedImagePage()
        let written = NoteMarkdown.serialize(page)
        #expect(written.contains("<!-- parc credit=\"Jane &quot;JJ&quot; &lt;Doe&gt; --&gt;\" credit-url=\"https://unsplash.com/@jane\" -->"), "the credit rides in the block's parc comment:\n\(written)")
    }

    @Test
    func anImageKeepsItsCreditThroughMarkdown() {
        let page = creditedImagePage()
        let written = NoteMarkdown.serialize(page)
        let read = NoteMarkdown.parse(written)
        #expect(read.blocks.first?.kind == .image, "the block stays an image")
        #expect(read.blocks.first?.props.credit == page.blocks[0].props.credit, "the credit survives a save and reload")
    }

    @Test
    func anImageCreditSavesTheSameBytesAgain() {
        let page = creditedImagePage()
        let written = NoteMarkdown.serialize(page)
        let read = NoteMarkdown.parse(written)
        #expect(NoteMarkdown.serialize(read) == written, "a second save writes the same bytes")
    }

    @Test
    func aVideoKeepsItsCreditWithoutALink() {
        let handWritten = "![](https://example.com/clip.mp4) <!-- parc credit=\"Sam\" -->\n"
        let video = NoteMarkdown.parse(handWritten)
        #expect(video.blocks.first?.kind == .video && video.blocks.first?.props.credit == NoteMediaCredit(name: "Sam"), "any media block can carry a credit")
        #expect(NoteMarkdown.serialize(video) == handWritten, "a credit without a link round-trips")
    }

    @Test
    func aParagraphCannotTakeAMediaCredit() {
        let paragraph = NoteMarkdown.parse("Hello <!-- parc credit=\"Sam\" -->\n")
        #expect(paragraph.blocks.first?.props.credit == nil, "text blocks don't take credits")
    }

    @Test
    func coverCreditsWriteImmediatelyBelowTheCover() {
        let page = creditedCoverPage()
        let written = NoteMarkdown.serialize(page)
        #expect(written.hasPrefix("---\ncover: Attachments/Photo by Jane.jpg\ncover-position: 0.3\ncover-credit: \"1999\"\ncover-credit-url: https://unsplash.com/@jane\n---\n"), "cover credits sit right under the cover:\n\(written)")
    }

    @Test
    func aCoverCreditRoundTripsWithoutBecomingAProperty() {
        let page = creditedCoverPage()
        let written = NoteMarkdown.serialize(page)
        let read = NoteMarkdown.parse(written)
        #expect(read.settings.cover == page.settings.cover, "the cover credit survives a save and reload")
        #expect(read.settings.properties.isEmpty, "the credit keys aren't page properties")
    }

    @Test
    func aCoverCreditSavesTheSameBytesAgain() {
        let page = creditedCoverPage()
        let written = NoteMarkdown.serialize(page)
        let read = NoteMarkdown.parse(written)
        #expect(NoteMarkdown.serialize(read) == written, "a second save writes the same bytes")
    }

    @Test
    func anOrphanedCoverCreditStaysInFrontMatter() {
        let orphan = "---\ncover-credit: Jane\ncover-credit-url: https://unsplash.com/@jane\n---\n\nBody\n"
        let orphaned = NoteMarkdown.parse(orphan)
        #expect(orphaned.settings.cover == nil && orphaned.settings.properties.count == 2, "a credit without a cover is kept as it was")
        #expect(NoteMarkdown.serialize(orphaned) == orphan, "an orphaned credit round-trips")
    }

    @Test
    func aCoverCreditLinkWithoutANameStaysInFrontMatter() {
        let linkOnly = "---\ncover: a.jpg\ncover-credit-url: https://unsplash.com/@jane\n---\n\nBody\n"
        let linked = NoteMarkdown.parse(linkOnly)
        #expect(linked.settings.cover?.credit == nil, "a link without a name isn't a credit")
        #expect(NoteMarkdown.serialize(linked) == linkOnly, "a lone credit link round-trips")
    }

    @Test
    func coverCreditKeysCannotBeUsedAsProperties() {
        #expect(NotePropertyEditing.reservedKeys.isSuperset(of: ["cover-credit", "cover-credit-url"]), "people can't make properties that shadow the credit")
    }
}
