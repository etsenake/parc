import Foundation

package enum NoteHTMLEntities {
    package static func decode(_ scalars: ArraySlice<Unicode.Scalar>, attribute: Bool = false) -> String {
        var result = String.UnicodeScalarView()
        guard scalars.contains("&") else {
            result.append(contentsOf: scalars)
            return String(result)
        }
        var index = scalars.startIndex
        while index < scalars.endIndex {
            let scalar = scalars[index]
            if scalar == "&", let (value, length) = reference(at: index, in: scalars, attribute: attribute) {
                result.append(contentsOf: value.unicodeScalars)
                index += length
            } else {
                result.append(scalar)
                index += 1
            }
        }
        return String(result)
    }

    package static func decode(_ string: String) -> String {
        decode(ArraySlice(Array(string.unicodeScalars)))
    }

    private static func isAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        return (value >= 48 && value <= 57) || (value >= 65 && value <= 90) || (value >= 97 && value <= 122)
    }

    private static func digit(_ scalar: Unicode.Scalar, hex: Bool) -> UInt32? {
        let value = scalar.value
        if value >= 48 && value <= 57 { return value - 48 }
        guard hex else { return nil }
        if value >= 65 && value <= 70 { return value - 55 }
        if value >= 97 && value <= 102 { return value - 87 }
        return nil
    }

    private static func reference(at index: Int, in scalars: ArraySlice<Unicode.Scalar>, attribute: Bool) -> (String, Int)? {
        let start = index + 1
        guard start < scalars.endIndex else { return nil }
        if scalars[start] == "#" {
            var cursor = start + 1
            var hex = false
            if cursor < scalars.endIndex, scalars[cursor] == "x" || scalars[cursor] == "X" {
                hex = true
                cursor += 1
            }
            let digitsStart = cursor
            var value: UInt32 = 0
            while cursor < scalars.endIndex, let next = digit(scalars[cursor], hex: hex) {
                value = min(value &* (hex ? 16 : 10) &+ next, 0x110000)
                cursor += 1
            }
            guard cursor > digitsStart else { return nil }
            if cursor < scalars.endIndex, scalars[cursor] == ";" { cursor += 1 }
            return (String(Character(numeric(value))), cursor - index)
        }
        var cursor = start
        var name = String.UnicodeScalarView()
        while cursor < scalars.endIndex, cursor - start < 32, isAlphanumeric(scalars[cursor]) {
            name.append(scalars[cursor])
            cursor += 1
        }
        guard !name.isEmpty else { return nil }
        let full = String(name)
        if cursor < scalars.endIndex, scalars[cursor] == ";", let value = named[full] {
            return (value, cursor + 1 - index)
        }
        let characters = Array(full)
        for length in stride(from: min(characters.count, 6), through: 2, by: -1) {
            let prefix = String(characters[0..<length])
            guard legacy.contains(prefix), let value = named[prefix] else { continue }
            let after = start + length
            if attribute, after < scalars.endIndex, isAlphanumeric(scalars[after]) || scalars[after] == "=" { return nil }
            return (value, 1 + length)
        }
        return nil
    }

    private static func numeric(_ value: UInt32) -> Unicode.Scalar {
        if value == 0 || value > 0x10FFFF || (0xD800...0xDFFF).contains(value) { return "\u{FFFD}" }
        if (0x80...0x9F).contains(value), let mapped = windows1252[value] { return Unicode.Scalar(mapped)! }
        return Unicode.Scalar(value) ?? "\u{FFFD}"
    }

    private static let windows1252: [UInt32: UInt32] = [
        0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E, 0x85: 0x2026, 0x86: 0x2020, 0x87: 0x2021, 0x88: 0x02C6,
        0x89: 0x2030, 0x8A: 0x0160, 0x8B: 0x2039, 0x8C: 0x0152, 0x8E: 0x017D, 0x91: 0x2018, 0x92: 0x2019, 0x93: 0x201C,
        0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014, 0x98: 0x02DC, 0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A,
        0x9C: 0x0153, 0x9E: 0x017E, 0x9F: 0x0178
    ]

    private static let latin1Names = """
    nbsp iexcl cent pound curren yen brvbar sect uml copy ordf laquo not shy reg macr deg plusmn sup2 sup3 acute micro \
    para middot cedil sup1 ordm raquo frac14 frac12 frac34 iquest Agrave Aacute Acirc Atilde Auml Aring AElig Ccedil \
    Egrave Eacute Ecirc Euml Igrave Iacute Icirc Iuml ETH Ntilde Ograve Oacute Ocirc Otilde Ouml times Oslash Ugrave \
    Uacute Ucirc Uuml Yacute THORN szlig agrave aacute acirc atilde auml aring aelig ccedil egrave eacute ecirc euml \
    igrave iacute icirc iuml eth ntilde ograve oacute ocirc otilde ouml divide oslash ugrave uacute ucirc uuml yacute \
    thorn yuml
    """.split(separator: " ").map(String.init)

    private static let otherNames = """
    quot 34 amp 38 lt 60 gt 62 apos 39 QUOT 34 AMP 38 LT 60 GT 62 COPY 169 REG 174 TRADE 8482 \
    OElig 338 oelig 339 Scaron 352 scaron 353 Yuml 376 fnof 402 circ 710 tilde 732 \
    Alpha 913 Beta 914 Gamma 915 Delta 916 Epsilon 917 Zeta 918 Eta 919 Theta 920 Iota 921 Kappa 922 Lambda 923 \
    Mu 924 Nu 925 Xi 926 Omicron 927 Pi 928 Rho 929 Sigma 931 Tau 932 Upsilon 933 Phi 934 Chi 935 Psi 936 Omega 937 \
    alpha 945 beta 946 gamma 947 delta 948 epsilon 949 zeta 950 eta 951 theta 952 iota 953 kappa 954 lambda 955 \
    mu 956 nu 957 xi 958 omicron 959 pi 960 rho 961 sigmaf 962 sigma 963 tau 964 upsilon 965 phi 966 chi 967 psi 968 \
    omega 969 thetasym 977 upsih 978 piv 982 \
    ensp 8194 emsp 8195 emsp13 8196 emsp14 8197 numsp 8199 puncsp 8200 thinsp 8201 hairsp 8202 ZeroWidthSpace 8203 \
    zwnj 8204 zwj 8205 lrm 8206 rlm 8207 hyphen 8208 dash 8208 ndash 8211 mdash 8212 horbar 8213 lsquo 8216 \
    rsquo 8217 rsquor 8217 sbquo 8218 lsquor 8218 ldquo 8220 rdquo 8221 rdquor 8221 bdquo 8222 ldquor 8222 \
    dagger 8224 Dagger 8225 bull 8226 bullet 8226 nldr 8229 hellip 8230 mldr 8230 permil 8240 prime 8242 Prime 8243 \
    lsaquo 8249 rsaquo 8250 oline 8254 caret 8257 frasl 8260 MediumSpace 8287 NoBreak 8288 euro 8364 image 8465 \
    ell 8467 numero 8470 copysr 8471 weierp 8472 real 8476 trade 8482 ohm 937 angst 197 alefsym 8501 \
    frac13 8531 frac23 8532 frac15 8533 frac18 8539 \
    larr 8592 leftarrow 8592 uarr 8593 uparrow 8593 rarr 8594 rightarrow 8594 darr 8595 downarrow 8595 harr 8596 \
    crarr 8629 lArr 8656 uArr 8657 rArr 8658 dArr 8659 hArr 8660 \
    forall 8704 part 8706 exist 8707 empty 8709 nabla 8711 isin 8712 notin 8713 ni 8715 prod 8719 sum 8721 \
    minus 8722 setminus 8726 lowast 8727 radic 8730 prop 8733 infin 8734 ang 8736 and 8743 or 8744 cap 8745 \
    cup 8746 int 8747 there4 8756 sim 8764 cong 8773 asymp 8776 approx 8776 ap 8776 ne 8800 equiv 8801 le 8804 \
    ge 8805 lE 8806 gE 8807 sub 8834 sup 8835 nsub 8836 sube 8838 supe 8839 oplus 8853 otimes 8855 perp 8869 \
    sdot 8901 lceil 8968 rceil 8969 lfloor 8970 rfloor 8971 lang 10216 rang 10217 loz 9674 \
    spades 9824 clubs 9827 hearts 9829 diams 9830 starf 9733 bigstar 9733 star 9734 phone 9742 female 9792 \
    male 9794 flat 9837 natural 9838 sharp 9839 check 10003 checkmark 10003 cross 10007 \
    Tab 9 NewLine 10 excl 33 num 35 dollar 36 percnt 37 lpar 40 rpar 41 ast 42 plus 43 comma 44 period 46 sol 47 \
    colon 58 semi 59 equals 61 quest 63 commat 64 lsqb 91 lbrack 91 bsol 92 rsqb 93 rbrack 93 Hat 94 lowbar 95 \
    grave 96 lcub 123 lbrace 123 verbar 124 vert 124 rcub 125 rbrace 125 centerdot 183 half 189 pm 177 \
    PlusMinus 177 div 247
    """.split(separator: " ").map(String.init)

    package static let named: [String: String] = {
        var table: [String: String] = [:]
        for (offset, name) in latin1Names.enumerated() {
            table[name] = String(Character(Unicode.Scalar(UInt32(160 + offset))!))
        }
        var index = 0
        while index + 1 < otherNames.count {
            if let code = UInt32(otherNames[index + 1]), let scalar = Unicode.Scalar(code) {
                table[otherNames[index]] = String(Character(scalar))
            }
            index += 2
        }
        return table
    }()

    private static let legacy: Set<String> = Set(latin1Names).union(["amp", "lt", "gt", "quot", "AMP", "LT", "GT", "QUOT", "COPY", "REG"])

    package static var latin1Count: Int { latin1Names.count }
}
