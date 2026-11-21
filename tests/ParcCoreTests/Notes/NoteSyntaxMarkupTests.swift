import Foundation
import Testing
@testable import ParcCore

struct NoteSyntaxMarkupTests {
    @Test func plainTextLeadsThePicker() {
        let all = NoteCodeLanguage.all
        #expect(all.first?.id == "plaintext" && all.first?.name == "Plain Text", "Plain Text leads the picker")
        let names = all.dropFirst().map { $0.name.lowercased() }
        #expect(names == names.sorted(), "the rest is alphabetical: \(names)")
        #expect(Set(all.map(\.id)).count == all.count, "ids are unique")
        #expect(all.count >= 36, "about thirty-five languages and then some")
        let fences: [String: String] = [
            "js": "javascript", "ts": "typescript", "sh": "bash", "shell": "bash", "zsh": "bash", "py": "python",
            "objc": "objectivec", "c++": "cpp", "yml": "yaml", "JSON": "json", "  Swift  ": "swift", "C#": "csharp",
            "rb": "ruby", "rs": "rust", "kt": "kotlin", "md": "markdown", "Dockerfile": "dockerfile", "patch": "diff",
            "python title=\"demo.py\"": "python", "{.rust}": "rust", "language-go": "go", "Objective-C": "objectivec",
            "gql": "graphql", "plain": "plaintext", "Plain Text": "plaintext", "tsx": "tsx", "jsx": "jsx",
        ]
        for (fence, id) in fences {
            #expect(NoteCodeLanguage.named(fence)?.id == id, "\(fence) names \(id), got \(NoteCodeLanguage.named(fence)?.id ?? "nil")")
        }
        #expect(NoteCodeLanguage.named("brainfudge") == nil, "unknown languages stay unknown")
        #expect(NoteCodeLanguage.named("") == nil, "empty info strings name nothing")
        #expect(NoteSyntaxHighlighter.tokens(in: "let x = 1", language: "klingon").isEmpty, "unknown languages get no tokens")
        #expect(NoteSyntaxHighlighter.tokens(in: "let x = 1", language: "text").isEmpty, "plain text gets no tokens")
        #expect(NoteSyntaxHighlighter.tokens(in: "", language: "swift").isEmpty, "empty code gets no tokens")
        for language in all where language.id != "plaintext" {
            #expect(NoteSyntaxLexer.lexer(for: language.id) != nil, "\(language.name) has a lexer")
        }
        let emoji = SyntaxProbe("swift", "let 🌳 = \"🌳\" // 🌳")
        emoji.expect("\"🌳\"", .string)
        emoji.expect("// 🌳", .comment)
        #expect(emoji.tokens.last?.range.upperBound == ("let 🌳 = \"🌳\" // 🌳" as NSString).length, "offsets are UTF-16")
    }

    @Test func html() {
        let probe = SyntaxProbe("html", """
        <!DOCTYPE html>
        <!-- a <b>comment</b> -->
        <html lang="en">
          <head>
            <style>
              body > .card:hover { color: #ff0066; margin: 0 auto; }
            </style>
            <script>
              const tag = "</div>"; if (a < b && c > d) { console.log(`x ${a}`); } // </p>
            </script>
            <script type="application/ld+json">{"name": "Parc"}</script>
          </head>
          <body class='main' hidden data-x=1>Fish &amp; chips &#x1F600;<br/><input disabled></body>
        </html>
        """)
        probe.expect("<!DOCTYPE html>", .meta)
        probe.expect("<!-- a <b>comment</b> -->", .comment)
        probe.expect("html", .tag, 2)
        probe.expect("lang", .attribute)
        probe.expect("\"en\"", .string)
        probe.expect("style", .tag)
        probe.expect("body", .tag)
        probe.expect(".card", .attribute)
        probe.expect(":hover", .keyword)
        probe.expect("color", .property)
        probe.expect("#ff0066", .constant)
        probe.expect("auto", .constant)
        probe.expect("const", .keyword)
        probe.expect("\"</div>\"", .string)
        probe.expect("<", .operatorSymbol, 11)
        probe.expect("console", .builtin)
        probe.expect("log", .function)
        probe.expect("`x ", .string)
        probe.expect("// </p>", .comment)
        probe.expect("script", .tag, 2)
        probe.expect("\"name\"", .property)
        probe.expect("\"Parc\"", .string)
        probe.expect("'main'", .string)
        probe.expect("hidden", .attribute)
        probe.expect("1", .string)
        probe.expect("Fish", nil)
        probe.expect("&amp;", .escape)
        probe.expect("&#x1F600;", .escape)
        probe.expect("br", .tag)
        probe.expect("/>", .punctuation)
        probe.expect("disabled", .attribute)
        probe.expectWellFormed()
    }

    @Test func xml() {
        let probe = SyntaxProbe("xml", """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>Name</key><string>Parc &lt;3</string>
        <![CDATA[ <raw> & stuff ]]><x:item xmlns:x="urn:x"/></dict></plist>
        <!-- done -->
        """)
        probe.expect("<?xml version=\"1.0\" encoding=\"UTF-8\"?>", .meta)
        probe.expect("plist", .tag)
        probe.expect("version", .attribute, 2)
        probe.expect("key", .tag)
        probe.expect("Name", nil)
        probe.expect("&lt;", .escape)
        probe.expect("<![CDATA[", .meta)
        probe.expect(" <raw> & stuff ", .string)
        probe.expect("x:item", .tag)
        probe.expect("xmlns:x", .attribute)
        probe.expect("<!-- done -->", .comment)
        probe.expectWellFormed()
    }

    @Test func styles() {
        let css = SyntaxProbe("css", """
        @import url(https://fonts.googleapis.com/css);
        :root { --accent: #6c5ce7; }
        @media (max-width: 600px) and screen {
          nav a[href^="http"]::after, #main > li + li { content: "→ { not a block"; width: calc(100% - 2rem) !important; }
        }
        /* comment with a "quote */
        .btn{background:rgba(0,0,0,.5);transition:all .2s ease-in-out}
        """)
        css.expect("@import", .keyword)
        css.expect("url", .function)
        css.expect("https://fonts.googleapis.com/css", .string)
        css.expect(":root", .keyword)
        css.expect("--accent", .variable)
        css.expect("#6c5ce7", .constant)
        css.expect("@media", .keyword)
        css.expect("max-width", .property)
        css.expect("600px", .number)
        css.expect("and", .keyword)
        css.expect("nav", .tag)
        css.expect("href", .attribute)
        css.expect("^", .operatorSymbol)
        css.expect("\"http\"", .string)
        css.expect("::after", .keyword)
        css.expect("#main", .attribute)
        css.expect(">", .operatorSymbol, 1)
        css.expect("content", .property)
        css.expect("\"→ { not a block\"", .string)
        css.expect("calc", .function)
        css.expect("100%", .number)
        css.expect("2rem", .number)
        css.expect("!important", .keyword)
        css.expect("/* comment with a \"quote */", .comment)
        css.expect(".btn", .attribute)
        css.expect("background", .property)
        css.expect("rgba", .function)
        css.expect(".5", .number)
        css.expect(".2s", .number)
        css.expect("ease-in-out", .constant)
        css.expectWellFormed()

        let scss = SyntaxProbe("scss", """
        @use "sass:math";
        $base: 16px !default; // line comment
        @mixin pad($size) { padding: math.div($size, 2); }
        .card {
          &:hover { color: darken($brand, 10%); }
          .title-#{$name} { @include pad(4px); }
          %placeholder { margin: 0; }
          @extend %placeholder;
        }
        """)
        scss.expect("@use", .keyword)
        scss.expect("\"sass:math\"", .string)
        scss.expect("$base", .variable)
        scss.expect("16px", .number)
        scss.expect("!default", .keyword)
        scss.expect("// line comment", .comment)
        scss.expect("@mixin", .keyword)
        scss.expect("pad", .function)
        scss.expect("padding", .property)
        scss.expect("div", .function)
        scss.expect("&", .keyword)
        scss.expect(":hover", .keyword)
        scss.expect("darken", .function)
        scss.expect("10%", .number)
        scss.expect(".title-", .attribute)
        scss.expect("#{", .punctuation)
        scss.expect("$name", .variable)
        scss.expect("@include", .keyword)
        scss.expect("%placeholder", .attribute)
        scss.expect("@extend", .keyword)
        scss.expectWellFormed()
    }

    @Test func markdown() {
        let probe = SyntaxProbe("markdown", """
        ---
        title: Hello
        tags: [a, b]
        ---
        # Big *title*
        Setext heading
        ==============
        Some **bold**, _soft_, ~~gone~~ and `code *not em*` with a [link](https://parc.dev "t") and ![img](a.png).
        snake_case_word stays plain, and so does 2 * 3 * 4.
        > quoted [ref][1] <span data-color="red">red</span>
        - [x] done item
        12. ordered \\*escaped\\*
        ```swift
        let x = "fenced" // comment
        ```
        ~~~
        plain fence
        ~~~
        [1]: https://example.com
        ***
        Visit https://parc.dev/notes, or <mailto:hi@parc.dev>.
        """)
        probe.expect("---", .meta)
        probe.expect("title", .property)
        probe.expect("Hello", .string)
        probe.expect("# Big *title*", .heading)
        probe.expect("Setext heading", .heading)
        probe.expect("==============", .punctuation)
        probe.expect("**bold**", .strong)
        probe.expect("_soft_", .emphasis)
        probe.expect("~~gone~~", .deleted)
        probe.expect("`code *not em*`", .string)
        probe.expect("[link]", .link)
        probe.expect("https://parc.dev", .string)
        probe.expect("[img]", .link)
        probe.expect("snake_case_word", nil)
        probe.expect("* 3 *", nil)
        probe.expect(">", .punctuation, 1)
        probe.expect("[ref]", .link)
        probe.expect("span", .tag)
        probe.expect("data-color", .attribute)
        probe.expect("\"red\"", .string)
        probe.expect("[x]", .keyword)
        probe.expect("12.", .punctuation)
        probe.expect("\\*", .escape)
        probe.expect("```", .punctuation)
        probe.expect("swift", .attribute)
        probe.expect("let", .keyword)
        probe.expect("\"fenced\"", .string)
        probe.expect("// comment", .comment)
        probe.expect("plain fence", .string)
        probe.expect("[1]", .link, 2)
        probe.expect("https://example.com", .string)
        probe.expect("***", .punctuation)
        probe.expect("https://parc.dev/notes", .link)
        probe.expect("<mailto:hi@parc.dev>", .link)
        probe.expectWellFormed()
        let list = SyntaxProbe("md", "- item\n* other\n+ third")
        list.expect("-", .punctuation)
        list.expect("*", .punctuation)
        list.expect("+", .punctuation)
    }

    @Test func data() {
        let json = SyntaxProbe("json", """
        {
          // jsonc comment
          "name": "Parc \\"Notes\\"",
          "version": -1.5e3,
          "tags": ["a", "b:c"],
          "ok": true, "none": null
        }
        """)
        json.expect("// jsonc comment", .comment)
        json.expect("\"name\"", .property)
        json.expect("\"Parc ", .string)
        json.expect("\\\"", .escape)
        json.expect("\"version\"", .property)
        json.expect("-1.5e3", .number)
        json.expect("\"a\"", .string)
        json.expect("\"b:c\"", .string)
        json.expect("true", .constant)
        json.expect("null", .constant)
        json.expect(":", .punctuation)
        json.expectWellFormed()

        let yaml = SyntaxProbe("yaml", """
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
        """)
        yaml.expect("%YAML 1.2", .meta)
        yaml.expect("---", .meta)
        yaml.expect("# config", .comment)
        yaml.expect("name", .property)
        yaml.expect("Parc Notes", .string)
        yaml.expect("# trailing comment", .comment)
        yaml.expect("2.11", .number)
        yaml.expect("yes", .constant)
        yaml.expect("~", .constant)
        yaml.expect("\"https://parc.dev/#not-comment\"", .string)
        yaml.expect("'it''s fine'", .string)
        yaml.expect("&base", .variable)
        yaml.expect("retries", .property)
        yaml.expect("3", .number)
        yaml.expect("*base", .variable)
        yaml.expect("!!str", .type)
        yaml.expect("one", .string)
        yaml.expect("key", .property)
        yaml.expect("flow", .string)
        yaml.expect("inner", .property)
        yaml.expect("|", .punctuation)
        yaml.expect("echo \"not: a key\"", .string)
        yaml.expect("# not a comment either", .string)
        yaml.expect("after", .property)
        yaml.expect("\"quoted key\"", .property)
        yaml.expectWellFormed()
        SyntaxProbe("yml", "- a").expect("-", .punctuation)

        let toml = SyntaxProbe("toml", """
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
        """)
        toml.expect("# settings", .comment)
        toml.expect("title", .property)
        toml.expect("\"Parc\"", .string)
        toml.expect("server.http", .type)
        toml.expect("port", .property)
        toml.expect("8_080", .number)
        toml.expect("'b'", .string)
        toml.expect("true", .constant)
        toml.expect("1979-05-27T07:32:00Z", .number)
        toml.expect("x", .property)
        toml.expect("y", .property)
        toml.expect("-2.5", .number)
        toml.expect("\"quoted.key\"", .property)
        toml.expect("multi \"line\"", .string)
        toml.expect("plugins", .type)
        toml.expect("# trailing", .comment)
        toml.expectWellFormed()
    }

    @Test func diff() {
        let probe = SyntaxProbe("diff", """
        diff --git a/notes.md b/notes.md
        index 83db48f..bf269f4 100644
        --- a/notes.md
        +++ b/notes.md
        @@ -1,4 +1,4 @@ func header()
         context line
        --- removed line that looks like a header
        +++ added line that looks like a header
        -old
        +new
        \\ No newline at end of file
        """)
        probe.expect("diff --git a/notes.md b/notes.md", .meta)
        probe.expect("index 83db48f..bf269f4 100644", .meta)
        probe.expect("--- a/notes.md", .heading)
        probe.expect("+++ b/notes.md", .heading)
        probe.expect("@@ -1,4 +1,4 @@", .meta)
        probe.expect("context line", nil)
        probe.expect("--- removed line that looks like a header", .deleted)
        probe.expect("+++ added line that looks like a header", .inserted)
        probe.expect("-old", .deleted)
        probe.expect("+new", .inserted)
        probe.expect("\\ No newline at end of file", .comment)
        probe.expectWellFormed()
        let loose = SyntaxProbe("patch", "+added\n-removed\n same")
        loose.expect("+added", .inserted)
        loose.expect("-removed", .deleted)
    }

    @Test func dockerfile() {
        let probe = SyntaxProbe("dockerfile", """
        # syntax=docker/dockerfile:1
        FROM --platform=$BUILDPLATFORM node:20-alpine AS build
        ARG VERSION=1.0
        ENV APP_HOME=/app PATH="$APP_HOME/bin:${PATH}"
        WORKDIR $APP_HOME
        # install
        RUN apk add --no-cache git \\
            && echo "built ${VERSION}" > /version.txt
        COPY --from=build /src ./
        EXPOSE 8080/tcp
        CMD ["node", "server.js"]
        """)
        probe.expect("# syntax=docker/dockerfile:1", .meta)
        probe.expect("FROM", .keyword)
        probe.expect("--platform", .attribute)
        probe.expect("AS", .keyword)
        probe.expect("ARG", .keyword)
        probe.expect("VERSION", .property)
        probe.expect("APP_HOME", .property)
        probe.expect("\"", .string, 1)
        probe.expect("$APP_HOME", .variable)
        probe.expect("${PATH}", .variable)
        probe.expect("$APP_HOME", .variable, 2)
        probe.expect("# install", .comment)
        probe.expect("RUN", .keyword)
        probe.expect("apk", .function)
        probe.expect("echo", .builtin)
        probe.expect("\"built ", .string)
        probe.expect("${VERSION}", .variable)
        probe.expect("--from", .attribute)
        probe.expect("8080/tcp", .number)
        probe.expect("CMD", .keyword)
        probe.expect("\"node\"", .string)
        probe.expectWellFormed()
    }

    @Test func makefile() {
        let probe = SyntaxProbe("makefile", """
        # build things
        CC ?= clang
        SOURCES := $(wildcard src/*.c)
        .PHONY: all clean
        all: build/app ## default
        build/%.o: src/%.c $(HEADERS)
        \t@echo "compiling $<" && $(CC) -c $< -o $@ $$HOME
        ifeq ($(DEBUG),1)
        CFLAGS += -g
        endif
        clean:
        \trm -rf build
        """)
        probe.expect("# build things", .comment)
        probe.expect("CC", .variable)
        probe.expect("?=", .operatorSymbol)
        probe.expect("SOURCES", .variable)
        probe.expect(":=", .operatorSymbol)
        probe.expect("wildcard", .builtin)
        probe.expect(".PHONY", .builtin)
        probe.expect("all", .function, 2)
        probe.expect("build/%.o", .function)
        probe.expect("$(HEADERS)", .variable)
        probe.expect("@", .operatorSymbol)
        probe.expect("echo", .builtin)
        probe.expect("$<", .variable)
        probe.expect("$(CC)", .variable)
        probe.expect("$@", .variable)
        probe.expect("$$HOME", .variable)
        probe.expect("ifeq", .keyword)
        probe.expect("$(DEBUG)", .variable)
        probe.expect("CFLAGS", .variable)
        probe.expect("endif", .keyword)
        probe.expect("clean", .function, 2)
        probe.expect("rm", .function)
        probe.expectWellFormed()
    }

    @Test func everyLanguageStaysLinearOn2000Line() {
        let languages = NoteCodeLanguage.all.map(\.id)
        let snippets = [
            "\"unterminated", "/* open", "`${`${`${", "<div <span", "'''", "#{", "${", "$(", "<<EOF", "@\"", "r#\"",
            "[[", "--[[", "{-", "```", "<!--", "\\", "\u{1F600}\"\u{1F600}", "a /b/ c", "\n\n\t ", "%w(", "~r/", "<?php",
        ]
        for language in languages {
            for snippet in snippets {
                SyntaxProbe(language, snippet).expectWellFormed()
                SyntaxProbe(language, String(repeating: snippet, count: 50)).expectWellFormed()
            }
        }
        let line = "let value = compute(\"text\", 0x2A) /* note */ + `tpl ${a / b}` // tail <b>x</b> $var #{x}\n"
        let big = String(repeating: line, count: 2_000)
        let pathological = String(repeating: "( / [ * _ ` < ${ #{ \" ' ", count: 4_000)
        let started = Date()
        for language in languages {
            SyntaxProbe(language, big).expectWellFormed()
            SyntaxProbe(language, pathological).expectWellFormed()
        }
        let elapsed = Date().timeIntervalSince(started)
        #expect(elapsed < 20, "every language stays linear on 2,000-line and adversarial blocks (\(elapsed)s)")
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

        func kind(_ fragment: String, _ occurrence: Int = 1) -> NoteSyntaxKind? {
            let text = code as NSString
            var searchStart = 0
            var found = NSRange(location: NSNotFound, length: 0)
            for _ in 0..<occurrence {
                found = text.range(of: fragment, options: [], range: NSRange(location: searchStart, length: text.length - searchStart))
                if found.location == NSNotFound { return nil }
                searchStart = found.location + max(1, found.length)
            }
            let target = found.location..<(found.location + found.length)
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
