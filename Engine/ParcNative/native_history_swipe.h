#ifndef PARC_NATIVE_NATIVE_HISTORY_SWIPE_H_
#define PARC_NATIVE_NATIVE_HISTORY_SWIPE_H_
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN
@class PCNativeHistorySwipeSource;

typedef NS_ENUM(NSInteger, PCNativeHistorySwipeTouchPhase) {
  PCNativeHistorySwipeTouchPhaseBegan,
  PCNativeHistorySwipeTouchPhaseMoved,
  PCNativeHistorySwipeTouchPhaseEnded,
  PCNativeHistorySwipeTouchPhaseCancelled,
};

NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeHistorySwipeEntry : NSObject
@property(nonatomic, readonly, copy) NSString* title;
@property(nonatomic, readonly, nullable) NSURL* URL;
@property(nonatomic, readonly, nullable) NSImage* favicon;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeHistorySwipeHistory : NSObject
@property(nonatomic, readonly, copy) NSArray<PCNativeHistorySwipeEntry*>* entries;
@property(nonatomic, readonly) NSInteger currentIndex;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

NS_SWIFT_UI_ACTOR
@protocol PCNativeHistorySwipeHandler <NSObject>
- (BOOL)historySwipeSource:(PCNativeHistorySwipeSource*)source
               scrollEvent:(NSEvent*)event
    NS_SWIFT_NAME(historySwipeSource(_:scroll:));
- (void)historySwipeSource:(PCNativeHistorySwipeSource*)source
                touchEvent:(NSEvent*)event
                     phase:(PCNativeHistorySwipeTouchPhase)phase
    NS_SWIFT_NAME(historySwipeSource(_:touches:phase:));
- (void)historySwipeSource:(PCNativeHistorySwipeSource*)source
    pageScrollBeganSynthetic:(BOOL)synthetic
                    momentum:(BOOL)momentum
    NS_SWIFT_NAME(historySwipeSource(_:pageScrollBeganSynthetic:momentum:));
- (void)historySwipeSource:(PCNativeHistorySwipeSource*)source
    pageScrollUpdatedConsumed:(BOOL)consumed
    NS_SWIFT_NAME(historySwipeSource(_:pageScrollUpdatedConsumed:));
- (void)historySwipeSource:(PCNativeHistorySwipeSource*)source
     overscrollPropagatesX:(BOOL)propagates
    NS_SWIFT_NAME(historySwipeSource(_:overscrollPropagatesX:));
- (void)historySwipeSourceDidCancel:(PCNativeHistorySwipeSource*)source
    NS_SWIFT_NAME(historySwipeSourceDidCancel(_:));
@end

NS_SWIFT_UI_ACTOR
@protocol PCNativeHistorySwipeClient <NSObject>
- (id<PCNativeHistorySwipeHandler>)historySwipeHandlerForSource:
    (PCNativeHistorySwipeSource*)source
    NS_SWIFT_NAME(historySwipeHandler(for:));
@end

NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeHistorySwipeSource : NSObject
@property(class, nonatomic, weak, nullable) id<PCNativeHistorySwipeClient> client;
@property(nonatomic, readonly, nullable) NSView* overlayContainer;
@property(nonatomic, readonly) BOOL allowsHistorySwipe;
- (NSInteger)historyEntriesBack:(BOOL)back NS_SWIFT_NAME(historyEntries(back:));
- (nullable PCNativeHistorySwipeHistory*)beginSwipeBack:(BOOL)back
    NS_SWIFT_NAME(beginSwipe(back:));
- (BOOL)navigateBack:(BOOL)back NS_SWIFT_NAME(navigate(back:));
- (BOOL)navigateBack:(BOOL)back distance:(NSInteger)distance
    NS_SWIFT_NAME(navigate(back:distance:));
- (void)endSwipe;
- (void)preloadBack;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
NS_ASSUME_NONNULL_END

#ifdef __cplusplus
#import "content/public/browser/render_widget_host_view_mac_delegate.h"
namespace content {
class RenderWidgetHost;
}
namespace parc {
NS_ASSUME_NONNULL_BEGIN
NSObject<RenderWidgetHostViewMacDelegate>* CreateNativeHistorySwipeDelegate(
    content::RenderWidgetHost* host);
NS_ASSUME_NONNULL_END
}
#endif
#endif
