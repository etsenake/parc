#pragma once
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSInteger, PCAutofillSaveOutcome) {
  PCAutofillSaveAccepted,
  PCAutofillSaveDeclined,
  PCAutofillSaveInterrupted,
  PCAutofillSaveNever,
};

// One request, main-thread-only. Weak page/window association; no app-modal
// fallback. Native labels are caller-supplied controller/reference copy.
// start and every completion are deferred through the main run loop, including
// immediate failure, so a Chromium caller can install its returned bubble
// first.
@interface PCAutofillSavePresenter : NSObject
- (instancetype)initWithPageView:(NSView*)page
                          window:(NSWindow*)window
                           title:(NSString*)title
                         message:(NSString*)message
                       saveLabel:(NSString*)saveLabel
                    declineLabel:(NSString*)declineLabel
                 validateContext:(BOOL (^)(void))validateContext
                      completion:(void (^)(PCAutofillSaveOutcome))completion
    NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
// Called only after the exact sheet is attached to the supplied page window.
// Cleared before delivery; callback may synchronously invalidate this request.
@property(nonatomic, copy, nullable) void (^onPresented)(void);
@property(nonatomic, copy, nullable) NSString* neverLabel;
- (void)start;
// Terminal. Call BEFORE page detach, navigation replacement or host teardown.
// Also downgrades an accepted result queued but not yet delivered.
- (void)invalidate;
@property(nonatomic, readonly, nullable) NSWindow* sheet;
@property(nonatomic, readonly, getter=isPresenting) BOOL presenting;
@property(nonatomic, readonly, getter=isMouseHovered) BOOL mouseHovered;
@end
NS_ASSUME_NONNULL_END
