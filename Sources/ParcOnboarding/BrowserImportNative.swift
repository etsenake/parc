import AppKit
import ParcCore
import ParcEngine

@MainActor
protocol BrowserImportNative: Sendable {
    func availableImportSources(completion: @escaping ([PCNativeImportSource]) -> Void) -> PCNativeImportDiscovery
    func loadImportSourceProfiles(_ source: PCNativeImportSource,
                                  completion: @escaping (PCNativeImportProfileResult) -> Void) -> PCNativeImportDiscovery
    func loadSafariExportProfiles(_ directories: [URL], names: [String],
                                  completion: @escaping (PCNativeImportProfileResult) -> Void) -> PCNativeImportDiscovery
    func importBrowserData(from profile: PCNativeImportProfile, toProfilePath path: String, in window: NSWindow,
                           categories: PCNativeImportCategories, skipExistingCookies: Bool,
                           progress: @escaping (PCNativeImportEvent) -> Void,
                           completion: @escaping (PCNativeImportResult) -> Void) -> PCNativeImportSession?
    func importPasswordFile(_ url: URL, toProfilePath path: String, in window: NSWindow,
                            completion: @escaping (PCNativePasswordFileImportResult) -> Void) -> PCNativePasswordFileImportSession?
    func installImportedExtensions(_ requests: [PCNativeImportExtensionRequest],
                                   completion: @escaping (PCNativeImportExtensionResult, [PCImportedExtensionFailure]) -> Void,
                                   backgroundFailures: @escaping ([PCImportedExtensionFailure]) -> Void) -> PCNativeImportSession?
    func installICloudPasswordsExtension(toProfilePath path: String, completion: @escaping (Error?) -> Void)
    func installSetupAdBlocker(toProfilePath path: String, completion: @escaping (Error?) -> Void)
    func removeSetupAdBlockers(_ identifiers: Set<String>, fromProfilePath path: String, completion: @escaping (Error?) -> Void)
    func extensionRestriction(for error: Error?) -> PCNativeExtensionRestriction
    nonisolated func background(_ qos: DispatchQoS.QoSClass, _ work: @escaping @Sendable () -> Void)
    nonisolated func main(_ work: @escaping @Sendable @MainActor () -> Void)
    func sidebarDecryptor(for profile: PCNativeImportProfile) -> SidebarDecryptor?
}

extension BrowserImportNative {
    func sidebarDecryptor(for profile: PCNativeImportProfile) -> SidebarDecryptor? { nil }
}

struct EngineBrowserImport: BrowserImportNative {
    nonisolated init() {}

    func availableImportSources(completion: @escaping ([PCNativeImportSource]) -> Void) -> PCNativeImportDiscovery {
        PCNativeBrowserApplication.availableImportSources(completion: completion)
    }

    func loadImportSourceProfiles(_ source: PCNativeImportSource,
                                  completion: @escaping (PCNativeImportProfileResult) -> Void) -> PCNativeImportDiscovery {
        PCNativeBrowserApplication.loadImportSourceProfiles(source, completion: completion)
    }

    func loadSafariExportProfiles(_ directories: [URL], names: [String],
                                  completion: @escaping (PCNativeImportProfileResult) -> Void) -> PCNativeImportDiscovery {
        PCNativeBrowserApplication.loadSafariExportProfiles(directories, names: names, completion: completion)
    }

    func importBrowserData(from profile: PCNativeImportProfile, toProfilePath path: String, in window: NSWindow,
                           categories: PCNativeImportCategories, skipExistingCookies: Bool,
                           progress: @escaping (PCNativeImportEvent) -> Void,
                           completion: @escaping (PCNativeImportResult) -> Void) -> PCNativeImportSession? {
        PCNativeBrowserApplication.importBrowserData(from: profile, toProfilePath: path, in: window,
            categories: categories, skipExistingCookies: skipExistingCookies, progress: progress, completion: completion)
    }

    func importPasswordFile(_ url: URL, toProfilePath path: String, in window: NSWindow,
                            completion: @escaping (PCNativePasswordFileImportResult) -> Void) -> PCNativePasswordFileImportSession? {
        PCNativeBrowserApplication.importPasswordFile(url, toProfilePath: path, in: window, completion: completion)
    }

    func installImportedExtensions(_ requests: [PCNativeImportExtensionRequest],
                                   completion: @escaping (PCNativeImportExtensionResult, [PCImportedExtensionFailure]) -> Void,
                                   backgroundFailures: @escaping ([PCImportedExtensionFailure]) -> Void) -> PCNativeImportSession? {
        PCImportedExtensions.install(requests, completion: completion, backgroundFailures: backgroundFailures)
    }

    func installICloudPasswordsExtension(toProfilePath path: String, completion: @escaping (Error?) -> Void) {
        PCNativeBrowserApplication.installICloudPasswordsExtension(toProfilePath: path, completion: completion)
    }

    func installSetupAdBlocker(toProfilePath path: String, completion: @escaping (Error?) -> Void) {
        PCNativeBrowserApplication.installSetupAdBlocker(toProfilePath: path, completion: completion)
    }

    func removeSetupAdBlockers(_ identifiers: Set<String>, fromProfilePath path: String, completion: @escaping (Error?) -> Void) {
        PCNativeBrowserApplication.removeSetupAdBlockers(identifiers, fromProfilePath: path, completion: completion)
    }

    func extensionRestriction(for error: Error?) -> PCNativeExtensionRestriction {
        PCImportedExtensions.restriction(for: error)
    }

    nonisolated func background(_ qos: DispatchQoS.QoSClass, _ work: @escaping @Sendable () -> Void) {
        DispatchQueue.global(qos: qos).async(execute: work)
    }

    nonisolated func main(_ work: @escaping @Sendable @MainActor () -> Void) {
        DispatchQueue.main.async { work() }
    }

    func sidebarDecryptor(for profile: PCNativeImportProfile) -> SidebarDecryptor? {
        guard PCImportedSidebarFiles.canDecrypt(from: profile) else { return nil }
        return { url, format in
            switch format {
            case .chromiumSession: try PCImportedSidebarFiles.decrypt(url, format: .chromiumSession, from: profile)
            case .diaTabs: try PCImportedSidebarFiles.decrypt(url, format: .diaTabs, from: profile)
            }
        }
    }
}
