import Foundation

enum ICloudPasswordsSupport {
    static func connects(on version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> Bool {
        let release = (version.majorVersion, version.minorVersion)
        return release >= (14, 0) && release < (15, 5)
    }
}
