#!/usr/bin/env python3
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
app = root / "Sources/ParcApp"
sidebar = (app / "SidebarView.swift").read_text()
controller = (app / "BrowserWindowController.swift").read_text()

assert (
    "guard title != paymentEntryTitle || symbol != paymentEntrySymbol\n"
    "                || enabled != paymentEntryEnabled || savedLabel != paymentEntrySavedLabel else {\n"
    "            return false\n"
    "        }"
) in sidebar, "updatePaymentEntry no longer skips when title/symbol/enabled/savedLabel are unchanged"
assert "needsLayout = true\n        return true" in sidebar, \
    "updatePaymentEntry no longer marks layout when a visible field changes"

payment = re.search(
    r"private func refreshPaymentControls\(\) \{(?P<body>.*?)\n    \}\n\n    private func performPaymentAction",
    controller, re.S)
assert payment, "refreshPaymentControls not found"
body = payment.group("body")
assert (
    "if sidebar.updatePaymentEntry(title: title, symbol: actions.first?.symbolName ?? \"creditcard\",\n"
    "                                      enabled: actions.contains { $0.isEnabled }, savedLabel: saved) {\n"
    "            sidebar.layoutSubtreeIfNeeded()\n"
    "        }"
) in body, "refreshPaymentControls no longer gates layoutSubtreeIfNeeded on a changed payment entry"
assert body.count("sidebar.layoutSubtreeIfNeeded()") == 1, \
    "refreshPaymentControls must layout the sidebar only inside the changed-entry gate"
assert (
    "guard sidebarPresentation != .hidden, sidebar.isPaymentEntryVisible else { return }\n"
    "        for action in actions where action.requiresPresentationAcknowledgment {"
) in body, "refreshPaymentControls no longer acknowledges payment presentation after the layout gate"
assert (
    "NSAccessibility.post(element: sidebar, notification: .announcementRequested,\n"
    "                             userInfo: [.announcement: saved, .priority: NSAccessibilityPriorityLevel.medium.rawValue])"
) in body, "refreshPaymentControls no longer announces the saved payment label"
print("PaymentControls: unchanged payment entry skips layout; changed entry still layouts and acknowledges")
