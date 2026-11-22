import AppKit
import Combine

@MainActor
package final class AppIconController: ObservableObject {
    package static let shared = AppIconController(resources: Bundle.main.resourceURL)
    static let changedNotification = Notification.Name("org.parc.Browser.appIconChanged")
    struct Variant {
        let id: String
        let title: String
        let image: NSImage
    }
    private struct Catalog: Decodable { let `default`: String; let variants: [String] }
    private struct Selection: Codable { let version: Int; let icon: String }
    private static let renamedIDs = ["Candy": "Sorbet", "Neon": "AfterHours", "FlutedGlass": "RainGlass", "Schoolbook": "Recess", "Colorful": "Twilight",
                                     "Hologram": "Opal", "EarlyBirds": "TracingPaper", "Canary": "Grapefruit", "Dev": "Terminal"]
    private(set) var variants: [Variant] = []
    private(set) var availabilityError: String?
    @Published private(set) var selectedID = "Original"
    @Published private(set) var message: String?
    @Published private(set) var canRetry = false
    private var preferenceURL: URL?
    private var apply: ((NSImage) -> String?)?

    init(resources: URL?) {
        do {
            guard let resources else { throw CocoaError(.fileNoSuchFile) }
            let root = resources.appendingPathComponent("AppIcons", isDirectory: true)
            let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: root.appendingPathComponent("catalog.json")))
            let order = ["Original", "Sorbet", "AfterHours", "RainGlass", "Recess", "Twilight", "Opal", "TracingPaper", "Grapefruit", "Terminal"]
            guard catalog.default == "Original", Set(catalog.variants) == Set(order),
                  catalog.variants.count == order.count else { throw CocoaError(.fileReadCorruptFile) }
            let titles = ["Original": "The Original Parc", "AfterHours": "After Hours", "RainGlass": "Rain Glass", "TracingPaper": "Tracing Paper"]
            variants = try order.map { id in
                let native = root.appendingPathComponent(id + ".icns")
                let artwork = FileManager.default.fileExists(atPath: native.path)
                    ? native : root.appendingPathComponent(id + ".png")
                guard let image = NSImage(contentsOf: artwork), image.isValid else { throw CocoaError(.fileReadCorruptFile) }
                return Variant(id: id, title: titles[id] ?? id, image: image)
            }
        } catch {
            availabilityError = "The app icon artwork is missing or damaged. Reinstall this build to restore it."
        }
    }

    package func configure(directory: URL, updatesSystemIdentity: Bool) {
        configure(preferenceURL: directory.appendingPathComponent("app-icon.json")) { image in
            NSApp.applicationIconImage = image
            let tile = NSApp.dockTile
            let view = NSImageView(image: image)
            view.frame = NSRect(origin: .zero, size: tile.size)
            view.wantsLayer = true
            view.imageScaling = .scaleProportionallyUpOrDown
            tile.contentView = view
            tile.display()
            guard updatesSystemIdentity else { return nil }
            DistributedNotificationCenter.default().postNotificationName(
                Self.changedNotification, object: Bundle.main.bundleURL.resolvingSymlinksInPath().path,
                userInfo: nil, deliverImmediately: true)
            guard NSWorkspace.shared.setIcon(image, forFile: Bundle.main.bundlePath, options: []) else {
                return "Your choice is saved and appears in the Dock. Finder couldn’t update this copy of Parc. Check that the app is in a writable location, then try again."
            }
            return nil
        }
    }

    func configure(preferenceURL: URL, apply: @escaping (NSImage) -> String?) {
        self.preferenceURL = preferenceURL
        self.apply = apply
        guard availabilityError == nil else { return }
        guard FileManager.default.fileExists(atPath: preferenceURL.path) else { return }
        do {
            let selection = try JSONDecoder().decode(Selection.self, from: Data(contentsOf: preferenceURL))
            let icon = Self.renamedIDs[selection.icon] ?? selection.icon
            guard selection.version == 1, variants.contains(where: { $0.id == icon }) else { throw CocoaError(.fileReadCorruptFile) }
            guard icon == selection.icon else { return select(icon) }
            selectedID = icon
            applyCurrent()
        } catch {
            message = "The saved icon choice couldn’t be read. Choose an icon to save a new preference."
        }
    }

    func select(_ id: String) {
        guard availabilityError == nil, let preferenceURL,
              variants.contains(where: { $0.id == id }) else { return }
        do {
            let data = try JSONEncoder().encode(Selection(version: 1, icon: id))
            try FileManager.default.createDirectory(at: preferenceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: preferenceURL, options: .atomic)
        } catch {
            message = "The icon choice couldn’t be saved. " + error.localizedDescription
            canRetry = false
            return
        }
        selectedID = id
        applyCurrent()
    }

    func applyCurrent() {
        guard let image = variants.first(where: { $0.id == selectedID })?.image, let apply else { return }
        message = apply(image)
        canRetry = message != nil
    }
}
