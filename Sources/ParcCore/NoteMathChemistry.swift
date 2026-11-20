import Foundation

enum NoteMathChemistry {
    private static let arrows: [(text: String, command: String)] = [
        ("<=>>", "xrightequilibrium"), ("<<=>", "xleftequilibrium"), ("<-->", "xrightleftarrows"),
        ("<=>", "xrightleftharpoons"), ("<->", "xleftrightarrow"), ("->", "xrightarrow"), ("<-", "xleftarrow"),
        ("\u{2192}", "xrightarrow"), ("\u{27F6}", "xrightarrow"), ("\u{2190}", "xleftarrow"),
        ("\u{2194}", "xleftrightarrow"), ("\u{21CC}", "xrightleftharpoons"), ("\u{21C4}", "xrightleftarrows"),
    ]

    static func formula(_ text: String) throws(NoteMathParseError) -> String {
        var scanner = Scanner(Array(text))
        return try scanner.formula()
    }

    static func units(_ text: String) throws(NoteMathParseError) -> String {
        var scanner = Scanner(Array(text))
        return try scanner.physicalUnits()
    }

    private struct Scanner {
        let characters: [Character]
        var index = 0

        init(_ characters: [Character]) {
            self.characters = characters
        }

        var atEnd: Bool { index >= characters.count }

        func peek(_ offset: Int = 0) -> Character? {
            index + offset < characters.count ? characters[index + offset] : nil
        }

        func failure(_ message: String) -> NoteMathParseError {
            NoteMathParseError(message: message, offset: 0, length: 0)
        }

        func isBoundary(_ offset: Int) -> Bool {
            guard let character = peek(offset) else { return true }
            return character.isWhitespace
        }

        func arrow(at position: Int) -> (text: String, command: String)? {
            for candidate in NoteMathChemistry.arrows {
                let length = candidate.text.count
                guard position + length <= characters.count else { continue }
                if String(characters[position..<(position + length)]) == candidate.text { return candidate }
            }
            return nil
        }

        mutating func balanced(open: Character, close: Character) throws(NoteMathParseError) -> String {
            let start = index
            var depth = 0
            while index < characters.count {
                let character = characters[index]
                if character == "\\", index + 1 < characters.count {
                    index += 2
                    continue
                }
                if character == open { depth += 1 }
                if character == close {
                    depth -= 1
                    if depth == 0 {
                        index += 1
                        return String(characters[(start + 1)..<(index - 1)])
                    }
                }
                index += 1
            }
            throw failure(open == "{" ? "Missing } in this formula" : "Missing \(close) in this formula")
        }

        mutating func mathEscape() throws(NoteMathParseError) -> String {
            index += 1
            let start = index
            while index < characters.count, characters[index] != "$" { index += 1 }
            guard index < characters.count else { throw failure("Missing $ to close this $") }
            index += 1
            return "{" + String(characters[start..<(index - 1)]) + "}"
        }

        mutating func command() throws(NoteMathParseError) -> String {
            let start = index
            index += 1
            if index < characters.count, characters[index].isASCII, characters[index].isLetter {
                while index < characters.count, characters[index].isASCII, characters[index].isLetter { index += 1 }
            } else if index < characters.count {
                index += 1
            }
            var result = String(characters[start..<index])
            while peek() == "{" {
                result += "{" + (try balanced(open: "{", close: "}")) + "}"
            }
            return result + " "
        }

        mutating func formula() throws(NoteMathParseError) -> String {
            var parts: [String] = []
            var spaced = true
            while !atEnd {
                let character = characters[index]
                if character.isWhitespace {
                    index += 1
                    spaced = true
                    continue
                }
                defer { spaced = false }
                if let arrow = arrow(at: index) {
                    index += arrow.text.count
                    parts.append(try reactionArrow(arrow.command))
                    continue
                }
                if spaced, isBoundary(1) {
                    switch character {
                    case "+":
                        index += 1
                        parts.append("+")
                        continue
                    case "=":
                        index += 1
                        parts.append("=")
                        continue
                    case "v":
                        index += 1
                        parts.append("\\mathrel{\\downarrow}")
                        continue
                    case "^":
                        index += 1
                        parts.append("\\mathrel{\\uparrow}")
                        continue
                    default:
                        break
                    }
                }
                if spaced, character.isLowercase, character.isASCII, isBoundary(1), character != "v" {
                    index += 1
                    parts.append(String(character) + "\\,")
                    continue
                }
                parts.append(try compound())
            }
            return parts.joined(separator: " ")
        }

        mutating func reactionArrow(_ command: String) throws(NoteMathParseError) -> String {
            var above = ""
            var below: String?
            if peek() == "[" {
                above = try NoteMathChemistry.formula(try balanced(open: "[", close: "]"))
                if peek() == "[" { below = try NoteMathChemistry.formula(try balanced(open: "[", close: "]")) }
            }
            let under = below.map { "[{" + $0 + "}]" } ?? ""
            return "\\" + command + under + "{" + above + "}"
        }

        mutating func coefficient() -> String? {
            let start = index
            var cursor = index
            var digits = ""
            while cursor < characters.count, characters[cursor].isASCII,
                  characters[cursor].isNumber || ((characters[cursor] == "." || characters[cursor] == "/") && cursor > start
                                                  && cursor + 1 < characters.count && characters[cursor + 1].isNumber) {
                digits.append(characters[cursor])
                cursor += 1
            }
            guard !digits.isEmpty else { return nil }
            index = cursor
            let pieces = digits.split(separator: "/", maxSplits: 1)
            if pieces.count == 2 { return "\\tfrac{\(pieces[0])}{\(pieces[1])}" }
            return digits
        }

        func stateEnd(from position: Int) -> Int? {
            guard position < characters.count, characters[position] == "(" else { return nil }
            var cursor = position + 1
            guard cursor < characters.count, characters[cursor].isLowercase else { return nil }
            while cursor < characters.count, characters[cursor] != ")" {
                if characters[cursor].isUppercase || characters[cursor] == "(" { return nil }
                cursor += 1
            }
            guard cursor < characters.count else { return nil }
            let after = cursor + 1
            if after < characters.count, !characters[after].isWhitespace, !"^+-".contains(characters[after]) { return nil }
            return cursor
        }

        mutating func prescripts() throws(NoteMathParseError) -> String {
            var upper = ""
            var lower = ""
            while let mark = peek(), mark == "^" || mark == "_" {
                index += 1
                let content = try scriptContent()
                if mark == "^" { upper = content } else { lower = content }
            }
            return "{}^{\\hphantom{" + upper + "}}_{\\hphantom{" + lower + "}}{}^{\\mathllap{" + upper + "}}_{\\mathllap{" + lower + "}}"
        }

        mutating func scriptContent() throws(NoteMathParseError) -> String {
            if peek() == "{" { return superscriptText(try balanced(open: "{", close: "}")) }
            var run = ""
            while let character = peek(), character.isNumber || "+-".contains(character)
                    || (run.isEmpty && (character.isLetter || character == ".")) {
                run.append(character)
                index += 1
                if character.isLetter || character == "." { break }
            }
            if run.isEmpty, let character = peek() {
                index += 1
                run = String(character)
            }
            return superscriptText(run)
        }

        func superscriptText(_ text: String) -> String {
            var result = ""
            var letters = ""
            func flush() {
                if !letters.isEmpty { result += "\\mathrm{" + letters + "}" }
                letters = ""
            }
            var characters = Array(text)[...]
            while let character = characters.first {
                characters = characters.dropFirst()
                if character == "\\" {
                    flush()
                    var name = "\\"
                    while let next = characters.first, next.isASCII, next.isLetter {
                        name.append(next)
                        characters = characters.dropFirst()
                    }
                    if name == "\\", let next = characters.first {
                        name.append(next)
                        characters = characters.dropFirst()
                    }
                    result += name + " "
                } else if character.isLetter {
                    letters.append(character)
                } else {
                    flush()
                    switch character {
                    case ".", "*": result += "\\cdot "
                    case "{", "}": result.append(character)
                    default: result.append(character)
                    }
                }
            }
            flush()
            return result
        }

        mutating func compound() throws(NoteMathParseError) -> String {
            var output = ""
            var canTakeScripts = false
            if let amount = coefficient() {
                output += amount
                if atEnd || characters[index].isWhitespace { return output }
            }
            if peek() == "^" || peek() == "_" {
                output += try prescripts()
            } else if peek() == "{", peek(1) == "}", let mark = peek(2), mark == "^" || mark == "_" {
                index += 2
                output += try prescripts()
            }
            while let character = peek(), !character.isWhitespace {
                if arrow(at: index) != nil { break }
                if character.isUppercase && character.isLetter {
                    var element = String(character)
                    index += 1
                    while let next = peek(), next.isLowercase, next.isLetter {
                        element.append(next)
                        index += 1
                    }
                    output += "\\mathrm{" + element + "}"
                    canTakeScripts = true
                } else if character.isLetter {
                    var letters = String(character)
                    index += 1
                    while let next = peek(), next.isLowercase, next.isLetter {
                        letters.append(next)
                        index += 1
                    }
                    output += "\\mathrm{" + letters + "}"
                    canTakeScripts = true
                } else if character.isNumber {
                    var digits = ""
                    while let next = peek(), next.isNumber {
                        digits.append(next)
                        index += 1
                    }
                    output += canTakeScripts ? "_{" + digits + "}" : digits
                } else {
                    switch character {
                    case "(":
                        if let end = stateEnd(from: index) {
                            output += "\\mathrm{(" + String(characters[(index + 1)..<end]) + ")}"
                            index = end + 1
                            canTakeScripts = false
                        } else {
                            output += "("
                            index += 1
                            canTakeScripts = false
                        }
                    case ")":
                        output += ")"
                        index += 1
                        canTakeScripts = true
                    case "[":
                        output += "\\lbrack "
                        index += 1
                        canTakeScripts = false
                    case "]":
                        output += "\\rbrack "
                        index += 1
                        canTakeScripts = true
                    case "^":
                        index += 1
                        output += "^{" + (try scriptContent()) + "}"
                    case "_":
                        index += 1
                        output += "_{" + (try scriptContent()) + "}"
                    case "+", "-":
                        let next = peek(1)
                        let bond = character == "-" && next.map { $0.isLetter || $0.isNumber || "([{\\$".contains($0) } == true
                        if bond {
                            output += "{-}"
                            index += 1
                        } else {
                            var charge = ""
                            while let mark = peek(), mark == "+" || mark == "-" {
                                charge.append(mark)
                                index += 1
                            }
                            output += "^{" + charge + "}"
                        }
                    case "=":
                        output += "{=}"
                        index += 1
                    case "#":
                        output += "{\\equiv}"
                        index += 1
                    case ".", "*", "\u{00B7}", "\u{22C5}":
                        index += 1
                        output += "\\,{\\cdot}\\,"
                        if let amount = coefficient() { output += amount }
                        canTakeScripts = false
                    case "$":
                        output += try mathEscape()
                        canTakeScripts = true
                    case "{":
                        output += "{" + (try balanced(open: "{", close: "}")) + "}"
                        canTakeScripts = true
                    case "\\":
                        output += try command()
                        canTakeScripts = true
                    case "&", "%", "~":
                        output += "\\" + String(character)
                        index += 1
                    case "'":
                        output += "'"
                        index += 1
                    default:
                        output.append(character)
                        index += 1
                    }
                }
            }
            return output
        }

        mutating func physicalUnits() throws(NoteMathParseError) -> String {
            while let character = peek(), character.isWhitespace { index += 1 }
            let number = try quantity()
            while let character = peek(), character.isWhitespace { index += 1 }
            let unit = try unitExpression()
            if number.isEmpty { return unit }
            return unit.isEmpty ? number : number + "~" + unit
        }

        func grouped(_ digits: String, fromLeft: Bool) -> String {
            guard digits.count >= 5 else { return digits }
            var groups: [String] = []
            var characters = Array(digits)
            if fromLeft {
                while !characters.isEmpty {
                    groups.append(String(characters.prefix(3)))
                    characters = Array(characters.dropFirst(3))
                }
            } else {
                while !characters.isEmpty {
                    groups.insert(String(characters.suffix(3)), at: 0)
                    characters = Array(characters.dropLast(3))
                }
            }
            return groups.joined(separator: "\\,")
        }

        mutating func plainNumber() -> String? {
            var integer = ""
            var fraction: String?
            while let character = peek(), character.isASCII, character.isNumber {
                integer.append(character)
                index += 1
            }
            if let mark = peek(), mark == "." || mark == ",", let next = peek(1), next.isASCII, next.isNumber {
                index += 1
                var digits = ""
                while let character = peek(), character.isASCII, character.isNumber {
                    digits.append(character)
                    index += 1
                }
                fraction = digits
            }
            guard !integer.isEmpty || fraction != nil else { return nil }
            var result = grouped(integer.isEmpty ? "0" : integer, fromLeft: false)
            if let fraction { result += "." + grouped(fraction, fromLeft: true) }
            return result
        }

        mutating func quantity() throws(NoteMathParseError) -> String {
            let start = index
            var result = ""
            if let sign = peek(), sign == "-" || sign == "+" || sign == "\u{2212}", let next = peek(1), next.isNumber || next == "." {
                result = sign == "+" ? "+" : "-"
                index += 1
            }
            guard let mantissa = plainNumber() else {
                index = start
                return ""
            }
            result += mantissa
            if peek() == "+", peek(1) == "-" {
                index += 2
                if let error = plainNumber() { result += "\\pm " + error }
            } else if peek() == "\u{00B1}" {
                index += 1
                if let error = plainNumber() { result += "\\pm " + error }
            }
            if let mark = peek(), mark == "e" || mark == "E",
               let next = peek(1), next.isNumber || ((next == "-" || next == "+") && peek(2)?.isNumber == true) {
                index += 1
                var exponent = ""
                if let sign = peek(), sign == "-" || sign == "+" {
                    if sign == "-" { exponent = "-" }
                    index += 1
                }
                while let character = peek(), character.isNumber {
                    exponent.append(character)
                    index += 1
                }
                result += (mark == "e" ? "\\cdot " : "\\times ") + "10^{" + exponent + "}"
            }
            return result
        }

        mutating func unitExpression() throws(NoteMathParseError) -> String {
            var numerator: [String] = []
            var denominator: [String]?
            var pendingSeparator: String?
            while !atEnd {
                let character = characters[index]
                if character.isWhitespace {
                    index += 1
                    if pendingSeparator == nil { pendingSeparator = "\\," }
                    continue
                }
                if character == "/", peek(1) == "/" {
                    index += 2
                    denominator = []
                    pendingSeparator = nil
                    continue
                }
                var separator: String?
                switch character {
                case "/":
                    separator = "/"
                case "*", ".", "\u{00B7}", "\u{22C5}":
                    separator = "\\cdot "
                default:
                    break
                }
                if let separator {
                    index += 1
                    pendingSeparator = separator
                    continue
                }
                let factor = try unitFactor()
                if denominator != nil {
                    if let separator = pendingSeparator, !denominator!.isEmpty { denominator!.append(separator) }
                    denominator!.append(factor)
                } else {
                    if let separator = pendingSeparator, !numerator.isEmpty { numerator.append(separator) }
                    numerator.append(factor)
                }
                pendingSeparator = nil
            }
            let top = numerator.joined()
            guard let denominator else { return top }
            return "\\frac{" + (top.isEmpty ? "1" : top) + "}{" + denominator.joined() + "}"
        }

        mutating func unitFactor() throws(NoteMathParseError) -> String {
            var base = ""
            var letters = ""
            func flush() {
                if !letters.isEmpty { base += "\\mathrm{" + letters + "}" }
                letters = ""
            }
            while let character = peek(), !character.isWhitespace, !"/*.\u{00B7}\u{22C5}^".contains(character),
                  !(character.isNumber || ((character == "-" || character == "+") && peek(1)?.isNumber == true)) {
                switch character {
                case "\u{00B0}":
                    flush()
                    base += "{}^{\\circ}"
                case "%":
                    flush()
                    base += "\\%"
                case "\u{00B5}", "\u{03BC}":
                    flush()
                    base += "\\mu "
                case "\u{2126}", "\u{03A9}":
                    flush()
                    base += "\\Omega "
                case "\\":
                    flush()
                    base += try command()
                    continue
                case "$":
                    flush()
                    base += try mathEscape()
                    continue
                case "{":
                    flush()
                    base += "{" + (try balanced(open: "{", close: "}")) + "}"
                    continue
                default:
                    if character.isLetter || character == "\u{00C5}" {
                        letters.append(character)
                    } else {
                        flush()
                        base.append(character)
                    }
                }
                index += 1
            }
            flush()
            var exponent: String?
            if peek() == "^" {
                index += 1
                if peek() == "{" {
                    exponent = try balanced(open: "{", close: "}")
                } else {
                    var digits = ""
                    if let sign = peek(), sign == "-" || sign == "+" {
                        digits.append(sign)
                        index += 1
                    }
                    while let character = peek(), character.isNumber {
                        digits.append(character)
                        index += 1
                    }
                    exponent = digits
                }
            } else if let character = peek(), character.isNumber || character == "-" || character == "+" {
                var digits = ""
                if character == "-" || character == "+" {
                    digits.append(character)
                    index += 1
                }
                while let next = peek(), next.isNumber {
                    digits.append(next)
                    index += 1
                }
                exponent = digits
            }
            if base.isEmpty {
                guard let exponent, !exponent.isEmpty else {
                    if let character = peek() {
                        index += 1
                        return String(character)
                    }
                    return ""
                }
                return exponent
            }
            if let exponent, !exponent.isEmpty { return base + "^{" + exponent + "}" }
            return base
        }
    }
}
