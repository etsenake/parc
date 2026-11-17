#pragma once
#import <AppKit/AppKit.h>
@class PCNativePageHost;
NS_ASSUME_NONNULL_BEGIN

typedef struct {
  CGFloat alpha;
  CGFloat lift;
  BOOL finished;
} PCExtensionPopupMotionFrame;

FOUNDATION_EXTERN PCExtensionPopupMotionFrame
PCExtensionPopupOpeningMotion(NSTimeInterval elapsed, BOOL reduceMotion);
FOUNDATION_EXTERN PCExtensionPopupMotionFrame PCExtensionPopupClosingMotion(
    NSTimeInterval elapsed,
    CGFloat alpha,
    CGFloat lift,
    BOOL reduceMotion);
FOUNDATION_EXTERN NSTimeInterval
PCExtensionPopupRevealTime(NSTimeInterval shown,
                           NSTimeInterval painted,
                           NSTimeInterval resized);

@interface PCExtensionPopupAnchor : NSObject
+ (instancetype)windowAnchor;
+ (instancetype)sidebarAnchorWithWidth:(CGFloat)width;
+ (instancetype)focusedViewAnchor:(NSView*)view;
@end

@protocol PCExtensionPopupPlacing <NSObject>
- (nullable NSValue*)parcExtensionPopupOriginForExtension:(NSString*)extensionID
                                                    popup:(NSWindow*)popup
                                                     size:(NSSize)size;
@end

@interface PCExtensionPopupPresenter : NSObject
- (instancetype)initWithParentWindow:(NSWindow*)parent
                            pageHost:(PCNativePageHost*)page
                              anchor:(PCExtensionPopupAnchor* (^)(void))anchor
              mayDismissForParentKey:(BOOL (^)(void))mayDismiss
                           onDismiss:(void (^)(void))onDismiss
    NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (BOOL)prepare;
- (BOOL)show;
- (BOOL)resizeContent:(NSSize)size;
- (void)contentDidPaint;
- (BOOL)dismissWithMotion:(nullable void (^)(void))completion;
- (void)invalidate;
@property(nonatomic, readonly, nullable) NSWindow* popupWindow;
@property(nonatomic, readonly, getter=isPresenting) BOOL presenting;
@property(nonatomic, readonly, getter=isInvalidated) BOOL invalidated;
@property(nonatomic, readonly) BOOL userHasMovedWindow;
@property(nonatomic, copy, nullable) NSString* extensionIdentifier;
@end
NS_ASSUME_NONNULL_END
