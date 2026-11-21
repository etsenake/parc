import Foundation
import Security

package enum ICloudPasswordsSupport {
    package enum Helper: Equatable {
        case unrestricted
        case restricted(Data)
    }

    package struct Signer {
        package var identifier: String?
        package var team: String?
        package var entitlements: [String: Any] = [:]

        package static var current: Signer {
            var code: SecCode?
            var staticCode: SecStaticCode?
            var information: CFDictionary?
            guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
                  SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
                  SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation),
                                                &information) == errSecSuccess,
                  let values = information as? [String: Any] else { return Signer() }
            return Signer(identifier: values[kSecCodeInfoIdentifier as String] as? String,
                          team: values[kSecCodeInfoTeamIdentifier as String] as? String,
                          entitlements: values[kSecCodeInfoEntitlementsDict as String] as? [String: Any] ?? [:])
        }
    }

    package static let manifest = URL(fileURLWithPath: "/Library/Google/Chrome/NativeMessagingHosts/com.apple.passwordmanager.json")
    package static let systemHelper = URL(fileURLWithPath:
        "/System/Cryptexes/App/System/Library/CoreServices/PasswordManagerBrowserExtensionHelper.app/Contents/MacOS/PasswordManagerBrowserExtensionHelper")

    package static func connects() -> Bool {
        connects(helper: installedHelper(), signer: .current, on: ProcessInfo.processInfo.operatingSystemVersion)
    }

    package static func connects(helper: Helper?, signer: @autoclosure () -> Signer, on version: OperatingSystemVersion) -> Bool {
        let release = (version.majorVersion, version.minorVersion)
        guard release >= (14, 0) else { return false }
        switch helper {
        case .unrestricted: return true
        case .restricted(let constraint):
            if let admitted = LaunchConstraint(constraint)?.admits(signer()) { return admitted }
        case nil: break
        }
        return release < (15, 5)
    }

    package static func installedHelper(manifest: URL = manifest, fallback: URL = systemHelper) -> Helper? {
        let named = (try? Data(contentsOf: manifest))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            .flatMap { $0["path"] as? String }
            .map { URL(fileURLWithPath: $0) }
        for candidate in [named, fallback].compactMap({ $0 }) {
            if let file = try? Data(contentsOf: candidate, options: .alwaysMapped),
               let helper = parentConstraint(in: file) { return helper }
        }
        return nil
    }

    package static func parentConstraint(in file: Data) -> Helper? {
        func word(_ offset: Int, bigEndian: Bool = false) -> Int? {
            guard offset >= 0, offset <= file.count - 4 else { return nil }
            let raw = file.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
            return Int(bigEndian ? UInt32(bigEndian: raw) : UInt32(littleEndian: raw))
        }
        func slice(at base: Int) -> Helper? {
            guard word(base) == 0xfeedfacf, let commands = word(base + 16) else { return nil }
            var cursor = base + 32
            for _ in 0..<min(commands, 4096) {
                guard let command = word(cursor), let size = word(cursor + 4), size >= 8 else { return nil }
                if command == 0x1d, let offset = word(cursor + 8) { return signature(at: base + offset) }
                cursor += size
            }
            return nil
        }
        func signature(at start: Int) -> Helper? {
            guard word(start, bigEndian: true) == 0xfade0cc0, let count = word(start + 8, bigEndian: true),
                  count <= 64 else { return nil }
            for index in 0..<count {
                guard let slot = word(start + 12 + index * 8, bigEndian: true),
                      let offset = word(start + 16 + index * 8, bigEndian: true) else { return nil }
                guard slot == 9 else { continue }
                let blob = start + offset
                guard word(blob, bigEndian: true) == 0xfade8181, let length = word(blob + 4, bigEndian: true),
                      length >= 8, blob + length <= file.count else { return nil }
                return .restricted(file.subdata(in: file.startIndex + blob + 8 ..< file.startIndex + blob + length))
            }
            return .unrestricted
        }
        guard let magic = word(0, bigEndian: true) else { return nil }
        guard magic == 0xcafebabe || magic == 0xcafebabf else { return slice(at: 0) }
        let wide = magic == 0xcafebabf
        guard let count = word(4, bigEndian: true) else { return nil }
        for index in 0..<min(count, 16) {
            let entry = 8 + index * (wide ? 32 : 20)
            guard !wide || word(entry + 8, bigEndian: true) == 0,
                  let offset = word(entry + (wide ? 12 : 8), bigEndian: true) else { continue }
            if let helper = slice(at: offset) { return helper }
        }
        return nil
    }

    package struct LaunchConstraint {
        package struct Term {
            package let key: String
            package let value: Value
        }
        package enum Value {
            case integer(Int)
            case boolean(Bool)
            case string(String)
            case array([Value])
            case dictionary([Term])
        }
        package let requirements: [Term]

        package init?(_ der: Data) {
            let bytes = [UInt8](der)
            var index = 0
            guard case .array(let root)? = Self.value(bytes, &index, limit: bytes.count, depth: 0), index == bytes.count,
                  root.count == 2, case .dictionary(let top) = root[1],
                  case .dictionary(let requirements)? = top.first(where: { $0.key == "reqs" })?.value else { return nil }
            self.requirements = requirements
        }

        package func admits(_ signer: Signer) -> Bool? { Self.all(requirements, signer) }

        private static func value(_ bytes: [UInt8], _ index: inout Int, limit: Int, depth: Int) -> Value? {
            guard depth < 32, index + 2 <= limit else { return nil }
            let tag = bytes[index]
            var length = Int(bytes[index + 1])
            index += 2
            if length & 0x80 != 0 {
                let count = length & 0x7f
                guard (1...4).contains(count), index + count <= limit else { return nil }
                length = bytes[index..<index + count].reduce(0) { $0 << 8 | Int($1) }
                index += count
            }
            guard length <= limit - index else { return nil }
            let start = index, end = index + length
            index = end
            switch tag {
            case 0x01:
                return length == 1 ? .boolean(bytes[start] != 0) : nil
            case 0x02:
                guard (1...7).contains(length) else { return nil }
                let magnitude = bytes[start..<end].reduce(0) { $0 << 8 | Int($1) }
                return .integer(bytes[start] & 0x80 == 0 ? magnitude : magnitude - 1 << (8 * length))
            case 0x0c:
                return String(bytes: bytes[start..<end], encoding: .utf8).map(Value.string)
            case 0x30, 0x70, 0xb0:
                var items: [Value] = []
                var cursor = start
                while cursor < end {
                    guard let item = value(bytes, &cursor, limit: end, depth: depth + 1) else { return nil }
                    items.append(item)
                }
                guard tag == 0xb0 else { return .array(items) }
                return pairs(.array(items)).map(Value.dictionary)
            default:
                return nil
            }
        }

        private static func pairs(_ value: Value) -> [Term]? {
            guard case .array(let items) = value else { return nil }
            var pairs: [Term] = []
            for item in items {
                guard case .array(let pair) = item, pair.count == 2, case .string(let key) = pair[0] else { return nil }
                pairs.append(Term(key: key, value: pair[1]))
            }
            return pairs
        }

        private static func all(_ terms: [Term], _ signer: Signer) -> Bool? {
            var result: Bool? = true
            for term in terms {
                switch evaluate(term, signer) {
                case false?: return false
                case nil: result = nil
                case true?: continue
                }
            }
            return result
        }

        private static func any(_ terms: [Term], _ signer: Signer) -> Bool? {
            var result: Bool? = false
            for term in terms {
                switch evaluate(term, signer) {
                case true?: return true
                case nil: result = nil
                case false?: continue
                }
            }
            return result
        }

        private static func evaluate(_ term: Term, _ signer: Signer) -> Bool? {
            switch (term.key, term.value) {
            case ("$or", .dictionary(let terms)): return any(terms, signer)
            case ("$and", .dictionary(let terms)): return all(terms, signer)
            case ("$or-array", let value): return pairs(value).flatMap { any($0, signer) }
            case ("$and-array", let value): return pairs(value).flatMap { all($0, signer) }
            case ("signing-identifier", let value): return matches(signer.identifier, value)
            case ("team-identifier", let value): return matches(signer.team, value)
            case ("entitlements", let value): return query(signer.entitlements, value)
            default: return nil
            }
        }

        private static func matches(_ fact: String?, _ value: Value) -> Bool? {
            switch value {
            case .string(let expected): return fact == expected
            case .dictionary(let operators):
                guard operators.count == 1, operators[0].key == "$in", case .array(let options) = operators[0].value else { return nil }
                let names = options.compactMap { option -> String? in
                    if case .string(let name) = option { return name }
                    return nil
                }
                guard names.count == options.count else { return nil }
                return fact.map(names.contains) ?? false
            default: return nil
            }
        }

        private static func query(_ entitlements: [String: Any], _ value: Value) -> Bool? {
            guard case .dictionary(let operators) = value, operators.count == 1, operators[0].key == "$query",
                  case .array(let steps) = operators[0].value else { return nil }
            var current: Any = entitlements
            for step in steps {
                guard case .array(let parts) = step, parts.count == 2, case .integer(let operation) = parts[0] else { return nil }
                switch (operation, parts[1]) {
                case (1, .string(let key)):
                    guard let next = (current as? [String: Any])?[key] else { return false }
                    current = next
                case (5, .boolean(let expected)):
                    guard (current as? Bool) == expected else { return false }
                default: return nil
                }
            }
            return true
        }
    }
}
