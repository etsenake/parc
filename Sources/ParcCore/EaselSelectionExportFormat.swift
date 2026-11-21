import Foundation
import UniformTypeIdentifiers

enum EaselSelectionExportFormat: String, CaseIterable {
    case image, pdf, html, stickies

    var title: String {
        switch self {
        case .image: return "Image…"
        case .pdf: return "PDF…"
        case .html: return "HTML File…"
        case .stickies: return "Stickies as CSV…"
        }
    }

    var symbol: String {
        switch self {
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case .html: return "doc.text"
        case .stickies: return "list.bullet.rectangle"
        }
    }

    var contentTypes: [UTType] {
        switch self {
        case .image: return [.png, .jpeg]
        case .pdf: return [.pdf]
        case .html: return [.html]
        case .stickies: return [.commaSeparatedText]
        }
    }

    var fileExtension: String {
        switch self {
        case .image: return "png"
        case .pdf: return "pdf"
        case .html: return "html"
        case .stickies: return "csv"
        }
    }
}
