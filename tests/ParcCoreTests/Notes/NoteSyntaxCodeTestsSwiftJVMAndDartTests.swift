import Foundation
import Testing
@testable import ParcCore

struct NoteSyntaxCodeTestsSwiftJVMAndDartTests {
    typealias TokenCase = NoteSyntaxCodeTestsSupport.TokenCase
    private typealias SyntaxProbe = NoteSyntaxCodeTestsSupport.SyntaxProbe

    private static let swiftSource = """
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
        """

    private static let swiftTokens = [
        TokenCase("@MainActor", .attribute),
        TokenCase("final", .keyword),
        TokenCase("class", .keyword),
        TokenCase("Box", .type),
        TokenCase("Codable", .type),
        TokenCase("\"https://parc.dev/a // b\"", .string),
        TokenCase("/* outer /* inner */ still comment */", .comment),
        TokenCase("still comment", .comment),
        TokenCase("0x1F_FF", .number),
        TokenCase("1_000.5e-3", .number),
        TokenCase("greet", .function),
        TokenCase("String", .type),
        TokenCase("\\(", .punctuation),
        TokenCase("uppercased", .function),
        TokenCase("\"nested ", .string),
        TokenCase("1", .number, 2),
        TokenCase("\\n", .escape),
        TokenCase("#\"no \\(interp) here ", .string),
        TokenCase("\\#(", .punctuation),
        TokenCase("count", nil, 2),
        TokenCase("line \"one\"", .string),
        TokenCase("#if", .keyword),
        TokenCase("self", .keyword),
        TokenCase("value", .property),
        TokenCase("nil", .constant),
        TokenCase("default", nil),
        TokenCase("$0", .variable),
    ]

    @Test(arguments: swiftTokens)
    func swiftFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("swift", Self.swiftSource).expect(token)
    }

    @Test
    func swiftTokenRangesAreWellFormed() {
        SyntaxProbe("swift", Self.swiftSource).expectWellFormed()
    }

    private static let swiftRegexSource = "let r = #/a+b/# // tail"

    private static let swiftRegexTokens = [
        TokenCase("#/a+b/#", .regex),
        TokenCase("// tail", .comment),
    ]

    @Test(arguments: swiftRegexTokens)
    func swiftRegexFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("swift", Self.swiftRegexSource).expect(token)
    }

    private static let javaSource = """
        @Override
        public static final long ID = 42L;
        String block = \"\"\"
            Hello "text" block
            \"\"\";
        char c = '\\'';
        if (list instanceof ArrayList<?> a) System.out.println(a.size());
        """

    private static let javaTokens = [
        TokenCase("@Override", .attribute),
        TokenCase("public", .keyword),
        TokenCase("long", .type),
        TokenCase("ID", .constant),
        TokenCase("42L", .number),
        TokenCase("Hello \"text\" block", .string),
        TokenCase("'", .string, 3),
        TokenCase("instanceof", .keyword),
        TokenCase("ArrayList", .type),
        TokenCase("println", .function),
    ]

    @Test(arguments: javaTokens)
    func javaFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("java", Self.javaSource).expect(token)
    }

    @Test
    func javaTokenRangesAreWellFormed() {
        SyntaxProbe("java", Self.javaSource).expectWellFormed()
    }

    private static let kotlinSource = """
        data class User(val name: String) {
            /* a /* nested */ b */
            fun greet() = "Hi $name, ${name.length} chars"
            val raw = \"\"\"C:\\no\\escape $name\"\"\"
        }
        """

    private static let kotlinTokens = [
        TokenCase("data", .keyword),
        TokenCase("User", .type),
        TokenCase("val", .keyword),
        TokenCase("/* a /* nested */ b */", .comment),
        TokenCase("greet", .function),
        TokenCase("\"Hi ", .string),
        TokenCase("$name", .variable),
        TokenCase("${", .punctuation),
        TokenCase("length", .property),
        TokenCase("\"\"\"C:\\no\\escape ", .string),
        TokenCase("$name", .variable, 2),
    ]

    @Test(arguments: kotlinTokens)
    func kotlinFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("kotlin", Self.kotlinSource).expect(token)
    }

    @Test
    func kotlinTokenRangesAreWellFormed() {
        SyntaxProbe("kotlin", Self.kotlinSource).expectWellFormed()
    }

    private static let scalaSource = """
        case class Point(x: Int, y: Int)
        object Main extends App {
          val msg = s"Point at $x and ${x + 1}"
          def show(p: Point): String = raw"\\d+"
          /* outer /* inner */ */
        }
        """

    private static let scalaTokens = [
        TokenCase("case", .keyword),
        TokenCase("Point", .type),
        TokenCase("object", .keyword),
        TokenCase("Main", .type),
        TokenCase("s\"Point at ", .string),
        TokenCase("$x", .variable),
        TokenCase("1", .number),
        TokenCase("show", .function),
        TokenCase("raw\"\\d+\"", .string),
        TokenCase("/* outer /* inner */ */", .comment),
    ]

    @Test(arguments: scalaTokens)
    func scalaFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("scala", Self.scalaSource).expect(token)
    }

    @Test
    func scalaTokenRangesAreWellFormed() {
        SyntaxProbe("scala", Self.scalaSource).expectWellFormed()
    }

    private static let dartSource = """
        @override
        Widget build(BuildContext context) {
          final name = 'Parc';
          return Text("Hi $name ${name.length}", style: r'raw $x');
        }
        """

    private static let dartTokens = [
        TokenCase("@override", .attribute),
        TokenCase("Widget", .type),
        TokenCase("build", .function),
        TokenCase("final", .keyword),
        TokenCase("'Parc'", .string),
        TokenCase("$name", .variable),
        TokenCase("length", .property),
        TokenCase("r'raw $x'", .string),
    ]

    @Test(arguments: dartTokens)
    func dartFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("dart", Self.dartSource).expect(token)
    }

    @Test
    func dartTokenRangesAreWellFormed() {
        SyntaxProbe("dart", Self.dartSource).expectWellFormed()
    }
}
