import Foundation
import Testing
@testable import ParcCore

struct NoteSyntaxCodeTestsCAndSystemsTests {
    typealias TokenCase = NoteSyntaxCodeTestsSupport.TokenCase
    private typealias SyntaxProbe = NoteSyntaxCodeTestsSupport.SyntaxProbe

    private static let cSource = """
        #include <stdio.h>
        #define MAX 10
        typedef struct node { int value; struct node *next; } node_t;
        int main(void) { char *s = "tab\\t\\"x\\" /* no */"; printf("%d\\n", p->value); return 0x10UL + 1.5f; }
        """

    private static let cTokens = [
        TokenCase("#include", .meta),
        TokenCase("<stdio.h>", .string),
        TokenCase("#define", .meta),
        TokenCase("MAX", .constant),
        TokenCase("typedef", .keyword),
        TokenCase("node", .type),
        TokenCase("int", .type),
        TokenCase("main", .function),
        TokenCase("\\t", .escape),
        TokenCase("/* no */", .string),
        TokenCase("printf", .builtin),
        TokenCase("value", .property, 2),
        TokenCase("0x10UL", .number),
        TokenCase("1.5f", .number),
    ]

    @Test(arguments: cTokens)
    func cFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("c", Self.cSource).expect(token)
    }

    @Test
    func cTokenRangesAreWellFormed() {
        SyntaxProbe("c", Self.cSource).expectWellFormed()
    }

    private static let cppSource = """
        template <typename T> class Stack : public Base {
            std::vector<T> items; auto x = 1'000'000; auto r = R"json({"a": ")"})json";
            constexpr bool empty() const noexcept { return items.empty() && nullptr == this; }
        };
        """

    private static let cppTokens = [
        TokenCase("template", .keyword),
        TokenCase("typename", .keyword),
        TokenCase("Stack", .type),
        TokenCase("public", .keyword),
        TokenCase("1'000'000", .number),
        TokenCase("R\"json({\"a\": \")\"})json\"", .string),
        TokenCase("constexpr", .keyword),
        TokenCase("empty", .function),
        TokenCase("nullptr", .constant),
    ]

    @Test(arguments: cppTokens)
    func cppFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("c++", Self.cppSource).expect(token)
    }

    @Test
    func cppTokenRangesAreWellFormed() {
        SyntaxProbe("c++", Self.cppSource).expectWellFormed()
    }

    private static let csharpSource = """
        #region Setup
        public record Person(string Name) { }
        var path = @"C:\\dir\\""quoted""\";
        var msg = $"Hello {name.ToUpper()} {{braces}}";
        var raw = \"\"\"
            {"json": true}
            \"\"\";
        var @class = await LoadAsync<int>(); // done
        """

    private static let csharpTokens = [
        TokenCase("#region Setup", .meta),
        TokenCase("record", .keyword),
        TokenCase("Person", .type),
        TokenCase("string", .type),
        TokenCase("@\"C:\\dir\\\"\"quoted\"\"\"", .string),
        TokenCase("$\"Hello ", .string),
        TokenCase("ToUpper", .function),
        TokenCase("{{braces}}", .string),
        TokenCase("{\"json\": true}", .string),
        TokenCase("@class", nil),
        TokenCase("await", .keyword),
        TokenCase("LoadAsync", .type),
        TokenCase("// done", .comment),
    ]

    @Test(arguments: csharpTokens)
    func csharpFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("cs", Self.csharpSource).expect(token)
    }

    @Test
    func csharpTokenRangesAreWellFormed() {
        SyntaxProbe("cs", Self.csharpSource).expectWellFormed()
    }

    private static let objectiveCSource = """
        #import <Foundation/Foundation.h>
        @interface Greeter : NSObject
        @property (nonatomic, copy) NSString *name;
        @end
        @implementation Greeter
        - (void)greet { NSLog(@"Hi %@", self.name); id list = @[@1, @YES]; }
        @end
        """

    private static let objectiveCTokens = [
        TokenCase("#import", .meta),
        TokenCase("@interface", .keyword),
        TokenCase("Greeter", .type),
        TokenCase("NSObject", .type),
        TokenCase("@property", .keyword),
        TokenCase("nonatomic", .keyword),
        TokenCase("NSString", .type),
        TokenCase("@end", .keyword),
        TokenCase("void", .type),
        TokenCase("NSLog", .builtin),
        TokenCase("@\"Hi %@\"", .string),
        TokenCase("self", .keyword),
        TokenCase("id", .type),
        TokenCase("@[", .punctuation),
        TokenCase("@1", .number),
        TokenCase("@YES", .constant),
    ]

    @Test(arguments: objectiveCTokens)
    func objectiveCFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("objc", Self.objectiveCSource).expect(token)
    }

    @Test
    func objectiveCTokenRangesAreWellFormed() {
        SyntaxProbe("objc", Self.objectiveCSource).expectWellFormed()
    }

    private static let goSource = """
        package main
        import "fmt"
        type Point struct{ X, Y float64 }
        func (p *Point) Len() int { return len(raw) + 'a' + 0x1p-2 + 3i }
        var raw = `C:\\path "quoted" // not comment`
        """

    private static let goTokens = [
        TokenCase("package", .keyword),
        TokenCase("\"fmt\"", .string),
        TokenCase("Point", .type),
        TokenCase("float64", .type),
        TokenCase("Len", .function),
        TokenCase("len", .builtin),
        TokenCase("'a'", .string),
        TokenCase("0x1p-2", .number),
        TokenCase("3i", .number),
        TokenCase("`C:\\path \"quoted\" // not comment`", .string),
    ]

    @Test(arguments: goTokens)
    func goFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("go", Self.goSource).expect(token)
    }

    @Test
    func goTokenRangesAreWellFormed() {
        SyntaxProbe("go", Self.goSource).expectWellFormed()
    }

    private static let rustSource = """
        #[derive(Debug, Clone)]
        pub struct Wrapper<'a> { inner: &'a str }
        /* outer /* nested */ still */
        impl<'a> Wrapper<'a> {
            fn new(s: &'a str) -> Self { println!("{} {}", s, '\\n'); Self { inner: s } }
        }
        let raw = r#"a "quoted" \\n str"#; let b = b'x'; let n = 1_000u32 + 0b1010 + 2.5e3f64;
        const MAX_SIZE: usize = 10;
        """

    private static let rustTokens = [
        TokenCase("#[derive(Debug, Clone)]", .attribute),
        TokenCase("pub", .keyword),
        TokenCase("Wrapper", .type),
        TokenCase("'a", .variable),
        TokenCase("str", .type, 2),
        TokenCase("/* outer /* nested */ still */", .comment),
        TokenCase("new", .function),
        TokenCase("Self", .keyword),
        TokenCase("println!", .function),
        TokenCase("\"{} {}\"", .string),
        TokenCase("\\n", .escape),
        TokenCase("r#\"a \"quoted\" \\n str\"#", .string),
        TokenCase("b'x'", .string),
        TokenCase("1_000u32", .number),
        TokenCase("0b1010", .number),
        TokenCase("2.5e3f64", .number),
        TokenCase("MAX_SIZE", .constant),
        TokenCase("usize", .type),
    ]

    @Test(arguments: rustTokens)
    func rustFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("rust", Self.rustSource).expect(token)
    }

    @Test
    func rustTokenRangesAreWellFormed() {
        SyntaxProbe("rust", Self.rustSource).expectWellFormed()
    }

    private static let zigSource = """
        const std = @import("std");
        pub fn main() !void {
            const text =
                \\\\multi "line"
                \\\\string // no comment
            ;
            var x: u7 = 0x7f; // real
            std.debug.print("{d}\\n", .{x});
        }
        """

    private static let zigTokens = [
        TokenCase("const", .keyword),
        TokenCase("@import", .builtin),
        TokenCase("\"std\"", .string),
        TokenCase("pub", .keyword),
        TokenCase("main", .function),
        TokenCase("void", .type),
        TokenCase("\\\\multi \"line\"", .string),
        TokenCase("\\\\string // no comment", .string),
        TokenCase("u7", .type),
        TokenCase("0x7f", .number),
        TokenCase("// real", .comment),
        TokenCase("print", .function),
    ]

    @Test(arguments: zigTokens)
    func zigFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("zig", Self.zigSource).expect(token)
    }

    @Test
    func zigTokenRangesAreWellFormed() {
        SyntaxProbe("zig", Self.zigSource).expectWellFormed()
    }
}
