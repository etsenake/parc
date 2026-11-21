import Foundation

package enum EaselObjectAddress {
    package static func urlString(easel: UUID, object: UUID) -> String {
        InternalPage.easel(easel).urlString + "#" + object.uuidString.lowercased()
    }

    package static func target(of urlString: String) -> (easel: UUID, object: UUID)? {
        guard let easel = InternalPage(urlString: urlString)?.easelID,
              let fragment = URLComponents(string: urlString)?.fragment,
              let object = UUID(uuidString: fragment) else { return nil }
        return (easel, object)
    }
}
