// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_PAGE_TOOL_APPEARANCE_H_
#define PARC_NATIVE_PAGE_TOOL_APPEARANCE_H_

#include <CoreGraphics/CGBase.h>

// TOOLS16 recovered/adapted chrome used by native overlay surfaces.
// Print/Save stay Chromium IDC_PRINT / IDC_SAVE_PAGE (file_dialog.mm).
// Settings DataActionButton 24/5/34 and Clear Browsing Data title/symbol
// stay recovered in tests/PageToolAppearance; SettingsWindow is out of
// TOOLS16 scope and ordinary clear-data stays Chromium WebUI.

//
// desktop ReaderView type exists; Chromium's DOM-distiller viewer is the
// explicit current-engine viewing chrome.
static const char kPCPageToolReaderScheme[] = "chrome-distiller";

// Private-profile copy uses the shared 430×180 AppKit decision sheet.
static const CGFloat kPCPageToolPrivateDecisionWidth = 430;
static const CGFloat kPCPageToolPrivateDecisionHeight = 180;

#endif  // PARC_NATIVE_PAGE_TOOL_APPEARANCE_H_
