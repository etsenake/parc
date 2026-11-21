#import <Cocoa/Cocoa.h>

#import "VideoPiPWindow.h"
#import "native_application_protocols.h"
#import "native_appkit_bridge.h"
#import "native_blocked_popups.h"
#import "native_history_swipe.h"
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
- (void)browserViewDidChangePageColor:(PCBrowserView*)view
    NS_SWIFT_NAME(browserViewDidChangePageColor(_:));
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
+ (int)run;
+ (void)requestTermination:(void (^)(BOOL allow))completion
    NS_SWIFT_NAME(requestTermination(completion:));
+ (void)shutdown;
@end

NS_SWIFT_UI_ACTOR
@interface PCImportedExtensionFailure : NSObject
@property(nonatomic, readonly, copy) NSString* name;
@property(nonatomic, readonly, copy, nullable) NSString* identifier;
@property(nonatomic, readonly, copy, nullable) NSString* profilePath;
@property(nonatomic, readonly) PCNativeExtensionRestriction restriction;
- (instancetype)init NS_UNAVAILABLE;
@end

NS_SWIFT_UI_ACTOR
@interface PCImportedExtensions : NSObject
+ (nullable PCNativeImportSession*)install:(NSArray<PCNativeImportExtensionRequest*>*)requests
    completion:(void (^)(PCNativeImportExtensionResult* result,
                         NSArray<PCImportedExtensionFailure*>* failures))completion
    backgroundFailures:(void (^)(NSArray<PCImportedExtensionFailure*>* failures))backgroundFailures
    NS_SWIFT_NAME(install(_:completion:backgroundFailures:));
+ (PCNativeExtensionRestriction)restrictionForError:(nullable NSError*)error
    NS_SWIFT_NAME(restriction(for:));
- (instancetype)init NS_UNAVAILABLE;
@end

NS_SWIFT_UI_ACTOR
@interface PCBrowserView : NSView
- (instancetype)initWithFrame:(NSRect)frame
                  profilePath:(NSString*)profilePath NS_DESIGNATED_INITIALIZER
    NS_SWIFT_NAME(init(frame:profilePath:));
- (instancetype)initWithFrame:(NSRect)frame
           adoptingNativePage:(PCNativePage*)page
    NS_SWIFT_NAME(init(frame:adoptingNativePage:));
@property(nonatomic, readonly, nullable) PCNativePage* nativePage;
- (nullable PCNativeEmbeddedPageRequest*)beginEmbeddedNavigation:(NSURL*)URL
    referrer:(nullable NSURL*)referrer
    validateOwner:(BOOL (^)(void))validateOwner
    completion:(void (^)(PCNativePage* _Nullable, NSError* _Nullable))completion
    NS_SWIFT_NAME(beginEmbeddedNavigation(_:referrer:validateOwner:completion:));
@property(nonatomic, readonly) BOOL hasPageInfo;
@property(nonatomic, readonly) BOOL canShowSiteInfo;
- (BOOL)showSiteInfoFromView:(NSView*)anchor
    NS_SWIFT_NAME(showSiteInfo(from:));
@property(nonatomic, readonly, nullable) PCNativeCaptureState* captureState;
@property(nonatomic, readonly) BOOL canShareThisTabInstead;
- (BOOL)shareThisTabInstead;
- (BOOL)stopCapture:(PCNativeCaptureState*)state sharing:(BOOL)sharing;
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
@property(nonatomic, readonly)
    PCArchiveProtectionState automaticArchiveProtectionState;
@property(nonatomic, readonly, nullable)
    NSError* automaticArchiveProtectionError;
- (void)loadURL:(NSURL*)URL NS_SWIFT_NAME(loadURL(_:));
- (BOOL)restoreNavigationState:(NSObject*)state URL:(NSURL*)URL
    NS_SWIFT_NAME(restoreNavigationState(_:url:));
- (BOOL)loadBackgroundURL:(NSURL*)URL NS_SWIFT_NAME(loadBackgroundURL(_:));
- (BOOL)loadBackgroundSearchNavigation:(PCNativeSearchNavigation*)navigation
    sourcePage:(nullable PCNativePage*)sourcePage validateOwner:(BOOL (^)(void))validateOwner
    completion:(void (^)(BOOL, NSError* _Nullable))completion;
- (void)loadSearchNavigation:(PCNativeSearchNavigation*)navigation NS_SWIFT_NAME(loadSearchNavigation(_:));
- (void)goBack;
- (void)goForward;
- (void)reload;
- (void)stop;
- (void)closeBrowser;
- (void)setZoomLevel:(double)level NS_SWIFT_NAME(setZoomLevel(_:));
- (BOOL)zoomPage:(NSInteger)direction NS_SWIFT_NAME(zoomPage(_:));
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
- (void)captureRenderingMetricsWithCompletion:
    (void (^)(NSDictionary<NSString*, id>* _Nullable metrics,
              NSError* _Nullable error))completion
    NS_SWIFT_NAME(captureRenderingMetrics(completion:));
@end
NS_ASSUME_NONNULL_END
