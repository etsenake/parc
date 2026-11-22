import Foundation
import Testing
@testable import ParcCore

struct NoteUnsplashTestsHTMLCreditTests {
    @Test
    func aCreditSitsUnderTheImageCaption() {
        var block = NoteBlock(.image)
        block.props.source = "https://images.unsplash.com/photo.jpg"
        block.props.caption = NoteText("Morning")
        block.props.credit = NoteMediaCredit(name: "Jane & Co", link: "https://unsplash.com/@jane")
        let fragment = NotePageHTML.fragment([block])
        #expect(fragment.contains("<figcaption>Morning<br><span class=\"credit\">Photo by <a href=\"https://unsplash.com/@jane?utm_source=parc&amp;utm_medium=referral\">Jane &amp; Co</a> on <a href=\"https://unsplash.com/?utm_source=parc&amp;utm_medium=referral\">Unsplash</a></span></figcaption>"), "exported images credit the photographer under the caption:\n\(fragment)")
    }

    @Test
    func aCreditMakesAFigcaptionEvenWithoutACaption() {
        var block = NoteBlock(.image)
        block.props.source = "https://images.unsplash.com/photo.jpg"
        block.props.caption = NoteText()
        block.props.credit = NoteMediaCredit(name: "Jane & Co", link: "https://unsplash.com/@jane")
        #expect(NotePageHTML.fragment([block]).contains("<figcaption><span class=\"credit\">Photo by"), "the credit alone still makes a caption")
    }

    @Test
    func anExportedCoverIncludesItsCredit() {
        var page = NotePage(blocks: [])
        page.settings.cover = NoteCover(source: "https://images.unsplash.com/cover.jpg", credit: NoteMediaCredit(name: "Jane", link: "https://unsplash.com/@jane"))
        let document = NotePageHTML.document(page, title: "Trip", assets: { _ in nil }, embedImages: false)
        #expect(document.contains("<div class=\"page-cover-frame\"><img class=\"page-cover\"") && document.contains("<p class=\"cover-credit\"><span class=\"credit\">Photo by <a"), "exported covers carry their credit")
    }

    @Test
    func anUncreditedExportedCoverHasNoCreditFrame() {
        var page = NotePage(blocks: [])
        page.settings.cover = NoteCover(source: "https://images.unsplash.com/cover.jpg", credit: nil)
        let plain = NotePageHTML.document(page, title: "Trip", assets: { _ in nil }, embedImages: false)
        #expect(!plain.contains("<div class=\"page-cover-frame\">") && plain.contains("<img class=\"page-cover\""), "covers without a credit export as before")
    }
}
