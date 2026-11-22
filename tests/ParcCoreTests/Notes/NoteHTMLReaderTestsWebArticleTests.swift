import Foundation
import Testing
@testable import ParcCore

struct NoteHTMLReaderTestsWebArticleTests {
    private typealias Fixture = NoteHTMLReaderTestsSupport

    private func importedBlocks() -> [NoteBlock] {
        let html = """
        <html><head><title>Ignore me</title><script>var x = "<p>not content</p>"; if (a < b) {}</script>
        <style>.byline{color:#999} .lede { font-weight: bold } nav a { color: red }</style></head><body>
        <nav class="site-nav"><ul><li><a href="/">Home</a></li><li><a href="/news">News</a></li></ul></nav>
        <div role="navigation" class="breadcrumbs"><a href="/">Home</a> › <a href="/tech">Tech</a></div>
        <article>
          <header><h1>The   quiet
          web</h1><p class="byline">By <a href="/authors/ada">Ada</a> &middot; <time datetime="2026-11-02">Nov 2</time></p></header>
          <p class="lede">Websites are getting
             lighter again.</p>
          <p>It started with a <em>simple</em> idea &mdash; ship less JavaScript. &ldquo;Less is more,&rdquo; said one engineer&nbsp;&nbsp;proudly.
          <p>Unclosed paragraphs are fine<br>and so are <b>unclosed <i>tags</b> here</i>.
          <figure><img src="/img/hero.jpg" alt="A calm website" width="800" height="400"><figcaption>Calm, isn't it?</figcaption></figure>
          <img src="https://tracker.example.com/pixel.gif" width="1" height="1">
          <aside class="pullquote">💬 Speed is a feature.</aside>
          <div style="display:none">Hidden promo</div>
          <span class="sr-only">Skip to footer</span>
          <h2>What changed<span hidden> (secret)</span></h2>
          <ul><li>Fewer trackers<li>Smaller images</ul>
          <p>Read more at <a href="javascript:void(0)">nowhere</a> or <a href="//cdn.example.com/more">the CDN</a> &amp; <a href="#top">top</a>.</p>
          <div class="ad-slot"><iframe src="https://ads.example.com/frame" width="300" height="250"></iframe></div>
          <iframe src="https://www.youtube.com/embed/dQw4w9WgXcQ" width="560" height="315" allowfullscreen></iframe>
          <!-- a comment <p>inside</p> -->
          <![CDATA[ raw & cdata ]]>
          <p>Tom &amp; Jerry &lt;3 &copy2026 &unknown; &#x1F600;</p>
        </article>
        <footer>&copy; 2026 Example &amp; Co</footer>
        </body></html>
        """
        return Fixture.read(html, base: "https://news.example.com/2026/quiet-web")
    }

    private func blocks() throws -> [NoteBlock] {
        let blocks = importedBlocks()
        try #require(blocks.count == 14)
        return blocks
    }

    @Test
    func theImportKeepsTheExpectedBlockOrder() {
        let blocks = importedBlocks()
        Fixture.shape(blocks, ["heading", "paragraph", "paragraph", "paragraph", "paragraph", "image", "callout", "heading", "bulletedItem",
                       "bulletedItem", "paragraph", "embed", "paragraph", "paragraph"], "Web article")
    }

    @Test
    func whitespaceCollapsesInWebHeadings() throws {
        let blocks = try blocks()
        #expect(blocks[0].text.string == "The quiet web", "whitespace collapses in headings")
    }

    @Test
    func aBylineKeepsItsTextWithoutGrayInk() throws {
        let blocks = try blocks()
        #expect(blocks[1].text.string == "By Ada · Nov 2" && Fixture.marks("By", blocks[1].text)?.color == nil, "byline keeps text, drops grey")
    }

    @Test
    func aRelativeAuthorLinkResolvesAgainstTheArticle() throws {
        let blocks = try blocks()
        #expect(Fixture.marks("Ada", blocks[1].text)?.link == "https://news.example.com/authors/ada", "relative author link resolves")
    }

    @Test
    func aStylesheetCanBoldTheOpeningParagraph() throws {
        let blocks = try blocks()
        #expect(blocks[2].text.string == "Websites are getting lighter again." && Fixture.marks("Websites", blocks[2].text)?.bold == true, "class rules can bold a lede")
    }

    @Test
    func entitiesAndNonbreakingSpacesKeepTheirText() throws {
        let blocks = try blocks()
        #expect(blocks[3].text.string == "It started with a simple idea — ship less JavaScript. “Less is more,” said one engineer  proudly.", "entities and non-breaking spaces: \(blocks[3].text.string.debugDescription)")
    }

    @Test
    func unclosedTagsKeepTheParagraphText() throws {
        let blocks = try blocks()
        #expect(blocks[4].text.string == "Unclosed paragraphs are fine\nand so are unclosed tags here.", "unclosed tags: \(blocks[4].text.string.debugDescription)")
    }

    @Test
    func misnestedTagsKeepTheirMarks() throws {
        let blocks = try blocks()
        #expect(Fixture.marks("unclosed", blocks[4].text)?.bold == true && Fixture.marks("tags", blocks[4].text)?.italic == true, "misnested marks")
    }

    @Test
    func aFigureKeepsItsResolvedImageAndCaption() throws {
        let blocks = try blocks()
        #expect(blocks[5].props.source == "https://news.example.com/img/hero.jpg" && blocks[5].props.caption.string == "Calm, isn't it?", "figure image and caption")
    }

    @Test
    func anAsideBecomesACalloutWithAnEmoji() throws {
        let blocks = try blocks()
        #expect(blocks[6].text.string == "Speed is a feature." && blocks[6].props.icon == "💬", "aside becomes a callout with its emoji")
    }

    @Test
    func hiddenSpansStayOutOfHeadings() throws {
        let blocks = try blocks()
        #expect(blocks[7].text.string == "What changed", "hidden spans are skipped")
    }

    @Test
    func impliedListItemEndsKeepBothItems() throws {
        let blocks = try blocks()
        #expect(blocks[8].text.string == "Fewer trackers" && blocks[9].text.string == "Smaller images", "implied li ends")
    }

    @Test
    func javascriptLinksAreDropped() throws {
        let blocks = try blocks()
        let links = blocks[10].text
        #expect(Fixture.marks("nowhere", links)?.link == nil, "javascript: links are dropped")
    }

    @Test
    func protocolRelativeLinksInheritHTTPS() throws {
        let blocks = try blocks()
        let links = blocks[10].text
        #expect(Fixture.marks("the CDN", links)?.link == "https://cdn.example.com/more", "protocol-relative links")
    }

    @Test
    func fragmentLinksResolveAgainstTheFullPageURL() throws {
        let blocks = try blocks()
        let links = blocks[10].text
        #expect(Fixture.marks("top", links)?.link == "https://news.example.com/2026/quiet-web#top", "fragment links resolve against the page")
    }

    @Test
    func knownFramesBecomeEmbeds() throws {
        let blocks = try blocks()
        #expect(blocks[11].props.source == "https://www.youtube.com/embed/dQw4w9WgXcQ", "known embeds survive, ad frames do not")
    }

    @Test
    func namedNumericAndUnknownEntitiesImportAsExpected() throws {
        let blocks = try blocks()
        #expect(blocks[12].text.string == "Tom & Jerry <3 ©2026 &unknown; 😀", "entity decoding: \(blocks[12].text.string.debugDescription)")
    }

    @Test
    func theFooterKeepsItsText() throws {
        let blocks = try blocks()
        #expect(blocks[13].text.string == "© 2026 Example & Co", "footer text")
    }

    @Test
    func pageChromeScriptsAndHiddenContentStayOut() throws {
        let blocks = try blocks()
        let flat = blocks.map(\.text.plainText).joined(separator: " ")
        #expect(!flat.contains("not content") && !flat.contains("Hidden promo") && !flat.contains("Skip to footer")
               && !flat.contains("News") && !flat.contains("cdata") && !flat.contains("secret"), "chrome, scripts and hidden bits stay out")
    }
}
