// Copyright 2026 Parc contributors.
#include "native_exclusive_access.h"

#include <algorithm>
#include <utility>

#include "base/check.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/lifetime/application_lifetime_desktop.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/common/pref_names.h"
#include "chrome/grit/generated_resources.h"
#include "components/prefs/pref_service.h"
#include "components/strings/grit/components_strings.h"
#include "ui/base/base_window.h"
#include "ui/base/l10n/l10n_util.h"
#include "ui/strings/grit/ui_strings.h"
#import "dialog_style.h"
#include "native_page_tool_appearance.h"
#include "window_security_reservation.h"

using namespace parc_dialog;

@interface PCNativeHostDecision : NSPanel <NSWindowDelegate>
+ (instancetype)showForWindow:(NSWindow*)window
                        title:(NSString*)title
                      message:(NSString*)message
                       accept:(NSString*)accept
                   completion:(void (^)(BOOL))completion;
+ (instancetype)showForWindow:(NSWindow*)window
                        title:(NSString*)title
                      message:(NSString*)message
                       accept:(NSString*)accept
                      dismiss:(NSString*)dismiss
                acceptDefault:(BOOL)acceptDefault
                   completion:(void (^)(BOOL))completion;
@end
@implementation PCNativeHostDecision {
  void (^_completion)(BOOL);
  __weak NSWindow* _parent;
  id _closing;
  PCNativeHostDecision* _lease;
  PCNativeWindowSecurityReservation* _reservation;
}
+ (instancetype)showForWindow:(NSWindow*)parent
                        title:(NSString*)title
                      message:(NSString*)message
                       accept:(NSString*)accept
                   completion:(void (^)(BOOL))completion {
  return [self showForWindow:parent title:title message:message accept:accept
                    dismiss:@"Cancel" acceptDefault:YES completion:completion];
}
+ (instancetype)showForWindow:(NSWindow*)parent
                        title:(NSString*)title
                      message:(NSString*)message
                       accept:(NSString*)accept
                      dismiss:(NSString*)dismiss
                acceptDefault:(BOOL)acceptDefault
                   completion:(void (^)(BOOL))completion {
  if (!parent || !parent.visible || parent.miniaturized ||
      parent.attachedSheet) {
    completion(NO);
    return nil;
  }
  // TOOLS16: private-profile Clear Browsing Data uses this shared AppKit
  // decision sheet, drawn as Parc's dialog. Profile Clear Browsing Data itself
  // is Chromium WebUI; Settings DataActionButton chrome stays in
  // SettingsCommandButton.
  PCNativeHostDecision* sheet = [[self alloc]
      initWithContentRect:NSMakeRect(0, 0, kPCPageToolPrivateDecisionWidth,
                                     kPCPageToolPrivateDecisionHeight)
                styleMask:NSWindowStyleMaskTitled
                  backing:NSBackingStoreBuffered
                    defer:NO];
  sheet->_parent = parent;
  sheet->_completion = [completion copy];
  sheet->_reservation =
      [PCNativeWindowSecurityReservation acquireForWindow:parent];
  if (!sheet->_reservation) {
    completion(NO);
    return nil;
  }
  sheet->_lease = sheet;
  sheet.title = title;
  sheet.accessibilityLabel = title;
  sheet.releasedWhenClosed = NO;
  PrepareSheet(sheet);
  PCDialogBaseView* root = [[PCDialogBaseView alloc] initWithFrame:NSZeroRect];
  CGFloat y = kInset;
  NSRect markRect;
  NSImage* mark = ParcMark(&markRect);
  PCDialogPictureIcon* art = [[PCDialogPictureIcon alloc] initWithImage:mark
                                                             imageRect:markRect];
  [art setAccessibilityElement:NO];
  art.frameOrigin = NSMakePoint(kInset, y);
  [root addSubview:art];
  y = AddHeading(root, title, message, y + kArtSize, 200) + 22;
  // The Return button carries the primary face; when Cancel is the default,
  // the accepting button has no key.
  PCDialogButton* cancel = [[PCDialogButton alloc] initWithTitle:dismiss
                                                         primary:!acceptDefault];
  cancel.target = sheet;
  cancel.action = @selector(cancelOperation:);
  cancel.keyEquivalent = acceptDefault ? @"\033" : @"\r";
  PCDialogButton* okay = [[PCDialogButton alloc] initWithTitle:accept
                                                       primary:acceptDefault];
  okay.target = sheet;
  okay.action = @selector(accept:);
  okay.keyEquivalent = acceptDefault ? @"\r" : @"";
  okay.showsHint = acceptDefault;
  y = PlaceFooter(root, y, nil, acceptDefault ? @[ okay, cancel ] : @[ cancel, okay ]);
  root.frame = NSMakeRect(0, 0, kWidth, y);
  sheet.contentView = root;
  [sheet setContentSize:NSMakeSize(kWidth, y)];
  sheet.defaultButtonCell = acceptDefault ? okay.cell : cancel.cell;
  [sheet setAccessibilityDefaultButton:acceptDefault ? okay : cancel];
  __weak PCNativeHostDecision* weak = sheet;
  sheet->_closing = [NSNotificationCenter.defaultCenter
      addObserverForName:NSWindowWillCloseNotification
                  object:parent
                   queue:nil
              usingBlock:^(NSNotification*) {
                [weak finish:NO];
              }];
  [parent beginSheet:sheet
      completionHandler:^(NSModalResponse) {
        [weak finish:NO];
      }];
  if (sheet.sheetParent != parent || !sheet.visible || !parent.visible) {
    [sheet finish:NO];
  }
  return sheet;
}
- (BOOL)canBecomeKeyWindow {
  return YES;
}
- (BOOL)acceptsFirstResponder {
  return YES;
}
- (void)keyDown:(NSEvent*)event {
  [self interpretKeyEvents:@[ event ]];
}
- (void)insertNewline:(id)sender {
  [self.defaultButtonCell performClick:sender];
}
- (void)accept:(id)sender {
  if (_parent && self.sheetParent == _parent && self.visible &&
      _parent.visible && _reservation.isOnlyReservation) {
    [self finish:YES];
  } else {
    [self finish:NO];
  }
}
- (void)cancelOperation:(id)sender {
  [self finish:NO];
}
- (void)finish:(BOOL)accepted {
  PCNativeHostDecision* __attribute__((objc_precise_lifetime)) keep = self;
  void (^callback)(BOOL) = _completion;
  if (!callback) {
    return;
  }
  _completion = nil;
  id closing = _closing;
  _closing = nil;
  if (closing) {
    [NSNotificationCenter.defaultCenter removeObserver:closing];
  }
  NSWindow* parent = self.sheetParent;
  if (parent) {
    [parent endSheet:self];
  }
  [self orderOut:nil];
  [_reservation invalidate];
  _reservation = nil;
  _lease = nil;
  callback(accepted);
}
@end

namespace parc {
PCNativeHostDecision* ShowNativeDownloadCloseDecision(
    NSWindow* window,
    int count,
    DownloadCloseType,
    base::OnceCallback<void(bool)> callback) {
  auto result =
      std::make_shared<base::OnceCallback<void(bool)>>(std::move(callback));
  return [PCNativeHostDecision
      showForWindow:window
              title:@"Downloads are in progress"
            message:[NSString
                        stringWithFormat:@"Closing this browser will interrupt "
                                         @"%d active download%@.",
                                         count, count == 1 ? @"" : @"s"]
             accept:@"Close browser"
         completion:^(BOOL accept) {
           if (*result) {
             std::move(*result).Run(accept);
           }
         }];
}
PCNativeHostDecision* ShowNativeCaretDecision(BrowserWindowInterface& browser,
                                              NSWindow* window) {
  base::WeakPtr<Profile> profile = browser.GetProfile()->GetWeakPtr();
  return
      [PCNativeHostDecision showForWindow:window
                                    title:@"Turn on caret browsing?"
                                  message:@"Use the arrow keys to move through "
                                          @"and select text on web pages."
                                   accept:@"Turn On"
                               completion:^(BOOL accept) {
                                 if (accept && profile) {
                                   profile->GetPrefs()->SetBoolean(
                                       prefs::kCaretBrowsingEnabled, true);
                                 }
                               }];
}
PCNativeHostDecision* ShowNativePrivateProfileDecision(
    BrowserWindowInterface& browser, NSWindow* window,
    bool history_information) {
  Profile* current = browser.GetProfile();
  if (!current || !current->IsOffTheRecord() || !browser.GetWindow() ||
      browser.GetWindow()->GetNativeWindow().GetNativeNSWindow() != window ||
      browser.IsDeleteScheduled()) {
    return nil;
  }
  const bool isolated = current->IsEnterpriseIsolatedModeProfile();
  const int title = history_information
      ? (isolated ? IDS_ISOLATED_HISTORY_BUBBLE_PRIMARY_TEXT
                  : IDS_INCOGNITO_HISTORY_BUBBLE_PRIMARY_TEXT)
      : (isolated ? IDS_ISOLATED_CLEAR_BROWSING_DATA_DIALOG_PRIMARY_TEXT
                  : IDS_INCOGNITO_CLEAR_BROWSING_DATA_DIALOG_PRIMARY_TEXT);
  const int message = history_information
      ? (isolated ? IDS_ISOLATED_HISTORY_BUBBLE_SECONDARY_TEXT
                  : IDS_INCOGNITO_HISTORY_BUBBLE_SECONDARY_TEXT)
      : (isolated ? IDS_ISOLATED_CLEAR_BROWSING_DATA_DIALOG_SECONDARY_TEXT
                  : IDS_INCOGNITO_CLEAR_BROWSING_DATA_DIALOG_SECONDARY_TEXT);
  const int close = history_information
      ? (isolated ? IDS_ISOLATED_HISTORY_BUBBLE_CLOSE_ISOLATED_BUTTON_TEXT
                  : IDS_INCOGNITO_HISTORY_BUBBLE_CLOSE_INCOGNITO_BUTTON_TEXT)
      : (isolated ? IDS_ISOLATED_CLEAR_BROWSING_DATA_DIALOG_CLOSE_WINDOWS_BUTTON
                  : IDS_INCOGNITO_CLEAR_BROWSING_DATA_DIALOG_CLOSE_WINDOWS_BUTTON);
  const int dismiss = history_information
      ? (isolated ? IDS_ISOLATED_HISTORY_BUBBLE_CANCEL_BUTTON_TEXT
                  : IDS_INCOGNITO_HISTORY_BUBBLE_CANCEL_BUTTON_TEXT)
      : IDS_CANCEL;
  auto string = [](int id) {
    return base::SysUTF16ToNSString(l10n_util::GetStringUTF16(id));
  };
  base::WeakPtr<BrowserWindowInterface> owner = browser.GetWeakPtr();
  base::WeakPtr<Profile> profile = current->GetWeakPtr();
  __weak NSWindow* parent = window;
  // The retained Arc142 compatibility slots 0x68a8f50/0x68a8fd4 are inert.
  // Current Chromium consumes these internal navigations before calling us;
  // this explicit native adaptation preserves its actual private-profile
  // policy and localized information instead of silently swallowing the URL.
  // TOOLS16: the sheet is the shared Parc decision dialog; ordinary profile
  // Clear Browsing Data remains Chromium WebUI.
  return [PCNativeHostDecision
      showForWindow:window title:string(title) message:string(message)
      accept:string(close) dismiss:string(dismiss)
      acceptDefault:!history_information
      completion:^(BOOL accepted) {
        if (!accepted || !owner || !profile || owner->IsDeleteScheduled() ||
            owner->GetProfile() != profile.get() || !profile->IsOffTheRecord() ||
            !owner->GetWindow() || !parent || !parent.visible ||
            owner->GetWindow()->GetNativeWindow().GetNativeNSWindow() != parent)
          return;
        // Same genuine closure as Chromium's private data/history UI. It
        // targets only this exact off-the-record Profile; the upstream method
        // also preserves its DevTools exception to beforeunload skipping.
        chrome::CloseAllBrowsersWithIncognitoProfile(profile.get());
      }];
}
void CancelNativeHostDecision(PCNativeHostDecision* decision) {
  [decision cancelOperation:nil];
}
}  // namespace parc
