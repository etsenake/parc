import Foundation

package enum ChromiumFlavorExtras {
    package static func adjusted(_ session: ChromiumSession, flavor: ChromiumFlavor, profileDirectory: URL) -> ChromiumSession {
        session
    }

    package static func favorites(flavor: ChromiumFlavor, profileDirectory: URL) -> [SidebarImport.Item] { [] }

    package static func spaces(_ session: ChromiumSession, flavor: ChromiumFlavor, profile: SidebarImportProfile)
        -> [(space: SidebarImport.Space, windowTabs: [Int32: Set<Int32>])]? {
        nil
    }
}
