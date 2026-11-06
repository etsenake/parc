// Copyright 2026 Parc contributors.
//
//
// compositor and its layer tree belong to pane_compositor.mm.
#ifndef CEF_LIBCEF_BROWSER_PARC_NATIVE_PANE_COMPOSITOR_VIEW_H_
#define CEF_LIBCEF_BROWSER_PARC_NATIVE_PANE_COMPOSITOR_VIEW_H_

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// Main-thread-only. Hosts the supplied layer and is invisible to events,
// focus, dragging and accessibility, so the renderer view beneath it keeps
// receiving them. It sits inside a page's WebContents view, above the
// renderer; PCNativePageHost never treats it as the renderer responder.
@interface PCNativePaneCompositorView : NSView

- (instancetype)initWithHostedLayer:(CALayer*)layer NS_DESIGNATED_INITIALIZER;

// Runs after a size, window, backing-scale or window-screen change.
@property(nonatomic, copy, nullable) void (^geometryHandler)(void);

// Runs when the view, or an ancestor, is hidden or unhidden, and when it
// joins or leaves a window: whenever `onScreen` may have changed.
@property(nonatomic, copy, nullable) void (^screenHandler)(void);

// In a window and neither hidden nor below a hidden ancestor.
@property(nonatomic, readonly, getter=isOnScreen) BOOL onScreen;

- (instancetype)initWithFrame:(NSRect)frameRect NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder*)coder NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END

#endif  // CEF_LIBCEF_BROWSER_PARC_NATIVE_PANE_COMPOSITOR_VIEW_H_
