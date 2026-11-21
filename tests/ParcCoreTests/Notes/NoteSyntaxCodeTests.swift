import Foundation
import Testing
@testable import ParcCore

struct NoteSyntaxCodeTests {
    @Test func swift() {
        let probe = SyntaxProbe("swift", """
        @MainActor final class Box<T>: Codable {
            let url = "https://parc.dev/a // b"
            /* outer /* inner */ still comment */
            var count = 0x1F_FF + 1_000.5e-3
            func greet(_ name: String) -> String { "Hi \\(name.uppercased()), \\("nested \\(1)")!\\n" }
            let raw = #"no \\(interp) here \\#(count)"#
            let multi = \"\"\"
              line "one"
              \"\"\"
            #if DEBUG
            let ok = self.value ?? nil
            #endif
            let `default` = $0
        }
        """)
        probe.expect("@MainActor", .attribute)
        probe.expect("final", .keyword)
        probe.expect("class", .keyword)
        probe.expect("Box", .type)
        probe.expect("Codable", .type)
        probe.expect("\"https://parc.dev/a // b\"", .string)
        probe.expect("/* outer /* inner */ still comment */", .comment)
        probe.expect("still comment", .comment)
        probe.expect("0x1F_FF", .number)
        probe.expect("1_000.5e-3", .number)
        probe.expect("greet", .function)
        probe.expect("String", .type)
        probe.expect("\\(", .punctuation)
        probe.expect("uppercased", .function)
        probe.expect("\"nested ", .string)
        probe.expect("1", .number, 2)
        probe.expect("\\n", .escape)
        probe.expect("#\"no \\(interp) here ", .string)
        probe.expect("\\#(", .punctuation)
        probe.expect("count", nil, 2)
        probe.expect("line \"one\"", .string)
        probe.expect("#if", .keyword)
        probe.expect("self", .keyword)
        probe.expect("value", .property)
        probe.expect("nil", .constant)
        probe.expect("default", nil)
        probe.expect("$0", .variable)
        probe.expectWellFormed()
        let regex = SyntaxProbe("swift", "let r = #/a+b/# // tail")
        regex.expect("#/a+b/#", .regex)
        regex.expect("// tail", .comment)
    }

    @Test func javascriptFamily() {
        let js = SyntaxProbe("js", """
        import { a } from "./mod.js" // "quote in comment
        const re = /[/]+\\d{2}/gi, half = total / 2 / count;
        const tpl = `sum ${ { a: 1 }.a + `inner ${deep}` } done`;
        let big = 12_345n, hex = 0xFFn; class Foo extends Bar { #secret = 1; get x() { return this.#secret } }
        const s = 'it\\'s /* not */ a comment';
        html`<b>${name}</b>`;
        function ok(y) { return /foo/.test(y) }
        """)
        js.expect("import", .keyword)
        js.expect("\"./mod.js\"", .string)
        js.expect("// \"quote in comment", .comment)
        js.expect("/[/]+\\d{2}/gi", .regex)
        js.expect("/", .operatorSymbol, 7)
        js.expect("/", .operatorSymbol, 8)
        js.expect("total", nil)
        js.expect("`sum ", .string)
        js.expect("${", .punctuation)
        js.expect("1", .number)
        js.expect("`inner ", .string)
        js.expect(" done`", .string)
        js.expect("12_345n", .number)
        js.expect("0xFFn", .number)
        js.expect("Foo", .type)
        js.expect("Bar", .type)
        js.expect("#secret", .property)
        js.expect("this", .keyword)
        js.expect("'it\\'s /* not */ a comment'", nil)
        js.expect("/* not */", .string)
        js.expect("\\'", .escape)
        js.expect("html", .function)
        js.expect("/foo/", .regex)
        js.expect("test", .function)
        js.expectWellFormed()

        let ts = SyntaxProbe("ts", "interface User { name: string; age?: number }\ntype Id = string | number;\nenum Color { Red }\n@Component({}) class A implements B {}")
        ts.expect("interface", .keyword)
        ts.expect("User", .type)
        ts.expect("string", .type)
        ts.expect("number", .type)
        ts.expect("type", .keyword)
        ts.expect("Id", .type)
        ts.expect("enum", .keyword)
        ts.expect("@Component", .attribute)
        ts.expect("implements", .keyword)

        let jsx = SyntaxProbe("jsx", """
        const App = () => (
          <div className="app" onClick={() => go(1)}>
            Hello {user.name}, it's <b>bold</b> &amp; <Card {...props} title='x' />
          </div>
        );
        const less = a < b;
        """)
        jsx.expect("div", .tag)
        jsx.expect("className", .attribute)
        jsx.expect("\"app\"", .string)
        jsx.expect("onClick", .attribute)
        jsx.expect("go", .function)
        jsx.expect("Hello", nil)
        jsx.expect("it's", nil)
        jsx.expect("name", .property)
        jsx.expect("b", .tag)
        jsx.expect("&amp;", .escape)
        jsx.expect("Card", .tag)
        jsx.expect("'x'", .string)
        jsx.expect("</", .punctuation)
        jsx.expect("<", .operatorSymbol, 6)
        jsx.expectWellFormed()

        let tsx = SyntaxProbe("tsx", "const el: JSX.Element = <Button kind=\"primary\">{label as string}</Button>;")
        tsx.expect("Button", .tag)
        tsx.expect("kind", .attribute)
        tsx.expect("as", .keyword)
        tsx.expect("string", .type)
    }

    @Test func python() {
        let probe = SyntaxProbe("python", """
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
        """)
        probe.expect("@dataclass", .attribute)
        probe.expect("True", .constant)
        probe.expect("class", .keyword, 2)
        probe.expect("Point", .type)
        probe.expect("'''Docstring with \"quotes\" and # not a comment'''", .string)
        probe.expect("def", .keyword)
        probe.expect("norm", .function)
        probe.expect("self", .variable)
        probe.expect("float", .builtin)
        probe.expect("1.0", .number)
        probe.expect("f\"", .string)
        probe.expect("{{literal}}", .string)
        probe.expect("scale", nil, 2)
        probe.expect("2", .number)
        probe.expect("# real comment", .comment)
        probe.expect("rb'\\d+\\''", .string)
        probe.expect("abs", .builtin)
        probe.expect("0o17", .number)
        probe.expect("1_000j", .number)
        probe.expect("None", .constant)
        probe.expect("@", nil, 2)
        probe.expect("\"\"\"multi\nline\"\"\"", .string)
        probe.expectWellFormed()
    }

    @Test func ruby() {
        let probe = SyntaxProbe("ruby", """
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
        """)
        probe.expect("# frozen_string_literal: true", .comment)
        probe.expect("module", .keyword)
        probe.expect("Shop", .type)
        probe.expect("Cart", .type)
        probe.expect("attr_reader", .builtin)
        probe.expect(":items", .constant)
        probe.expect("total?", .function)
        probe.expect("tax:", .constant)
        probe.expect("0.2", .number)
        probe.expect("@items", .variable)
        probe.expect("sum", .property)
        probe.expect("unless", .keyword)
        probe.expect("@@closed", .variable)
        probe.expect("$debug", .variable)
        probe.expect("\"Total: ", .string)
        probe.expect("#{", .punctuation)
        probe.expect("\\u00e9", .escape)
        probe.expect("%w[apple banana]", .string)
        probe.expect("%i(a b)", .string)
        probe.expect("/\\A\\d+\\z/i", .regex)
        probe.expect("SQL", .string)
        probe.expect("SELECT * FROM t WHERE id = ", .string)
        probe.expect("id", nil, 2)
        probe.expect("block \"comment\"", .comment)
        probe.expect("puts", .builtin)
        probe.expect("'done'", .string)
        probe.expectWellFormed()
    }

    @Test func goAndRust() {
        let go = SyntaxProbe("go", """
        package main
        import "fmt"
        type Point struct{ X, Y float64 }
        func (p *Point) Len() int { return len(raw) + 'a' + 0x1p-2 + 3i }
        var raw = `C:\\path "quoted" // not comment`
        """)
        go.expect("package", .keyword)
        go.expect("\"fmt\"", .string)
        go.expect("Point", .type)
        go.expect("float64", .type)
        go.expect("Len", .function)
        go.expect("len", .builtin)
        go.expect("'a'", .string)
        go.expect("0x1p-2", .number)
        go.expect("3i", .number)
        go.expect("`C:\\path \"quoted\" // not comment`", .string)
        go.expectWellFormed()

        let rust = SyntaxProbe("rust", """
        #[derive(Debug, Clone)]
        pub struct Wrapper<'a> { inner: &'a str }
        /* outer /* nested */ still */
        impl<'a> Wrapper<'a> {
            fn new(s: &'a str) -> Self { println!("{} {}", s, '\\n'); Self { inner: s } }
        }
        let raw = r#"a "quoted" \\n str"#; let b = b'x'; let n = 1_000u32 + 0b1010 + 2.5e3f64;
        const MAX_SIZE: usize = 10;
        """)
        rust.expect("#[derive(Debug, Clone)]", .attribute)
        rust.expect("pub", .keyword)
        rust.expect("Wrapper", .type)
        rust.expect("'a", .variable)
        rust.expect("str", .type, 2)
        rust.expect("/* outer /* nested */ still */", .comment)
        rust.expect("new", .function)
        rust.expect("Self", .keyword)
        rust.expect("println!", .function)
        rust.expect("\"{} {}\"", .string)
        rust.expect("\\n", .escape)
        rust.expect("r#\"a \"quoted\" \\n str\"#", .string)
        rust.expect("b'x'", .string)
        rust.expect("1_000u32", .number)
        rust.expect("0b1010", .number)
        rust.expect("2.5e3f64", .number)
        rust.expect("MAX_SIZE", .constant)
        rust.expect("usize", .type)
        rust.expectWellFormed()
    }

    @Test func cFamily() {
        let c = SyntaxProbe("c", """
        #include <stdio.h>
        #define MAX 10
        typedef struct node { int value; struct node *next; } node_t;
        int main(void) { char *s = "tab\\t\\"x\\" /* no */"; printf("%d\\n", p->value); return 0x10UL + 1.5f; }
        """)
        c.expect("#include", .meta)
        c.expect("<stdio.h>", .string)
        c.expect("#define", .meta)
        c.expect("MAX", .constant)
        c.expect("typedef", .keyword)
        c.expect("node", .type)
        c.expect("int", .type)
        c.expect("main", .function)
        c.expect("\\t", .escape)
        c.expect("/* no */", .string)
        c.expect("printf", .builtin)
        c.expect("value", .property, 2)
        c.expect("0x10UL", .number)
        c.expect("1.5f", .number)
        c.expectWellFormed()

        let cpp = SyntaxProbe("c++", """
        template <typename T> class Stack : public Base {
            std::vector<T> items; auto x = 1'000'000; auto r = R"json({"a": ")"})json";
            constexpr bool empty() const noexcept { return items.empty() && nullptr == this; }
        };
        """)
        cpp.expect("template", .keyword)
        cpp.expect("typename", .keyword)
        cpp.expect("Stack", .type)
        cpp.expect("public", .keyword)
        cpp.expect("1'000'000", .number)
        cpp.expect("R\"json({\"a\": \")\"})json\"", .string)
        cpp.expect("constexpr", .keyword)
        cpp.expect("empty", .function)
        cpp.expect("nullptr", .constant)
        cpp.expectWellFormed()

        let csharp = SyntaxProbe("cs", """
        #region Setup
        public record Person(string Name) { }
        var path = @"C:\\dir\\""quoted""\";
        var msg = $"Hello {name.ToUpper()} {{braces}}";
        var raw = \"\"\"
            {"json": true}
            \"\"\";
        var @class = await LoadAsync<int>(); // done
        """)
        csharp.expect("#region Setup", .meta)
        csharp.expect("record", .keyword)
        csharp.expect("Person", .type)
        csharp.expect("string", .type)
        csharp.expect("@\"C:\\dir\\\"\"quoted\"\"\"", .string)
        csharp.expect("$\"Hello ", .string)
        csharp.expect("ToUpper", .function)
        csharp.expect("{{braces}}", .string)
        csharp.expect("{\"json\": true}", .string)
        csharp.expect("@class", nil)
        csharp.expect("await", .keyword)
        csharp.expect("LoadAsync", .type)
        csharp.expect("// done", .comment)
        csharp.expectWellFormed()

        let objc = SyntaxProbe("objc", """
        #import <Foundation/Foundation.h>
        @interface Greeter : NSObject
        @property (nonatomic, copy) NSString *name;
        @end
        @implementation Greeter
        - (void)greet { NSLog(@"Hi %@", self.name); id list = @[@1, @YES]; }
        @end
        """)
        objc.expect("#import", .meta)
        objc.expect("@interface", .keyword)
        objc.expect("Greeter", .type)
        objc.expect("NSObject", .type)
        objc.expect("@property", .keyword)
        objc.expect("nonatomic", .keyword)
        objc.expect("NSString", .type)
        objc.expect("@end", .keyword)
        objc.expect("void", .type)
        objc.expect("NSLog", .builtin)
        objc.expect("@\"Hi %@\"", .string)
        objc.expect("self", .keyword)
        objc.expect("id", .type)
        objc.expect("@[", .punctuation)
        objc.expect("@1", .number)
        objc.expect("@YES", .constant)
        objc.expectWellFormed()
    }

    @Test func jvmFamily() {
        let java = SyntaxProbe("java", """
        @Override
        public static final long ID = 42L;
        String block = \"\"\"
            Hello "text" block
            \"\"\";
        char c = '\\'';
        if (list instanceof ArrayList<?> a) System.out.println(a.size());
        """)
        java.expect("@Override", .attribute)
        java.expect("public", .keyword)
        java.expect("long", .type)
        java.expect("ID", .constant)
        java.expect("42L", .number)
        java.expect("Hello \"text\" block", .string)
        java.expect("'", .string, 3)
        java.expect("instanceof", .keyword)
        java.expect("ArrayList", .type)
        java.expect("println", .function)
        java.expectWellFormed()

        let kotlin = SyntaxProbe("kotlin", """
        data class User(val name: String) {
            /* a /* nested */ b */
            fun greet() = "Hi $name, ${name.length} chars"
            val raw = \"\"\"C:\\no\\escape $name\"\"\"
        }
        """)
        kotlin.expect("data", .keyword)
        kotlin.expect("User", .type)
        kotlin.expect("val", .keyword)
        kotlin.expect("/* a /* nested */ b */", .comment)
        kotlin.expect("greet", .function)
        kotlin.expect("\"Hi ", .string)
        kotlin.expect("$name", .variable)
        kotlin.expect("${", .punctuation)
        kotlin.expect("length", .property)
        kotlin.expect("\"\"\"C:\\no\\escape ", .string)
        kotlin.expect("$name", .variable, 2)
        kotlin.expectWellFormed()

        let scala = SyntaxProbe("scala", """
        case class Point(x: Int, y: Int)
        object Main extends App {
          val msg = s"Point at $x and ${x + 1}"
          def show(p: Point): String = raw"\\d+"
          /* outer /* inner */ */
        }
        """)
        scala.expect("case", .keyword)
        scala.expect("Point", .type)
        scala.expect("object", .keyword)
        scala.expect("Main", .type)
        scala.expect("s\"Point at ", .string)
        scala.expect("$x", .variable)
        scala.expect("1", .number)
        scala.expect("show", .function)
        scala.expect("raw\"\\d+\"", .string)
        scala.expect("/* outer /* inner */ */", .comment)
        scala.expectWellFormed()
    }

    @Test func dartAndPHP() {
        let dart = SyntaxProbe("dart", """
        @override
        Widget build(BuildContext context) {
          final name = 'Parc';
          return Text("Hi $name ${name.length}", style: r'raw $x');
        }
        """)
        dart.expect("@override", .attribute)
        dart.expect("Widget", .type)
        dart.expect("build", .function)
        dart.expect("final", .keyword)
        dart.expect("'Parc'", .string)
        dart.expect("$name", .variable)
        dart.expect("length", .property)
        dart.expect("r'raw $x'", .string)
        dart.expectWellFormed()

        let php = SyntaxProbe("php", """
        <!DOCTYPE html>
        <p class="x"><?php echo "Hi {$user->name} and $count items"; ?></p>
        <?php
        function total(array $items): int { // sum
            $text = <<<EOT
            Total: $sum
            EOT;
            return count($items) + $this->tax;
        }
        """)
        php.expect("<!DOCTYPE html>", .meta)
        php.expect("p", .tag)
        php.expect("class", .attribute)
        php.expect("<?php", .meta)
        php.expect("echo", .keyword)
        php.expect("\"Hi ", .string)
        php.expect("$user", .variable)
        php.expect("name", .property)
        php.expect("$count", .variable)
        php.expect("?>", .meta)
        php.expect("function", .keyword)
        php.expect("total", .function)
        php.expect("array", .type)
        php.expect("$items", .variable)
        php.expect("// sum", .comment)
        php.expect("EOT", .string)
        php.expect("Total: ", .string)
        php.expect("$sum", .variable)
        php.expect("count", .builtin, 2)
        php.expect("tax", .property)
        php.expectWellFormed()

        let bare = SyntaxProbe("php", "$x = ['a' => 1]; # hash comment\n#[Attribute]\nclass A {}")
        bare.expect("$x", .variable)
        bare.expect("'a'", .string)
        bare.expect("# hash comment", .comment)
        bare.expect("#[Attribute]", .attribute)
        bare.expect("A", .type, 2)
    }

    @Test func shells() {
        let bash = SyntaxProbe("bash", """
        #!/usr/bin/env bash
        set -euo pipefail
        NAME="world" # greet
        if [[ -n "$NAME" ]]; then
          echo "Hello, ${NAME:-you}! Today is $(date +%A) and `whoami`" | tee out.log
        fi
        cat <<'EOF' > config.txt
        literal $NOT_EXPANDED
        EOF
        cat <<-EOT
        	value=$HOME
        	EOT
        for f in *.txt; do git add "$f"; done
        echo url#fragment
        """)
        bash.expect("#!/usr/bin/env bash", .comment)
        bash.expect("set", .builtin)
        bash.expect("NAME", .variable)
        bash.expect("\"world\"", .string)
        bash.expect("# greet", .comment)
        bash.expect("if", .keyword)
        bash.expect("$NAME", .variable)
        bash.expect("then", .keyword)
        bash.expect("echo", .builtin)
        bash.expect("${NAME:-you}", .variable)
        bash.expect("$(", .punctuation)
        bash.expect("date", .function)
        bash.expect("whoami", .function)
        bash.expect("tee", .function)
        bash.expect("'EOF'", .string)
        bash.expect("literal $NOT_EXPANDED", .string)
        bash.expect("$HOME", .variable)
        bash.expect("for", .keyword)
        bash.expect("git", .function)
        bash.expect("add", nil)
        bash.expect("done", .keyword)
        bash.expect("url#fragment", nil)
        bash.expect("#fragment", nil)
        bash.expectWellFormed()

        let powershell = SyntaxProbe("powershell", """
        <# block
           comment #>
        function Get-Greeting([string]$Name = 'World') {
            $env:PATH -split ';' | Where-Object { $_ -like "*bin*" }
            Write-Host "Hello $Name, $(Get-Date) `n" -ForegroundColor Green
            return $true
        }
        $doc = @"
        Here $Name
        "@
        """)
        powershell.expect("<# block\n   comment #>", .comment)
        powershell.expect("function", .keyword)
        powershell.expect("Get-Greeting", .function)
        powershell.expect("string", .type)
        powershell.expect("$Name", .variable)
        powershell.expect("'World'", .string)
        powershell.expect("$env:PATH", .variable)
        powershell.expect("-split", .operatorSymbol)
        powershell.expect("$_", .variable)
        powershell.expect("-like", .operatorSymbol)
        powershell.expect("Write-Host", .function)
        powershell.expect("$(", .punctuation)
        powershell.expect("Get-Date", .function)
        powershell.expect("`n", .escape)
        powershell.expect("-ForegroundColor", .attribute)
        powershell.expect("$true", .constant)
        powershell.expect("Here ", .string)
        powershell.expect("$Name", .variable, 3)
        powershell.expectWellFormed()
    }

    @Test func scriptingFamily() {
        let lua = SyntaxProbe("lua", """
        --[==[ long
        comment ]==]
        local function greet(name) -- line comment
          local s = [[raw "string" -- not comment]]
          return string.format("Hi %s\\n", name) .. #s
        end
        """)
        lua.expect("--[==[ long\ncomment ]==]", .comment)
        lua.expect("local", .keyword)
        lua.expect("greet", .function)
        lua.expect("-- line comment", .comment)
        lua.expect("[[raw \"string\" -- not comment]]", .string)
        lua.expect("string", .builtin, 2)
        lua.expect("format", .function)
        lua.expect("\\n", .escape)
        lua.expect("end", .keyword)
        lua.expectWellFormed()

        let r = SyntaxProbe("r", """
        library(dplyr) # load
        df <- data.frame(x = c(1L, 2L), y = r"(C:\\raw)")
        result <- df %>% filter(!is.na(x)) %in% TRUE
        `my var` <- NULL
        """)
        r.expect("library", .builtin)
        r.expect("# load", .comment)
        r.expect("<-", .operatorSymbol)
        r.expect("data.frame", .builtin)
        r.expect("1L", .number)
        r.expect("r\"(C:\\raw)\"", .string)
        r.expect("%>%", .operatorSymbol)
        r.expect("filter", .function)
        r.expect("is.na", .builtin)
        r.expect("%in%", .operatorSymbol)
        r.expect("TRUE", .constant)
        r.expect("`my var`", nil)
        r.expect("NULL", .constant)
        r.expectWellFormed()

        let elixir = SyntaxProbe("elixir", """
        defmodule Greeter do
          @moduledoc \"\"\"
          Says #{"hi"}
          \"\"\"
          def hello(name, opts \\\\ []) when is_binary(name) do
            pattern = ~r/^\\w+$/i
            words = ~w(a b c)
            IO.puts("Hello #{name}") |> then(fn _ -> :ok end)
            %{status: :done, valid?: true}
          end
        end
        """)
        elixir.expect("defmodule", .keyword)
        elixir.expect("Greeter", .type)
        elixir.expect("@moduledoc", .attribute)
        elixir.expect("Says ", .string)
        elixir.expect("\"hi\"", .string)
        elixir.expect("def", .keyword)
        elixir.expect("hello", .function)
        elixir.expect("when", .keyword)
        elixir.expect("~r/^\\w+$/i", .regex)
        elixir.expect("~w(a b c)", .string)
        elixir.expect("IO", .builtin)
        elixir.expect("puts", .function)
        elixir.expect("|>", .operatorSymbol)
        elixir.expect(":ok", .constant)
        elixir.expect("status:", .constant)
        elixir.expect(":done", .constant)
        elixir.expect("valid?:", .constant)
        elixir.expect("true", .constant)
        elixir.expectWellFormed()
    }

    @Test func functionalFamily() {
        let haskell = SyntaxProbe("haskell", """
        {-# LANGUAGE OverloadedStrings #-}
        module Main where
        {- outer {- nested -} still -}
        data Shape = Circle Double | Square Double deriving (Show)
        area :: Shape -> Double
        area (Circle r) = pi * r ^ 2 -- comment
        area' x = x --> y
        main = putStrLn "it's \\"fine\\"" >> print 'c'
        """)
        haskell.expect("{-# LANGUAGE OverloadedStrings #-}", .meta)
        haskell.expect("module", .keyword)
        haskell.expect("{- outer {- nested -} still -}", .comment)
        haskell.expect("data", .keyword)
        haskell.expect("Shape", .type)
        haskell.expect("Circle", .type)
        haskell.expect("deriving", .keyword)
        haskell.expect("area", .function)
        haskell.expect("::", .operatorSymbol)
        haskell.expect("-- comment", .comment)
        haskell.expect("area'", .function)
        haskell.expect("-->", .operatorSymbol)
        haskell.expect("putStrLn", .builtin)
        haskell.expect("\\\"", .escape)
        haskell.expect("'c'", .string)
        haskell.expectWellFormed()

        let zig = SyntaxProbe("zig", """
        const std = @import("std");
        pub fn main() !void {
            const text =
                \\\\multi "line"
                \\\\string // no comment
            ;
            var x: u7 = 0x7f; // real
            std.debug.print("{d}\\n", .{x});
        }
        """)
        zig.expect("const", .keyword)
        zig.expect("@import", .builtin)
        zig.expect("\"std\"", .string)
        zig.expect("pub", .keyword)
        zig.expect("main", .function)
        zig.expect("void", .type)
        zig.expect("\\\\multi \"line\"", .string)
        zig.expect("\\\\string // no comment", .string)
        zig.expect("u7", .type)
        zig.expect("0x7f", .number)
        zig.expect("// real", .comment)
        zig.expect("print", .function)
        zig.expectWellFormed()
    }

    @Test func queryFamily() {
        let sql = SyntaxProbe("sql", """
        -- top users
        SELECT u.name, COUNT(*) AS total FROM users u
        WHERE u.bio LIKE 'it''s -- fine' AND u.id = :id OR "Weird Col" > $1
        /* block */ GROUP BY u.name ORDER BY total DESC;
        CREATE FUNCTION f() RETURNS int AS $$ SELECT 1 $$ LANGUAGE sql;
        """)
        sql.expect("-- top users", .comment)
        sql.expect("SELECT", .keyword)
        sql.expect("name", .property)
        sql.expect("COUNT", .builtin)
        sql.expect("AS", .keyword)
        sql.expect("'it''s -- fine'", .string)
        sql.expect(":id", .variable)
        sql.expect("\"Weird Col\"", .variable)
        sql.expect("$1", .variable)
        sql.expect("/* block */", .comment)
        sql.expect("DESC", .keyword)
        sql.expect("int", .type)
        sql.expect("$$ SELECT 1 $$", .string)
        sql.expectWellFormed()

        let graphql = SyntaxProbe("graphql", """
        # fetch a user
        query GetUser($id: ID!, $withPosts: Boolean = false) @cached {
          user(id: $id) { name ...UserFields posts @include(if: $withPosts) { title } }
        }
        type User implements Node { "doc" name: String! }
        """)
        graphql.expect("# fetch a user", .comment)
        graphql.expect("query", .keyword)
        graphql.expect("GetUser", .function)
        graphql.expect("$id", .variable)
        graphql.expect("ID", .type)
        graphql.expect("false", .constant)
        graphql.expect("@cached", .attribute)
        graphql.expect("user", .function, 2)
        graphql.expect("id", .property, 2)
        graphql.expect("UserFields", .type)
        graphql.expect("@include", .attribute)
        graphql.expect("type", .keyword)
        graphql.expect("implements", .keyword)
        graphql.expect("\"doc\"", .string)
        graphql.expect("name", .property, 2)
        graphql.expect("ID", .type)
        graphql.expectWellFormed()
    }

    struct SyntaxProbe {
        let language: String
        let code: String
        let tokens: [NoteSyntaxToken]

        init(_ language: String, _ code: String) {
            self.language = language
            self.code = code
            tokens = NoteSyntaxHighlighter.tokens(in: code, language: language)
        }

        func range(of fragment: String, occurrence: Int) -> Range<Int>? {
            let text = code as NSString
            var searchStart = 0
            var found = NSRange(location: NSNotFound, length: 0)
            for _ in 0..<occurrence {
                found = text.range(of: fragment, options: [], range: NSRange(location: searchStart, length: text.length - searchStart))
                if found.location == NSNotFound { return nil }
                searchStart = found.location + max(1, found.length)
            }
            return found.location..<(found.location + found.length)
        }

        func kind(_ fragment: String, _ occurrence: Int = 1) -> NoteSyntaxKind? {
            guard let target = range(of: fragment, occurrence: occurrence) else { return nil }
            return tokens.first { $0.range.lowerBound <= target.lowerBound && $0.range.upperBound >= target.upperBound }?.kind
        }

        func expect(_ fragment: String, _ kind: NoteSyntaxKind?, _ occurrence: Int = 1) {
            let actual = self.kind(fragment, occurrence)
            if actual != kind {
                let dump = tokens.map { token -> String in
                    let piece = (code as NSString).substring(with: NSRange(location: token.range.lowerBound, length: token.range.count))
                    return "\(token.kind.rawValue)=\(piece.debugDescription)"
                }.joined(separator: " ")
                Issue.record("[\(language)] \(fragment.debugDescription)#\(occurrence) expected \(kind?.rawValue ?? "none"), got \(actual?.rawValue ?? "none")\n\(dump)")
            }
        }

        func expectWellFormed(file: StaticString = #file) {
            let length = (code as NSString).length
            var previous = 0
            for token in tokens {
                if token.range.lowerBound < previous || token.range.isEmpty || token.range.upperBound > length {
                    Issue.record("[\(language)] malformed token \(token) after \(previous)")
                }
                previous = token.range.upperBound
            }
        }
    }
}
