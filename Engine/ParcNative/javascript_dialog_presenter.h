// Parc-owned page-bound AppKit dialogs. See tests/NativeJavaScriptDialogs.
#pragma once

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN
@protocol PCNativePresentation, PCNativeScheduling;

typedef NS_ENUM(NSInteger, PCJavaScriptDialogKind) {
  PCJavaScriptDialogAlert,
  PCJavaScriptDialogConfirm,
  PCJavaScriptDialogPrompt,
  PCJavaScriptDialogBeforeUnload,
};

typedef void (^PCJavaScriptDialogCompletion)(BOOL accepted,
                                             NSString* input,
                                             BOOL suppress);

// Main-thread-only, one presenter per live page. It owns requests/sheets, never
// the page or NSWindow. A request's window identity is captured when presented.
// Completion is called exactly once, after removing the request and its sheet;
// it may synchronously destroy this presenter or submit a new request.
//
// Presentation is Parc's dialog sheet (dialog_style.h, see
// docs/web-interactions.md): Parc's mark, the title, the page text, a prompt's
// field, the optional suppression checkbox and OK plus (except for an alert)
// Cancel. OK is inert for half a second after the sheet appears. Before
// unload uses the same OK/Cancel sheet.
@interface PCJavaScriptDialogPresenter : NSObject
- (instancetype)initWithPageView:(NSView*)pageView NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@property(nonatomic, readonly, getter=isPresenting) BOOL presenting;
@property(nonatomic, readonly, nullable) NSWindow* presentedSheet;
@property(nonatomic, strong) id<PCNativePresentation> presentation;
@property(nonatomic, strong) id<PCNativeScheduling> scheduler;

// No window, a closing window, an unrelated existing sheet, or a concurrent
// request completes with NO. No app-modal fallback or automatic consent.
// offersSuppression adds the checkbox; before unload never shows it.
- (void)presentKind:(PCJavaScriptDialogKind)kind
                title:(NSString*)title
              message:(NSString*)message
          defaultText:(NSString*)defaultText
    offersSuppression:(BOOL)offersSuppression
           completion:(PCJavaScriptDialogCompletion)completion;

// nil override preserves the current prompt; an empty string replaces it.
- (void)handleAccepted:(BOOL)accepted promptOverride:(nullable NSString*)input;
- (void)cancel;

// Call BEFORE detaching/moving the page host, including profile/window swaps.
// Blocks new requests before cancellation callbacks run. Pair with didAttach
// only after the actual view hierarchy has been restored (even the same
// window).
- (void)pageHostWillDetach;
- (void)pageHostDidAttach;

// Terminal, idempotent; call before WebContents/page/host destruction. The
// destructor also cancels, but explicit invalidation establishes ordering.
- (void)invalidate;
@end

NS_ASSUME_NONNULL_END
