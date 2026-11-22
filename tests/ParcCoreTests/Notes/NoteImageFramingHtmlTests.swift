import CoreGraphics
import Foundation
import Testing
@testable import ParcCore

struct NoteImageFramingHtmlTests {
    private func framedImages() -> (cropped: NoteBlock, starred: NoteBlock, rounded: NoteBlock, mystery: NoteBlock) {
        var cropped = NoteBlock(.image)
        cropped.props.source = "Attachments/cat.png"
        cropped.props.alt = "Cat"
        cropped.props.crop = NoteImageCrop(x: 0.25, y: 0.5, width: 0.5, height: 0.25)
        var starred = NoteBlock(.image)
        starred.props.source = "Attachments/star.png"
        starred.props.mask = .star
        starred.props.width = 0.4
        var rounded = NoteBlock(.image)
        rounded.props.source = "Attachments/round.png"
        rounded.props.mask = .rounded
        rounded.props.crop = NoteImageCrop(x: 0, y: 0, width: 1, height: 0.5)
        var mystery = NoteBlock(.image)
        mystery.props.source = "https://example.com/unknown.png"
        mystery.props.crop = NoteImageCrop(x: 0.1, y: 0.2, width: 0.5, height: 0.6)
        return (cropped, starred, rounded, mystery)
    }

    private func document() -> String {
        let images = framedImages()
        let sizes: [String: CGSize] = ["Attachments/cat.png": CGSize(width: 800, height: 400), "Attachments/star.png": CGSize(width: 300, height: 300),
                                       "Attachments/round.png": CGSize(width: 600, height: 600)]
        let page = NotePage(blocks: [images.cropped, images.starred, images.rounded, images.mystery])
        return NotePageHTML.document(page, title: "Framed", assets: { _ in nil }, embedImages: false, imageSize: { sizes[$0] })
    }

    @Test func theCropSetsTheFrameAndPositionsTheImage() {
        let html = document()
        #expect(html.contains("<span class=\"image-frame cropped\" style=\"aspect-ratio:400/100;width:400px\">"), "crops size their frame:\n\(html)")
        #expect(html.contains("data-crop=\"0.25,0.5,0.5,0.25\" style=\"width:200%;left:-50%;top:-200%\">"), "the picture shifts behind the frame")
    }

    @Test func masksWrapImagesAndOnlyUsedMasksGetStyles() {
        let html = document()
        #expect(html.contains("<span class=\"image-frame mask-star\"><img src=\"Attachments/star.png\" alt=\"\" data-mask=\"star\"></span>"), "shapes wrap the picture")
        #expect(html.contains(".image-frame.mask-star{-webkit-mask:url(\"data:image/svg+xml,"), "used shapes get a mask rule")
        #expect(!html.contains(".image-frame.mask-heart{"), "unused shapes stay out of the stylesheet")
    }

    @Test func roundedCropsExportTheirExactCornerRadii() {
        let html = document()
        #expect(html.contains("class=\"image-frame mask-rounded cropped\" style=\"border-radius:5%/10%;aspect-ratio:600/300;width:600px\""), "rounded frames get exact corners")
    }

    @Test func cropsWithUnknownDimensionsUseAnObjectViewBox() {
        let html = document()
        #expect(html.contains("style=\"object-view-box:inset(20% 40% 20% 10%)\""), "unknown sizes still crop where browsers can")
    }

    @Test func clipboardHtmlCarriesFramingAsData() {
        let (cropped, starred, _, _) = framedImages()
        let fragment = NotePageHTML.fragment([cropped, starred])
        #expect(!fragment.contains("image-frame") && fragment.contains("data-crop=\"0.25,0.5,0.5,0.25\"") && fragment.contains("data-mask=\"star\""), "clipboard HTML keeps framing as data")
    }

    @Test func clipboardHtmlRestoresCropAndMask() {
        let (cropped, starred, _, _) = framedImages()
        let fragment = NotePageHTML.fragment([cropped, starred])
        let back = NoteHTMLReader.blocks(from: fragment, baseURL: nil)
        #expect(back.count == 2 && back[0].props.crop == cropped.props.crop && back[1].props.mask == .star, "clipboard HTML reads framing back")
    }

    @Test func exportedHtmlRestoresImageFraming() {
        let (cropped, _, _, _) = framedImages()
        let html = document()
        let reread = NoteHTMLReader.blocks(from: html, baseURL: nil).filter { $0.kind == .image }
        #expect(reread.count == 4 && reread[0].props.crop == cropped.props.crop && reread[1].props.mask == .star && reread[2].props.mask == .rounded, "exported documents read framing back: \(reread.map { ($0.props.crop?.attribute ?? "-") + "/" + ($0.props.mask?.rawValue ?? "-") })")
    }

    @Test func unframedImagesStayPlainInHtml() {
        let plain = NotePageHTML.document(NotePage(blocks: [NoteBlock(.image)]), title: "", assets: { _ in nil }, embedImages: false)
        #expect(!plain.contains("image-frame mask") && !plain.contains("<span class=\"image-frame"), "plain images stay plain")
    }
}
