import AppKit
import Testing
@testable import Parc

struct FieldAnchorTests {
    private static let address = "example.test/projects/archive?query=long-project-name&sort=updated&view=all"
    private static let typed = "example.test"
    private typealias Anchor = CommandBarFieldAnchor
    private typealias Title = CommandBarCompletionTitle

    private static func inline(query: String = typed, address: String = address) -> CommandBarEditState {
        var state = CommandBarEditState(query: "")
        let end = NSRange(location: query.utf16.count, length: 0)
        state.userEdit(query, selection: end, hasMarkedText: false, didBackspace: false)
        _ = state.projectInline(resultID: "row", text: address, selection: end, hasMarkedText: false)
        return state
    }

    @Test(arguments: [("example.test", "example.test/docs", 12, 5), ("git", "github.com", 3, 7),
                      ("🌌", "🌌🌌🌌🌌🌌🌌🌌🌌🌌🌌🌌🌌🌌🌌", 2, 24)])
    func anchoringKeepsTheBeginningOfTheCompletedSuffix(query: String, address: String, start: Int, length: Int) {
        let state = Self.inline(query: query, address: address)
        let shown = Anchor.visibleRange(text: address, displayed: state.displayedText, selection: state.selection,
                                       completion: Anchor.completion(state), hasMarkedText: false)
        #expect(shown == NSRange(location: start, length: length))
    }

    enum Reason: CaseIterable { case movedCaret, changedSelection, composition, staleText, manuallyScrolled }

    @Test(arguments: Reason.allCases)
    func anInterruptedCompletionLeavesScrollingWithTheNativeEditor(reason: Reason) {
        let state = Self.inline()
        let selection: NSRange
        switch reason {
        case .movedCaret: selection = NSRange(location: 5, length: 0)
        case .changedSelection: selection = NSRange(location: 5, length: 5)
        default: selection = state.selection
        }
        let text = reason == .staleText ? "example.test/other" : Self.address
        let shown = Anchor.visibleRange(text: text, displayed: state.displayedText, selection: selection,
                                       completion: Anchor.completion(state), hasMarkedText: reason == .composition,
                                       touched: reason == .manuallyScrolled)
        #expect(shown == nil)
    }

    @Test func anAcceptedCompletionHasNoAnchor() {
        var state = Self.inline()
        state.accept()
        #expect(Anchor.completion(state) == nil)
    }

    @Test func rightToLeftCompletionsUseNativeScrolling() {
        let state = Self.inline(query: "של", address: "שלום עולם")
        #expect(Anchor.visibleRange(text: state.displayedText, displayed: state.displayedText, selection: state.selection,
                                   completion: Anchor.completion(state), hasMarkedText: false) == nil)
    }

    @Test func aNonPrefixResultStartsAtTheBeginningOfItsAddress() {
        var state = CommandBarEditState(query: "docs")
        state.project(resultID: "row", text: Self.address)
        let shown = Anchor.visibleRange(text: Self.address, displayed: state.displayedText, selection: state.selection,
                                       completion: Anchor.completion(state), hasMarkedText: false)
        #expect(shown?.location == 0)
    }

    @Test(arguments: [("a", 300.4, 0, false), ("a", 305.5, 5, false), ("a", 320, 0, true),
                      ("a", 120, 0, false), ("", 400, 0, false), ("שלום עולם", 400, 0, false),
                      ("a", nil, 0, true)] as [(String, Double?, Double, Bool)])
    func onlyOverflowingLeftToRightTextFades(text: String, end: Double?, padding: Double, fades: Bool) {
        #expect(Anchor.fades(text: text, textEnd: end.map { CGFloat($0) }, visibleEnd: 300, padding: padding) == fades)
    }

    @Test(arguments: [(600.0, 18.0, 24.0), (400, 13, 17), (20, 18, 10)])
    func theFadeFitsTheFieldAndFont(width: Double, font: Double, expected: Double) {
        #expect(Anchor.fadeWidth(fieldWidth: width, fontSize: font) == CGFloat(expected))
    }

    @Test(arguments: [
        ("Quarterly Dashboard", false, "Quarterly Dashboard"),
        ("  Quarterly\nDashboard ", false, "Quarterly Dashboard"),
        ("", false, nil), ("example.test", false, nil), ("www.example.test", false, nil),
        ("example.test/docs", false, nil), ("Example", false, "Example"), ("Weather", true, nil),
    ] as [(String, Bool, String?)])
    func onlyRealPageTitlesFollowACompletion(title: String, isSearch: Bool, expected: String?) {
        #expect(Title.text(title: title, url: "https://example.test/docs", isSearch: isSearch,
                           completion: "example.test") == expected)
    }

    @Test(arguments: [(200.0, 180.0, 180.0), (450, 300, 146), (560, 300, nil),
                      (560, 30, 30), (640, 30, nil)] as [(Double, Double, Double?)])
    func theTitleTruncatesOnlyWhenThereIsRoomForWords(textEnd: Double, natural: Double, expected: Double?) {
        let frame = Title.frame(textEnd: textEnd, fieldEnd: 600, natural: natural, gap: 4, minimum: 72)
        #expect(frame?.width == expected.map { CGFloat($0) })
    }

    @MainActor private final class EditorFixture {
        let clip = NSClipView(frame: NSRect(x: 0, y: 0, width: 240, height: 22))
        let editor = CommandBarAnchoredEditor(frame: NSRect(x: 0, y: 0, width: 240, height: 22))
        let state: CommandBarEditState
        var touched = false
        var geometryChanges = 0

        init(query: String, anchors: Bool) {
            state = inline(query: query)
            editor.isFieldEditor = true
            editor.isHorizontallyResizable = true
            editor.isVerticallyResizable = false
            editor.textContainer?.widthTracksTextView = false
            editor.textContainer?.containerSize = NSSize(width: 10_000, height: 22)
            editor.maxSize = NSSize(width: 10_000, height: 22)
            editor.font = CommandBarTypography.field
            editor.onClipChange = { [weak self] _ in self?.geometryChanges += 1 }
            editor.onUserScroll = { [weak self] in self?.touched = true }
            if anchors {
                editor.anchorsScroll = { [weak self] in
                    guard let self, let range = Anchor.visibleRange(
                        text: self.editor.string, displayed: self.state.displayedText, selection: self.editor.selectedRange(),
                        completion: Anchor.completion(self.state), hasMarkedText: self.editor.hasMarkedText(), touched: self.touched)
                    else { return false }
                    self.editor.reveal(range)
                    return true
                }
            }
            clip.documentView = editor
        }

        func show() {
            touched = false
            editor.string = state.displayedText
            editor.setSelectedRange(state.selection)
            editor.scrollRangeToVisible(editor.selectedRange())
        }

        func boundary(_ length: Int) -> CGFloat {
            let prefix = editor.textStorage!.attributedSubstring(from: NSRange(location: 0, length: length))
            return editor.textContainerOrigin.x + editor.textContainer!.lineFragmentPadding + prefix.size().width
        }
    }

    @Test(arguments: [false, true])
    @MainActor func anchoringKeepsTheTypedBoundaryInView(anchors: Bool) {
        let fixture = EditorFixture(query: Self.typed, anchors: anchors)
        fixture.show()
        let boundary = fixture.boundary(Self.typed.count)
        #expect((fixture.clip.bounds.minX <= boundary && boundary < fixture.clip.bounds.maxX) == anchors)
    }

    @Test @MainActor func aUserCanStillScrollToTheEndOfTheAddress() {
        let query = String(Self.address.prefix(45))
        let fixture = EditorFixture(query: query, anchors: true)
        fixture.show()
        fixture.editor.doCommand(by: #selector(NSResponder.scrollToEndOfDocument(_:)))
        #expect(fixture.touched)
        #expect(fixture.editor.selectedRange() == fixture.state.selection)
        #expect(!Anchor.fades(text: fixture.editor.string, textEnd: fixture.editor.textEnd,
                             visibleEnd: fixture.editor.visibleEnd, padding: fixture.editor.trailingPadding))
    }

    @Test @MainActor func resizingKeepsTheFadeOnTheTrailingEdge() {
        let field = CommandBarInputField(frame: NSRect(x: 0, y: 0, width: 600, height: 31))
        field.wantsLayer = true
        field.setTrailingFade(true, width: 24)
        field.setFrameSize(NSSize(width: 300, height: 31))
        let gradient = field.layer?.mask as? CAGradientLayer
        #expect(gradient?.frame == field.bounds)
        #expect(gradient?.locations?.map(\.doubleValue) == [0, 276.0 / 300.0, 1])
    }

    @Test @MainActor func theTitleAnnouncesOnlyItsTextAndLetsClicksReachTheField() {
        let label = CommandBarCompletionTitleLabel.make()
        label.stringValue = Title.display("Quarterly Dashboard")
        label.spokenTitle = "Quarterly Dashboard"
        label.frame = NSRect(x: 0, y: 0, width: 200, height: 31)
        #expect(label.hitTest(NSPoint(x: 10, y: 10)) == nil)
        #expect(label.accessibilityValue() == "Quarterly Dashboard")
        #expect(label.accessibilityRole() == .staticText)
        #expect(!label.isEditable && !label.isSelectable)
    }
}
