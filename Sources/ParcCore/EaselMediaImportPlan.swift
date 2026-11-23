import Foundation
import UniformTypeIdentifiers

package enum EaselMediaImportPlan {
    package enum Source: Equatable {
        case image
        case video(EaselAssetType)
        case audio(EaselAssetType)
        case pdf
        case file

        package var itemKind: EaselItemKind {
            switch self {
            case .image: return .image
            case .video: return .video
            case .audio: return .audio
            case .pdf: return .pdf
            case .file: return .file
            }
        }

        package static func forKind(_ kind: EaselItemKind) -> Source {
            switch kind {
            case .image: return .image
            case .video: return .video(.mp4)
            case .audio: return .audio(.mp3)
            case .pdf: return .pdf
            default: return .file
            }
        }

        package var needsFacts: Bool {
            switch self {
            case .video, .audio: return true
            default: return false
            }
        }
    }

    package static func classify(sniffed: EaselAssetType?, fileExtension: String?, isImage: Bool, isMovie: Bool, byteCount: Int) -> Source? {
        guard byteCount > 0 else { return nil }
        if isMovie { return .video(sniffed.flatMap { $0.isVideo ? $0 : nil } ?? .mp4) }
        if isImage { return .image }
        if let audio = EaselAssetType.audioType(forExtension: fileExtension) {
            guard let sniffed, sniffed.isAudio, sniffed != .mp3, sniffed != .aac else { return .audio(audio) }
            return .audio(sniffed)
        }
        if fileExtension?.lowercased() == "pdf" { return .pdf }
        if isKnownExtension(fileExtension) { return .file }
        if let sniffed {
            if sniffed.isVideo { return .video(sniffed) }
            if sniffed.isAudio { return .audio(sniffed) }
            if sniffed == .pdf { return .pdf }
            if sniffed.isPicture { return .image }
        }
        return .file
    }

    private static func isKnownExtension(_ raw: String?) -> Bool {
        guard let raw, !raw.isEmpty, let type = UTType(filenameExtension: raw.lowercased()) else { return false }
        return !type.isDynamic
    }

    package static func tooLargeError(for source: Source) -> EaselStoreError {
        switch source {
        case .image: return .assetImageTooLarge
        case .video: return .videoTooLarge
        case .audio: return .audioTooLarge
        case .pdf: return .pdfTooLarge
        case .file: return .fileTooLarge
        }
    }

    package static func cleanFileName(_ raw: String) -> String? {
        let scalars = raw.unicodeScalars.filter { $0.properties.generalCategory != .control }
        var name = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        while name.utf8.count > 1024 { name.removeLast() }
        return EaselMediaText.isValidFileName(name) ? name : nil
    }

    package static func linkFileName(_ url: URL) -> String? {
        let last = url.lastPathComponent
        guard last != "/", !last.isEmpty else { return nil }
        return cleanFileName(last.removingPercentEncoding ?? last)
    }

    package static func isLinkable(_ url: URL, kind: EaselItemKind) -> Bool {
        guard kind.takesMediaLink, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return false }
        return url.absoluteString.utf8.count <= 4096
    }

    package static func pageSize(width: Double, height: Double, rotation: Int) -> (width: Double, height: Double)? {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        return rotation.magnitude % 180 == 90 ? (height, width) : (width, height)
    }

    package static func layout(_ sizes: [(width: Double, height: Double)], centre: EaselPoint) -> [EaselRect] {
        EaselMediaPlacement.row(of: sizes, centredAt: centre)
    }
}
