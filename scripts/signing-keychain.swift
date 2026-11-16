import Foundation
import Security

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8)); exit(1)
}
guard let request = (try? JSONSerialization.jsonObject(with: FileHandle.standardInput.readDataToEndOfFile())) as? [String: String] else { fail("Invalid credential request") }
guard let password = request["password"], password.count >= 32 else { fail("Use a strong PKCS12 password") }
var parameters = SecItemImportExportKeyParameters()
parameters.version = UInt32(SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION)
let passphrase = password as CFString
parameters.passphrase = Unmanaged.passUnretained(passphrase)
if CommandLine.arguments[1] == "export" {
    guard let name = request["identity"], name.hasPrefix("Developer ID Application: "), name.hasSuffix("(94HKA7L2DR)") else { fail("Wrong production identity") }
    var items: CFTypeRef?
    let query = [kSecClass: kSecClassIdentity, kSecMatchLimit: kSecMatchLimitAll, kSecReturnRef: true] as CFDictionary
    let status = SecItemCopyMatching(query, &items)
    guard status == errSecSuccess, let identities = items as? [SecIdentity] else { fail("Identity lookup failed: \(status)") }
    var selected: SecIdentity?
    for identity in identities {
        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let cert = certificate else { continue }
        var common: CFString?
        if SecCertificateCopyCommonName(cert, &common) == errSecSuccess, common as String? == name {
            if selected != nil { fail("Ambiguous identity; no private keys exported") }
            selected = identity
        }
    }
    guard let identity = selected else { fail("Selected identity/private key missing") }
    var exported: CFData?
    let result = SecItemExport(identity, .formatPKCS12, [], &parameters, &exported)
    guard result == errSecSuccess, let data = exported as Data? else { fail("Selected key export failed: \(result); normal Keychain approval may be required") }
    print(data.base64EncodedString())
} else if CommandLine.arguments[1] == "import" {
    guard let encoded = request["pkcs12"], let data = Data(base64Encoded: encoded) else { fail("Missing encrypted PKCS12") }
    var items: CFArray?
    let result = SecPKCS12Import(data as CFData, [kSecImportExportPassphrase: passphrase] as CFDictionary, &items)
    guard result != errSecNoDefaultKeychain else { fail("Default login Keychain unavailable: \(result)") }
    guard result == errSecSuccess || result == errSecDuplicateItem else { fail("Selected key import failed: \(result)") }
    print("Imported selected production identity")
} else { fail("Use export or import") }
