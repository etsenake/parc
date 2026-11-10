#import <Cocoa/Cocoa.h>

#import "VideoPiPWindow.h"
#import "native_application_protocols.h"
#import "native_appkit_bridge.h"
#import "page_host.h"
#import "content_drop_router.h"
#import "content_drop_bridge.h"

NS_ASSUME_NONNULL_BEGIN
@class PCBrowserView;

typedef NS_ENUM(NSInteger, PCArchiveProtectionState) {
  PCArchiveProtectionStateUnknown = 0,
  PCArchiveProtectionStateEligible,
  PCArchiveProtectionStateProtected,
};

NS_SWIFT_UI_ACTOR
@protocol PCBrowserViewDelegate <NSObject>
@optional
- (void)browserViewDidChangeFavicon:(PCBrowserView*)view;
// The page came into view and its frame is on screen.
- (void)browserViewDidPresentFrame:(PCBrowserView*)view
    NS_SWIFT_NAME(browserViewDidPresentFrame(_:));
- (void)browserView:(PCBrowserView*)view addContextImageToEasel:(PCNativeContextImage*)image
    NS_SWIFT_NAME(browserView(_:addContextImageToEasel:));
- (void)browserView:(PCBrowserView*)view openLinkInSplitView:(NSURL*)url
    NS_SWIFT_NAME(browserView(_:openLinkInSplitView:));
- (BOOL)browserViewCanOpenLinkInSplitView:(PCBrowserView*)view
    NS_SWIFT_NAME(browserViewCanOpenLinkInSplitView(_:));
- (void)browserView:(PCBrowserView*)view
    didChangeCaptureState:(nullable PCNativeCaptureState*)state
    NS_SWIFT_NAME(browserView(_:didChangeCaptureState:));
- (void)browserView:(PCBrowserView*)view
     didChangeTitle:(NSString*)title
    NS_SWIFT_NAME(browserView(_:didChangeTitle:));
- (void)browserView:(PCBrowserView*)view
       didChangeURL:(NSURL*)URL NS_SWIFT_NAME(browserView(_:didChangeURL:));
- (void)browserView:(PCBrowserView*)view
    didChangeLoading:(BOOL)loading
           canGoBack:(BOOL)back
        canGoForward:(BOOL)forward
    NS_SWIFT_NAME(browserView(_:didChangeLoading:canGoBack:canGoForward:));
- (void)browserView:(PCBrowserView*)view
    didChangeRendererCrash:(nullable PCNativeRendererCrash*)crash
    NS_SWIFT_NAME(browserView(_:didChangeRendererCrash:));
// The page's top-bar colour inputs changed: developerModeTint, or
// pageBackgroundColor where the engine has it. Colour-only; repaint the bar,
// not the window's chrome, since background transitions can notify per frame.
- (void)browserViewDidChangePageColor:(PCBrowserView*)view
    NS_SWIFT_NAME(browserViewDidChangePageColor(_:));
// The page's media controls, tab audio or media route changed
// (mediaControlsRevision moved). No other key carries these.
- (void)browserViewDidChangeMedia:(PCBrowserView*)view
    NS_SWIFT_NAME(browserViewDidChangeMedia(_:));
- (void)browserView:(PCBrowserView*)view
    requestFocusForRendererCrash:(PCNativeRendererCrash*)crash
    NS_SWIFT_NAME(browserView(_:requestFocusForRendererCrash:));
- (void)browserViewDidRequestClose:(PCBrowserView*)view
    NS_SWIFT_NAME(browserViewDidRequestClose(_:));
- (void)browserView:(PCBrowserView*)view
    didFailWithError:(NSError*)error
    NS_SWIFT_NAME(browserView(_:didFailWithError:));
// The engine learned that `site` needs Safari's identity for FairPlay; record
// it for the page's Profile, or its private context (docs/fairplay-identity.md).
- (void)browserView:(PCBrowserView*)view
    didLearnSafariIdentityForSite:(NSString*)site
                      profilePath:(NSString*)profilePath
                     offTheRecord:(BOOL)offTheRecord
    NS_SWIFT_NAME(browserView(_:didLearnSafariIdentityForSite:profilePath:offTheRecord:));

@end

typedef NS_ENUM(NSInteger, PCBrowserEngineStartStatus) {
  PCBrowserEngineStartStatusReady,
  PCBrowserEngineStartStatusEarlyExit,
  PCBrowserEngineStartStatusFailed,
};

// A normal singleton handoff is an early exit with no error. Preserve exitCode
// from main; run/shutdown are legal only after Ready.
@interface PCBrowserEngineStartup : NSObject
@property(nonatomic, readonly) PCBrowserEngineStartStatus status;
@property(nonatomic, readonly) int exitCode;
@property(nonatomic, readonly, nullable) NSError* error;
- (instancetype)init NS_UNAVAILABLE;
@end

NS_SWIFT_UI_ACTOR
@interface PCBrowserEngine : NSObject
+ (PCBrowserEngineStartup*)startWithFrameworkPath:(NSString*)frameworkPath
                                        cachePath:(NSString*)cachePath
    NS_SWIFT_NAME(start(frameworkPath:cachePath:));
// The independent Chromium backend owns its native message loop; run once on
// the main thread.
+ (int)run;
// Call from the NSApplication terminate: override, which must return without
// entering NSTerminateLater. YES follows consent, actual drain and engine shutdown;
// NO leaves the native loop and same browser pages alive. Main-thread callback.
+ (void)requestTermination:(void (^)(BOOL allow))completion
    NS_SWIFT_NAME(requestTermination(completion:));
// Release engine state after run returns. This does not request termination.
+ (void)shutdown;
@end

NS_SWIFT_UI_ACTOR
@interface PCBrowserView : NSView
- (instancetype)initWithFrame:(NSRect)frame
                  profilePath:(NSString*)profilePath NS_DESIGNATED_INITIALIZER
    NS_SWIFT_NAME(init(frame:profilePath:));
// Adopts the same real page, including popup opener/POST state. Never
// navigates.
- (instancetype)initWithFrame:(NSRect)frame
           adoptingNativePage:(PCNativePage*)page
    NS_SWIFT_NAME(init(frame:adoptingNativePage:));
@property(nonatomic, readonly, nullable) PCNativePage* nativePage;
// The wrapper must already belong to the original Easel's registered window.
// A nil return creates nothing. Retain the request for pre-creation cancellation;
// after completion use this wrapper/page's normal beforeunload close APIs.
- (nullable PCNativeEmbeddedPageRequest*)beginEmbeddedNavigation:(NSURL*)URL
    validateOwner:(BOOL (^)(void))validateOwner
    completion:(void (^)(PCNativePage* _Nullable, NSError* _Nullable))completion
    NS_SWIFT_NAME(beginEmbeddedNavigation(_:validateOwner:completion:));
// Chromium's desktop PageInfo refuses WebUI, DevTools, view-source and
// extension pages, judged on the committed URL. Only a visible and committed
// http/https page (developerModeHost) is offered it.
@property(nonatomic, readonly) BOOL hasPageInfo;
@property(nonatomic, readonly) BOOL canShowSiteInfo;
- (BOOL)showSiteInfoFromView:(NSView*)anchor
    NS_SWIFT_NAME(showSiteInfo(from:));
@property(nonatomic, readonly, nullable) PCNativeCaptureState* captureState;
//
@property(nonatomic, readonly) BOOL canShareThisTabInstead;
- (BOOL)shareThisTabInstead;
- (BOOL)stopCapture:(PCNativeCaptureState*)state sharing:(BOOL)sharing;
// Actual native SadTab instance state. A reload request does not clear it.
@property(nonatomic, readonly, nullable) PCNativeRendererCrash* rendererCrash;
- (BOOL)rendererCrashDidPresent:(PCNativeRendererCrash*)crash;
- (BOOL)performRendererCrashAction:(PCNativeRendererCrash*)crash;
- (void)requestClose:(void (^)(PCNativePageCloseResult result))completion
    NS_SWIFT_NAME(requestClose(completion:));
- (instancetype)initWithFrame:(NSRect)frame NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder*)coder NS_UNAVAILABLE;
@property(nonatomic, weak, nullable) id<PCBrowserViewDelegate> delegate;
@property(nonatomic, readonly, nullable) NSURL* URL;
@property(nonatomic, readonly, copy) NSString* title;
@property(nonatomic, readonly) BOOL isLoading;
@property(nonatomic, readonly) BOOL canGoBack;
@property(nonatomic, readonly) BOOL canGoForward;
// Main-thread live preflight for automatic archive only. Unknown must protect
// the tab, as must Protected. Eligible is not consent for a manual close and
// does not replace the shell's age, selection, pinning or split checks.
@property(nonatomic, readonly)
    PCArchiveProtectionState automaticArchiveProtectionState;
@property(nonatomic, readonly, nullable)
    NSError* automaticArchiveProtectionError;
- (void)loadURL:(NSURL*)URL NS_SWIFT_NAME(loadURL(_:));
// Instead of the first loadURL for a tab Undo or Reopen restores: its page is
// created from a -[PCNativePage captureNavigationState] value, with `URL` as
// its address until then. If the engine lacks the restore or refuses the
// value, the page opens `URL` alone. NO when a page already exists or is
// being created, so the caller loads `URL` itself.
- (BOOL)restoreNavigationState:(NSObject*)state URL:(NSURL*)URL
    NS_SWIFT_NAME(restoreNavigationState(_:url:));
// Initial creation only: exact supplied window/profile, no tab/window activation.
- (BOOL)loadBackgroundURL:(NSURL*)URL NS_SWIFT_NAME(loadBackgroundURL(_:));
- (BOOL)loadBackgroundSearchNavigation:(PCNativeSearchNavigation*)navigation
    sourcePage:(nullable PCNativePage*)sourcePage validateOwner:(BOOL (^)(void))validateOwner
    completion:(void (^)(BOOL, NSError* _Nullable))completion;
- (void)loadSearchNavigation:(PCNativeSearchNavigation*)navigation NS_SWIFT_NAME(loadSearchNavigation(_:));
- (void)goBack;
- (void)goForward;
- (void)reload;
- (void)stop;
// Explicit disposal compatibility; UI tab removal must use requestClose.
- (void)closeBrowser;
- (void)setZoomLevel:(double)level NS_SWIFT_NAME(setZoomLevel(_:));
/// Chromium's page zoom command (its preset steps, remembered per site):
/// negative zooms out, positive in, zero resets. NO when the engine predates it.
- (BOOL)zoomPage:(NSInteger)direction NS_SWIFT_NAME(zoomPage(_:));
/// The page's current zoom level on Chromium's log-1.2 scale.
@property(nonatomic, readonly) double pageZoomLevel;
- (void)showDevTools;
- (BOOL)canPerformPageTool:(PCNativePageTool)tool NS_SWIFT_NAME(canPerformPageTool(_:));
- (BOOL)performPageTool:(PCNativePageTool)tool NS_SWIFT_NAME(performPageTool(_:));
@property(nonatomic, readonly) PCNativeReaderMode readerMode;
@property(nonatomic, readonly) NSUInteger readerRevision;
@property(nonatomic, readonly, copy) NSString* readerMessage;
- (BOOL)canToggleReaderMode;
- (BOOL)toggleReaderMode;
- (void)findText:(NSString*)text
         forward:(BOOL)forward
        findNext:(BOOL)findNext NS_SWIFT_NAME(findText(_:forward:findNext:));
- (void)stopFinding;
// The independent renderer diagnostics transport is not connected yet. This
// compatibility call reports an explicit error; no metrics are fabricated.
- (void)captureRenderingMetricsWithCompletion:
    (void (^)(NSDictionary<NSString*, id>* _Nullable metrics,
              NSError* _Nullable error))completion
    NS_SWIFT_NAME(captureRenderingMetrics(completion:));
@end
NS_ASSUME_NONNULL_END
