import Foundation
import Testing
@testable import ParcCore

struct NoteMathParserTestsDelimitersTests {
    typealias NodeCase = NoteMathParserTestsSupport.NodeCase
    private typealias Parser = NoteMathParserTestsSupport

    @Test(arguments: [
        NodeCase("bra", "\\bra{x}") { [.classed(.inner, [.char("⟨", .open), .char("x", .ord), .char("|", .close)])] },
        NodeCase("ket", "\\ket{x}") { [.classed(.inner, [.char("|", .open), .char("x", .ord), .char("⟩", .close)])] },
        NodeCase("braket", "\\braket{x}") { [.classed(.inner, [.char("⟨", .open), .char("x", .ord), .char("⟩", .close)])] },
        NodeCase("Bra", "\\Bra{x}") { [.fenced(left: "⟨", right: "|", middles: [], segments: [[.char("x", .ord)]])] },
        NodeCase("Ket", "\\Ket{x}") { [.fenced(left: "|", right: "⟩", middles: [], segments: [[.char("x", .ord)]])] },
        NodeCase("Braket splits at bars", "\\Braket{x|y}") { [.fenced(left: "⟨", right: "⟩", middles: ["|"], segments: [[.char("x", .ord), .space(3.0 / 18)], [.space(3.0 / 18), .char("y", .ord)]])] },
        NodeCase("set uses mid", "\\set{x|y}") { [.group([.char("{", .open), .space(3.0 / 18), .char("x", .ord), .char("∣", .rel), .char("y", .ord), .space(3.0 / 18), .char("}", .close)])] },
    ])
    func braketAndSetCommandsKeepTheirDelimiters(fixture: NodeCase) throws {
        #expect(try Parser.parse(fixture.source) == fixture.expected())
    }

    @Test
    func aCapitalSetSplitsOnlyAtTheFirstBar() throws {
        guard case .fenced("{", "}", let middles, let segments) = try Parser.parse("\\Set{x|y|z}")[0] else { Issue.record("Set is fenced"); return }
        #expect(middles == ["|"] && segments.count == 2, "Set splits only the first bar")
    }

    @Test(arguments: ["bra", "ket", "braket", "Bra", "Ket", "Braket", "set", "Set"])
    func braketAndSetCommandsAreBuiltIn(name: String) {
        #expect(NoteMathParser.isBuiltIn(name), "\\\(name) is built in")
    }

    @Test(arguments: [
        NodeCase("left right", "\\left( x \\right)") { [.fenced(left: "(", right: ")", middles: [], segments: [[.char("x", .ord)]])] },
        NodeCase("middle and null", "\\left\\{ x \\middle| y \\right.") { [.fenced(left: "{", right: nil, middles: ["|"],
            segments: [[.char("x", .ord)], [.char("y", .ord)]])] },
        NodeCase("angle brackets", "\\left\\langle a \\right\\rangle") { [.fenced(left: "⟨", right: "⟩", middles: [], segments: [[.char("a", .ord)]])] },
        NodeCase("big delimiters", "\\bigl( x \\bigr)") { [.sizedDelimiter("(", size: 1, kind: .open), .char("x", .ord),
            .sizedDelimiter(")", size: 1, kind: .close)] },
        NodeCase("Bigg arrow", "\\Bigg\\uparrow") { [.sizedDelimiter("↑", size: 4, kind: .ord)] },
    ])
    func pairedAndSizedDelimitersKeepTheirContentsAndSize(fixture: NodeCase) throws {
        #expect(try Parser.parse(fixture.source) == fixture.expected())
    }

    @Test
    func floorAndCeilingDelimitersCanBeMixed() throws {
        #expect(try Parser.parse("\\left\\lfloor a \\right\\rceil").first == .fenced(left: "⌊", right: "⌉", middles: [], segments: [[.char("a", .ord)]]), "floor and ceiling")
    }

    @Test
    func barsCanBeSingleOrDouble() throws {
        #expect(try Parser.parse("\\left| a \\right\\|").first == .fenced(left: "|", right: "‖", middles: [], segments: [[.char("a", .ord)]]), "bars")
    }

    @Test
    func fencesTakeScripts() throws {
        #expect(try Parser.parse("\\left[ a \\right]^2").first.map { node in
            if case .scripts(.fenced?, _, nil) = node { return true }
            return false
        } == true, "fence takes scripts")
    }

    @Test
    func delimiterAliasesWorkWithLeftAndRight() throws {
        #expect(try Parser.parse("\\left\\lparen x \\right\\rang").count == 1, "new delimiter names work with left and right")
    }
}
