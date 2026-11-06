// Copyright 2026 Parc contributors.
//
#pragma once
#import <AppKit/AppKit.h>
@class PCNativePageHost;
NS_ASSUME_NONNULL_BEGIN

@interface PCExtensionPopupAnchor : NSObject
+ (instancetype)windowAnchor;
+ (instancetype)sidebarAnchorWithWidth:(CGFloat)width;
+ (instancetype)focusedViewAnchor:(NSView*)view;
@end

// Main thread only. Owns presentation, never an ExtensionViewHost/WebContents.
//
// controller and keep its page alive until engine modal-handler teardown.
@interface PCExtensionPopupPresenter : NSObject
- (instancetype)initWithParentWindow:(NSWindow*)parent
                            pageHost:(PCNativePageHost*)page
                              anchor:(PCExtensionPopupAnchor* (^)(void))anchor
              mayDismissForParentKey:(BOOL (^)(void))mayDismiss
                           onDismiss:(void (^)(void))onDismiss
    NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
// Attach without showing; install all engine callbacks before starting load.
- (BOOL)prepare;
- (BOOL)show;
- (BOOL)resizeContent:(NSSize)size;
// Terminal, idempotent. Suppresses callbacks and explicitly detaches the page.
// Does not invalidate the page host or destroy its supplied native contents.
- (void)invalidate;
@property(nonatomic, readonly, nullable) NSWindow* popupWindow;
@property(nonatomic, readonly, getter=isPresenting) BOOL presenting;
@property(nonatomic, readonly, getter=isInvalidated) BOOL invalidated;
@property(nonatomic, readonly) BOOL userHasMovedWindow;
@end
NS_ASSUME_NONNULL_END
