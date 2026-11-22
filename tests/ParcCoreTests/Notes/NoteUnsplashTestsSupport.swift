import Foundation
import Testing
@testable import ParcCore

enum NoteUnsplashTestsSupport {
    static let photoJSON = """

    {
      "id": "Dwu85P9SOIk",
      "width": 6000,
      "height": 4000,
      "color": "#26598c",
      "description": null,
      "alt_description": "a mountain lake at\\nsunrise",
      "urls": {
        "raw": "https://images.unsplash.com/photo-1417325384643?ixid=M3w1&ixlib=rb-4.0.3",
        "full": "https://images.unsplash.com/photo-1417325384643?ixid=M3w1&q=85&fm=jpg",
        "regular": "https://images.unsplash.com/photo-1417325384643?ixid=M3w1&w=1080",
        "small": "https://images.unsplash.com/photo-1417325384643?ixid=M3w1&w=400",
        "thumb": "https://images.unsplash.com/photo-1417325384643?ixid=M3w1&w=200"
      },
      "links": {
        "html": "https://unsplash.com/photos/Dwu85P9SOIk",
        "download": "https://unsplash.com/photos/Dwu85P9SOIk/download",
        "download_location": "https://api.unsplash.com/photos/Dwu85P9SOIk/download?ixid=M3w1"
      },
      "user": {
        "username": "jane",
        "name": "Jane \\"JJ\\" Doe",
        "links": { "html": "https://unsplash.com/@jane" }
      }
    }

    """

    static func photo() throws -> NoteUnsplashPhoto {
        guard let photo = try? NoteUnsplash.decoder().decode(NoteUnsplashPhoto.self, from: Data(photoJSON.utf8)) else {
            throw NoteTestFailure("a photo from the API decodes")
        }
        return photo
    }

    static func query(_ url: URL?) -> [String: String] {
        let items = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
    }
}
