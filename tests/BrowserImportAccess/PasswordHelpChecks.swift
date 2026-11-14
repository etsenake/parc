import Foundation

func passwordHelpChecks() throws -> Int {
    var checks = 0
    func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1; precondition(condition(), message)
    }
    let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../Sources/ParcApp").standardizedFileURL
    func source(_ name: String) throws -> String {
        try String(contentsOf: app.appendingPathComponent(name), encoding: .utf8)
    }
    let controller = try source("BrowserImportViewController.swift")
    let setup = try source("OnboardingWindow.swift")
    let help = try source("OnboardingPasswordHelp.swift")

    expect(!controller.contains("NSAlert(") && !controller.contains("Exporting Safari passwords"),
           "The menu window's password help is never an alert")
    for owner in [controller, setup] {
        expect(owner.contains("help = OnboardingPasswordHelp(frame: root.bounds)")
               && owner.contains("root.addSubview(help, positioned: .above, relativeTo: nil)"),
               "Setup and the menu window each present the one shared help panel above their content")
    }
    expect(controller.contains("passwordsView.onHelp = { [weak self] in self?.showPasswordHelp() }")
           && controller.contains("        if embedded {\n            onShowPasswordHelp?()\n            return\n        }\n        let help: OnboardingPasswordHelp"),
           "The help link presents setup's panel in setup and the same panel in the menu window")
    expect(controller.contains("        help.present()\n        coverContent(help.isPresented)\n"),
           "The panel counts as shown before the window covers its content")
    expect(controller.contains("help.onDismiss = { [weak self] in self?.coverContent(false) }")
           && controller.contains("root.subviews.forEach { if $0 !== passwordHelp { $0.setAccessibilityHidden(covered) } }"),
           "As setup's card, the menu window's covered content leaves accessibility until the panel closes")
    expect(controller.contains("let closes = (isSafariAccess || isSafariPasswords) && !helpCoversContent")
           && controller.contains("guard let self, !self.helpCoversContent else { return }\n            self.coordinator.continueAfterPasswords()"),
           "Escape and Return reach the panel, not the covered close and Continue controls")
    expect(!controller.contains("OnboardingPasswordHelp.fittingSize")
           && controller.contains("BrowserImportGeometry.resize(window, contentSize: NSSize(width: requestedWidth, height: requestedHeight))"),
           "The menu window keeps its step's size while help shows")
    expect(controller.contains("if !canShowPasswordHelp { dismissPasswordHelp() }")
           && controller.contains("onHidePasswordHelp?(); dismissPasswordHelp(remove: true)"),
           "The panel closes when its step ends or the window closes")
    expect(!help.contains("scaleEffect")
           && help.contains("let size = CGSize(width: min(Self.cardSize.width, max(0, space.width - 2 * Self.margin)),")
           && help.contains("ViewThatFits(in: .vertical) {\n                    page(inset: inset, width: width)\n                    ScrollView { page(inset: inset, width: width) }"),
           "A smaller window narrows the card at setup's text size, scrolling only if it must")
    expect(!help.contains("Passkeys") && !help.contains("readable passwords"),
           "The help has a title and the export steps, and no footnote")
    return checks
}
