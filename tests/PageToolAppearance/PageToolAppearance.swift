import AppKit

/// TOOLS16 recovered chrome for page-tool surfaces. Native overlay chrome is
/// the production UI (`native_page_tool_appearance.h`). This fixture keeps the
/// same recovered metrics for the Swift compile check and must stay pinned to
/// that header. Reader viewing, print/save and profile Clear Browsing Data keep
/// Chromium/platform dialogs; those are explicit current-engine adaptations,
/// not invented desktop layouts.
enum PageToolAppearance {
    /// ADK.DistilledArticle is title plus html pages. No desktop ReaderView was
    /// recovered; Chromium's DOM distiller viewer is the viewing chrome.
    enum Reader {
        static let scheme = "chrome-distiller"
        static let articleTitleField = "title"
        static let articlePagesField = "pages"
    }

    /// Print and Save Page keep Chromium IDC_PRINT / IDC_SAVE_PAGE. Save-to-PDF
    ///
    /// "Save as PDF" string or custom accessory was recovered.
    enum PrintSave {
        static let printCommand = "IDC_PRINT"
        static let saveCommand = "IDC_SAVE_PAGE"
    }

    /// Settings DataActionButton chrome is already recovered (24-pt badge, 5-pt
    /// padding, 34-pt row). The actual clear-data dialog is Chromium WebUI;
    /// private-profile copy uses the shared 430×180 AppKit decision sheet.
    enum DataDialog {
        static let commandHeight: CGFloat = 34
        static let badgeSize: CGFloat = 24
        static let padding: CGFloat = 5
        static let decisionWidth: CGFloat = 430
        static let decisionHeight: CGFloat = 180
        static let clearTitle = "Clear Browsing Data"
        static let clearSymbol = "trash.fill"
    }
}
