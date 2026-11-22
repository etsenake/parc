import Foundation
import Testing
@testable import ParcCore

struct NoteSyntaxCodeTestsShellTests {
    typealias TokenCase = NoteSyntaxCodeTestsSupport.TokenCase
    private typealias SyntaxProbe = NoteSyntaxCodeTestsSupport.SyntaxProbe

    private static let bashSource = """
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
        \tvalue=$HOME
        \tEOT
        for f in *.txt; do git add "$f"; done
        echo url#fragment
        """

    private static let bashTokens = [
        TokenCase("#!/usr/bin/env bash", .comment),
        TokenCase("set", .builtin),
        TokenCase("NAME", .variable),
        TokenCase("\"world\"", .string),
        TokenCase("# greet", .comment),
        TokenCase("if", .keyword),
        TokenCase("$NAME", .variable),
        TokenCase("then", .keyword),
        TokenCase("echo", .builtin),
        TokenCase("${NAME:-you}", .variable),
        TokenCase("$(", .punctuation),
        TokenCase("date", .function),
        TokenCase("whoami", .function),
        TokenCase("tee", .function),
        TokenCase("'EOF'", .string),
        TokenCase("literal $NOT_EXPANDED", .string),
        TokenCase("$HOME", .variable),
        TokenCase("for", .keyword),
        TokenCase("git", .function),
        TokenCase("add", nil),
        TokenCase("done", .keyword),
        TokenCase("url#fragment", nil),
        TokenCase("#fragment", nil),
    ]

    @Test(arguments: bashTokens)
    func bashFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("bash", Self.bashSource).expect(token)
    }

    @Test
    func bashTokenRangesAreWellFormed() {
        SyntaxProbe("bash", Self.bashSource).expectWellFormed()
    }

    private static let powerShellSource = """
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
        """

    private static let powerShellTokens = [
        TokenCase("<# block\n   comment #>", .comment),
        TokenCase("function", .keyword),
        TokenCase("Get-Greeting", .function),
        TokenCase("string", .type),
        TokenCase("$Name", .variable),
        TokenCase("'World'", .string),
        TokenCase("$env:PATH", .variable),
        TokenCase("-split", .operatorSymbol),
        TokenCase("$_", .variable),
        TokenCase("-like", .operatorSymbol),
        TokenCase("Write-Host", .function),
        TokenCase("$(", .punctuation),
        TokenCase("Get-Date", .function),
        TokenCase("`n", .escape),
        TokenCase("-ForegroundColor", .attribute),
        TokenCase("$true", .constant),
        TokenCase("Here ", .string),
        TokenCase("$Name", .variable, 3),
    ]

    @Test(arguments: powerShellTokens)
    func powerShellFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("powershell", Self.powerShellSource).expect(token)
    }

    @Test
    func powerShellTokenRangesAreWellFormed() {
        SyntaxProbe("powershell", Self.powerShellSource).expectWellFormed()
    }
}
