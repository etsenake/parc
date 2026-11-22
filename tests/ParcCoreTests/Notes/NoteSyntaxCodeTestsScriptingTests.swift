import Foundation
import Testing
@testable import ParcCore

struct NoteSyntaxCodeTestsScriptingTests {
    typealias TokenCase = NoteSyntaxCodeTestsSupport.TokenCase
    private typealias SyntaxProbe = NoteSyntaxCodeTestsSupport.SyntaxProbe

    private static let pythonSource = """
        @dataclass(frozen=True)
        class Point:
            '''Docstring with "quotes" and # not a comment'''
            def norm(self, scale: float = 1.0) -> float:
                s = f"{self.x!r:>10} {{literal}} {scale * 2}"  # real comment
                raw = rb'\\d+\\''
                return abs(self.x) ** 2 + 0o17 + 1_000j if True else None
        matrix = a @ b
        \"\"\"multi
        line\"\"\"
        """

    private static let pythonTokens = [
        TokenCase("@dataclass", .attribute),
        TokenCase("True", .constant),
        TokenCase("class", .keyword, 2),
        TokenCase("Point", .type),
        TokenCase("'''Docstring with \"quotes\" and # not a comment'''", .string),
        TokenCase("def", .keyword),
        TokenCase("norm", .function),
        TokenCase("self", .variable),
        TokenCase("float", .builtin),
        TokenCase("1.0", .number),
        TokenCase("f\"", .string),
        TokenCase("{{literal}}", .string),
        TokenCase("scale", nil, 2),
        TokenCase("2", .number),
        TokenCase("# real comment", .comment),
        TokenCase("rb'\\d+\\''", .string),
        TokenCase("abs", .builtin),
        TokenCase("0o17", .number),
        TokenCase("1_000j", .number),
        TokenCase("None", .constant),
        TokenCase("@", nil, 2),
        TokenCase("\"\"\"multi\nline\"\"\"", .string),
    ]

    @Test(arguments: pythonTokens)
    func pythonFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("python", Self.pythonSource).expect(token)
    }

    @Test
    func pythonTokenRangesAreWellFormed() {
        SyntaxProbe("python", Self.pythonSource).expectWellFormed()
    }

    private static let rubySource = """
        # frozen_string_literal: true
        module Shop
          class Cart < Base
            attr_reader :items
            def total?(tax: 0.2)
              @items.sum { |i| i.price } * (1 + tax) unless @@closed || $debug
            end
          end
        end
        msg = "Total: #{cart.total?(tax: 0.1)} \\u00e9"
        words = %w[apple banana] + %i(a b)
        pattern = /\\A\\d+\\z/i
        sql = <<~SQL
          SELECT * FROM t WHERE id = #{id}
        SQL
        =begin
        block "comment"
        =end
        puts 'done'
        """

    private static let rubyTokens = [
        TokenCase("# frozen_string_literal: true", .comment),
        TokenCase("module", .keyword),
        TokenCase("Shop", .type),
        TokenCase("Cart", .type),
        TokenCase("attr_reader", .builtin),
        TokenCase(":items", .constant),
        TokenCase("total?", .function),
        TokenCase("tax:", .constant),
        TokenCase("0.2", .number),
        TokenCase("@items", .variable),
        TokenCase("sum", .property),
        TokenCase("unless", .keyword),
        TokenCase("@@closed", .variable),
        TokenCase("$debug", .variable),
        TokenCase("\"Total: ", .string),
        TokenCase("#{", .punctuation),
        TokenCase("\\u00e9", .escape),
        TokenCase("%w[apple banana]", .string),
        TokenCase("%i(a b)", .string),
        TokenCase("/\\A\\d+\\z/i", .regex),
        TokenCase("SQL", .string),
        TokenCase("SELECT * FROM t WHERE id = ", .string),
        TokenCase("id", nil, 2),
        TokenCase("block \"comment\"", .comment),
        TokenCase("puts", .builtin),
        TokenCase("'done'", .string),
    ]

    @Test(arguments: rubyTokens)
    func rubyFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("ruby", Self.rubySource).expect(token)
    }

    @Test
    func rubyTokenRangesAreWellFormed() {
        SyntaxProbe("ruby", Self.rubySource).expectWellFormed()
    }

    private static let phpSource = """
        <!DOCTYPE html>
        <p class="x"><?php echo "Hi {$user->name} and $count items"; ?></p>
        <?php
        function total(array $items): int { // sum
            $text = <<<EOT
            Total: $sum
            EOT;
            return count($items) + $this->tax;
        }
        """

    private static let phpTokens = [
        TokenCase("<!DOCTYPE html>", .meta),
        TokenCase("p", .tag),
        TokenCase("class", .attribute),
        TokenCase("<?php", .meta),
        TokenCase("echo", .keyword),
        TokenCase("\"Hi ", .string),
        TokenCase("$user", .variable),
        TokenCase("name", .property),
        TokenCase("$count", .variable),
        TokenCase("?>", .meta),
        TokenCase("function", .keyword),
        TokenCase("total", .function),
        TokenCase("array", .type),
        TokenCase("$items", .variable),
        TokenCase("// sum", .comment),
        TokenCase("EOT", .string),
        TokenCase("Total: ", .string),
        TokenCase("$sum", .variable),
        TokenCase("count", .builtin, 2),
        TokenCase("tax", .property),
    ]

    @Test(arguments: phpTokens)
    func phpFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("php", Self.phpSource).expect(token)
    }

    @Test
    func phpTokenRangesAreWellFormed() {
        SyntaxProbe("php", Self.phpSource).expectWellFormed()
    }

    private static let barePHPSource = "$x = ['a' => 1]; # hash comment\n#[Attribute]\nclass A {}"

    private static let barePHPTokens = [
        TokenCase("$x", .variable),
        TokenCase("'a'", .string),
        TokenCase("# hash comment", .comment),
        TokenCase("#[Attribute]", .attribute),
        TokenCase("A", .type, 2),
    ]

    @Test(arguments: barePHPTokens)
    func barePHPFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("php", Self.barePHPSource).expect(token)
    }

    private static let luaSource = """
        --[==[ long
        comment ]==]
        local function greet(name) -- line comment
          local s = [[raw "string" -- not comment]]
          return string.format("Hi %s\\n", name) .. #s
        end
        """

    private static let luaTokens = [
        TokenCase("--[==[ long\ncomment ]==]", .comment),
        TokenCase("local", .keyword),
        TokenCase("greet", .function),
        TokenCase("-- line comment", .comment),
        TokenCase("[[raw \"string\" -- not comment]]", .string),
        TokenCase("string", .builtin, 2),
        TokenCase("format", .function),
        TokenCase("\\n", .escape),
        TokenCase("end", .keyword),
    ]

    @Test(arguments: luaTokens)
    func luaFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("lua", Self.luaSource).expect(token)
    }

    @Test
    func luaTokenRangesAreWellFormed() {
        SyntaxProbe("lua", Self.luaSource).expectWellFormed()
    }

    private static let rSource = """
        library(dplyr) # load
        df <- data.frame(x = c(1L, 2L), y = r"(C:\\raw)")
        result <- df %>% filter(!is.na(x)) %in% TRUE
        `my var` <- NULL
        """

    private static let rTokens = [
        TokenCase("library", .builtin),
        TokenCase("# load", .comment),
        TokenCase("<-", .operatorSymbol),
        TokenCase("data.frame", .builtin),
        TokenCase("1L", .number),
        TokenCase("r\"(C:\\raw)\"", .string),
        TokenCase("%>%", .operatorSymbol),
        TokenCase("filter", .function),
        TokenCase("is.na", .builtin),
        TokenCase("%in%", .operatorSymbol),
        TokenCase("TRUE", .constant),
        TokenCase("`my var`", nil),
        TokenCase("NULL", .constant),
    ]

    @Test(arguments: rTokens)
    func rFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("r", Self.rSource).expect(token)
    }

    @Test
    func rTokenRangesAreWellFormed() {
        SyntaxProbe("r", Self.rSource).expectWellFormed()
    }
}
