import AppKit

@main @MainActor
struct NoteTextRenderingTests {
    static func main() {
        exitOnFailure {
            loadFonts()
            roundTrips()
            typing()
            measurement()
            presentation()
            alignment()
            equationArtwork()
            numbering()
            dates()
            print("NoteTextRenderingTests passed")
        }
    }

    static func loadFonts() {
        let repo = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath
        for folder in ["Resources/NoteFonts", "Resources/EaselFonts"] {
            let url = URL(fileURLWithPath: repo).appendingPathComponent(folder)
            for file in (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            where ["ttf", "otf"].contains(file.pathExtension) {
                CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
            }
        }
        NoteMathRenderer.useFont(at: URL(fileURLWithPath: repo + "/Resources/NoteFonts/STIXTwoMath-Regular.otf"))
    }

    static func roundTrip(_ text: NoteText, _ message: String, in presentation: NoteTextPresentation = NoteTextPresentation()) {
        let attributed = NoteTextRendering.attributedString(text, presentation)
        expectEqual(attributed.length, text.length, message + " keeps its length")
        expectEqual(NoteTextRendering.noteText(from: attributed), text, message + " survives the round trip")
    }

    static func roundTrips() {
        roundTrip(NoteText(), "empty text")
        roundTrip("Plain words", "plain text")
        roundTrip("Two\nlines", "a soft line break")
        roundTrip("Emoji 👩🏽‍💻 and ünïcode", "emoji and accents")
        let link = marks { $0.link = "https://parc.app" }
        let red = marks { $0.color = .text(.red) }
        let highlight = marks { $0.color = .background(.yellow) }
        let everything = marks { $0.bold = true; $0.italic = true; $0.underline = true; $0.strikethrough = true }
        let code = marks { $0.code = true }
        roundTrip(NoteText(pieces: [("Bold ", boldMarks), ("italic ", italicMarks), ("all ", everything), ("code", code),
                                    (" link", link), (" red", red), (" glow", highlight)]), "every mark")
        roundTrip(NoteText(pieces: [("same ", boldMarks), ("same", boldMarks)]), "merged runs")
        let date = NoteDateMention(year: 2026, month: 11, day: 20, hour: 9, minute: 30, remind: true)
        let atoms = NoteText.atom(.equation("x^2")) + NoteText.atom(.equation("x^2")) + NoteText(" ")
            + NoteText.atom(.page(target: "Other.md", title: "Other")) + NoteText.atom(.date(date))
            + NoteText.atom(.link(url: "https://parc.app", title: "Parc")) + NoteText.atom(.raw("<kbd>K</kbd>"))
            + NoteText.atom(.equation("y"), marks: boldMarks)
        roundTrip(atoms, "every atom, including identical neighbours")
        roundTrip(NoteText("Stray \u{FFFC} object"), "a raw object character without an atom")
        roundTrip(NoteText(pieces: [("linked ", link), ("bold link", marks { $0.link = "https://parc.app"; $0.bold = true })]),
                  "a link across marks")
        let checked = NoteTextPresentation(completed: true)
        roundTrip(NoteText(pieces: [("done ", boldMarks), ("red", red)]), "a checked to-do", in: checked)
        roundTrip("Heading", "a heading", in: NoteTextPresentation(role: .heading(1)))
        let attributed = NoteTextRendering.attributedString(NoteText.atom(.page(target: "a.md", title: "A")), NoteTextPresentation())
        expect(attributed.attribute(.attachment, at: 0, effectiveRange: nil) is NoteAtomAttachment, "atoms render as attachments")
        let styled = NoteTextRendering.attributedString(NoteText(pieces: [("x", code), ("y", highlight)]), NoteTextPresentation())
        expect(styled.attribute(.noteInlineCode, at: 0, effectiveRange: nil) as? Bool == true, "inline code gets its pill")
        expect(styled.attribute(.noteHighlight, at: 1, effectiveRange: nil) is NSColor, "highlights get their rounded fill")
        expect(styled.attribute(.backgroundColor, at: 1, effectiveRange: nil) == nil, "highlights never use flat backgrounds")
    }

    static func makeTextView(_ presentation: NoteTextPresentation, width: CGFloat) -> NSTextView {
        let view = NSTextView(usingTextLayoutManager: false)
        view.textContainer?.replaceLayoutManager(NoteLayoutManager())
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isVerticallyResizable = false
        view.frame = NSRect(x: 0, y: 0, width: width, height: 400)
        view.isRichText = true
        view.typingAttributes = NoteTextRendering.typingAttributes(.plain, presentation)
        return view
    }

    static func typing() {
        let presentation = NoteTextPresentation()
        let view = makeTextView(presentation, width: 300)
        view.textStorage?.setAttributedString(NoteTextRendering.attributedString(NoteText(pieces: [("Hi ", .plain)]), presentation))
        view.setSelectedRange(NSRange(location: 3, length: 0))
        view.typingAttributes = NoteTextRendering.typingAttributes(boldMarks, presentation)
        view.insertText("there", replacementRange: view.selectedRange())
        view.typingAttributes = NoteTextRendering.typingAttributes(.plain, presentation)
        view.insertText("\n!", replacementRange: view.selectedRange())
        let result = NoteTextRendering.noteText(from: view.textStorage!)
        expectEqual(result, NoteText(pieces: [("Hi ", .plain), ("there", boldMarks), ("\n!", .plain)]), "typed text keeps its marks")
        let pending = NoteTextRendering.typingAttributes(NoteMarks(atom: .equation("x")), presentation)
        expect((pending[.noteMarks] as? NoteMarksValue)?.marks.atom == nil, "typing never inherits an atom")
    }

    static func measurement() {
        let samples: [NoteText] = [
            "", "Short", "A line that is long enough to wrap around the narrow column at least once, maybe twice even.",
            "Ends with a break\n", "Two\nlines\n\nwith a gap", "😀 emoji line that also wraps around because it keeps going on",
            NoteText(pieces: [("Inline ", .plain), ("code", marks { $0.code = true }), (" and ", .plain)])
                + NoteText.atom(.page(target: "x.md", title: "A page mention")) + NoteText(" and ")
                + NoteText.atom(.date(NoteDateMention(year: 2026, month: 1, day: 2))),
            NoteText("Equation ") + NoteText.atom(.equation("\\frac{a}{b}")) + NoteText(" inline"),
        ]
        let presentations = [NoteTextPresentation(), NoteTextPresentation(role: .heading(1)), NoteTextPresentation(role: .heading(3)),
                             NoteTextPresentation(small: true), NoteTextPresentation(role: .quote)]
        for presentation in presentations {
            let lineHeight = NoteTextRendering.lineHeight(presentation)
            expect(lineHeight >= 20, "line height is generous")
            for width in [120.0, 260.0, 600.0] as [CGFloat] {
                for sample in samples {
                    let view = makeTextView(presentation, width: width)
                    view.typingAttributes = NoteTextRendering.typingAttributes(.plain, presentation)
                    view.textStorage?.setAttributedString(NoteTextRendering.attributedString(sample, presentation))
                    view.layoutManager!.ensureLayout(for: view.textContainer!)
                    let live = max(lineHeight, ceil(view.layoutManager!.usedRect(for: view.textContainer!).height))
                    let measured = NoteTextRendering.height(of: sample, presentation, width: width)
                    expectEqual(measured, live, "measuring \(sample.string.debugDescription) at \(width) matches the live view")
                    if !sample.string.contains("\n"), !NoteTextRendering.needsFlexibleLines(sample) {
                        expectEqual(measured.truncatingRemainder(dividingBy: lineHeight), 0,
                                    "lines stay on the \(lineHeight) grid for \(sample.string.debugDescription)")
                    }
                }
            }
        }
        expectEqual(NoteTextRendering.height(of: NoteText(), NoteTextPresentation(), width: 300),
                    NoteTextRendering.lineHeight(NoteTextPresentation()), "an empty block is one line tall")
    }

    static func presentation() {
        let heading = NoteTextPresentation(block: NoteBlock.heading(2, "Hi"), settings: NotePageSettings())
        expectEqual(heading.role, .heading(2), "headings use their level")
        let done = NoteTextPresentation(block: todo("x", checked: true), settings: NotePageSettings())
        expect(done.completed, "checked to-dos are completed")
        let attributes = NoteTextRendering.attributes(for: .plain, done)
        expect(attributes[.strikethroughStyle] != nil, "completed text is struck through")
        expect((attributes[.foregroundColor] as? NSColor) == NoteTheme.todoDoneInk, "completed text fades")
        var settings = NotePageSettings()
        settings.smallText = true
        settings.font = .serif
        let small = NoteTextPresentation(block: para("x"), settings: settings)
        expect(small.small && small.pageFont == .serif, "page settings reach the presentation")
        let boldFont = NoteTextRendering.font(for: boldMarks, NoteTextPresentation())
        let regularFont = NoteTextRendering.font(for: .plain, NoteTextPresentation())
        expectEqual(boldFont.pointSize, regularFont.pointSize, "bold keeps the body size")
        let codeFont = NoteTextRendering.font(for: marks { $0.code = true }, NoteTextPresentation())
        expect(codeFont.pointSize < regularFont.pointSize, "inline code is a touch smaller")
    }

    static func alignment() {
        let natural = NoteTextPresentation()
        expectEqual(natural.alignment, .natural, "text starts naturally aligned")
        let centered = NoteTextPresentation(role: .tableCell, alignment: .center)
        let right = NoteTextPresentation(role: .tableHeader, small: true, alignment: .right)
        let equation = NoteText("Total ") + NoteText.atom(.equation("x^2")) + NoteText(" done", marks: boldMarks)
        for (presentation, name) in [(centered, "centred"), (right, "right-aligned")] {
            roundTrip("Two\nlines", name + " text", in: presentation)
            roundTrip(equation, name + " text with an equation", in: presentation)
            let attributed = NoteTextRendering.attributedString(equation, presentation)
            var alignments = Set<Int>()
            attributed.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
                alignments.insert((value as? NSParagraphStyle)?.alignment.rawValue ?? -1)
            }
            expectEqual(alignments, [presentation.alignment.rawValue], name + " runs all share the alignment")
            let typing = NoteTextRendering.typingAttributes(boldMarks, presentation)
            expectEqual((typing[.paragraphStyle] as? NSParagraphStyle)?.alignment, presentation.alignment, name + " typing keeps the alignment")
            let placeholder = NoteTextRendering.placeholder("Type here", presentation)
            expectEqual((placeholder.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment,
                        presentation.alignment, name + " placeholders line up with the text")
        }
        var plain = centered
        plain.alignment = .natural
        expectEqual(NoteTextRendering.lineHeight(centered), NoteTextRendering.lineHeight(plain), "alignment never changes the line height")
        expectEqual(NoteTextRendering.font(for: .plain, centered), NoteTextRendering.font(for: .plain, plain), "alignment never changes the font")
        expect(centered != plain, "alignment is part of the presentation, so views refresh when it changes")
        let attributed = NoteTextRendering.attributedString("Middle", centered)
        let width: CGFloat = 300
        let storage = NSTextStorage(attributedString: attributed)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: width, height: 1000))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container)
        let glyphs = manager.boundingRect(forGlyphRange: manager.glyphRange(for: container), in: container)
        expect(abs(glyphs.midX - width / 2) < 2, "centred text lays out in the middle (centre \(glyphs.midX), used \(used))")
    }

    static func equationArtwork() {
        guard let inline = NotePageEquationArtwork.svg("x^2 + y^2 = z^2", display: false),
              let display = NotePageEquationArtwork.svg("\\frac{a}{b} = c", display: true) else {
            failTest("equations render to SVG artwork")
        }
        expect(inline.markup.hasPrefix("<svg ") && inline.markup.contains("prefers-color-scheme:dark"), "artwork carries light and dark ink")
        expect(inline.markup.components(separatedBy: "data:image/png;base64,").count == 3, "artwork embeds a light and a dark rendering")
        expect(inline.size.width > 20 && inline.size.height > 10, "inline artwork has a real size (\(inline.size))")
        let fontSize = NotePageEquationArtwork.fontSize(display: false)
        let rendering = NoteMathRenderer.render("x^2 + y^2 = z^2", fontSize: fontSize, color: .black, display: false)
        expect(inline.size.height >= ceil(rendering.size.height), "inline artwork pads around the maths, never crops it")
        expect(display.size.height > inline.size.height, "display maths is bigger than inline maths")
        expect(NotePageEquationArtwork.fontSize(display: true) > fontSize, "display maths uses the larger size")
        expect(NotePageEquationArtwork.svg("   ", display: false) == nil, "blank equations fall back to their source")
        expect(NotePageEquationArtwork.svg("\\frac{", display: false) == nil, "broken equations fall back to their source")
        guard let url = NotePageEquationArtwork.url("e^{i\\pi} + 1 = 0", display: true) else { failTest("artwork becomes a data URL") }
        expect(url.absoluteString.hasPrefix("data:image/svg+xml;charset=utf-8,%3Csvg"), "the data URL is a percent-encoded SVG")
        expect(url.absoluteString.removingPercentEncoding?.contains("width=") == true, "the SVG keeps its intrinsic size")
        let html = NotePageHTML.document(NotePage(blocks: [NoteBlock(.equation, text: "a^2"),
                                                           .paragraph(NoteText("Area ") + NoteText.atom(.equation("\\pi r^2")))]),
                                         title: "Maths", assets: { _ in nil }, embedImages: true,
                                         equationImage: { tex, display in NotePageEquationArtwork.url(tex, display: display) })
        expect(html.components(separatedBy: "data:image/svg+xml").count == 3, "exported HTML typesets block and inline equations")
        expect(!html.contains("<span class=\"tex\">"), "no raw TeX is left behind when artwork renders")
        expect(html.contains("img.equation{vertical-align:middle;max-width:100%}"), "inline artwork keeps its own size in the stylesheet")
    }

    static func numbering() {
        let page = NotePage(blocks: [
            numbered("one"), numbered("two", [numbered("a"), numbered("b", [numbered("i"), numbered("ii")])]), numbered("three"),
            para("break"), numbered("again", start: 5), numbered("six"),
            bullet("dot", [bullet("ring", [bullet("square", [bullet("dot again")])])]),
        ])
        func label(_ path: [Int]) -> String? {
            var list = page.blocks
            var found: NoteBlock?
            for index in path { found = list[index]; list = list[index].children }
            return found.flatMap { NoteListMarker.label(for: $0, in: page) }
        }
        expectEqual(label([0]), "1.", "first item")
        expectEqual(label([1]), "2.", "second item")
        expectEqual(label([1, 0]), "a.", "nested items use letters")
        expectEqual(label([1, 1]), "b.", "letters count up")
        expectEqual(label([1, 1, 0]), "i.", "deeper items use roman numerals")
        expectEqual(label([1, 1, 1]), "ii.", "roman numerals count up")
        expectEqual(label([2]), "3.", "numbering continues after nested items")
        expectEqual(label([4]), "5.", "a paragraph restarts the list at its own start")
        expectEqual(label([5]), "6.", "and keeps counting")
        expectEqual(label([6]), "•", "top-level bullets are dots")
        expectEqual(label([6, 0]), "◦", "nested bullets are rings")
        expectEqual(label([6, 0, 0]), "▪", "deeper bullets are squares")
        expectEqual(label([6, 0, 0, 0]), "•", "bullets cycle")
        expectEqual(NoteListMarker.numberLabel(27, level: 1), "aa.", "letters roll over past z")
        expectEqual(NoteListMarker.numberLabel(4, level: 2), "iv.", "roman four")
        expectEqual(NoteListMarker.numberLabel(3, level: 0, delimiter: ")"), "3)", "parenthesis delimiters show")
    }

    static func dates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let locale = Locale(identifier: "en_US")
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12))!
        func label(_ mention: NoteDateMention) -> String {
            NoteAtomRendering.dateLabel(mention, now: now, calendar: calendar, locale: locale).replacingOccurrences(of: "\u{202F}", with: " ")
        }
        expectEqual(label(NoteDateMention(year: 2026, month: 11, day: 20)), "Today", "today reads as Today")
        expectEqual(label(NoteDateMention(year: 2026, month: 11, day: 21)), "Tomorrow", "tomorrow reads as Tomorrow")
        expectEqual(label(NoteDateMention(year: 2026, month: 11, day: 19)), "Yesterday", "yesterday reads as Yesterday")
        expectEqual(label(NoteDateMention(year: 2026, month: 12, day: 25)), "December 25", "this year drops the year")
        expectEqual(label(NoteDateMention(year: 2027, month: 1, day: 12)), "January 12, 2027", "other years keep it")
        expectEqual(label(NoteDateMention(year: 2026, month: 11, day: 21, hour: 15, minute: 5)), "Tomorrow 3:05 PM", "times show")
        expect(NoteAtomRendering.isOverdue(NoteDateMention(year: 2026, month: 11, day: 20, hour: 9, minute: 0), now: now, calendar: calendar),
               "a past time is overdue")
        expect(!NoteAtomRendering.isOverdue(NoteDateMention(year: 2026, month: 11, day: 21), now: now, calendar: calendar),
               "tomorrow isn't overdue")
        expect(NoteAtomRendering.isOverdue(NoteDateMention(year: 2026, month: 11, day: 20), now: now, calendar: calendar),
               "an all-day reminder is due on its day")
    }
}
