import Foundation

package enum ChromiumSidebarReader {
    package static func read(flavor: ChromiumFlavor, root: URL, profiles: [SidebarImportProfile],
                             decrypt: SidebarDecryptor?) throws -> SidebarImport {
        SidebarImport(spaces: [])
    }
}
