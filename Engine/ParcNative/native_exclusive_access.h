// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_EXCLUSIVE_ACCESS_H_
#define PARC_NATIVE_NATIVE_EXCLUSIVE_ACCESS_H_
#import <AppKit/AppKit.h>

#include "base/functional/callback_forward.h"
#include "chrome/browser/ui/browser_window.h"
@class PCNativeHostDecision;
namespace parc {
PCNativeHostDecision* ShowNativeDownloadCloseDecision(
    NSWindow*,
    int count,
    DownloadCloseType,
    base::OnceCallback<void(bool)>);
PCNativeHostDecision* ShowNativeCaretDecision(BrowserWindowInterface&,
                                              NSWindow*);
// Actual private Profile command, with explicit consent before closing only
// that Profile's browsers. Never clears or closes the original profile.
// TOOLS16: this is the recovered 430×180 AppKit decision sheet. Ordinary
// profile Clear Browsing Data stays Chromium WebUI; do not invent a second
// native clear-data layout.
PCNativeHostDecision* ShowNativePrivateProfileDecision(
    BrowserWindowInterface&, NSWindow*, bool history_information);
void CancelNativeHostDecision(PCNativeHostDecision*);
}  // namespace parc
#endif
