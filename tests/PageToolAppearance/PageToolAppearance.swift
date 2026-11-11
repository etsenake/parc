import AppKit

enum PageToolAppearance {
    enum Reader {
        static let scheme = "chrome-distiller"
        static let articleTitleField = "title"
        static let articlePagesField = "pages"
    }

    enum PrintSave {
        static let printCommand = "IDC_PRINT"
        static let saveCommand = "IDC_SAVE_PAGE"
    }

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
