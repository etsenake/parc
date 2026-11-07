// Copyright 2026 Parc contributors.
// Public Objective-C boundary shared by the built engine and the existing
//
#pragma once
#import <AppKit/AppKit.h>
NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSInteger, PCVideoPiPAction) {
  PCVideoPiPClose,
  PCVideoPiPReturn,
  PCVideoPiPMinimize,
  PCVideoPiPPlayPause,
  PCVideoPiPSkipAd,
  PCVideoPiPNextTrack,
  PCVideoPiPPreviousTrack,
  PCVideoPiPMicrophone,
  PCVideoPiPCamera,
  PCVideoPiPHangUp,
  PCVideoPiPNextSlide,
  PCVideoPiPPreviousSlide,
  PCVideoPiPMute,
  PCVideoPiPSeek,
  PCVideoPiPSystemClose,
  PCVideoPiPBeginScrubbing,
  PCVideoPiPEndScrubbing,
};

// App-owned visible video PiP presentation. The engine supplies the actual
// composited NSView and real controller callbacks; no second WebContents.
NS_SWIFT_UI_ACTOR
@protocol PCNativeVideoPiPWindow <NSObject>
@property(nonatomic, readonly) NSPanel* panel;
@property(nonatomic, readonly) NSView* videoView;
@property(nonatomic, readonly, getter=isInvalidated) BOOL invalidated;
- (void)showInactive;
- (void)hide;
- (void)invalidate;
- (void)setNaturalSize:(NSSize)size;
- (void)setAction:(PCVideoPiPAction)action visible:(BOOL)visible;
- (void)setAction:(PCVideoPiPAction)action title:(NSString*)title;
- (void)setControlsVisible:(BOOL)visible;
- (void)setSourceTitle:(NSString*)title;
- (void)setFavicon:(nullable NSImage*)image;
- (void)setPosition:(double)position duration:(double)duration;
@end

@class PCNativePage;
// A user-requested screenshot of one original renderer document. Pixel data
// contains only page content; viewport/region coordinates are upper-left DIPs.
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeCaptureLayout : NSObject
@property(nonatomic, readonly) NSSize viewportSize;
@property(nonatomic, readonly) NSPoint scrollOffset;
@property(nonatomic, readonly) NSRect region;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativePageCaptureResult : NSObject
@property(nonatomic, readonly, copy, nullable) NSData* pngData;
@property(nonatomic, readonly, nullable) NSImage* image;
@property(nonatomic, readonly) NSSize pixelSize;
@property(nonatomic, readonly, copy, nullable) NSString* errorMessage;
// CSS-pixel geometry, present only when the original document's geometry
// remained unchanged around the actual compositor copy. Full-page has no crop.
@property(nonatomic, readonly, nullable) PCNativeCaptureLayout* layout;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

// An opaque hover offer from one capture lease and query generation. Bounds are
// clipped to the original viewport in upper-left DIPs; no page object escapes.
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativePageCaptureTarget : NSObject
@property(nonatomic, readonly) NSRect viewportRect;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativePageCapture : NSObject
// Validity is independent of the lease owner's Save/Easel sheet. Starting
// another capture separately requires the active visible source window.
@property(nonatomic, readonly, getter=isValid) BOOL valid;
@property(nonatomic, readonly, getter=isCapturing) BOOL capturing;
@property(nonatomic, readonly) NSSize viewportSize;
// Actual renderer rectangle in page.nativeView AppKit coordinates.
@property(nonatomic, readonly) NSRect viewportFrame;
@property(nonatomic, readonly, copy) NSString* sourceURL;
@property(nonatomic, readonly, copy) NSString* pageTitle;
// Actual theme color of this lease's original live document; never a Space color.
@property(nonatomic, readonly, nullable) NSColor* pageThemeColor;
@property(nonatomic, copy, nullable) void (^invalidated)(void);
// Replies are asynchronous on main. Superseded, invalid or ineligible queries
// reply nil. Only the latest offered token from this lease may be captured.
- (void)targetElementAtPoint:(NSPoint)point
                 completion:(void (^)(PCNativePageCaptureTarget* _Nullable))completion
    NS_SWIFT_NAME(targetElement(at:completion:));
// Revalidates the original point and geometry before copying compositor pixels.
- (void)captureElement:(PCNativePageCaptureTarget*)target
           completion:(void (^)(PCNativePageCaptureResult*))completion
    NS_SWIFT_NAME(captureElement(_:completion:));
- (void)invalidate;
- (void)captureRegion:(NSRect)region
          completion:(void (^)(PCNativePageCaptureResult*))completion
    NS_SWIFT_NAME(captureRegion(_:completion:));
- (void)captureViewportWithCompletion:(void (^)(PCNativePageCaptureResult*))completion
    NS_SWIFT_NAME(captureViewport(completion:));
- (void)captureFullPageWithCompletion:(void (^)(PCNativePageCaptureResult*))completion
    NS_SWIFT_NAME(captureFullPage(completion:));
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

@class PCNativeRendererCrash;
@class PCNativeBrowserWindow;

typedef NS_ENUM(NSInteger, PCNativeShortcutPriority) {
  PCNativeShortcutPriorityPreferWebsites,
  PCNativeShortcutPriorityUseBoth,
  PCNativeShortcutPriorityPreferParc,
};
// The native router retains a weak menu identity, not a command name resolved
// later against another window. The shell revalidates its binding revision.
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeShortcutCommand : NSObject
@property(nonatomic, readonly, weak, nullable) NSMenuItem* item;
@property(nonatomic, readonly) uint64_t revision;
@property(nonatomic, readonly) PCNativeShortcutPriority priority;
- (instancetype)initWithItem:(NSMenuItem*)item revision:(uint64_t)revision
                   priority:(PCNativeShortcutPriority)priority
    NS_SWIFT_NAME(init(item:revision:priority:));
+ (void)bindingsDidChange;
@end

// Copied presentation for the actual page's card/IBAN controller. The opaque
// token is checked again at dispatch; no payment credentials cross this ABI.
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativePaymentAction : NSObject
@property(nonatomic, readonly, copy) NSString* title;
@property(nonatomic, readonly, copy) NSString* symbolName;
@property(nonatomic, readonly, copy) NSString* savedLabel;
// An actual omnibox suggestion request awaits visible native entry
// acknowledgment.
@property(nonatomic, readonly) BOOL requiresPresentationAcknowledgment;
@property(nonatomic, readonly, getter=isEnabled) BOOL enabled;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

// A real offered Open in App action, bound to the exact document and window.
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeOpenAppAction : NSObject
@property(nonatomic, readonly, copy) NSString* title;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

// A close request is not a close notification. Only Closed authorizes removal
// from the shell's saved tab model; Cancelled retains the same live page.
typedef NS_ENUM(NSInteger, PCNativeDownloadAction) {
  PCNativeDownloadActionPause,
  PCNativeDownloadActionResume,
  PCNativeDownloadActionCancel,
  PCNativeDownloadActionRetry,
  PCNativeDownloadActionOpen,
  PCNativeDownloadActionReveal,
  PCNativeDownloadActionRemove,
  PCNativeDownloadActionToggleOpen,
};

typedef NS_ENUM(NSInteger, PCNativeDownloadReviewAction) {
  PCNativeDownloadReviewActionKeep,
  PCNativeDownloadReviewActionDiscard,
  PCNativeDownloadReviewActionScan,
  PCNativeDownloadReviewActionBypassScan,
  PCNativeDownloadReviewActionCancelScan,
};

NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeDownloadReviewButton : NSObject
@property(nonatomic, readonly) PCNativeDownloadReviewAction action;
@property(nonatomic, readonly, copy) NSString* title;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

// Immutable warning/decision lease for one Profile and item incarnation.
// The engine revalidates the complete warning and allowed actions on use.
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeDownloadReview : NSObject
@property(nonatomic, readonly, copy) NSString* identifier;
@property(nonatomic, readonly, copy) NSString* profilePath;
@property(nonatomic, readonly, copy) NSString* fileName;
@property(nonatomic, readonly, copy) NSString* sourceURL;
@property(nonatomic, readonly, copy) NSString* warning;
@property(nonatomic, readonly, copy) NSString* secondaryWarning;
@property(nonatomic, readonly, copy) NSString* keepTitle;
@property(nonatomic, readonly, copy) NSString* discardTitle;
@property(nonatomic, readonly) BOOL canKeep;
@property(nonatomic, readonly) BOOL canDiscard;
@property(nonatomic, readonly, copy) NSArray<PCNativeDownloadReviewButton*>* buttons;
@property(nonatomic, readonly, copy) NSArray<NSString*>* linkTitles;
@property(nonatomic, readonly) BOOL needsPassword;
@property(nonatomic, readonly) BOOL incorrectPassword;
@property(nonatomic, readonly) BOOL scanning;
@property(nonatomic, readonly) BOOL needsJustification;
@property(nonatomic, readonly, copy) NSString* passwordLabel;
@property(nonatomic, readonly, copy) NSString* passwordError;
@property(nonatomic, readonly, copy) NSString* passwordEmptyError;
@property(nonatomic, readonly, copy) NSString* justificationLabel;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

// Memory-only lease for one existing OTR DownloadManager. It does not retain
// or create a Profile. Every operation resolves the exact live private owner;
// the identifier cannot authorize a replacement context at the same path.
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativePrivateDownloadContext : NSObject
@property(nonatomic, readonly, copy) NSString* identifier;
@property(nonatomic, readonly, copy) NSString* profilePath;
@property(nonatomic, readonly) BOOL isValid;
@property(nonatomic, readonly, nullable) PCNativeBrowserWindow* sourceWindow;
- (void)refreshWithCompletion:(void (^)(NSArray<NSString*>* _Nullable identifiers, NSError* _Nullable error))completion
    NS_SWIFT_NAME(refresh(completion:));
- (BOOL)performAction:(PCNativeDownloadAction)action identifier:(NSString*)identifier itemIdentity:(NSString*)identity
    NS_SWIFT_NAME(perform(_:identifier:itemIdentity:));
- (nullable NSURL*)fileURLForIdentifier:(NSString*)identifier itemIdentity:(NSString*)identity
    NS_SWIFT_NAME(fileURL(identifier:itemIdentity:));
- (nullable PCNativeDownloadReview*)reviewForIdentifier:(NSString*)identifier itemIdentity:(NSString*)identity
    NS_SWIFT_NAME(review(identifier:itemIdentity:));
- (BOOL)performReviewAction:(PCNativeDownloadReviewAction)action forReview:(PCNativeDownloadReview*)review
                  password:(NSString*)password justification:(NSString*)justification
    NS_SWIFT_NAME(performReview(_:for:password:justification:));
- (nullable NSURL*)reviewLinkAtIndex:(NSUInteger)index forReview:(PCNativeDownloadReview*)review
    NS_SWIFT_NAME(reviewLink(at:for:));
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

// Effective values of the actual persistent Profile. This immutable snapshot
// also carries private weak profile identity; retaining it cannot keep a
// Profile alive or authorize a write to a later Profile at the same path.
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeDownloadPreferences : NSObject
@property(nonatomic, readonly, copy) NSString* profilePath;
@property(nonatomic, readonly, copy) NSURL* directoryURL;
@property(nonatomic, readonly) BOOL promptForDownload;
@property(nonatomic, readonly) BOOL directoryManaged;
@property(nonatomic, readonly) BOOL promptManaged;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

typedef NS_ENUM(NSInteger, PCNativePageCloseResult) {
  PCNativePageCloseResultClosed,
  PCNativePageCloseResultCancelled,
};
typedef NS_ENUM(NSInteger, PCNativeArchiveProtectionState) {
  PCNativeArchiveProtectionStateUnknown,
  PCNativeArchiveProtectionStateEligible,
  PCNativeArchiveProtectionStateProtected,
};
typedef NS_ENUM(NSInteger, PCNativeWindowKind) {
  PCNativeWindowKindBrowser,
  PCNativeWindowKindPopup,
  PCNativeWindowKindDeveloperTools,
  PCNativeWindowKindPictureInPicture,
};

// Actual registered Chromium contexts, independent of profile directory names.
// Multiple regular Profiles in one physical window still form a regular window.
typedef NS_ENUM(NSInteger, PCNativeBrowsingContextKind) {
  PCNativeBrowsingContextKindUnavailable,
  PCNativeBrowsingContextKindRegular,
  PCNativeBrowsingContextKindOffTheRecord,
  PCNativeBrowsingContextKindMixed,
};

// Copied presentation descriptor for one synchronous native reservation.
// Source identity is weak and optional; it never selects an unrelated window
// or keeps an opener Browser alive. Geometry is in AppKit screen coordinates.
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeWindowRequest : NSObject
@property(nonatomic, readonly, copy) NSString* profilePath;
@property(nonatomic, readonly) PCNativeWindowKind kind;
// Copied from the exact original Profile at reservation time. OTR and regular
// Profiles can share a path; callers must never infer this from profilePath.
@property(nonatomic, readonly, getter=isOffTheRecord) BOOL offTheRecord;
@property(nonatomic, readonly, weak, nullable) PCNativeBrowserWindow* source;
@property(nonatomic, readonly) NSRect initialFrame;
@property(nonatomic, readonly) BOOL initialOriginSpecified;
@property(nonatomic, readonly) BOOL canResize;
@property(nonatomic, readonly) BOOL canMaximize;
@property(nonatomic, readonly) BOOL canFullscreen;
@property(nonatomic, readonly) BOOL userGesture;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

typedef NS_ENUM(NSInteger, PCNativePageDisposition) {
  PCNativePageDispositionForegroundTab,
  PCNativePageDispositionBackgroundTab,
  PCNativePageDispositionNewWindow,
  PCNativePageDispositionPopup,
  PCNativePageDispositionPeek,
  PCNativePageDispositionSplitTab,
};

// One original renderer context image and its exact source-document/window lease.
// Invalidated by navigation, page detachment or window closure. PNG bytes never
// come from a URL re-fetch or the shared pasteboard.
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeContextImage : NSObject
@property(nonatomic, readonly, copy) NSData* PNGData NS_SWIFT_NAME(pngData);
@property(nonatomic, readonly, nullable, copy) NSString* errorMessage;
@property(nonatomic, readonly, nullable, copy) NSURL* sourceURL;
@property(nonatomic, readonly, copy) NSString* pageTitle;
@property(nonatomic, readonly, getter=isValid) BOOL valid;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

//
//
// theme's SemanticColorPalette.background). The appearance keeps the pill's
// named colors in that palette's light/dark variant. Read on presentation.
NS_SWIFT_UI_ACTOR
@protocol PCNativeStatusTextThemeSource <NSObject>
- (nullable NSColor*)statusTextThemeBackgroundColor;
- (nullable NSAppearance*)statusTextThemeAppearance;
@end

NS_SWIFT_UI_ACTOR
@protocol PCNativePageObserver <NSObject>
- (void)nativePageDidChange:(PCNativePage*)page;
- (void)nativePageDidClose:(PCNativePage*)page;
- (void)nativePage:(PCNativePage*)page didFailWithError:(NSError*)error;

@optional
// Image-only update; never republishes a URL/title as a history event.
- (void)nativePageFaviconDidChange:(PCNativePage*)page;
- (void)nativePage:(PCNativePage*)page addContextImageToEasel:(PCNativeContextImage*)image;
//
// 0x4266d7c): the chosen link of this exact visible page, revalidated for the
// same document/window when chosen. The shell places it as a split pane after
// that page or refuses; the engine opens nothing itself.
- (void)nativePage:(PCNativePage*)page openLinkInSplitView:(NSURL*)url;
// Whether the shell could place a split pane after this page now (menu
// validation; a pure state read). The pane-limit refusal is still an action.
- (BOOL)nativePageCanOpenLinkInSplitView:(PCNativePage*)page;
// Explicit engine focus only; metadata changes must not steal address focus.
- (void)nativePage:(PCNativePage*)page
    requestFocusForRendererCrash:(PCNativeRendererCrash*)crash;
// The engine held this page's request for a Widevine CDM, so no Widevine
// license request left, added `site` to the Safari sites of the page's
// browsing context and reloaded the site's pages with Safari's identity
// (docs/fairplay-identity.md). The shell records the site for that context:
// the page's Profile, or its private context when
// fairPlayIdentityOffTheRecord is YES.
- (void)nativePage:(PCNativePage*)page didLearnSafariIdentityForSite:(NSString*)site;
@end

// One immutable snapshot per actual native SadTab instance. Status is the
// current engine termination value, not a shell classification. A retained
// snapshot cannot authorize actions after that instance is reset/replaced.
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeRendererCrash : NSObject
@property(nonatomic, readonly) NSInteger terminationStatus;
@property(nonatomic, readonly) NSInteger errorCode;
@property(nonatomic, readonly, copy) NSString* title;
@property(nonatomic, readonly, copy) NSString* message;
@property(nonatomic, readonly, copy) NSString* actionTitle;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

// Copied producer state plus leases to the exact currently active stream
// callbacks. No device permission, picker selection or saved tab flag is an
// active capture. Stop leases cannot stop later replacement streams.
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeCaptureState : NSObject
@property(nonatomic, readonly) BOOL camera;
@property(nonatomic, readonly) BOOL microphone;
@property(nonatomic, readonly) BOOL tab;
@property(nonatomic, readonly) BOOL window;
@property(nonatomic, readonly) BOOL display;
@property(nonatomic, readonly) BOOL mirrored;
// This page is the actual DesktopMediaID source of a started capture.
@property(nonatomic, readonly) BOOL shared;
@property(nonatomic, readonly) BOOL active;
@property(nonatomic, readonly) BOOL canStopDevices;
@property(nonatomic, readonly) BOOL canStopSharing;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

// Page commands keep the actual Chromium document, policy and native parent.
// Print uses the real preview (including PDF destination) unless profile policy
// selects the system dialog. No exported file or replacement tab is
// synthesized.
typedef NS_ENUM(NSInteger, PCNativePageTool) {
  PCNativePageToolPrint,
  PCNativePageToolSave,
  PCNativePageToolViewSource,
  PCNativePageToolClearBrowsingData,
  PCNativePageToolClearCacheAndRefresh,
  PCNativePageToolClearCookiesAndRefresh,
  PCNativePageToolDeveloperTools,
  PCNativePageToolInspectElements,
  PCNativePageToolJavaScriptConsole,
  PCNativePageToolNetworkInspector,
  PCNativePageToolCast,
  //
  // MainMenu record 382); enabled by CanOpenTaskManager().
  PCNativePageToolTaskManager,
  // Keep this case last: the command bar's pre-open snapshot asks the engine
  // for every value from Print through PCNativePageToolTaskManager.
};

typedef NS_ENUM(NSInteger, PCNativeReaderMode) {
  PCNativeReaderModeInactive,
  PCNativeReaderModeDistilling,
  PCNativeReaderModeViewing,
  PCNativeReaderModeUnavailable,
  PCNativeReaderModeFailedViewer,
};

// Retains a handle to the same real WebContents/CEF host through a tab move.
// It never owns/deletes WebContents; the actual TabStripModel does. The view is
// its existing native page wrapper, not a newly navigated replacement.
// Immutable state of the original document's live Chromium media session.
// Retaining a snapshot cannot authorize actions after navigation/transfer.
typedef NS_ENUM(NSInteger, PCNativeMediaAction) {
  PCNativeMediaActionPlay, PCNativeMediaActionPause,
  PCNativeMediaActionPreviousTrack, PCNativeMediaActionNextTrack,
  PCNativeMediaActionToggleMuted, PCNativeMediaActionToggleMicrophone,
  PCNativeMediaActionToggleCamera, PCNativeMediaActionEnterPictureInPicture
};
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeMediaState : NSObject
@property(nonatomic, readonly, nullable) NSImage* icon;
@property(nonatomic, readonly, copy) NSString* identifier;
@property(nonatomic, readonly, copy) NSString* title;
@property(nonatomic, readonly, copy) NSString* sourceURL;
@property(nonatomic, readonly, getter=isOffTheRecord) BOOL offTheRecord;
// Stable admission order, scoped to the original privacy context.
@property(nonatomic, readonly) uint64_t admissionSequence;
@property(nonatomic, readonly) BOOL playing;
@property(nonatomic, readonly) BOOL canPlayPause;
@property(nonatomic, readonly) BOOL hasPreviousTrack;
@property(nonatomic, readonly) BOOL hasNextTrack;
@property(nonatomic, readonly) BOOL muted;
@property(nonatomic, readonly) double volume;
@property(nonatomic, readonly) BOOL canSetVolume;
@property(nonatomic, readonly) BOOL canToggleMicrophone;
@property(nonatomic, readonly) BOOL canToggleCamera;
@property(nonatomic, readonly) BOOL microphoneOn;
@property(nonatomic, readonly) BOOL cameraOn;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

// Immutable output of the original document's FindTabHelper, never a count
// synthesized from a query or a result from another page. Negative counts are
// still unknown; finalUpdate is Chromium's actual completion flag.
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeFindResult : NSObject
@property(nonatomic, readonly, copy) NSString* query;
@property(nonatomic, readonly) NSUInteger documentRevision;
@property(nonatomic, readonly) NSInteger numberOfMatches;
@property(nonatomic, readonly) NSInteger activeMatchOrdinal;
@property(nonatomic, readonly) BOOL finalUpdate;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativePage : NSObject
// Stable provenance: this page is owned by an Easel object, never an ordinary
// saved tab. It keeps the same real page through an admitted collection move.
@property(nonatomic, readonly, getter=isEmbedded) BOOL embedded;
// Remains valid while parked. A moved/destroyed Browser, Profile or original
// physical window never silently grants the child a replacement owner. Only
// the explicit original-page collection transaction can rebind this lease.
@property(nonatomic, readonly) BOOL embeddedOwnerValid;
@property(nonatomic, readonly, copy) NSString* identifier;
@property(nonatomic, readonly, copy) NSString* profilePath;
@property(nonatomic, readonly) NSView* nativeView;
@property(nonatomic, readonly, nullable) NSURL* URL;
// The original committed page icon, including OTR. No history lookup, URL
// synthesis, new request or cross-profile fallback. Changes use the existing
// nativePageFaviconDidChange callback; a deleted/missing/closed icon is nil.
@property(nonatomic, readonly, nullable) NSImage* favicon;
@property(nonatomic, readonly, copy) NSString* title;
// Same snapshot identity until the real SadTabHelper resets its presentation.
@property(nonatomic, readonly, nullable) PCNativeRendererCrash* rendererCrash;
@property(nonatomic, readonly, nullable) PCNativeCaptureState* captureState;
// Revalidates page/document/window ownership, then invokes only the producer
// callbacks retained by this snapshot. Returns NO for a stale/empty lease.
- (BOOL)stopCapture:(PCNativeCaptureState*)state sharing:(BOOL)sharing;
@property(nonatomic, readonly) BOOL loading;
@property(nonatomic, readonly) BOOL canGoBack;
@property(nonatomic, readonly) BOOL canGoForward;
@property(nonatomic, readonly)
    PCNativeArchiveProtectionState archiveProtectionState;
@property(nonatomic, readonly, getter=isClosed) BOOL closed;
@property(nonatomic, weak, nullable) id<PCNativePageObserver> observer;
- (void)loadURL:(NSURL*)url;
- (void)goBack;
- (void)goForward;
- (void)reload;
// Acknowledge only actual visible native crash presentation. This records the
// real SadTab first paint once; merely creating/adopting a page is insufficient.
- (BOOL)rendererCrashDidPresent:(PCNativeRendererCrash*)crash;
// Exact current snapshot and a prior presentation are required. Runs the real
// SadTab button action; recovery alone resets the snapshot.
- (BOOL)performRendererCrashAction:(PCNativeRendererCrash*)crash;
- (void)stop;
- (void)setZoomLevel:(double)level;
// Chromium's own page zoom command (zoom::PageZoom::Zoom): Chrome's preset
// steps, remembered per site. Negative zooms out, positive in, zero resets.
- (void)zoomPage:(NSInteger)direction;
// The page's current zoom level, on Chromium's log-1.2 scale.
@property(nonatomic, readonly) double pageZoomLevel;
// Original selected page/document only. Capability is prospective for an owned
// command panel; execution rechecks the real key window and native page owner.
@property(nonatomic, readonly) BOOL canFindInPage;
// Posted asynchronously on main, with the original PCNativePage as object.
// Consumers re-read findResult and revalidate their original document owner.
@property(class, nonatomic, readonly) NSNotificationName findResultDidChangeNotification;
@property(nonatomic, readonly, nullable) PCNativeFindResult* findResult;
@property(nonatomic, readonly, copy) NSString* selectionForFind;
- (void)findText:(NSString*)text forward:(BOOL)forward findNext:(BOOL)findNext;
- (void)stopFinding;
- (void)showDeveloperTools;
// Actual committed host and page theme; no persisted tab URL reconstruction.
@property(nonatomic, readonly, nullable, copy) NSString* developerModeHost;
// The committed chrome-extension:// page's host, its extension ID.
@property(nonatomic, readonly, nullable, copy) NSString* developerModeExtensionHost;
@property(nonatomic, readonly, nullable) NSColor* developerModeTint;
@property(nonatomic, readonly) BOOL developerModeSecure;
// Live main-thread preflight; action revalidates exact selected attachment and
// policy. YES means the real command accepted delivery, not completed output.
- (BOOL)canPerformPageTool:(PCNativePageTool)tool;
- (BOOL)performPageTool:(PCNativePageTool)tool;
@property(nonatomic, readonly) PCNativeReaderMode readerMode;
@property(nonatomic, readonly) NSUInteger readerRevision;
@property(nonatomic, readonly, copy) NSString* readerMessage;
- (BOOL)canToggleReaderMode;
- (BOOL)toggleReaderMode;
- (void)requestClose:(void (^)(PCNativePageCloseResult))completion;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

NS_SWIFT_UI_ACTOR
@interface PCNativePage (ShortcutHint)
// Accept the exact currently visible original-page cue once, before its Edit
// accessory transfers focus to Settings. Does not execute the menu action.
- (BOOL)consumeShortcutHint:(PCNativeShortcutCommand*)command
    NS_SWIFT_NAME(consumeShortcutHint(_:));
@end

// Read-only admission for browser-window Undo. False preserves the original
// renderer edit responder, including editable nodes, IME and unavailable owners.
NS_SWIFT_UI_ACTOR
@interface PCNativePage (WindowUndo)
@property(nonatomic, readonly) BOOL canUseWindowUndo;
@end

NS_SWIFT_UI_ACTOR
@interface PCNativePage (CreatedPage)
// Admission/reconciliation metadata for the original source document and owner.
// Copy the exact parent identity when accepting Peek. A later nil value is not
// a dismissal signal: the accepted shell modal owns its parent-tab lifetime.
// Never reconstruct a parent by URL or the current tab index.
@property(nonatomic, readonly, nullable) PCNativePage* peekParentPage;
// Exact creator document in the original Profile. Ordinary matched routes
// may retain a different original window; Peek's parent stays same-window.
// Cross-Profile, new-window URL-only and expired document/owner carriers are
// nil. Use only during original page adoption, never to infer an opener grant.
@property(nonatomic, readonly, nullable) PCNativePage* creationSourcePage NS_SWIFT_NAME(creationSourcePage);
// YES when that source was carried by a matched current-link route into its
//
//
// source only as the creating window's active item. Absent in older engines.
@property(nonatomic, readonly) BOOL routedLinkCreation;
// A browser-owned, one-use presentation lease for this exact original split
// request. It does not grant navigation, opener or Profile permissions.
@property(nonatomic, readonly, nullable) id splitLinkLease;
- (void)finishSplitLinkLease:(id)lease NS_SWIFT_NAME(finishSplitLinkLease(_:));
@end

NS_SWIFT_UI_ACTOR
@interface PCNativePage (NavigationState)
// This page's committed back/forward entries and current index, captured
// before a close destroys it so Undo or Reopen of that close can bring them
//
// the item's session). The value lives in this process only, so a private
// window's history stays in memory, and it restores only into the Profile it
// came from. Nil for a closed, embedded or uncommitted page. Opaque, so the
// app needs no class from older engines.
- (nullable NSObject*)captureNavigationState NS_SWIFT_NAME(captureNavigationState());
// This page's back/forward entries as bytes for the app's Tab History file,
// so a relaunch or crash brings the tab back with them and with each entry's
//
// entry and up to sessions::gMaxPersistNavigationCount on each side, each
// pickled the way Chromium's SessionService writes it. Nil for a private,
// closed, embedded or uncommitted page.
- (nullable NSData*)archivedNavigationState NS_SWIFT_NAME(archivedNavigationState());
// A value -[PCNativeBrowserWindow openNavigationState:...] accepts only for
// the persistent Profile at `profilePath` (error code 1 elsewhere). Nil for
// bytes this engine cannot read.
+ (nullable NSObject*)navigationStateWithArchive:(NSData*)data
                                     profilePath:(NSString*)profilePath
    NS_SWIFT_NAME(navigationState(archive:profilePath:));
@end

NS_SWIFT_UI_ACTOR
@interface PCNativePage (Discard)
// Frees a hidden page's renderer in place (Chromium's WebContents::Discard):
// the page keeps its identity, WebContents and back/forward entries, and
//
// discarded web content does. NO leaves the page alive: it is shown, loading,
// not archive-eligible (typed text, audio, capture or sharing, PiP, an active
// media session), holds a device or file handle, has beforeunload or unload
// handlers, is being debugged, is not an HTTP(S) page, or is already discarded.
- (BOOL)discardIfIdle NS_SWIFT_NAME(discardIfIdle());
@end

NS_SWIFT_UI_ACTOR
@interface PCNativePage (ReopenedPeek)
//
// Opens an HTTP(S) URL as a new Peek child of this exact parent page, in its
// Profile and physical window, through the ordinary created-page Peek offer
// (containerForPage: with the Peek disposition). NO creates nothing: the shell
// refused canPresentPeekFrom: for this page, or the URL is not HTTP(S). YES
// means the page exists; a source change during creation or a later shell
// refusal follows the existing created-page adoption contract.
- (BOOL)openPeekWithURL:(NSURL*)url NS_SWIFT_NAME(openPeek(url:));
// The same offer, with the Peek's page restored from a captureNavigationState
// value of the closed Peek instead of a fresh load of `url`. A nil state, or
// one from another Profile, opens `url` as above.
- (BOOL)openPeekWithURL:(NSURL*)url navigationState:(nullable NSObject*)state
    NS_SWIFT_NAME(openPeek(url:navigationState:));
// YES for the page either call above created, so the shell can tell the Peek
// it asked for from any other Peek its parent offers.
@property(nonatomic, readonly, getter=isReopenedPeek) BOOL reopenedPeek;
@end

// Immutable copied presentation state for one exact action model, Browser,
// Profile and selected document. Retaining this value never retains a Browser
// or grants permission. Stale values are rejected by every user operation.
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeExtensionAction : NSObject
@property(nonatomic, readonly, copy) NSString* identifier;
@property(nonatomic, readonly, copy) NSString* pageIdentifier;
@property(nonatomic, readonly, copy) NSString* profilePath;
@property(nonatomic, readonly) NSUInteger generation;
@property(nonatomic, readonly) NSUInteger modelIndex;
@property(nonatomic, readonly)
    NSUInteger pinnedIndex;  // NSNotFound if unpinned.
@property(nonatomic, readonly, copy) NSString* name;
@property(nonatomic, readonly, copy) NSString* title;
@property(nonatomic, readonly, copy) NSString* tooltip;
@property(nonatomic, readonly, copy) NSString* accessibilityLabel;
// The actual model's 32-point raster includes its badge, grayscale and blocked
// marker. Do not paint badgeText over this image again.
@property(nonatomic, readonly, copy, nullable) NSImage* icon;
// The same raster without its badge; grayscale and the blocked marker are
// kept, for a shell that draws badgeText itself. Absent before overlay 290.
@property(nonatomic, readonly, copy, nullable) NSImage* iconWithoutBadge;
@property(nonatomic, readonly, copy) NSString* badgeText;
// Resolved as Chromium paints them: an unset background is the theme default,
// an unset text colour contrasts with it. Raw action values before overlay 290.
@property(nonatomic, readonly, copy, nullable) NSColor* badgeTextColor;
@property(nonatomic, readonly, copy, nullable) NSColor* badgeBackgroundColor;
@property(nonatomic, readonly, getter=isEnabled) BOOL enabled;
@property(nonatomic, readonly, getter=isPinned) BOOL pinned;
@property(nonatomic, readonly) BOOL canChangePin;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

// Enabled Profile extension metadata, including extensions without actions.
// The opaque token binds dispatch to the exact original page and extension.
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeEnabledExtension : NSObject
@property(nonatomic, readonly, copy) NSString* identifier;
@property(nonatomic, readonly, copy) NSString* name;
@property(nonatomic, readonly, copy, nullable) NSImage* icon;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

typedef NS_ENUM(NSInteger, PCNativeExtensionPopupAnchorKind) {
  PCNativeExtensionPopupAnchorWindow,
  PCNativeExtensionPopupAnchorSidebar,
  PCNativeExtensionPopupAnchorFocusedView,
};

//
// Queries must return an actual view of this exact physical window, or a finite
// sidebar width. The engine rejects a detached/foreign view and falls back to
// the owning window rather than borrowing another window's geometry.
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeExtensionPopupAnchor : NSObject
@property(nonatomic, readonly) PCNativeExtensionPopupAnchorKind kind;
@property(nonatomic, readonly, weak, nullable) NSView* focusedView;
@property(nonatomic, readonly) CGFloat sidebarWidth;
+ (instancetype)windowAnchor NS_SWIFT_NAME(window());
+ (instancetype)sidebarAnchorWithWidth:(CGFloat)width
    NS_SWIFT_NAME(sidebar(width:));
+ (instancetype)focusedViewAnchor:(NSView*)view NS_SWIFT_NAME(focusedView(_:));
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

// Immutable result of a synchronous, in-memory matched-rule query.
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeLinkRoute : NSObject
@property(nonatomic, readonly, copy) NSString* ruleIdentifier;
@property(nonatomic, readonly, copy) NSString* spaceIdentifier;
@property(nonatomic, readonly, copy) NSString* profilePath;
- (instancetype)initWithRuleIdentifier:(NSString*)ruleIdentifier
    spaceIdentifier:(NSString*)spaceIdentifier profilePath:(NSString*)profilePath
    NS_SWIFT_NAME(init(ruleIdentifier:spaceIdentifier:profilePath:));
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

NS_SWIFT_UI_ACTOR
@interface PCNativePage (RoutedLink)
@property(nonatomic, readonly, nullable, copy) NSString* routedSpaceIdentifier;
@property(nonatomic, readonly) BOOL authenticationFlowUnlocked;
@end

// A transient creation receipt for one genuine original download in one
//
// Contains no file bytes or persistent metadata. Admission (key window, page
// visible in it) ran once at creation; `valid` is then identity only: the same
// live document, page, Profile, physical window and item incarnation. It makes
// no client callback. Dismissal of a delivered arrival belongs to the window
// owner, not to this receipt.
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeDownloadArrival : NSObject
@property(nonatomic, readonly, weak, nullable) PCNativePage* page;
@property(nonatomic, readonly, copy) NSString* profilePath;
@property(nonatomic, readonly, copy) NSString* downloadIdentifier;
@property(nonatomic, readonly, copy) NSString* itemIdentity;
@property(nonatomic, readonly, nullable, copy) NSString* privateContextIdentifier;
// Global screen point, bottom-left origin: the hovered anchor's centre, or the
//
@property(nonatomic, readonly) NSPoint sourceScreenPoint;
@property(nonatomic, readonly, getter=isValid) BOOL valid;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

NS_SWIFT_UI_ACTOR
@protocol PCNativeBrowserWindowClient <NSObject>
// All callbacks are main-thread. This exact window owns the shell UI. The
// client is weak; it must remain alive until requestClose completes. Queries
// must not spin the run loop or tear down Browser/Profile/this binding.
- (NSWindow*)nativeBrowserWindow;
// Return the actual selected page, including focus changes between split panes.
- (nullable PCNativePage*)selectedNativePage;
- (NSArray<PCNativePage*>*)visibleNativePages;
@optional
// Pure existing-state reads; called while the originating renderer waits.
- (nullable id)nativeBrowser:(PCNativeBrowserWindow*)browser
    splitLinkLeaseForPage:(PCNativePage*)page
    NS_SWIFT_NAME(nativeBrowser(_:splitLinkLeaseFor:));
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
    isSplitLinkLeaseCurrent:(id)lease forPage:(PCNativePage*)page
    NS_SWIFT_NAME(nativeBrowser(_:isSplitLinkLeaseCurrent:for:));
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
    canRouteCurrentLinkFrom:(PCNativePage*)page
    NS_SWIFT_NAME(nativeBrowser(_:canRouteCurrentLinkFrom:));
// Pure source-Space identity for original-created-page admission.
- (nullable NSString*)nativeBrowser:(PCNativeBrowserWindow*)browser
    linkRouteSourceSpaceForPage:(PCNativePage*)page
    NS_SWIFT_NAME(nativeBrowser(_:linkRouteSourceSpaceFor:));
- (nullable PCNativeLinkRoute*)nativeBrowser:(PCNativeBrowserWindow*)browser
    routeCurrentLinkFrom:(PCNativePage*)page targetURL:(NSURL*)url
    authenticationContinuation:(BOOL)authentication
    NS_SWIFT_NAME(nativeBrowser(_:routeCurrentLinkFrom:targetURL:authenticationContinuation:));
// Actual saved sidebar URL for an eligible favorite/pinned item, or nil.
- (nullable NSURL*)nativeBrowser:(PCNativeBrowserWindow*)browser
    authenticationReturnURLForPage:(PCNativePage*)page
    NS_SWIFT_NAME(nativeBrowser(_:authenticationReturnURLFor:));
// Pure destination revalidation after asynchronous context preparation.
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
    canAcceptLinkRoute:(PCNativeLinkRoute*)route
    NS_SWIFT_NAME(nativeBrowser(_:canAcceptLinkRoute:));
// These execute only after the synchronous query has returned.
- (nullable PCNativeBrowserWindow*)nativeBrowser:(PCNativeBrowserWindow*)browser
    prepareLinkRoute:(PCNativeLinkRoute*)route
    NS_SWIFT_NAME(nativeBrowser(_:prepareLinkRoute:));
- (void)nativeBrowser:(PCNativeBrowserWindow*)browser
    didFailLinkRoute:(NSError*)error
    NS_SWIFT_NAME(nativeBrowser(_:didFailLinkRoute:));
// Pure current-shell query for the original renderer gesture owner.
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
  allowsHistorySwipeForPage:(PCNativePage*)page
    NS_SWIFT_NAME(nativeBrowser(_:allowsHistorySwipeFor:));
// Called during synchronous renderer policy. Pure existing-state query only;
// do not perform IO, present UI, create pages, or call back into the renderer.
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
  shouldOpenCurrentLinkInPeekFrom:(PCNativePage*)page targetURL:(NSURL*)url
    NS_SWIFT_NAME(nativeBrowser(_:shouldOpenCurrentLinkInPeekFrom:targetURL:));
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
  canPresentPeekFrom:(PCNativePage*)page
    NS_SWIFT_NAME(nativeBrowser(_:canPresentPeekFrom:));
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
  shouldOpenNewPageInPeekFrom:(PCNativePage*)page targetURL:(NSURL*)url
    NS_SWIFT_NAME(nativeBrowser(_:shouldOpenNewPageInPeekFrom:targetURL:));
// Separate recovered preferences: modalEnabled, and inverse
// disableShiftClickToOpenLinksInModal. Native supplies captured gesture state.
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
  allowsPeekWithShift:(BOOL)shift
    NS_SWIFT_NAME(nativeBrowser(_:allowsPeekWithShift:));
// Genuine creation in this original visible document of this key window,
// delivered once after the hovered-anchor query resolves. Never history
// replay. A newer creation in the same window supersedes a pending one.
- (void)nativeBrowser:(PCNativeBrowserWindow*)browser
    downloadDidBegin:(PCNativeDownloadArrival*)arrival
    NS_SWIFT_NAME(nativeBrowser(_:downloadDidBegin:));
// Original OTR context only, never delivered to the regular application catalog.
- (void)nativeBrowser:(PCNativeBrowserWindow*)browser
    privateDownloadDidUpdate:(NSDictionary<NSString*, id>*)update
    NS_SWIFT_NAME(nativeBrowser(_:privateDownloadDidUpdate:));
- (void)nativeBrowserPrivateDownloadsDidInvalidate:(PCNativeBrowserWindow*)browser;
@required
// Called only for internal/popup creation after the real ownership stack
// unwinds. External openURL uses its supplied container directly. Insert a
// saved tab for ordinary pages; auxiliary clients host an unsaved engine page.
// Return the exact page container in either case. Never reload its URL.
- (nullable NSView*)nativeBrowser:(PCNativeBrowserWindow*)browser
                 containerForPage:(PCNativePage*)page
                      disposition:(PCNativePageDisposition)disposition;
- (void)nativeBrowser:(PCNativeBrowserWindow*)browser
         didClosePage:(PCNativePage*)page;
// An actual engine selection, delivered after model mutation has unwound.
// Select the existing exact page; do not reload or adopt a substitute by URL.
// Updating presentation in response must not issue another selection command.
- (void)nativeBrowser:(PCNativeBrowserWindow*)browser
        didSelectPage:(PCNativePage*)page
    NS_SWIFT_NAME(nativeBrowser(_:didSelect:));
- (void)nativeBrowser:(PCNativeBrowserWindow*)browser
     didFailWithError:(NSError*)error;
// Existing shell actions, not replacement engine UI.
- (void)nativeBrowserFocusAddress:(PCNativeBrowserWindow*)browser;
// Uses the shell's actual key-view traversal, never the declaration order of
//
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
    rotateFocusForward:(BOOL)forward;
// Native tab fullscreen changes only the supplied page layout/chrome. Engine
// owns real FullscreenController state and the NSWindow transition separately.
// nil restores the shell's prior normal/split presentation.
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
    setTabFullscreenPage:(nullable PCNativePage*)page;
- (void)nativeBrowserShowTabSearch:(PCNativeBrowserWindow*)browser;
- (void)nativeBrowserCloseTabSearch:(PCNativeBrowserWindow*)browser;
- (void)nativeBrowserShowProfiles:(PCNativeBrowserWindow*)browser;
- (void)nativeBrowser:(PCNativeBrowserWindow*)browser bookmarkURL:(NSURL*)url;
// This container belongs to this physical window, and must not be a renderer
// view. Apply layout synchronously; false means the requested state was not
// applied. The side-panel service verifies actual hierarchy and visibility.
- (NSView*)nativeBrowserSidePanelContainer:(PCNativeBrowserWindow*)browser;
@optional
// Exact panel-only chrome and content scope for keyboard focus restoration.
// Omission means the content container alone; never infer a parent/root view.
- (NSView*)nativeBrowserSidePanelFocusScope:(PCNativeBrowserWindow*)browser;
@required
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
    setSidePanelVisible:(BOOL)visible;
// Present engine capability failure in the existing shell; never pretend an
// unsupported optional prompt was displayed or accepted.
- (void)nativeBrowser:(PCNativeBrowserWindow*)browser
    capabilityUnavailable:(NSString*)capability;
@optional
// Exact active Peek admission and the matching renderer-ACK outcome. Native
// code retains the original document/widget/window lease and consumes it once.
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
    canHandlePeekEscapeFrom:(PCNativePage*)page
    NS_SWIFT_NAME(nativeBrowser(_:canHandlePeekEscapeFrom:));
- (void)nativeBrowser:(PCNativeBrowserWindow*)browser
    handlePeekEscapeFrom:(PCNativePage*)page prefersConfirmation:(BOOL)confirmation
    NS_SWIFT_NAME(nativeBrowser(_:handlePeekEscapeFrom:prefersConfirmation:));
// Query and dispatch are synchronous, main-thread, and must not spin a nested
// run loop. Dispatch uses the same original page, event, menu item and revision.
- (nullable PCNativeShortcutCommand*)nativeBrowser:(PCNativeBrowserWindow*)browser
    shortcutForEvent:(NSEvent*)event page:(PCNativePage*)page editable:(BOOL)editable
    NS_SWIFT_NAME(nativeBrowser(_:shortcutFor:page:editable:));
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
    performShortcut:(PCNativeShortcutCommand*)command event:(NSEvent*)event
    page:(PCNativePage*)page editable:(BOOL)editable
    NS_SWIFT_NAME(nativeBrowser(_:performShortcut:event:page:editable:));
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
    showShortcutHint:(nullable PCNativeShortcutCommand*)command
    page:(nullable PCNativePage*)page
    NS_SWIFT_NAME(nativeBrowser(_:showShortcutHint:page:));
// All cue callbacks use the exact command object acknowledged at presentation.
- (void)nativeBrowser:(PCNativeBrowserWindow*)browser
    dismissShortcutHint:(PCNativeShortcutCommand*)command page:(PCNativePage*)page
    NS_SWIFT_NAME(nativeBrowser(_:dismissShortcutHint:page:));
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
    isShortcutHintHovered:(PCNativeShortcutCommand*)command page:(PCNativePage*)page
    NS_SWIFT_NAME(nativeBrowser(_:isShortcutHintHovered:page:));
// Posted/coalesced after real action model/icon/pinning/selection updates.
// Pull a new snapshot for the current selected page. No model crosses the ABI.
- (void)nativeBrowserExtensionActionsDidChange:(PCNativeBrowserWindow*)browser;
- (void)nativeBrowserPaymentActionsDidChange:(PCNativeBrowserWindow*)browser;
// Side-effect-free snapshot of the shell's actual focused layout.
- (PCNativeExtensionPopupAnchor*)nativeBrowserExtensionPopupAnchor:
    (PCNativeBrowserWindow*)browser;
// Posted only after actual Browser/service drain, and revalidated against a
// new preparation/registration. Docking may release an auxiliary Browser while
// its tools WebContents remains alive; this is not a page-close notification.
- (void)nativeBrowserDidReleaseLastBrowser:(PCNativeBrowserWindow*)browser;
// Exact unused reservation failed before binding a Browser. The binding is
// still empty with no pending reservation when delivered. Auxiliary clients
// may close the unused shell; ordinary clients can retain their window.
- (void)nativeBrowserCreationReservationDidAbort:
    (PCNativeBrowserWindow*)browser;
@end

NS_SWIFT_UI_ACTOR
@protocol PCNativeBrowserApplicationClient <NSObject>
@optional
// The engine learned that `site` needs Safari's identity for Apple FairPlay
// in the browsing context of the Profile at `profilePath` (its private
// context with offTheRecord) and reloaded its pages (docs/fairplay-identity.md).
// Delivered for every learned site, whether or not a page observer also
// received nativePage:didLearnSafariIdentityForSite:.
- (void)nativeApplicationDidLearnSafariIdentityForSite:(NSString*)site
                                           profilePath:(NSString*)profilePath
                                          offTheRecord:(BOOL)offTheRecord
    NS_SWIFT_NAME(nativeApplicationDidLearnSafariIdentity(forSite:profilePath:offTheRecord:));
// Live private records join the shared presentation only in memory. Context
// retirement is delivered after native invalidation; never serialize updates.
- (void)nativeApplicationPrivateDownloadDidUpdate:(NSDictionary<NSString*, id>*)update
                                         context:(PCNativePrivateDownloadContext*)context;
- (void)nativeApplicationPrivateDownloadContextDidInvalidate:(PCNativePrivateDownloadContext*)context;
// Synchronous, non-reentrant construction; must return a retained application
// presenter after preflight. App retains it until the matching release.
- (id<PCNativeVideoPiPWindow>)
    createVideoPictureInPictureWindow:(NSView*)videoView
                          sourceFrame:(NSRect)sourceFrame
                               action:(void (^)(PCVideoPiPAction, double))action
                              changed:(dispatch_block_t)changed
    NS_SWIFT_NAME(createVideoPictureInPictureWindow(videoView:sourceFrame:action:changed:));
- (void)releaseVideoPictureInPictureWindow:(id<PCNativeVideoPiPWindow>)window
    NS_SWIFT_NAME(releaseVideoPictureInPictureWindow(_:));
// DownloadFilePicker requests this only for an actual Profile-owned download
// with no WebContents. The shell chooses/reveals a window whose selected Space
// has this exact Profile, or opens a normal browser window for that Profile.
// Validation must remain true for the same physical window until completion.
- (nullable NSWindow*)nativeDownloadDialogWindowForProfilePath:(NSString*)path
    NS_SWIFT_NAME(nativeDownloadDialogWindow(forProfilePath:));
- (BOOL)nativeDownloadDialogWindow:(NSWindow*)window
            representsProfilePath:(NSString*)path
    NS_SWIFT_NAME(nativeDownloadDialogWindow(_:representsProfilePath:));
@required

// Profile-scoped copied values. Delivery continues after the originating page
// closes. No live DownloadItem or per-page callback crosses this boundary.
- (void)nativeApplicationDownloadDidUpdate:(NSDictionary<NSString*, id>*)update;

// Synchronous preflight before constructing a Browser. Return a registered,
// caller-owned native window; source may be nil. A new Browser always receives
// a fresh one-use reservation, even if this returns a shared physical window.
// Returning nil is a refusal, not permission to fall back to BrowserView.
- (nullable id<PCNativeBrowserWindowClient>)
    prepareNativeWindowForRequest:(PCNativeWindowRequest*)request
    NS_SWIFT_NAME(prepareNativeWindow(request:));
// Receives an existing instance's command-line handoff. Arguments are copied
// before CEF detaches its read-only command object. The shell owns window/URL
// routing; the engine never falls back to a Chrome-styled window.
- (void)nativeApplicationRelaunchedWithArguments:(NSArray<NSString*>*)arguments
                                currentDirectory:(NSString*)currentDirectory
    NS_SWIFT_NAME(nativeApplicationRelaunched(arguments:currentDirectory:));
@end

// Cancellable admission for an unsaved, window-owned Easel renderer. Cancel
// settles a pending request without creating/navigating a page; after commit,
// use the actual page's beforeunload-aware close or whole-set retirement API.
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeEmbeddedPageRequest : NSObject
@property(nonatomic, readonly, getter=isPending) BOOL pending;
- (void)cancel;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

// One physical NSWindow registration. Engine Browsers are indexed by its stable
// identity AND actual Profile. registerWindow never creates a Chrome window.
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeBrowserWindow : NSObject
@property(nonatomic, readonly, getter=isPrivateBrowsing) BOOL privateBrowsing;
// Create only against an initialized original profile. A success owns a real
// empty OTR Browser; requestClose remains the only destruction path.
- (BOOL)beginPrivateBrowsingWithProfilePath:(NSString*)path error:(NSError**)error
    NS_SWIFT_NAME(beginPrivateBrowsing(profilePath:));
- (BOOL)adoptPrivateContextFromRequest:(PCNativeWindowRequest*)request error:(NSError**)error
    NS_SWIFT_NAME(adoptPrivateContext(request:));
// Live, non-retaining classification of this binding's actual Browsers. Empty,
// closed or invalid registrations return unavailable rather than normal.
@property(nonatomic, readonly) PCNativeBrowsingContextKind browsingContextKind;
@property(nonatomic, readonly, weak, nullable) NSWindow* window;
@property(nonatomic, readonly, weak, nullable) id<PCNativeBrowserWindowClient>
    client;
- (void)openURL:(NSURL*)url
    profilePath:(NSString*)profilePath
      container:(NSView*)container
     completion:
         (void (^)(PCNativePage* _Nullable, NSError* _Nullable))completion;
// Creates a fresh saved destination in this exact normal Profile/window without
// selecting its tab or showing a first Browser. The source caller owns all IDs.
- (void)openBackgroundURL:(NSURL*)url
              profilePath:(NSString*)profilePath
                container:(NSView*)container
               completion:(void (^)(PCNativePage* _Nullable, NSError* _Nullable))completion;
// Creates the page of a tab that Undo or Reopen restores, in this exact window
// and Profile (this window's own private Profile in a private window), from a
// -[PCNativePage captureNavigationState] value; its current entry loads at
// once. A value from another Profile or a closed private context is refused
// before any page exists, with error code 1, and the caller may load the tab's
// address instead. Any other error means a page was inserted and closed again.
- (void)openNavigationState:(NSObject*)state
                profilePath:(NSString*)profilePath
                  container:(NSView*)container
                 background:(BOOL)background
                 completion:(void (^)(PCNativePage* _Nullable, NSError* _Nullable))completion;
// Creates genuine HTTP(S) content in this exact Profile/window, without saved
// tab adoption or selecting an ordinary tab. validateOwner is a pure, fast
// main-thread query and is repeated after asynchronous Profile acquisition.
// Completion is once, on main, after this method returns. No requested URL is
// loaded before successful owner validation. Hidden pages retain their owner.
- (PCNativeEmbeddedPageRequest*)createEmbeddedPageWithURL:(NSURL*)url
    profilePath:(NSString*)profilePath container:(NSView*)container
    validateOwner:(BOOL (^)(void))validateOwner
    completion:(void (^)(PCNativePage* _Nullable, NSError* _Nullable))completion
    NS_SWIFT_NAME(createEmbeddedPage(url:profilePath:container:validateOwner:completion:));
// Call after shell selection/split/layout changes, before scheduling focus.
- (void)synchronizeSelectionAndLayout;
// Geometry/visibility reconciliation only. Safe for engine presentation
// callbacks; never selects a Browser or mutates the active tab.
- (void)synchronizeLayout;
// Document Picture-in-Picture's back-to-tab: closes this window's PiP page and
// activates the page that opened it. NO when this window holds no PiP page.
- (BOOL)returnPictureInPictureToOpener;
// NO when this window holds no PiP page or its page set
// disallowReturnToOpener.
@property(nonatomic, readonly) BOOL canReturnPictureInPictureToOpener;
// Publishes only to this physical window's actual page owners. Nil revokes
// this owned stylesheet; navigation/restore and newly attached pages inherit it.
- (void)setWebsiteThemeStylesheet:(nullable NSString*)stylesheet;
// The app must call these before/after actual page container reparenting.
- (void)pageWillDetach:(PCNativePage*)page;
- (BOOL)pageDidAttach:(PCNativePage*)page container:(NSView*)container;
// One physical-window coordinator waits for every attached Browser/Profile.
// The caller may close NSWindow only on YES. It must not force-close pages from
// windowWillClose or remove saved tabs before the individual close callback.
- (void)requestClose:(void (^)(BOOL allow))completion;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

// Memory-only manager access bound to this original private physical window.
// No path fallback or Profile creation. Each action requires the original item
// incarnation; profile/window retirement invalidates every offer and callback.
NS_SWIFT_UI_ACTOR
@interface PCNativeBrowserWindow (PrivateDownloads)
@property(nonatomic, readonly) BOOL privateDownloadsAvailable;
- (void)refreshPrivateDownloadsWithCompletion:
    (void (^)(NSArray<NSString*>* _Nullable identifiers, NSError* _Nullable error))completion
    NS_SWIFT_NAME(refreshPrivateDownloads(completion:));
- (BOOL)performPrivateDownloadAction:(PCNativeDownloadAction)action
                         identifier:(NSString*)identifier itemIdentity:(NSString*)identity
    NS_SWIFT_NAME(performPrivateDownloadAction(_:identifier:itemIdentity:));
- (nullable NSURL*)privateDownloadFileURLForIdentifier:(NSString*)identifier itemIdentity:(NSString*)identity
    NS_SWIFT_NAME(privateDownloadFileURL(identifier:itemIdentity:));
- (nullable PCNativeDownloadReview*)privateDownloadReviewForIdentifier:(NSString*)identifier itemIdentity:(NSString*)identity
    NS_SWIFT_NAME(privateDownloadReview(identifier:itemIdentity:));
- (BOOL)performPrivateDownloadReviewAction:(PCNativeDownloadReviewAction)action
                               forReview:(PCNativeDownloadReview*)review
                                password:(NSString*)password justification:(NSString*)justification
    NS_SWIFT_NAME(performPrivateDownloadReviewAction(_:for:password:justification:));
- (nullable NSURL*)privateDownloadReviewLinkAtIndex:(NSUInteger)index forReview:(PCNativeDownloadReview*)review
    NS_SWIFT_NAME(privateDownloadReviewLink(at:for:));
@end

// Exact original-page focus. Uses this physical window's registered focus
// manager, preserving focused descendants/field editors and pending requests.
// Does not select, show, activate, reconstruct or schedule a replacement page.
// YES means already focused, pending or accepted; actual AppKit focus is final.
NS_SWIFT_UI_ACTOR
@interface PCNativeBrowserWindow (PageFocus)
- (BOOL)requestFocusForPage:(PCNativePage*)page NS_SWIFT_NAME(requestFocus(for:));
@end

NS_SWIFT_UI_ACTOR
@interface PCNativeBrowserWindow (OpenAppActions)
- (nullable PCNativeOpenAppAction*)openAppActionForPage:(PCNativePage*)page
    NS_SWIFT_NAME(openAppAction(for:));
// YES is dispatch, not a fabricated launch result. The real intent helper
// rediscovers current eligible apps, presents a choice and owns launch.
- (BOOL)executeOpenAppAction:(PCNativeOpenAppAction*)action
                   forPage:(PCNativePage*)page
    NS_SWIFT_NAME(executeOpenAppAction(_:for:));
@end

// The shell remains the supplied window's sole delegate. Forward only an
// actual AppKit failure; successful will/did events come from its association.
// One original document's existing content-fullscreen exit. This neither
// enters fullscreen nor toggles a different page/window mode.
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeFullscreenExit : NSObject
@property(nonatomic, readonly, getter=isAvailable) BOOL available;
- (BOOL)perform;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

NS_SWIFT_UI_ACTOR
@interface PCNativeBrowserWindow (FullscreenEvents)
- (nullable PCNativeFullscreenExit*)prepareFullscreenExitForPage:(PCNativePage*)page
    NS_SWIFT_NAME(prepareFullscreenExit(for:));
// Register the ordinary shell window before presentation, so its original
// frame is known even if the first Browser attaches after a native toggle.
+ (void)prepareNativeWindowFullscreen:(NSWindow*)window
    NS_SWIFT_NAME(prepareNativeWindowFullscreen(_:));
+ (void)nativeWindowDidFailToEnterFullscreen:(NSWindow*)window
    NS_SWIFT_NAME(nativeWindowDidFailToEnterFullscreen(_:));
@end

NS_SWIFT_UI_ACTOR
@interface PCNativeBrowserWindow (PaymentActions)
- (NSArray<PCNativePaymentAction*>*)paymentActionsForPage:(PCNativePage*)page
    NS_SWIFT_NAME(paymentActions(for:));
- (BOOL)executePaymentAction:(PCNativePaymentAction*)action
                     forPage:(PCNativePage*)page
    NS_SWIFT_NAME(executePaymentAction(_:for:));
// Call only after the matching native entry is visible, or after the shell
// displays/announces the supplied saved feedback. Each request is consumed
// once.
- (BOOL)paymentFeedbackPresented:(PCNativePaymentAction*)action
                         forPage:(PCNativePage*)page
    NS_SWIFT_NAME(paymentFeedbackPresented(_:for:));
@end

NS_SWIFT_UI_ACTOR
@interface PCNativeBrowserWindow (ExtensionActions)
// Synchronous user dismissal of the visible panel in this exact selected,
// key native window. Refuses detached, background and retiring Browser owners.
- (BOOL)closeExtensionSidePanel;
// Model order is retained; pinnedIndex carries the Profile's actual pin order.
// A different/background/detached page returns an empty snapshot.
- (NSArray<PCNativeExtensionAction*>*)extensionActionsForPage:
    (PCNativePage*)page NS_SWIFT_NAME(extensionActions(for:));
// User-visible entries in the original Profile's enabled registry, including
// extensions without an action.
// A different/background/detached page returns NO. This does not grant private access.
- (BOOL)hasEnabledExtensionsForPage:(PCNativePage*)page
    NS_SWIFT_NAME(hasEnabledExtensions(for:));
// Manifest icons load asynchronously; nil means pending or unavailable.
// The existing extension-change callback signals a completed load.
- (NSArray<PCNativeEnabledExtension*>*)enabledExtensionsForPage:(PCNativePage*)page
    NS_SWIFT_NAME(enabledExtensions(for:));
// YES reports a real action dispatch or context-menu tracking, respectively.
// Extensions without an available action return NO, including in private mode.
- (BOOL)executeEnabledExtension:(PCNativeEnabledExtension*)extension
                        forPage:(PCNativePage*)page
    NS_SWIFT_NAME(executeEnabledExtension(_:for:));
- (BOOL)showEnabledExtensionContextMenu:(PCNativeEnabledExtension*)extension
                                forPage:(PCNativePage*)page
    NS_SWIFT_NAME(showEnabledExtensionContextMenu(_:for:));
// Call only for an actual user gesture. Enabled is visual state: the real
// model may route a disabled action to its native context-menu fallback.
// YES means the real action was dispatched, not that a popup became visible.
- (BOOL)executeExtensionAction:(PCNativeExtensionAction*)action
                       forPage:(PCNativePage*)page
    NS_SWIFT_NAME(executeExtensionAction(_:for:));
// YES means native tracking actually began, including a cancelled menu.
- (BOOL)showExtensionActionContextMenu:(PCNativeExtensionAction*)action
                               forPage:(PCNativePage*)page
    NS_SWIFT_NAME(showExtensionActionContextMenu(_:for:));
- (BOOL)setExtensionAction:(PCNativeExtensionAction*)action
                    pinned:(BOOL)pinned
                   forPage:(PCNativePage*)page
    NS_SWIFT_NAME(setExtensionAction(_:pinned:for:));
@end

typedef NS_ENUM(NSInteger, PCNativePageTransferResult) {
  PCNativePageTransferTransferred,
  PCNativePageTransferRefused,
  PCNativePageTransferRestored,
  PCNativePageTransferInterrupted,
};

NS_SWIFT_UI_ACTOR
@interface PCNativeBrowserWindow (LivePageTransfer)
// Read-only registered-window/security gate. Drag destinations need not be key.
@property(nonatomic, readonly) BOOL canParticipateInPageTransfer;
// Same security and lifetime admission for a registered hidden destination.
// Does not authorize a transfer or show/order the window. Recheck before show.
@property(nonatomic, readonly) BOOL canAdmitHiddenPageTransferDestination;
// Reserve shell ownership/container claims before calling. This moves the same
// engine page and TabInterface; it never navigates or reconstructs a URL. The
// destination Profile must exactly match the page's current Profile. A failed
// native attachment restores the actual tab to its source when that owner is
// still alive. Independent owner/page destruction is explicitly Interrupted.
// Completion is posted. Do not close/dispose the underlying page when moving
// its source wrapper; selection of a nonempty destination is a separate action.
- (void)transferPage:(PCNativePage*)page
         profilePath:(NSString*)profilePath
           container:(NSView*)container
          completion:(void (^)(PCNativePageTransferResult result,
                               NSError* _Nullable error))completion
    NS_SWIFT_NAME(transferPage(_:profilePath:container:completion:));
// Original collection, one source Browser/Profile. Containers are parallel to
// pages. commit runs synchronously only after every page is attached and must
// persist the captured shell move without running a nested loop. False rolls
// surviving pages back. Valid auxiliary pages retain their original identity
// and explicitly rebind their Browser/window lease within this transaction.
// Completion is posted; both physical shells retain their empty Browsers.
- (void)transferPages:(NSArray<PCNativePage*>*)pages
         profilePath:(NSString*)profilePath
          containers:(NSArray<NSView*>*)containers
              commit:(BOOL (^)(void))commit
          completion:(void (^)(PCNativePageTransferResult result,
                               NSError* _Nullable error))completion
    NS_SWIFT_NAME(transferPages(_:profilePath:containers:commit:completion:));
@end

// Startup/message-loop export is supplied by the typed route entrypoint.
// This registration surface is consumed by the existing ParcEngine facade.
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeBrowserApplication : NSObject
+ (void)preparePrivateBrowsingWithProfilePath:(NSString*)path
    completion:(void (^)(NSError* _Nullable error))completion
    NS_SWIFT_NAME(preparePrivateBrowsing(profilePath:completion:));
// Forward the actual NSApplication AX requests/KVO here. Role/manual/enhanced
// demand enables Chromium's real basic tree; genuine VoiceOver enables its
// complete screen-reader mode. Requests before CEF readiness are remembered;
// no new scope is created after engine shutdown. These do not replace AX nodes.
+ (void)accessibilityRoleRequested;
+ (void)accessibilitySetValue:(nullable id)value
                 forAttribute:(NSString*)attribute;
+ (BOOL)accessibilityHandleObservationForKeyPath:(nullable NSString*)keyPath
                                        ofObject:(nullable id)object
                                          change:(nullable NSDictionary*)change
                                         context:(nullable void*)context
    NS_SWIFT_NAME(handleAccessibilityObservation(forKeyPath:of:change:context:));
// Acceptance is not completion; later manager updates contain actual state.
+ (BOOL)performDownloadAction:(PCNativeDownloadAction)action
                   identifier:(NSString*)identifier
                  profilePath:(NSString*)profilePath
    NS_SWIFT_NAME(performDownloadAction(_:identifier:profilePath:));
// Initializes the requested owned regular Profile without creating a page.
// Completion is asynchronous on main, after real manager history readiness.
+ (void)refreshDownloadsForProfilePath:(NSString*)profilePath
                           completion:(void (^)(NSArray<NSString*>* _Nullable identifiers, NSError* _Nullable error))completion
    NS_SWIFT_NAME(refreshDownloads(profilePath:completion:));
// Library controls bind to the live manager's item incarnation, not just GUID.
+ (BOOL)performDownloadAction:(PCNativeDownloadAction)action
                  identifier:(NSString*)identifier
                 profilePath:(NSString*)profilePath
                itemIdentity:(NSString*)itemIdentity
    NS_SWIFT_NAME(performDownloadAction(_:identifier:profilePath:itemIdentity:));
+ (nullable NSURL*)downloadFileURLForIdentifier:(NSString*)identifier
                                   profilePath:(NSString*)profilePath
                                  itemIdentity:(NSString*)itemIdentity
    NS_SWIFT_NAME(downloadFileURL(identifier:profilePath:itemIdentity:));
+ (nullable PCNativeDownloadReview*)downloadReviewForIdentifier:(NSString*)identifier
                                                  profilePath:(NSString*)profilePath
    NS_SWIFT_NAME(downloadReview(identifier:profilePath:));
+ (BOOL)performDownloadReviewAction:(PCNativeDownloadReviewAction)action
                         forReview:(PCNativeDownloadReview*)review
                          password:(NSString*)password
                     justification:(NSString*)justification
    NS_SWIFT_NAME(performDownloadReviewAction(_:for:password:justification:));
+ (nullable NSURL*)downloadReviewLinkAtIndex:(NSUInteger)index
                                  forReview:(PCNativeDownloadReview*)review
    NS_SWIFT_NAME(downloadReviewLink(at:for:));

// Acquires only the exact owned regular profile; no page is created. Reply is
// asynchronous on main and returns a snapshot retaining weak Profile identity.
+ (void)loadDownloadPreferencesForProfilePath:(NSString*)profilePath
    completion:(void (^)(PCNativeDownloadPreferences* _Nullable preferences,
                         NSError* _Nullable error))completion
    NS_SWIFT_NAME(downloadPreferences(profilePath:completion:));
// Synchronous inspection never initializes a Profile. Setters bind the weak
// snapshot identity and return current effective values or a truthful error.
+ (nullable PCNativeDownloadPreferences*)downloadPreferencesForProfilePath:
    (NSString*)profilePath NS_SWIFT_NAME(downloadPreferences(profilePath:));
+ (nullable PCNativeDownloadPreferences*)
    setDownloadDirectoryURL:(NSURL*)directoryURL
             forPreferences:(PCNativeDownloadPreferences*)preferences
                      error:(NSError**)error
    NS_SWIFT_NAME(setDownloadDirectory(_:for:));
+ (nullable PCNativeDownloadPreferences*)
    setPromptForDownload:(BOOL)prompt
          forPreferences:(PCNativeDownloadPreferences*)preferences
                   error:(NSError**)error
    NS_SWIFT_NAME(setPromptForDownload(_:for:));

+ (nullable PCNativeBrowserWindow*)windowForNativeWindow:(NSWindow*)window;
// Read-only, callback-free lookup of exact current TabInterface membership and
// CEF Browser association. Nil means no currently registered matching owner;
// it never infers ownership from a page view or the frontmost NSWindow.
+ (nullable PCNativeBrowserWindow*)ownerForPage:(PCNativePage*)page
    NS_SWIFT_NAME(owner(of:));
+ (nullable PCNativeBrowserWindow*)registerWindowClient:
                                       (id<PCNativeBrowserWindowClient>)client
                                                  error:(NSError**)error;
+ (void)setApplicationClient:(id<PCNativeBrowserApplicationClient>)client;
// Snapshot existing leases only; this never prepares or opens an OTR Profile.
+ (NSArray<PCNativePrivateDownloadContext*>*)privateDownloadContexts;
+ (void)requestCloseAllWindows:(void (^)(BOOL allow))completion;
@end
NS_SWIFT_UI_ACTOR
@interface PCNativeBrowserApplication (CookieStore)
// YES when every persistent Profile brings back its session cookies after a
//
// relaunches), without Chrome's "Continue where you left off" preference.
// Older engines need the app to pass Chromium's restore-last-session switch.
@property(class, nonatomic, readonly) BOOL restoresSessionCookies;
// Commits every persistent Profile's pending cookie changes now. Chromium's
// cookie store otherwise commits every 30 seconds (or on a clean quit), so a
// crash or force quit soon after signing in would sign the user out again.
+ (void)flushCookieStores;
@end
NS_SWIFT_UI_ACTOR
@interface PCNativeBrowserApplication (TabAudioBatch)
// Apply one explicit mute state to every live native page frame, guarded by the source window.
+ (BOOL)setAllTabAudioMuted:(BOOL)muted inWindow:(NSWindow*)window NS_SWIFT_NAME(setAllTabAudioMuted(_:in:));
@end

// shouldCommit runs synchronously after all approvals and before any unload.
// It must revalidate the model operation; native page/document leases are then
// checked again after callback reentry.
// Exact selected-page retirement. All target beforeunload decisions complete
// before any transaction-driven unload. NO preserves uncommitted targets; YES
// is delivered only after every actual WebContents is destroyed. The caller
// retains its whole-set model transaction until completion. Independent page
// destruction/navigation invalidates preparation; no page is reconstructed.
NS_SWIFT_UI_ACTOR
@interface PCNativeBrowserApplication (PageRetirement)
+ (void)requestClosePages:(NSArray<PCNativePage*>*)pages
             shouldCommit:(BOOL (^)(void))shouldCommit
               completion:(void (^)(BOOL success))completion
    NS_SWIFT_NAME(requestClosePages(_:shouldCommit:completion:));
@end
NS_SWIFT_UI_ACTOR
@interface PCNativePage (TabSharing)
//
//
// tab-sharing delegate offers that button enabled. Changes notify the observer.
@property(nonatomic, readonly) BOOL canShareThisTabInstead;
- (BOOL)shareThisTabInstead;
@end
NS_SWIFT_UI_ACTOR
@interface PCNativePage (SiteInfo)
@property(nonatomic, readonly) BOOL canShowSiteInfo;
- (BOOL)showSiteInfoFromView:(NSView*)anchor
    NS_SWIFT_NAME(showSiteInfo(from:));
@end
// Site Control Center Settings rows (WEB14): one headless genuine PageInfo
// session for this page's current document. The handler runs on main with the
// presenter's permission rows ("title" and stable "key" NSString, "allowed",
// "changeable" and "autoPictureInPicture" BOOL, "index" and "revision"
// integers) whenever it republishes them, and once with nil when the document,
// page or close ends the session. A toggle names a shown row and its revision;
// stale rows are refused. Index -2 is the profile's Automatic Picture-in-
// Picture setting while PageInfo lists no such row. Closing runs the
// presenter's own OnUIClosing (its reload infobar decision).
NS_SWIFT_UI_ACTOR
@interface PCNativePage (SiteControls)
- (BOOL)openSiteControlsWithHandler:(void (^)(NSArray<NSDictionary<NSString*, id>*>* _Nullable rows))handler
    NS_SWIFT_NAME(openSiteControls(handler:));
- (BOOL)toggleSiteControlsPermission:(NSInteger)index revision:(NSUInteger)revision
    NS_SWIFT_NAME(toggleSiteControlsPermission(_:revision:));
- (void)closeSiteControls;
// The footer's Secure/Insecure button: Chromium's certificate viewer for the
// visible entry's server certificate. Pages without one have nothing to show.
@property(nonatomic, readonly) BOOL canShowCertificate;
- (BOOL)showCertificate;
@end
// Immutable Profile/search-model leases. Copied engine IDs are genuine
// TemplateURL sync GUIDs, never indexes or shell-maintained URL templates.
FOUNDATION_EXPORT NSNotificationName const PCNativeSearchPreferencesDidChangeNotification;
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeSearchEngine : NSObject
@property(nonatomic, readonly, copy) NSString* identifier;
@property(nonatomic, readonly, copy) NSString* name;
@property(nonatomic, readonly, copy) NSString* keyword;
@property(nonatomic, readonly) BOOL canMakeDefault;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeSearchPreferences : NSObject
@property(nonatomic, readonly, copy) NSString* profilePath;
@property(nonatomic, readonly) uint64_t revision;
@property(nonatomic, readonly, copy) NSArray<PCNativeSearchEngine*>* engines;
@property(nonatomic, readonly, copy, nullable) NSString* defaultIdentifier;
@property(nonatomic, readonly) BOOL defaultEditable;
@property(nonatomic, readonly) BOOL defaultManaged;
@property(nonatomic, readonly) BOOL defaultExtensionControlled;
@property(nonatomic, readonly) BOOL suggestionsEnabled;
@property(nonatomic, readonly) BOOL suggestionsEditable;
@property(nonatomic, readonly) BOOL suggestionsManaged;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeSearchNavigation : NSObject
@property(nonatomic, readonly, copy) NSString* profilePath;
@property(nonatomic, readonly) uint64_t revision;
@property(nonatomic, readonly, copy) NSURL* URL;
@property(nonatomic, readonly, copy) NSString* title;
@property(nonatomic, readonly, copy) NSString* detail;
@property(nonatomic, readonly) BOOL search;
// Exact provider text for editing a highlighted result. It is not a URL or a
// replacement navigation request. The original token keeps POST/profile data.
@property(nonatomic, readonly, copy) NSString* editText;
// Only the genuine default match may offer this input-plus-provider suffix.
// Nil for explicit-selection-only, scoped, suppressed or non-default results.
@property(nonatomic, readonly, copy, nullable) NSString* inlineCompletionText;
// The explicit non-scope Tab completion capability; search is broader (for
// example, search-history and other-engine results remain distinct).
@property(nonatomic, readonly) BOOL canCompleteWithTab;
// Chromium's AutocompleteMatchType::ToString name, for example
// "search-what-you-typed", "search-suggest", "search-suggest-entity",
// "search-history", "url-what-you-typed", "history-url", "navsuggest",
// "bookmark-title" or "search-calculator-answer".
@property(nonatomic, readonly, copy) NSString* matchType;
// The provider's relevance score, which orders Chromium's own result.
@property(nonatomic, readonly) NSInteger relevance;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
NS_SWIFT_UI_ACTOR
@interface PCNativeBrowserApplication (Search)
// Initializes only the exact registered profile path when needed. Completion
// may be synchronous; callers guard their selected-profile/request generation.
+ (void)searchPreferencesForProfilePath:(NSString*)path
                            completion:(void (^)(PCNativeSearchPreferences* _Nullable, NSError* _Nullable))completion
    NS_SWIFT_NAME(searchPreferences(profilePath:completion:));
+ (nullable PCNativeSearchPreferences*)setDefaultSearchEngine:(NSString*)identifier
                                    forPreferences:(PCNativeSearchPreferences*)preferences
                                             error:(NSError**)error
    NS_SWIFT_NAME(setDefaultSearchEngine(_:for:));
+ (nullable PCNativeSearchPreferences*)setSearchSuggestionsEnabled:(BOOL)enabled
                                          forPreferences:(PCNativeSearchPreferences*)preferences
                                                   error:(NSError**)error
    NS_SWIFT_NAME(setSearchSuggestionsEnabled(_:for:));
+ (void)resolveSearchInput:(NSString*)input profilePath:(NSString*)path
                   page:(nullable PCNativePage*)page
               completion:(void (^)(PCNativeSearchNavigation* _Nullable, NSError* _Nullable))completion
    NS_SWIFT_NAME(resolveSearchInput(_:profilePath:page:completion:));
+ (void)resolveSearchInput:(NSString*)input profilePath:(NSString*)path
    page:(nullable PCNativePage*)page window:(nullable PCNativeBrowserWindow*)window
    completion:(void (^)(PCNativeSearchNavigation* _Nullable, NSError* _Nullable))completion
    NS_SWIFT_NAME(resolveSearchInput(_:profilePath:page:window:completion:));
@end
NS_SWIFT_UI_ACTOR
@interface PCNativePage (Search)
// Consumes the complete classified request once, including real POST content.
- (BOOL)loadSearchNavigation:(PCNativeSearchNavigation*)navigation
    NS_SWIFT_NAME(loadSearchNavigation(_:));
@end
NS_SWIFT_UI_ACTOR
@interface PCNativeBrowserWindow (Search)
// Repeated command-bar open preserves the publication; native makes a new
// one-shot request with the exact original payload and Profile. No URL replay.
- (void)openBackgroundSearchNavigation:(PCNativeSearchNavigation*)navigation
    sourcePage:(nullable PCNativePage*)sourcePage container:(NSView*)container validateOwner:(BOOL (^)(void))validateOwner
    completion:(void (^)(PCNativePage* _Nullable, NSError* _Nullable))completion;
- (void)openSearchNavigation:(PCNativeSearchNavigation*)navigation container:(NSView*)container
                 completion:(void (^)(PCNativePage* _Nullable, NSError* _Nullable))completion;
@end
// Extension results are event actions, not navigation requests. They have no
// destination URL: only their original live omnibox session may execute them.
typedef NS_ENUM(NSInteger, PCNativeOmniboxExtensionDisposition) {
  PCNativeOmniboxExtensionDispositionCurrentTab,
  PCNativeOmniboxExtensionDispositionNewForegroundTab,
  PCNativeOmniboxExtensionDispositionNewBackgroundTab,
};
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeOmniboxExtensionAction : NSObject
@property(nonatomic, readonly, copy) NSString* identifier;
@property(nonatomic, readonly, copy) NSString* extensionID;
@property(nonatomic, readonly, copy) NSString* title;
@property(nonatomic, readonly, copy) NSString* detail;
@property(nonatomic, readonly, copy) NSString* editText;
// Position in the original combined native result order, before shell commands.
@property(nonatomic, readonly) NSUInteger resultIndex;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
// A native keyword offer is valid only in the session/snapshot which issued it.
// Its result is the identical object in that snapshot's results (nil for active
// scope). Do not infer a scope from a URL or attach it to a local command/tab.
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeOmniboxScope : NSObject
@property(nonatomic, readonly, copy) NSString* identifier;
@property(nonatomic, readonly, copy) NSString* name;
@property(nonatomic, readonly, copy) NSString* keyword;
// Issuing snapshot for an offer; first active snapshot for an entered scope.
@property(nonatomic, readonly) uint64_t revision;
// Actual originating profile preference; changes invalidate the offer.
@property(nonatomic, readonly) BOOL spaceTriggerEnabled;
@property(nonatomic, readonly, strong, nullable) PCNativeSearchNavigation* result;
@property(nonatomic, readonly, strong, nullable) PCNativeOmniboxExtensionAction* extensionAction;
@property(nonatomic, readonly, getter=isExtension) BOOL extension;
// The engine's search URL template, the host of its empty-query search URL and
// whether it is one of Chromium's prepopulated providers.
@property(nonatomic, readonly, copy) NSString* templateURL;
@property(nonatomic, readonly, copy) NSString* searchHost;
@property(nonatomic, readonly, getter=isPrepopulated) BOOL prepopulated;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
// Immutable website menu lease: exact session, active engine, input generation,
// Profile and original document. Provider result refresh alone does not revoke it.
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeOmniboxScopeMenu : NSObject
@property(nonatomic, readonly, strong) PCNativeOmniboxScope* activeScope;
@property(nonatomic, readonly, copy) NSArray<PCNativeOmniboxScope*>* choices;
@property(nonatomic, readonly) BOOL canRemove;
@property(nonatomic, readonly) BOOL requiresRemovalConfirmation;
@property(nonatomic, readonly) BOOL canManage;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeOmniboxSnapshot : NSObject
@property(nonatomic, readonly) uint64_t revision;
@property(nonatomic, readonly, copy) NSString* input;
@property(nonatomic, readonly, copy) NSArray<PCNativeSearchNavigation*>* results;
@property(nonatomic, readonly, copy) NSArray<PCNativeOmniboxExtensionAction*>* extensionActions;
@property(nonatomic, readonly, copy) NSArray<PCNativeOmniboxScope*>* scopeOffers;
// Every active website engine, enterable while this snapshot is current.
@property(nonatomic, readonly, copy) NSArray<PCNativeOmniboxScope*>* siteScopes;
// Convenience for the first result only; selected rows use scopeOffers/result.
@property(nonatomic, readonly, strong, nullable) PCNativeOmniboxScope* offeredScope;
@property(nonatomic, readonly, strong, nullable) PCNativeOmniboxScope* activeScope;
@property(nonatomic, readonly, strong, nullable) NSError* error;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeOmnibox : NSObject
// When set, snapshotChanged supersedes the legacy resultsChanged callback.
@property(nonatomic, copy, nullable) void (^snapshotChanged)(PCNativeOmniboxSnapshot*);
@property(nonatomic, copy, nullable) void (^resultsChanged)(NSArray<PCNativeSearchNavigation*>*, NSError* _Nullable);
- (instancetype)initWithProfilePath:(NSString*)path page:(nullable PCNativePage*)page NS_SWIFT_NAME(init(profilePath:page:));
- (instancetype)initWithProfilePath:(NSString*)path page:(nullable PCNativePage*)page
    window:(nullable PCNativeBrowserWindow*)window NS_SWIFT_NAME(init(profilePath:page:window:));
- (void)updateInput:(NSString*)input NS_SWIFT_NAME(updateInput(_:));
// Editing eligibility is captured with the query, including while Profile load
// is pending. The legacy entry deliberately suppresses automatic completion.
- (void)updateInput:(NSString*)input allowsInlineCompletion:(BOOL)allowed
    NS_SWIFT_NAME(updateInput(_:allowsInlineCompletion:));
// Entry clears native input. Exit clears scope/results; the shell restores its
// exact original text/selection with updateInput:. Neither operation navigates.
- (BOOL)enterScope:(PCNativeOmniboxScope*)offer NS_SWIFT_NAME(enterScope(_:));
- (BOOL)leaveScope;
- (nullable PCNativeOmniboxScopeMenu*)scopeMenu;
- (BOOL)canUseScopeMenu:(PCNativeOmniboxScopeMenu*)menu NS_SWIFT_NAME(canUseScopeMenu(_:));
// Switch retains the native query. Remove deletes the actual saved TemplateURL
// through Chromium's policy controller; never an OTR-to-original-profile write.
- (BOOL)changeScope:(PCNativeOmniboxScope*)scope menu:(PCNativeOmniboxScopeMenu*)menu
    NS_SWIFT_NAME(changeScope(_:menu:));
- (BOOL)removeScope:(PCNativeOmniboxScopeMenu*)menu confirmed:(BOOL)confirmed
    NS_SWIFT_NAME(removeScope(_:confirmed:));
// Only the identical result in this session's current delivered publication is
// eligible. Removal consumes that lease and delegates persistence to its real
// Chromium provider; it never derives a history URL from display text.
@property(nonatomic, readonly) BOOL canSubmit;
- (BOOL)canDeleteResult:(PCNativeSearchNavigation*)result NS_SWIFT_NAME(canDeleteResult(_:));
- (BOOL)deleteResult:(PCNativeSearchNavigation*)result NS_SWIFT_NAME(deleteResult(_:));
// Dispatch consumes this exact delivered action before notifying the extension.
// Invoke before cancel/dismiss. True means dispatched, not navigation completed.
- (BOOL)canExecuteExtensionAction:(PCNativeOmniboxExtensionAction*)action
    NS_SWIFT_NAME(canExecuteExtensionAction(_:));
- (BOOL)executeExtensionAction:(PCNativeOmniboxExtensionAction*)action
    disposition:(PCNativeOmniboxExtensionDisposition)disposition
    NS_SWIFT_NAME(executeExtensionAction(_:disposition:));
- (BOOL)canDeleteExtensionAction:(PCNativeOmniboxExtensionAction*)action
    NS_SWIFT_NAME(canDeleteExtensionAction(_:));
- (BOOL)deleteExtensionAction:(PCNativeOmniboxExtensionAction*)action
    NS_SWIFT_NAME(deleteExtensionAction(_:));
- (void)cancel;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

NS_SWIFT_UI_ACTOR
@interface PCNativeBrowserApplication (Favicons)
// Exact persistent-profile history lookup; completion is always on main.
// Missing/deleted icons, private profiles and cancelled profile work return nil.
+ (void)faviconForURL:(NSURL*)url profilePath:(NSString*)path
          completion:(void (^)(NSImage* _Nullable))completion
    NS_SWIFT_NAME(favicon(for:profilePath:completion:));
@end


// A switcher subscribes only while visible. Images are produced by the actual
// tab thumbnail helper; no page is created, selected or navigated for preview.
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeTabPreview : NSObject
- (void)invalidate;
@end

NS_SWIFT_UI_ACTOR
@interface PCNativePage (TabPreview)
- (nullable PCNativeTabPreview*)observePreviewInWindow:(NSWindow*)window
    handler:(void (^)(NSImage* _Nullable))handler
    NS_SWIFT_NAME(observePreview(in:handler:));
@end

//
//
// holds web content size during a sidebar-width drag until it reports the size
// last applied. Parc's choice, not recovered: the viewport, in points, of the
// latest frame the browser activated for this page's primary main-frame
// widget, cc::RenderFrameMetadata viewport_size_in_pixels /
// device_scale_factor. NSZeroSize before the first frame or for a closed page.
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeRenderFrameObservation : NSObject
- (void)invalidate;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

NS_SWIFT_UI_ACTOR
@interface PCNativePage (RenderFrameViewport)
@property(nonatomic, readonly) NSSize renderFrameViewportSize;
// The handler runs on main, synchronously from Chromium's
// RenderFrameMetadataProvider, after each activation of a frame whose metadata
// changed, and follows the primary main-frame widget across renderer swaps. It
// is not called with the current value. The lease ends on invalidate,
// release, page close or WebContents destruction; nil for a closed page.
// Absent in older engines.
- (nullable PCNativeRenderFrameObservation*)observeRenderFrameViewportSize:
    (void (^)(NSSize size))handler NS_SWIFT_NAME(observeRenderFrameViewportSize(_:));
@end

//
//
//
// NONE -> none, SECURE -> secure, every other level (WARNING, DANGEROUS) ->
//
// visible security state; DidChangeVisibleSecurityState already notifies the
// page observer. None for a closed or retiring page. Absent in older engines.
typedef NS_ENUM(NSInteger, PCNativeSecureContextState) {
  PCNativeSecureContextStateNone,
  PCNativeSecureContextStateInsecure,
  PCNativeSecureContextStateSecure,
};
NS_SWIFT_UI_ACTOR
@interface PCNativePage (SecureContext)
@property(nonatomic, readonly) PCNativeSecureContextState secureContextState;
@end

// The page's background as Chromium composites it
// (WebContents::GetBackgroundColor): the root CSS background over the base
// background, white or the dark canvas for `color-scheme: dark`, so opaque in
// Parc. Nil until the renderer first reports it for the current document, and
// for a closed or retiring page. The pane top bar falls back to it after the
// theme colour. Observer notifies carry changes to the colour the bar shows
// (TopBarPageColor). Absent before overlay 293.
NS_SWIFT_UI_ACTOR
@interface PCNativePage (PageBackgroundColor)
@property(nonatomic, readonly, nullable) NSColor* pageBackgroundColor;
@end

//
// renderer chose for the main frame's top band, or the browser's sample of
// the composited frame there, delivered only when it changes.
// `topBandColor` is nil before the first delivery for the current document
// and when a delivery has no colour, which the top bar ignores.
// `topBandColorHost` is the host of the committed http or https document that
// produced it, never the visible or Reader display URL's; nil for Reader,
// extension, internal and hostless pages, whose colours are not cached.
// `topBandColorCrossfades` is false for reports before the document's first
// largest-contentful-paint update and for the first report after it. Observer
// notifies carry deliveries that change the colour. Absent before overlay 294.
NS_SWIFT_UI_ACTOR
@interface PCNativePage (TopBandColor)
@property(nonatomic, readonly) BOOL hasTopBandColorSample;
@property(nonatomic, readonly, nullable) NSColor* topBandColor;
@property(nonatomic, readonly, nullable, copy) NSString* topBandColorHost;
@property(nonatomic, readonly) BOOL topBandColorCrossfades;
@end

// From overlay 294 a regular profile's history deletions (Clear Browsing Data,
// history removal) post "PCNativeHistoryDidDeleteNotification" on main, with
// userInfo `allHistory` (NSNumber BOOL), `hosts` (NSArray<NSString*> of fully
// deleted URLs' hosts), and `timeRange` (NSNumber BOOL) with `begin`/`end`
// (NSNumber, seconds since the reference date) when a time range was deleted.
// From overlay 320 it also carries `profilePath` (NSString), `urls`
// (NSArray<NSString*> of the fully deleted URLs) and, for a time range limited
// to some URLs, `restrictURLs` (NSArray<NSString*>). Shell caches keyed by site
// forget them, and the shell's own visits follow them. The name is a string so
// older engines need no symbol.

// Also admits an empty original window, before a Chromium Browser exists.
// Shell callers retain/revalidate their actual window-controller ownership.
NS_SWIFT_UI_ACTOR
@interface PCNativeBrowserApplication (WindowUndo)
+ (BOOL)canUseWindowUndoInWindow:(NSWindow*)window
    NS_SWIFT_NAME(canUseWindowUndo(in:));
@end

NS_SWIFT_UI_ACTOR
@interface PCNativeBrowserApplication (TabSwitcher)
@property(class, nonatomic, readonly) NSNotificationName tabSwitcherAvailabilityDidChangeNotification;
+ (BOOL)canPresentTabSwitcherInWindow:(NSWindow*)window
    NS_SWIFT_NAME(canPresentTabSwitcher(in:));
@end

// Local database entries for the eligible sidebar recent-pages providers.
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeRecentPage : NSObject
@property(nonatomic, readonly, copy) NSURL* url;
@property(nonatomic, readonly, copy) NSString* title;
@property(nonatomic, readonly, copy) NSDate* visitedAt;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeHistoryQuery : NSObject
// Drops pending delivery and releases all native query/profile observers.
- (void)invalidate;
@end

NS_SWIFT_UI_ACTOR
@interface PCNativeBrowserApplication (RecentPages)
// Domain is notion, figma, linear, confluence or all (every web page, for the
// command bar's empty list). Completion is asynchronous on main, with
// newest-first distinct URLs from this persistent profile only.
+ (nullable PCNativeHistoryQuery*)recentPagesForDomain:(NSString*)domain
    profilePath:(NSString*)path
    completion:(void (^)(NSArray<PCNativeRecentPage*>*))completion
    NS_SWIFT_NAME(recentPages(forDomain:profilePath:completion:));
@end

// Durable removal is independent of the Settings sheet's lifetime. Failed
// guarantees that this operation never crossed the irreversible journal gate.
// Pending remains natively owned or committed and must stay blocked/recovered;
// only Removed permits
// publishing app metadata removal. All callbacks run on the main thread.
typedef NS_ENUM(NSInteger, PCNativeProfileRemovalState) {
  PCNativeProfileRemovalStateRemoved,
  PCNativeProfileRemovalStatePending,
  PCNativeProfileRemovalStateFailed,
};
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeProfileRemoval : NSObject
@property(nonatomic, readonly, copy) NSString* operationID;
@property(nonatomic, readonly, copy) NSString* profilePath;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (void)cancel;
- (void)commitWithRevalidate:(BOOL (^)(void))revalidate
                completion:(void (^)(PCNativeProfileRemovalState, NSError* _Nullable))completion
    NS_SWIFT_NAME(commit(revalidate:completion:));
@end
NS_SWIFT_UI_ACTOR
@interface PCNativeBrowserApplication (ProfileRemoval)
+ (void)prepareProfileRemoval:(NSString*)path
         protectedProfilePath:(NSString*)protectedPath
                  operationID:(NSString*)operationID
                   completion:(void (^)(PCNativeProfileRemoval* _Nullable, NSError* _Nullable))completion
    NS_SWIFT_NAME(prepareProfileRemoval(profilePath:protectedProfilePath:operationID:completion:));
+ (void)recoverProfileRemoval:(NSString*)path
         protectedProfilePath:(NSString*)protectedPath
                  operationID:(NSString*)operationID
                   completion:(void (^)(PCNativeProfileRemovalState, NSError* _Nullable))completion
    NS_SWIFT_NAME(recoverProfileRemoval(profilePath:protectedProfilePath:operationID:completion:));
@end


// A history chooser leases the original page, document and complete ordered
// NavigationEntry ID list. Never replay an entry's display URL.
typedef NS_ENUM(NSInteger, PCNativeNavigationAction) {
  PCNativeNavigationActionBack,
  PCNativeNavigationActionForward,
  PCNativeNavigationActionReload,
  PCNativeNavigationActionReloadBypassingCache,
  PCNativeNavigationActionStop,
};
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeNavigationEntry : NSObject
@property(nonatomic, readonly) int identifier;
@property(nonatomic, readonly, copy) NSString* title;
@property(nonatomic, readonly, nullable) NSURL* URL;
@property(nonatomic, readonly, nullable) NSImage* favicon;
- (instancetype)init NS_UNAVAILABLE;
@end
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeNavigationHistory : NSObject
@property(nonatomic, readonly, copy) NSArray<PCNativeNavigationEntry*>* entries;
@property(nonatomic, readonly, getter=isValid) BOOL valid;
// An alternate selection uses Chromium's original WebContents::Clone and
// NavigateToIndexWithDisposition; beforeunload/repost policy stays upstream.
- (BOOL)navigateToEntry:(PCNativeNavigationEntry*)entry inNewTab:(BOOL)inNewTab
    NS_SWIFT_NAME(navigate(to:inNewTab:));
- (void)invalidate;
- (instancetype)init NS_UNAVAILABLE;
@end
//
//
// eligibility and dismissal.
typedef NS_ENUM(NSInteger, PCNativeMediaSessionStatus) {
  PCNativeMediaSessionStatusActive, PCNativeMediaSessionStatusDucking,
  PCNativeMediaSessionStatusSuspended, PCNativeMediaSessionStatusInactive
};
NS_SWIFT_UI_ACTOR
@interface PCNativePage (MediaControls)
@property(nonatomic, readonly) PCNativeMediaSessionStatus mediaSessionStatus;
// Monotonic counter bumped on every MediaState::Changed (info/actions/
// metadata/mute/…). Facade chrome ticks include it in the mini-player source
// fingerprint so Inactive mic/cam CanAdmit flips still invalidate a cached skip
// even when shell title/URL/loading are unchanged.
@property(nonatomic, readonly) uint64_t mediaControlsRevision;
// Removes this exact media-control episode without changing playback.
- (BOOL)dismissMediaState:(PCNativeMediaState*)state NS_SWIFT_NAME(dismissMediaState(_:));
// An opaque original-document lease avoids requiring the class on older engines.
@property(nonatomic, readonly, nullable) NSObject* tabAudioState;
- (BOOL)tabAudioIsAudible:(NSObject*)state NS_SWIFT_NAME(tabAudioIsAudible(_:));
- (BOOL)tabAudioIsMuted:(NSObject*)state NS_SWIFT_NAME(tabAudioIsMuted(_:));
- (BOOL)toggleTabAudioMuted:(NSObject*)state NS_SWIFT_NAME(toggleTabAudioMuted(_:));
@property(nonatomic, readonly, nullable) PCNativeMediaState* mediaState;
// Called only after the app validates the original source lease. Reading
// mediaState alone never admits an episode.
- (nullable PCNativeMediaState*)admitMediaState NS_SWIFT_NAME(admitMediaState());
// Capture a one-shot original source/document lease before a recovered
// presentation replacement. Consume synchronously after its successful commit.
- (nullable NSObject*)captureMediaPresentationLease NS_SWIFT_NAME(captureMediaPresentationLease());
- (void)mediaPresentationDidRemove:(NSObject*)lease NS_SWIFT_NAME(mediaPresentationDidRemove(_:));
// Retire an existing admission without changing media playback or a prior
// explicit dismissal. Used for a closing/retiring source, not a transfer.
- (void)withdrawMediaState NS_SWIFT_NAME(withdrawMediaState());
- (BOOL)performMediaAction:(PCNativeMediaAction)action state:(PCNativeMediaState*)state
    NS_SWIFT_NAME(performMediaAction(_:state:));
- (BOOL)setMediaVolume:(double)volume state:(PCNativeMediaState*)state
    NS_SWIFT_NAME(setMediaVolume(_:state:));
// The presenting window and the original page are separate leases. The
// implementation revalidates both and refuses a cross-privacy action.
- (BOOL)canPresentMediaState:(PCNativeMediaState*)state inWindow:(NSWindow*)window
    NS_SWIFT_NAME(canPresentMediaState(_:in:));
- (BOOL)canRevealMediaState:(PCNativeMediaState*)state inWindow:(NSWindow*)window
    NS_SWIFT_NAME(canRevealMediaState(_:in:));
- (BOOL)canContinueMediaReveal:(PCNativeMediaState*)state inWindow:(NSWindow*)window
    NS_SWIFT_NAME(canContinueMediaReveal(_:in:));
- (BOOL)dismissMediaState:(PCNativeMediaState*)state inWindow:(NSWindow*)window
    NS_SWIFT_NAME(dismissMediaState(_:in:));
- (BOOL)performMediaAction:(PCNativeMediaAction)action state:(PCNativeMediaState*)state
                  inWindow:(NSWindow*)window NS_SWIFT_NAME(performMediaAction(_:state:in:));
- (BOOL)setMediaVolume:(double)volume state:(PCNativeMediaState*)state
               inWindow:(NSWindow*)window NS_SWIFT_NAME(setMediaVolume(_:state:in:));
@end

NS_SWIFT_UI_ACTOR
@interface PCNativePage (NavigationControls)
@property(nonatomic, readonly) BOOL canShowBackHistory;
@property(nonatomic, readonly) BOOL canShowForwardHistory;
- (nullable PCNativeNavigationHistory*)navigationHistoryBack:(BOOL)back
    NS_SWIFT_NAME(navigationHistory(back:));
- (BOOL)canPerformNavigationAction:(PCNativeNavigationAction)action
    NS_SWIFT_NAME(canPerformNavigation(_:));
- (BOOL)performNavigationAction:(PCNativeNavigationAction)action
                      inNewTab:(BOOL)inNewTab
    NS_SWIFT_NAME(performNavigation(_:inNewTab:));
// The exact page whose Back/Forward/Reload/history alternate created this
// clone, while it remains live in the same Profile. Arrow alternates place at
// the explicit top of Today; Reload and history rows use the referrer rule.
@property(nonatomic, readonly, nullable) PCNativePage* alternateNavigationSourcePage
    NS_SWIFT_NAME(alternateNavigationSourcePage);
@property(nonatomic, readonly) BOOL alternateNavigationPlacesAtTop;
@end

// Source-page link commands. Quote invokes the renderer's real current-selection
// text-fragment generator; no selected text or JavaScript crosses this ABI.
typedef NS_ENUM(NSInteger, PCNativeLinkCopyFormat) {
  PCNativeLinkCopyFormatPlain, PCNativeLinkCopyFormatMarkdown, PCNativeLinkCopyFormatQuote,
};
typedef NS_ENUM(NSInteger, PCNativeLinkCopyResult) {
  PCNativeLinkCopyResultCopied, PCNativeLinkCopyResultUnavailable,
  PCNativeLinkCopyResultCancelled, PCNativeLinkCopyResultBlocked,
};
// An immutable lease for one original document/window/selection. No selected
// text crosses the ABI. Invalidated by selection, document, focus or lifetime.
NS_SWIFT_UI_ACTOR
@interface PCNativeSharedQuoteSelection : NSObject
- (instancetype)init NS_UNAVAILABLE;
@property(nonatomic, readonly) BOOL canCopy;
- (void)copyWithCompletion:(void (^)(PCNativeLinkCopyResult))completion
    NS_SWIFT_NAME(copy(completion:));
@end
NS_SWIFT_UI_ACTOR
@interface PCNativeSharedQuoteObservation : NSObject
- (instancetype)init NS_UNAVAILABLE;
- (void)invalidate;
@end
NS_SWIFT_UI_ACTOR
@interface PCNativePage (CopyLink)
- (nullable PCNativeSharedQuoteObservation*)observeSharedQuoteSelection:
    (void (^)(PCNativeSharedQuoteSelection* _Nullable, BOOL reset))changed
    NS_SWIFT_NAME(observeSharedQuoteSelection(_:));
// Explicit browser-owned auxiliary command (for example Essentials). Plain URL
// only, through the original document and real clipboard policy. The exact key
// command window, original selected page/binding and both window lifetimes gate
// execution/completion. No cached URL or implicit front-window lookup.
- (BOOL)canCopyURLFromCommandWindow:(NSWindow*)window browser:(PCNativeBrowserWindow*)browser
    NS_SWIFT_NAME(canCopyURL(fromCommandWindow:browser:));
- (void)copyURLFromCommandWindow:(NSWindow*)window browser:(PCNativeBrowserWindow*)browser
                     completion:(void (^)(PCNativeLinkCopyResult))completion
    NS_SWIFT_NAME(copyURL(fromCommandWindow:browser:completion:));
- (BOOL)canCopyLinkWithFormat:(PCNativeLinkCopyFormat)format NS_SWIFT_NAME(canCopyLink(as:));
- (void)copyLinkWithFormat:(PCNativeLinkCopyFormat)format
              completion:(void (^)(PCNativeLinkCopyResult))completion NS_SWIFT_NAME(copyLink(as:completion:));
@end

NS_SWIFT_UI_ACTOR
@interface PCNativePage (Capture)
// Read-only command eligibility. The shell validates its own command-bar
// ownership; beginCapture still requires the original parent key window.
- (BOOL)canCaptureInWindow:(NSWindow*)window NS_SWIFT_NAME(canCapture(in:));
- (nullable PCNativePageCapture*)beginCaptureInWindow:(NSWindow*)window
    NS_SWIFT_NAME(beginCapture(in:));
@end

NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeLiveCapturePosition : NSObject
- (void)cancel;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
NS_SWIFT_UI_ACTOR
@interface PCNativePage (LiveCapture)
@property(nonatomic, readonly) double liveCaptureZoomFactor;
// A fixed positioning operation on this existing embedded page, never a page
// factory or an arbitrary script API. Cancellation retires pending retries.
- (nullable PCNativeLiveCapturePosition*)positionLiveCapture:(NSRect)region
    scrollOffset:(NSPoint)scrollOffset displayWidth:(double)displayWidth
    completion:(void (^)(BOOL))completion
    NS_SWIFT_NAME(positionLiveCapture(_:scrollOffset:displayWidth:completion:));
@end

NS_SWIFT_UI_ACTOR
@interface PCNativePage (EmbeddedSnapshot)
// The compositor pixels of this embedded page's whole viewport, for the owner
// that draws the page into its own artwork (an Easel export). Unlike
// beginCapture, any page whose embedded owner lease holds qualifies: not
// selected, scrolled away, hidden or under an attached sheet. Screenshot policy
// still refuses. A hidden renderer is made to draw a frame for the copy.
// Returns NO without replying when ineligible; otherwise replies exactly once,
// asynchronously on main, with pixels or an error.
- (BOOL)snapshotEmbeddedPageWithCompletion:(void (^)(PCNativePageCaptureResult*))completion
    NS_SWIFT_NAME(snapshotEmbeddedPage(completion:));
@end

NS_ASSUME_NONNULL_END

// AppleScript execution is bound to the original primary document and profile.
// JSON is text (including quotes for a JavaScript string), never an AE record.
NS_ASSUME_NONNULL_BEGIN
@interface PCNativeAppleScriptResult : NSObject
@property(nonatomic, readonly, nullable) NSString* json;
@property(nonatomic, readonly, nullable) NSString* errorMessage;
@property(nonatomic, readonly) NSInteger errorNumber;
@end
@interface PCNativeAppleScriptExecution : NSObject
- (void)cancel;
@end
@interface PCNativePage (AppleScript)
@property(nonatomic, readonly) BOOL appleEventJavaScriptAllowed;
@property(nonatomic, readonly) BOOL canToggleAppleEventJavaScript;
// Uses Chromium's current-event PID/HID-source check; never bypasses it.
- (BOOL)toggleAppleEventJavaScript;
- (PCNativeAppleScriptExecution*)executeAppleEventJavaScript:(NSString*)script
    completion:(void (^)(PCNativeAppleScriptResult*))completion
    NS_SWIFT_NAME(executeAppleEventJavaScript(_:completion:));
@end
typedef NS_OPTIONS(NSUInteger, PCNativeImportCategories) {
  PCNativeImportCategoryHistory = 1 << 0,
  PCNativeImportCategoryBookmarks = 1 << 1,
  PCNativeImportCategoryCookies = 1 << 2,
  PCNativeImportCategoryPasswords = 1 << 3,
  PCNativeImportCategoryAutofill = 1 << 4,
  PCNativeImportCategoryExtensions = 1 << 5,
};
typedef NS_ENUM(NSInteger, PCNativeImportAccess) {
  PCNativeImportAccessComplete,
  PCNativeImportAccessRestricted,
};
typedef NS_ENUM(NSInteger, PCNativeImportPhase) {
  PCNativeImportPhaseReading,
  PCNativeImportPhaseWriting,
  PCNativeImportPhaseFinished,
};
typedef NS_ENUM(NSInteger, PCNativeImportOutcome) {
  PCNativeImportOutcomeCompleted,
  PCNativeImportOutcomePartial,
  PCNativeImportOutcomeCancelled,
  PCNativeImportOutcomeFailed,
};
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeImportSource : NSObject
@property(nonatomic, readonly, copy) NSString* identifier;
@property(nonatomic, readonly, copy) NSString* displayName;
@property(nonatomic, readonly, copy) NSURL* appURL;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeImportExtension : NSObject
@property(nonatomic, readonly, copy) NSString* identifier;
@property(nonatomic, readonly, copy) NSString* displayName;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeImportProfile : NSObject
@property(nonatomic, readonly, copy) NSString* identifier;
@property(nonatomic, readonly) PCNativeImportSource* source;
@property(nonatomic, readonly, copy) NSString* displayName;
@property(nonatomic, readonly) PCNativeImportCategories supportedCategories;
@property(nonatomic, readonly, copy) NSArray<PCNativeImportExtension*>* extensions;
@property(nonatomic, readonly) PCNativeImportAccess access;
// Human-readable source/platform restrictions, never credential values.
@property(nonatomic, readonly, copy) NSArray<NSString*>* constraints;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeImportProfileResult : NSObject
@property(nonatomic, readonly, copy) NSArray<PCNativeImportProfile*>* profiles;
@property(nonatomic, readonly) PCNativeImportAccess access;
@property(nonatomic, readonly, copy) NSArray<NSString*>* constraints;
@property(nonatomic, readonly, nullable) NSError* error;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeImportedBookmark : NSObject
// Stable within the immutable source snapshot, including same-title siblings.
@property(nonatomic, readonly, copy) NSString* identifier;
@property(nonatomic, readonly, copy) NSString* title;
@property(nonatomic, readonly, copy, nullable) NSURL* url;
@property(nonatomic, readonly, copy) NSArray<PCNativeImportedBookmark*>* children;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeImportEvent : NSObject
@property(nonatomic, readonly) PCNativeImportCategories category;
@property(nonatomic, readonly) PCNativeImportPhase phase;
@property(nonatomic, readonly) NSUInteger itemCount;
@property(nonatomic, readonly, copy, nullable) NSString* message;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeImportResult : NSObject
@property(nonatomic, readonly) PCNativeImportOutcome outcome;
@property(nonatomic, readonly) PCNativeImportCategories completedCategories;
@property(nonatomic, readonly) PCNativeImportCategories failedCategories;
// Bookmarks are returned for the shell's original-target outline selection and
// atomic sidebar insertion. They are not also written into a second bookmark UI.
@property(nonatomic, readonly, copy) NSArray<PCNativeImportedBookmark*>* bookmarks;
// Source-snapshot visit counts for the setup bookmark recommendation. These
// never query a different Profile or include credentials.
@property(nonatomic, readonly, copy) NSDictionary<NSString*, NSNumber*>* historyVisitCounts;
@property(nonatomic, readonly, copy) NSArray<NSString*>* warnings;
@property(nonatomic, readonly, nullable) NSError* error;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeImportDiscovery : NSObject
// Cancel drops a pending discovery/profile result. No profile is created.
- (void)cancel;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeImportSession : NSObject
// Stops further reads/writes; already committed category writes are retained.
// Completion is once, asynchronously on main, including cancellation.
- (void)cancel;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
NS_SWIFT_UI_ACTOR
@interface PCNativeBrowserApplication (DirectBrowserImport)
+ (PCNativeImportDiscovery*)availableImportSourcesWithCompletion:
    (void (^)(NSArray<PCNativeImportSource*>*))completion
    NS_SWIFT_NAME(availableImportSources(completion:));
+ (PCNativeImportDiscovery*)loadImportSourceProfiles:(PCNativeImportSource*)source
    completion:(void (^)(PCNativeImportProfileResult*))completion
    NS_SWIFT_NAME(loadImportSourceProfiles(_:completion:));
// Exact opaque profile token from loadImportSourceProfiles; no arbitrary source
// paths. The exact durable Parc profile path is acquired asynchronously; a
// new target context is allowed, but an off-the-record target is not.
// A nil return is immediate rejection and never calls completion. Accepted
// sessions complete once asynchronously on main, including early cancellation.
// Extensions require explicit selected identifiers; an empty set installs none.
+ (nullable PCNativeImportSession*)importBrowserDataFromProfile:(PCNativeImportProfile*)source
    toProfilePath:(NSString*)profilePath
    inWindow:(NSWindow*)window
    categories:(PCNativeImportCategories)categories
    allowedExtensionIDs:(NSSet<NSString*>*)extensionIDs
    skipExistingCookies:(BOOL)skipExistingCookies
    progress:(void (^)(PCNativeImportEvent*))progress
    completion:(void (^)(PCNativeImportResult*))completion
    NS_SWIFT_NAME(importBrowserData(from:toProfilePath:in:categories:allowedExtensionIDs:skipExistingCookies:progress:completion:));
@end

// Explicit, user-selected CSV import into one original regular Profile. Only
// aggregate counts/errors cross the bridge, never credential values.
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativePasswordFileImportResult : NSObject
@property(nonatomic, readonly) PCNativeImportOutcome outcome;
@property(nonatomic, readonly) NSUInteger importedCount;
@property(nonatomic, readonly) NSUInteger existingCount;
@property(nonatomic, readonly) NSUInteger invalidCount;
@property(nonatomic, readonly) BOOL canRemoveSourceFile;
@property(nonatomic, readonly, nullable) NSError* error;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativePasswordFileImportSession : NSObject
- (void)cancel;
// User consent is required; only the exact successfully imported source can
// move to Trash. Changed files and lost original owners are refused.
- (void)removeSourceFileWithCompletion:(void (^)(NSError* _Nullable))completion
    NS_SWIFT_NAME(removeSourceFile(completion:));
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
NS_SWIFT_UI_ACTOR
@interface PCNativeBrowserApplication (PasswordFileImport)
+ (nullable PCNativePasswordFileImportSession*)importPasswordFile:(NSURL*)fileURL
    toProfilePath:(NSString*)profilePath inWindow:(NSWindow*)window
    completion:(void (^)(PCNativePasswordFileImportResult*))completion
    NS_SWIFT_NAME(importPasswordFile(_:toProfilePath:in:completion:));
@end

// Only the explicitly accepted setup choice may submit this fixed Apple
// extension. No arbitrary ID, active tab or Web Store navigation is accepted.
// Submission and genuine terminal completion belong to the captured regular
// Profile and may outlive the welcome window. Completion is once on main.
NS_SWIFT_UI_ACTOR
@interface PCNativeBrowserApplication (SetupPasswordExtension)
+ (void)installICloudPasswordsExtensionToProfilePath:(NSString*)profilePath
    completion:(void (^)(NSError* _Nullable))completion
    NS_SWIFT_NAME(installICloudPasswordsExtension(toProfilePath:completion:));
@end

// Safari's identity for the sites that need Apple FairPlay, Chrome's
// everywhere else (docs/fairplay-identity.md). A site is a registrable domain
// as the engine reports it ("netflix.com"). A page whose main document is on
// a Safari site presents Safari's user agent, vendor and key systems (no
// Widevine, no UA client hints, no navigator.userAgentData), as do its frames
// on that site and the site's workers; frames on other sites and every other
// page stay Chrome.
NS_SWIFT_UI_ACTOR
@interface PCNativeBrowserApplication (FairPlayIdentity)
// Replaces the engine's lists for one browsing context: the Profile at
// `profilePath`, or with offTheRecord its private browsing context. Safari
// sites present Safari's identity; Chrome sites are the user's choice and win
// over a Safari entry, and learning never adds them. Open pages whose main
// document's identity no longer matches reload. Callable before the Profile
// or private context exists; the engine keeps the lists in memory only.
+ (void)setFairPlayIdentitySafariSites:(NSArray<NSString*>*)safariSites
                           chromeSites:(NSArray<NSString*>*)chromeSites
                           profilePath:(NSString*)profilePath
                          offTheRecord:(BOOL)offTheRecord
    NS_SWIFT_NAME(setFairPlayIdentity(safariSites:chromeSites:profilePath:offTheRecord:));
@end

NS_SWIFT_UI_ACTOR
@interface PCNativePage (FairPlayIdentity)
// The site of the committed main document; nil when it has none (not HTTP(S),
// or nothing committed).
@property(nonatomic, readonly, nullable, copy) NSString* fairPlayIdentitySite;
// The committed main document presents Safari's identity.
@property(nonatomic, readonly) BOOL usesSafariIdentity;
// The page belongs to a private browsing context.
@property(nonatomic, readonly) BOOL fairPlayIdentityOffTheRecord;
@end

NS_ASSUME_NONNULL_END
