import AppKit

@main
struct PageToolAppearanceTests {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        var assertions = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            assertions += 1
            precondition(condition(), message)
        }

        expect(PageToolAppearance.Reader.articleTitleField == "title"
                && PageToolAppearance.Reader.articlePagesField == "pages",
               "DistilledArticle is title plus html pages")
        expect(PageToolAppearance.PrintSave.printCommand == "IDC_PRINT"
                && PageToolAppearance.PrintSave.saveCommand == "IDC_SAVE_PAGE",
               "Print/save stay Chromium commands")
        expect(PageToolAppearance.DataDialog.commandHeight == 34
                && PageToolAppearance.DataDialog.badgeSize == 24
                && PageToolAppearance.DataDialog.padding == 5,
               "Settings clear-data command matches recovered DataActionButton geometry")
        expect(PageToolAppearance.DataDialog.decisionWidth == 430
                && PageToolAppearance.DataDialog.decisionHeight == 180,
               "Private-profile decision keeps the shared 430×180 AppKit sheet")
        expect(PageToolAppearance.DataDialog.clearTitle == "Clear Browsing Data"
                && PageToolAppearance.DataDialog.clearSymbol == "trash.fill",
               "Clear Browsing Data keeps trash.fill")

        print("Page tool appearance: \(assertions) assertions passed")
    }
}
