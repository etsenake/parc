import Foundation
import Testing
@testable import ParcCore

struct NoteSyntaxMarkupTestsDataTests {
    typealias TokenCase = NoteSyntaxMarkupTestsSupport.TokenCase
    private typealias SyntaxProbe = NoteSyntaxMarkupTestsSupport.SyntaxProbe

    private static let jsonSource = """
        {
          // jsonc comment
          "name": "Parc \\"Notes\\"",
          "version": -1.5e3,
          "tags": ["a", "b:c"],
          "ok": true, "none": null
        }
        """

    private static let jsonTokens = [
        TokenCase("// jsonc comment", .comment),
        TokenCase("\"name\"", .property),
        TokenCase("\"Parc ", .string),
        TokenCase("\\\"", .escape),
        TokenCase("\"version\"", .property),
        TokenCase("-1.5e3", .number),
        TokenCase("\"a\"", .string),
        TokenCase("\"b:c\"", .string),
        TokenCase("true", .constant),
        TokenCase("null", .constant),
        TokenCase(":", .punctuation),
    ]

    @Test(arguments: jsonTokens)
    func jsonFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("json", Self.jsonSource).expect(token)
    }

    @Test
    func jsonTokenRangesAreWellFormed() {
        SyntaxProbe("json", Self.jsonSource).expectWellFormed()
    }

    private static let yamlSource = """
        %YAML 1.2
        ---
        # config
        name: Parc Notes   # trailing comment
        version: 2.11
        enabled: yes
        nothing: ~
        url: "https://parc.dev/#not-comment"
        quote: 'it''s fine'
        anchors: &base
          retries: 3
        derived: *base
        typed: !!str 123
        list:
          - one
          - key: value
          - [flow, {inner: 1}]
        script: |
          echo "not: a key"
          # not a comment either
        after: done
        "quoted key": 1
        """

    private static let yamlTokens = [
        TokenCase("%YAML 1.2", .meta),
        TokenCase("---", .meta),
        TokenCase("# config", .comment),
        TokenCase("name", .property),
        TokenCase("Parc Notes", .string),
        TokenCase("# trailing comment", .comment),
        TokenCase("2.11", .number),
        TokenCase("yes", .constant),
        TokenCase("~", .constant),
        TokenCase("\"https://parc.dev/#not-comment\"", .string),
        TokenCase("'it''s fine'", .string),
        TokenCase("&base", .variable),
        TokenCase("retries", .property),
        TokenCase("3", .number),
        TokenCase("*base", .variable),
        TokenCase("!!str", .type),
        TokenCase("one", .string),
        TokenCase("key", .property),
        TokenCase("flow", .string),
        TokenCase("inner", .property),
        TokenCase("|", .punctuation),
        TokenCase("echo \"not: a key\"", .string),
        TokenCase("# not a comment either", .string),
        TokenCase("after", .property),
        TokenCase("\"quoted key\"", .property),
    ]

    @Test(arguments: yamlTokens)
    func yamlFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("yaml", Self.yamlSource).expect(token)
    }

    @Test
    func yamlTokenRangesAreWellFormed() {
        SyntaxProbe("yaml", Self.yamlSource).expectWellFormed()
    }

    private static let yamlListSource = "- a"

    private static let yamlListTokens = [
        TokenCase("-", .punctuation),
    ]

    @Test(arguments: yamlListTokens)
    func yamlListFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("yml", Self.yamlListSource).expect(token)
    }

    private static let tomlSource = """
        # settings
        title = "Parc"
        [server.http]
        port = 8_080
        hosts = ["a", 'b']
        enabled = true
        started = 1979-05-27T07:32:00Z
        point = { x = 1, y = -2.5 }
        "quoted.key" = '''
        multi "line"
        '''
        [[plugins]]
        name = "emoji" # trailing
        """

    private static let tomlTokens = [
        TokenCase("# settings", .comment),
        TokenCase("title", .property),
        TokenCase("\"Parc\"", .string),
        TokenCase("server.http", .type),
        TokenCase("port", .property),
        TokenCase("8_080", .number),
        TokenCase("'b'", .string),
        TokenCase("true", .constant),
        TokenCase("1979-05-27T07:32:00Z", .number),
        TokenCase("x", .property),
        TokenCase("y", .property),
        TokenCase("-2.5", .number),
        TokenCase("\"quoted.key\"", .property),
        TokenCase("multi \"line\"", .string),
        TokenCase("plugins", .type),
        TokenCase("# trailing", .comment),
    ]

    @Test(arguments: tomlTokens)
    func tomlFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("toml", Self.tomlSource).expect(token)
    }

    @Test
    func tomlTokenRangesAreWellFormed() {
        SyntaxProbe("toml", Self.tomlSource).expectWellFormed()
    }
}
