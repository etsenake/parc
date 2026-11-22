import Foundation
import Testing
@testable import ParcCore

enum NoteMathParserTestsSupport {
    static func parse(_ source: String) throws -> [NoteMathNode] {
        do {
            return try NoteMathParser.parse(source)
        } catch {
            throw NoteTestFailure("\(source) failed to parse: \(error.message) at \(error.offset)")
        }
    }

    static func failure(_ source: String) throws -> NoteMathParseError {
        do {
            let nodes = try NoteMathParser.parse(source)
            throw NoteTestFailure("\(source) should fail but parsed as \(nodes)")
        } catch let error as NoteMathParseError {
            return error
        }
    }

    static func contains(_ nodes: [NoteMathNode], _ predicate: (NoteMathNode) -> Bool) -> Bool {
        nodes.contains { node in
            if predicate(node) { return true }
            switch node {
            case .group(let content), .styled(_, let content), .classed(_, let content), .colored(_, let content),
                 .mathStyle(_, let content), .decorated(_, let content):
                return contains(content, predicate)
            case .scripts(let base, let upper, let lower):
                return contains(base.map { [$0] } ?? [], predicate) || contains(upper ?? [], predicate) || contains(lower ?? [], predicate)
            case .extensibleArrow(_, let over, let under):
                return contains(over, predicate) || contains(under ?? [], predicate)
            default:
                return false
            }
        }
    }

    static func arrow(_ nodes: [NoteMathNode]) -> (String, [NoteMathNode], [NoteMathNode]?)? {
        for node in nodes {
            if case .extensibleArrow(let symbol, let over, let under) = node { return (symbol, over, under) }
            if case .group(let content) = node, let found = arrow(content) { return found }
        }
        return nil
    }

    static func equation(_ source: String, display: Bool = true) throws -> NoteMathEquation {
        do {
            return try NoteMathParser.parseEquation(source, display: display)
        } catch {
            throw NoteTestFailure("\(source) failed to parse: \(error.message) at \(error.offset)")
        }
    }

    static func rowTags(_ source: String) throws -> [[NoteMathNode]?] {
        guard case .environment(let environment)? = try equation(source).nodes.first else {
            throw NoteTestFailure("\(source) parses as an environment")
        }
        return environment.tags
    }

    static func failure(_ source: String, display: Bool) throws -> NoteMathParseError {
        do {
            let parsed = try NoteMathParser.parseEquation(source, display: display)
            throw NoteTestFailure("\(source) should fail but parsed as \(parsed)")
        } catch let error as NoteMathParseError {
            return error
        }
    }

    struct NodeCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let source: String
        let expected: @Sendable () -> [NoteMathNode]

        init(_ label: String, _ source: String, _ expected: @escaping @Sendable () -> [NoteMathNode]) {
            testDescription = label
            self.source = source
            self.expected = expected
        }
    }

    struct ExpansionCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let source: String
        let expanded: String

        init(_ label: String, _ source: String, _ expanded: String) {
            testDescription = label
            self.source = source
            self.expanded = expanded
        }
    }

    struct ErrorCase: Sendable, CustomTestStringConvertible {
        enum Match: Sendable {
            case exact(String)
            case prefix(String)
            case suffix(String)
            case contains(String)
        }

        let testDescription: String
        let source: String
        let match: Match

        init(_ label: String, _ source: String, _ match: Match) {
            testDescription = label
            self.source = source
            self.match = match
        }
    }

    static func expectError(_ fixture: ErrorCase) throws {
        let message = try failure(fixture.source).message
        switch fixture.match {
        case .exact(let expected): #expect(message == expected)
        case .prefix(let expected): #expect(message.hasPrefix(expected))
        case .suffix(let expected): #expect(message.hasSuffix(expected))
        case .contains(let expected): #expect(message.contains(expected))
        }
    }
}
