// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_BROWSER_WINDOW_H_
#define PARC_NATIVE_BROWSER_WINDOW_H_

// Native components for the future BrowserWindow adapter, not a complete
// BrowserWindow implementation. No BrowserView or Chrome-owned window is used.

#ifdef __OBJC__
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PCNativeWindowEvent) {
  PCNativeWindowEventWillClose,
  PCNativeWindowEventDidBecomeKey,
  PCNativeWindowEventDidResignKey,
  PCNativeWindowEventDidEnterFullScreen,
  PCNativeWindowEventDidExitFullScreen,
  PCNativeWindowEventWillEnterFullScreen,
  PCNativeWindowEventWillExitFullScreen,
  // Final state after a managed native transition, including cross-display
  // exit/move/re-entry and original-frame restoration.
  PCNativeWindowEventFullscreenDidSettle,
};

@class PCNativeWindowAssociation;
@protocol PCNativeWindowAssociationObserver <NSObject>
// On WillClose, association.window is already nil. The event's window remains
// valid for this call. This notification is not beforeunload consent: the
// Browser/NSWindow close coordinator must obtain consent before native close.
- (void)nativeWindowAssociation:(PCNativeWindowAssociation*)association
               didReceiveEvent:(PCNativeWindowEvent)event
                        window:(NSWindow*)window;
@end

// All access and final release must occur on the AppKit/Chromium UI thread.
// The shell owns the window; the browser-side owner retains this association.
// Initial activation is queried by the owner after Browser registration, not
// synthesized during attachment. Event callbacks may detach or invalidate.
@interface PCNativeWindowAssociation : NSObject
@property(nonatomic, weak, readonly, nullable) NSWindow* window;
@property(nonatomic, readonly, getter=isInvalidated) BOOL invalidated;
// Shared physical-window placement, independent of which Profile's Browser
// currently supplies the selected page. Queries never retain the NSWindow.
@property(nonatomic, readonly) NSRect restoredFrame;
@property(nonatomic, readonly) BOOL fullscreenTransitioning;
@property(nonatomic, readonly) NSUInteger stateRequestGeneration;
- (NSUInteger)beginStateRequest;
- (instancetype)initWithObserver:
    (id<PCNativeWindowAssociationObserver>)observer NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
// Idempotent for the same live window; rejects a different live attachment.
// A closed/deallocated/detached window permits a later attachment.
- (BOOL)attachToWindow:(NSWindow*)window;
- (void)detach;
// Terminal. Removes notifications and clears the weak observer/window.
- (void)invalidate;
@end

NS_ASSUME_NONNULL_END
#endif  // __OBJC__

#ifdef __cplusplus
#include "base/memory/raw_ptr.h"
#include "base/observer_list.h"
#include "components/web_modal/web_contents_modal_dialog_host.h"
#include "ui/gfx/geometry/point.h"
#include "ui/gfx/geometry/size.h"

namespace parc {

// The real BrowserWindow adapter will implement this using its active contents
// and native window geometry. It must outlive its host or invalidate it first.
// All queries run on the AppKit/Chromium UI thread.
class NativeModalDialogHostDelegate {
 public:
  virtual ~NativeModalDialogHostDelegate() = default;
  // The current active page's actual native wrapper (not NSWindow.contentView).
  virtual gfx::NativeView GetActivePageHostView() const = 0;
  // Dimensions of BrowserWindow::GetBounds, already in gfx coordinates.
  virtual gfx::Size GetBrowserWindowSize() const = 0;
  // Active content size, or the window frame-size fallback when absent/zero.
  virtual gfx::Size GetContentsSize() const = 0;
};

//
// primary positioning method centers using separately truncated half-sizes;
// GetHostView resolves the active page wrapper on every call. No cached active
// tab, duplicated NSWindow ownership, or invented per-pane policy is introduced.
//
// Chromium 156 additionally requires position/destruction observer delivery.
//
// list. Call NotifyPositionRequiresUpdate after active-host or geometry changes.
// Invalidate is reentrant and may run during a position callback; destruction
//
class NativeModalDialogHost final
    : public web_modal::WebContentsModalDialogHost {
 public:
  explicit NativeModalDialogHost(NativeModalDialogHostDelegate& delegate);
  ~NativeModalDialogHost() override;
  NativeModalDialogHost(const NativeModalDialogHost&) = delete;
  NativeModalDialogHost& operator=(const NativeModalDialogHost&) = delete;

  gfx::NativeView GetHostView() const override;
  gfx::Point GetDialogPosition(const gfx::Size& size) override;
  gfx::Size GetMaximumDialogSize() override;
  bool ShouldActivateDialog() const override;
  bool ShouldConstrainDialogBoundsByHost() override;
  void AddObserver(web_modal::ModalDialogHostObserver* _Nonnull observer) override;
  void RemoveObserver(web_modal::ModalDialogHostObserver* _Nonnull observer) override;
  void NotifyPositionRequiresUpdate() override;
  void Invalidate();

 private:
  raw_ptr<NativeModalDialogHostDelegate> delegate_;
  // Reentrancy is intentional: an observer may invalidate during position
  // notification, causing nested destruction notification to the same list.
  base::ObserverList<web_modal::ModalDialogHostObserver, false,
                     base::ObserverListReentrancyPolicy::kAllowReentrancy>
      observers_{base::ObserverListPolicy::EXISTING_ONLY};
  bool notifying_position_ = false;
  bool notifying_destruction_ = false;
};

}  // namespace parc
#endif  // __cplusplus
#endif  // PARC_NATIVE_BROWSER_WINDOW_H_
