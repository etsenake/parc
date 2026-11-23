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
- (void)setCaptions:(nullable NSImage*)image bounds:(NSRect)bounds;
@end

@class PCNativePage;
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeCaptureScrollContainer : NSObject
@property(nonatomic, readonly, copy, nullable) NSString* anchorID;
@property(nonatomic, readonly, copy) NSString* path;
@property(nonatomic, readonly) NSPoint scrollOffset;
@property(nonatomic, readonly) NSRect frame;
- (nullable instancetype)initWithAnchorID:(nullable NSString*)anchorID path:(NSString*)path
    scrollOffset:(NSPoint)scrollOffset frame:(NSRect)frame NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeCaptureLayout : NSObject
@property(nonatomic, readonly) NSSize viewportSize;
@property(nonatomic, readonly) NSPoint scrollOffset;
@property(nonatomic, readonly) NSRect region;
@property(nonatomic, readonly, copy) NSArray<PCNativeCaptureScrollContainer*>* scrollContainers;
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
@property(nonatomic, readonly, nullable) PCNativeCaptureLayout* layout;
@property(nonatomic, readonly, copy, nullable) NSData* pdfData;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

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
@property(nonatomic, readonly, getter=isValid) BOOL valid;
@property(nonatomic, readonly, getter=isCapturing) BOOL capturing;
@property(nonatomic, readonly) NSSize viewportSize;
@property(nonatomic, readonly) NSRect viewportFrame;
@property(nonatomic, readonly, copy) NSString* sourceURL;
@property(nonatomic, readonly, copy) NSString* pageTitle;
@property(nonatomic, readonly, nullable) NSColor* pageThemeColor;
@property(nonatomic, copy, nullable) void (^invalidated)(void);
- (void)targetElementAtPoint:(NSPoint)point
                 completion:(void (^)(PCNativePageCaptureTarget* _Nullable))completion
    NS_SWIFT_NAME(targetElement(at:completion:));
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

NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativePaymentAction : NSObject
@property(nonatomic, readonly, copy) NSString* title;
@property(nonatomic, readonly, copy) NSString* symbolName;
@property(nonatomic, readonly, copy) NSString* savedLabel;
@property(nonatomic, readonly) BOOL requiresPresentationAcknowledgment;
@property(nonatomic, readonly, getter=isEnabled) BOOL enabled;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeOpenAppAction : NSObject
@property(nonatomic, readonly, copy) NSString* title;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

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

typedef NS_ENUM(NSInteger, PCNativeBrowsingContextKind) {
  PCNativeBrowsingContextKindUnavailable,
  PCNativeBrowsingContextKindRegular,
  PCNativeBrowsingContextKindOffTheRecord,
  PCNativeBrowsingContextKindMixed,
};

NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeWindowRequest : NSObject
@property(nonatomic, readonly, copy) NSString* profilePath;
@property(nonatomic, readonly) PCNativeWindowKind kind;
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

typedef NS_ENUM(NSInteger, PCNativeNoteLinkDisposition) {
  PCNativeNoteLinkDispositionInPlace,
  PCNativeNoteLinkDispositionForegroundTab,
  PCNativeNoteLinkDispositionBackgroundTab,
  PCNativeNoteLinkDispositionNewWindow,
};

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

NS_SWIFT_UI_ACTOR
@protocol PCNativeStatusTextThemeSource <NSObject>
- (nullable NSColor*)statusTextThemeBackgroundColor;
- (nullable NSAppearance*)statusTextThemeAppearance;
@end

NS_SWIFT_UI_ACTOR
@protocol PCNativeAirPlayThemeSource <NSObject>
- (nullable NSColor*)airPlayThemeTintColor;
- (nullable NSColor*)airPlayThemeTintColorOnLightSurface;
@end
#define PCNativeAirPlayThemeDidChangeNotification @"PCNativeAirPlayThemeDidChange"
#define PCNativeLinkOutcomeInputsDidChangeNotification @"PCNativeLinkOutcomeInputsDidChange"

NS_SWIFT_UI_ACTOR
@protocol PCNativePageObserver <NSObject>
- (void)nativePageDidChange:(PCNativePage*)page;
- (void)nativePageDidClose:(PCNativePage*)page;
- (void)nativePage:(PCNativePage*)page didFailWithError:(NSError*)error;

@optional
- (void)nativePageFaviconDidChange:(PCNativePage*)page;
- (void)nativePage:(PCNativePage*)page addContextImageToEasel:(PCNativeContextImage*)image;
- (void)nativePage:(PCNativePage*)page openLinkInSplitView:(NSURL*)url;
- (BOOL)nativePageCanOpenLinkInSplitView:(PCNativePage*)page;
- (void)nativePage:(PCNativePage*)page
    requestFocusForRendererCrash:(PCNativeRendererCrash*)crash;
- (void)nativePage:(PCNativePage*)page didLearnSafariIdentityForSite:(NSString*)site;
- (void)nativePageDidPresentFrame:(PCNativePage*)page;
@end

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

NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeCaptureState : NSObject
@property(nonatomic, readonly) BOOL camera;
@property(nonatomic, readonly) BOOL microphone;
@property(nonatomic, readonly) BOOL tab;
@property(nonatomic, readonly) BOOL window;
@property(nonatomic, readonly) BOOL display;
@property(nonatomic, readonly) BOOL mirrored;
@property(nonatomic, readonly) BOOL shared;
@property(nonatomic, readonly) BOOL active;
@property(nonatomic, readonly) BOOL canStopDevices;
@property(nonatomic, readonly) BOOL canStopSharing;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

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
  PCNativePageToolTaskManager,
};

typedef NS_ENUM(NSInteger, PCNativeReaderMode) {
  PCNativeReaderModeInactive,
  PCNativeReaderModeDistilling,
  PCNativeReaderModeViewing,
  PCNativeReaderModeUnavailable,
  PCNativeReaderModeFailedViewer,
};

typedef NS_ENUM(NSInteger, PCNativeMediaAction) {
  PCNativeMediaActionPlay, PCNativeMediaActionPause,
  PCNativeMediaActionPreviousTrack, PCNativeMediaActionNextTrack,
  PCNativeMediaActionToggleMuted, PCNativeMediaActionToggleMicrophone,
  PCNativeMediaActionToggleCamera, PCNativeMediaActionEnterPictureInPicture
};
typedef NS_ENUM(NSInteger, PCNativeAirPlayState) {
  PCNativeAirPlayStateUnavailable = 0,
  PCNativeAirPlayStateAvailable,
  PCNativeAirPlayStateConnecting,
  PCNativeAirPlayStateConnected,
};
typedef NS_ENUM(NSInteger, PCNativeCastState) {
  PCNativeCastStateUnavailable = 0,
  PCNativeCastStateAvailable,
  PCNativeCastStateConnecting,
  PCNativeCastStateConnected,
};
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeMediaState : NSObject
@property(nonatomic, readonly, nullable) NSImage* icon;
@property(nonatomic, readonly, copy) NSString* identifier;
@property(nonatomic, readonly, copy) NSString* title;
@property(nonatomic, readonly, copy) NSString* sourceURL;
@property(nonatomic, readonly, getter=isOffTheRecord) BOOL offTheRecord;
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
@property(nonatomic, readonly) BOOL canEnterPictureInPicture;
@property(nonatomic, readonly) PCNativeAirPlayState airPlayState;
@property(nonatomic, readonly, copy, nullable) NSString* airPlayDeviceName;
@property(nonatomic, readonly) PCNativeCastState castState;
@property(nonatomic, readonly, copy, nullable) NSString* castDeviceName;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

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
@property(nonatomic, readonly, getter=isEmbedded) BOOL embedded;
@property(nonatomic, readonly) BOOL embeddedOwnerValid;
@property(nonatomic, readonly, copy) NSString* identifier;
@property(nonatomic, readonly, copy) NSString* profilePath;
@property(nonatomic, readonly) NSView* nativeView;
@property(nonatomic, readonly, nullable) NSURL* URL;
@property(nonatomic, readonly, nullable) NSImage* favicon;
@property(nonatomic, readonly, copy) NSString* title;
@property(nonatomic, readonly, nullable) PCNativeRendererCrash* rendererCrash;
@property(nonatomic, readonly, nullable) PCNativeCaptureState* captureState;
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
- (BOOL)rendererCrashDidPresent:(PCNativeRendererCrash*)crash;
- (BOOL)performRendererCrashAction:(PCNativeRendererCrash*)crash;
- (void)stop;
- (void)setZoomLevel:(double)level;
- (void)zoomPage:(NSInteger)direction;
@property(nonatomic, readonly) double pageZoomLevel;
@property(nonatomic, readonly) BOOL canFindInPage;
@property(class, nonatomic, readonly) NSNotificationName findResultDidChangeNotification;
@property(nonatomic, readonly, nullable) PCNativeFindResult* findResult;
@property(nonatomic, readonly, copy) NSString* selectionForFind;
- (void)findText:(NSString*)text forward:(BOOL)forward findNext:(BOOL)findNext;
- (void)stopFinding;
- (void)showDeveloperTools;
@property(nonatomic, readonly, nullable, copy) NSString* developerModeHost;
@property(nonatomic, readonly, nullable, copy) NSString* developerModeExtensionHost;
@property(nonatomic, readonly, nullable) NSColor* developerModeTint;
@property(nonatomic, readonly) BOOL developerModeSecure;
- (BOOL)canPerformPageTool:(PCNativePageTool)tool;
- (BOOL)performPageTool:(PCNativePageTool)tool;
@property(nonatomic, readonly) BOOL hasDeveloperTools;
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
- (BOOL)consumeShortcutHint:(PCNativeShortcutCommand*)command
    NS_SWIFT_NAME(consumeShortcutHint(_:));
@end

NS_SWIFT_UI_ACTOR
@interface PCNativePage (WindowUndo)
@property(nonatomic, readonly) BOOL canUseWindowUndo;
@end

NS_SWIFT_UI_ACTOR
@interface PCNativePage (CreatedPage)
@property(nonatomic, readonly, nullable) PCNativePage* peekParentPage;
@property(nonatomic, readonly, nullable) PCNativePage* creationSourcePage NS_SWIFT_NAME(creationSourcePage);
@property(nonatomic, readonly) BOOL routedLinkCreation;
@property(nonatomic, readonly, nullable) id splitLinkLease;
- (void)finishSplitLinkLease:(id)lease NS_SWIFT_NAME(finishSplitLinkLease(_:));
@end

NS_SWIFT_UI_ACTOR
@interface PCNativePage (NavigationState)
- (nullable NSObject*)captureNavigationState NS_SWIFT_NAME(captureNavigationState());
- (nullable NSData*)archivedNavigationState NS_SWIFT_NAME(archivedNavigationState());
+ (nullable NSObject*)navigationStateWithArchive:(NSData*)data
                                     profilePath:(NSString*)profilePath
    NS_SWIFT_NAME(navigationState(archive:profilePath:));
@end

NS_SWIFT_UI_ACTOR
@interface PCNativePage (Discard)
- (BOOL)discardIfIdle NS_SWIFT_NAME(discardIfIdle());
@end

NS_SWIFT_UI_ACTOR
@interface PCNativePage (ReopenedPeek)
- (BOOL)openPeekWithURL:(NSURL*)url NS_SWIFT_NAME(openPeek(url:));
- (BOOL)openPeekWithURL:(NSURL*)url navigationState:(nullable NSObject*)state
    NS_SWIFT_NAME(openPeek(url:navigationState:));
@property(nonatomic, readonly, getter=isReopenedPeek) BOOL reopenedPeek;
@end

NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeExtensionAction : NSObject
@property(nonatomic, readonly, copy) NSString* identifier;
@property(nonatomic, readonly, copy) NSString* pageIdentifier;
@property(nonatomic, readonly, copy) NSString* profilePath;
@property(nonatomic, readonly) NSUInteger generation;
@property(nonatomic, readonly) NSUInteger modelIndex;
@property(nonatomic, readonly)
    NSUInteger pinnedIndex;
@property(nonatomic, readonly, copy) NSString* name;
@property(nonatomic, readonly, copy) NSString* title;
@property(nonatomic, readonly, copy) NSString* tooltip;
@property(nonatomic, readonly, copy) NSString* accessibilityLabel;
@property(nonatomic, readonly, copy, nullable) NSImage* icon;
@property(nonatomic, readonly, copy, nullable) NSImage* iconWithoutBadge;
@property(nonatomic, readonly, copy) NSString* badgeText;
@property(nonatomic, readonly, copy, nullable) NSColor* badgeTextColor;
@property(nonatomic, readonly, copy, nullable) NSColor* badgeBackgroundColor;
@property(nonatomic, readonly, getter=isEnabled) BOOL enabled;
@property(nonatomic, readonly, getter=isPinned) BOOL pinned;
@property(nonatomic, readonly) BOOL canChangePin;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

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

NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeDownloadArrival : NSObject
@property(nonatomic, readonly, weak, nullable) PCNativePage* page;
@property(nonatomic, readonly, copy) NSString* profilePath;
@property(nonatomic, readonly, copy) NSString* downloadIdentifier;
@property(nonatomic, readonly, copy) NSString* itemIdentity;
@property(nonatomic, readonly, nullable, copy) NSString* privateContextIdentifier;
@property(nonatomic, readonly) NSPoint sourceScreenPoint;
@property(nonatomic, readonly, getter=isValid) BOOL valid;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

NS_SWIFT_UI_ACTOR
@protocol PCNativeBrowserWindowClient <NSObject>
- (NSWindow*)nativeBrowserWindow;
- (nullable PCNativePage*)selectedNativePage;
- (NSArray<PCNativePage*>*)visibleNativePages;
@optional
- (nullable id)nativeBrowser:(PCNativeBrowserWindow*)browser
    splitLinkLeaseForPage:(PCNativePage*)page
    NS_SWIFT_NAME(nativeBrowser(_:splitLinkLeaseFor:));
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
    canSplitLinkFromPage:(PCNativePage*)page
    NS_SWIFT_NAME(nativeBrowser(_:canSplitLinkFrom:));
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
    isSplitLinkLeaseCurrent:(id)lease forPage:(PCNativePage*)page
    NS_SWIFT_NAME(nativeBrowser(_:isSplitLinkLeaseCurrent:for:));
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
    canRouteCurrentLinkFrom:(PCNativePage*)page
    NS_SWIFT_NAME(nativeBrowser(_:canRouteCurrentLinkFrom:));
- (nullable NSString*)nativeBrowser:(PCNativeBrowserWindow*)browser
    linkRouteSourceSpaceForPage:(PCNativePage*)page
    NS_SWIFT_NAME(nativeBrowser(_:linkRouteSourceSpaceFor:));
- (nullable PCNativeLinkRoute*)nativeBrowser:(PCNativeBrowserWindow*)browser
    routeCurrentLinkFrom:(PCNativePage*)page targetURL:(NSURL*)url
    authenticationContinuation:(BOOL)authentication
    NS_SWIFT_NAME(nativeBrowser(_:routeCurrentLinkFrom:targetURL:authenticationContinuation:));
- (nullable NSURL*)nativeBrowser:(PCNativeBrowserWindow*)browser
    authenticationReturnURLForPage:(PCNativePage*)page
    NS_SWIFT_NAME(nativeBrowser(_:authenticationReturnURLFor:));
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
    canAcceptLinkRoute:(PCNativeLinkRoute*)route
    NS_SWIFT_NAME(nativeBrowser(_:canAcceptLinkRoute:));
- (nullable PCNativeBrowserWindow*)nativeBrowser:(PCNativeBrowserWindow*)browser
    prepareLinkRoute:(PCNativeLinkRoute*)route
    NS_SWIFT_NAME(nativeBrowser(_:prepareLinkRoute:));
- (void)nativeBrowser:(PCNativeBrowserWindow*)browser
    didFailLinkRoute:(NSError*)error
    NS_SWIFT_NAME(nativeBrowser(_:didFailLinkRoute:));
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
  allowsHistorySwipeForPage:(PCNativePage*)page
    NS_SWIFT_NAME(nativeBrowser(_:allowsHistorySwipeFor:));
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
  shouldOpenCurrentLinkInPeekFrom:(PCNativePage*)page targetURL:(NSURL*)url
    NS_SWIFT_NAME(nativeBrowser(_:shouldOpenCurrentLinkInPeekFrom:targetURL:));
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
  canPresentPeekFrom:(PCNativePage*)page
    NS_SWIFT_NAME(nativeBrowser(_:canPresentPeekFrom:));
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
  canPeekLinkFromPage:(PCNativePage*)page
    NS_SWIFT_NAME(nativeBrowser(_:canPeekLinkFrom:));
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
  canNavigatePeekLinkFromPage:(PCNativePage*)page
    NS_SWIFT_NAME(nativeBrowser(_:canNavigatePeekLinkFrom:));
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
  isPeekPage:(PCNativePage*)page
    NS_SWIFT_NAME(nativeBrowser(_:isPeekPage:));
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
  shouldOpenNewPageInPeekFrom:(PCNativePage*)page targetURL:(NSURL*)url
    NS_SWIFT_NAME(nativeBrowser(_:shouldOpenNewPageInPeekFrom:targetURL:));
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
  allowsPeekWithShift:(BOOL)shift
    NS_SWIFT_NAME(nativeBrowser(_:allowsPeekWithShift:));
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
    openNoteFileURL:(NSURL*)url fromPage:(PCNativePage*)page
        disposition:(PCNativeNoteLinkDisposition)disposition
    NS_SWIFT_NAME(nativeBrowser(_:openNoteFile:from:disposition:));
- (void)nativeBrowser:(PCNativeBrowserWindow*)browser
    downloadDidBegin:(PCNativeDownloadArrival*)arrival
    NS_SWIFT_NAME(nativeBrowser(_:downloadDidBegin:));
- (void)nativeBrowser:(PCNativeBrowserWindow*)browser
    privateDownloadDidUpdate:(NSDictionary<NSString*, id>*)update
    NS_SWIFT_NAME(nativeBrowser(_:privateDownloadDidUpdate:));
- (void)nativeBrowserPrivateDownloadsDidInvalidate:(PCNativeBrowserWindow*)browser;
@required
- (nullable NSView*)nativeBrowser:(PCNativeBrowserWindow*)browser
                 containerForPage:(PCNativePage*)page
                      disposition:(PCNativePageDisposition)disposition;
- (void)nativeBrowser:(PCNativeBrowserWindow*)browser
         didClosePage:(PCNativePage*)page;
- (void)nativeBrowser:(PCNativeBrowserWindow*)browser
        didSelectPage:(PCNativePage*)page
    NS_SWIFT_NAME(nativeBrowser(_:didSelect:));
- (void)nativeBrowser:(PCNativeBrowserWindow*)browser
     didFailWithError:(NSError*)error;
- (void)nativeBrowserFocusAddress:(PCNativeBrowserWindow*)browser;
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
    rotateFocusForward:(BOOL)forward;
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
    setTabFullscreenPage:(nullable PCNativePage*)page;
- (void)nativeBrowserShowTabSearch:(PCNativeBrowserWindow*)browser;
- (void)nativeBrowserCloseTabSearch:(PCNativeBrowserWindow*)browser;
- (void)nativeBrowserShowProfiles:(PCNativeBrowserWindow*)browser;
- (void)nativeBrowser:(PCNativeBrowserWindow*)browser bookmarkURL:(NSURL*)url;
- (NSView*)nativeBrowserSidePanelContainer:(PCNativeBrowserWindow*)browser;
@optional
- (NSView*)nativeBrowserSidePanelFocusScope:(PCNativeBrowserWindow*)browser;
@required
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
    setSidePanelVisible:(BOOL)visible;
- (void)nativeBrowser:(PCNativeBrowserWindow*)browser
    capabilityUnavailable:(NSString*)capability;
@optional
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
    canHandlePeekEscapeFrom:(PCNativePage*)page
    NS_SWIFT_NAME(nativeBrowser(_:canHandlePeekEscapeFrom:));
- (void)nativeBrowser:(PCNativeBrowserWindow*)browser
    handlePeekEscapeFrom:(PCNativePage*)page prefersConfirmation:(BOOL)confirmation
    NS_SWIFT_NAME(nativeBrowser(_:handlePeekEscapeFrom:prefersConfirmation:));
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
- (void)nativeBrowser:(PCNativeBrowserWindow*)browser
    dismissShortcutHint:(PCNativeShortcutCommand*)command page:(PCNativePage*)page
    NS_SWIFT_NAME(nativeBrowser(_:dismissShortcutHint:page:));
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
    isShortcutHintHovered:(PCNativeShortcutCommand*)command page:(PCNativePage*)page
    NS_SWIFT_NAME(nativeBrowser(_:isShortcutHintHovered:page:));
- (void)nativeBrowserExtensionActionsDidChange:(PCNativeBrowserWindow*)browser;
- (void)nativeBrowserPaymentActionsDidChange:(PCNativeBrowserWindow*)browser;
- (PCNativeExtensionPopupAnchor*)nativeBrowserExtensionPopupAnchor:
    (PCNativeBrowserWindow*)browser;
- (void)nativeBrowserDidReleaseLastBrowser:(PCNativeBrowserWindow*)browser;
- (void)nativeBrowserCreationReservationDidAbort:
    (PCNativeBrowserWindow*)browser;
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
    focusDebuggerWarningForPage:(PCNativePage*)page
    NS_SWIFT_NAME(nativeBrowser(_:focusDebuggerWarningFor:));
@end

NS_SWIFT_UI_ACTOR
@protocol PCNativeBrowserApplicationClient <NSObject>
@optional
- (void)nativeApplicationDidLearnSafariIdentityForSite:(NSString*)site
                                           profilePath:(NSString*)profilePath
                                          offTheRecord:(BOOL)offTheRecord
    NS_SWIFT_NAME(nativeApplicationDidLearnSafariIdentity(forSite:profilePath:offTheRecord:));
- (void)nativeApplicationPrivateDownloadDidUpdate:(NSDictionary<NSString*, id>*)update
                                         context:(PCNativePrivateDownloadContext*)context;
- (void)nativeApplicationPrivateDownloadContextDidInvalidate:(PCNativePrivateDownloadContext*)context;
- (id<PCNativeVideoPiPWindow>)
    createVideoPictureInPictureWindow:(NSView*)videoView
                          sourceFrame:(NSRect)sourceFrame
                               action:(void (^)(PCVideoPiPAction, double))action
                              changed:(dispatch_block_t)changed
    NS_SWIFT_NAME(createVideoPictureInPictureWindow(videoView:sourceFrame:action:changed:));
- (void)releaseVideoPictureInPictureWindow:(id<PCNativeVideoPiPWindow>)window
    NS_SWIFT_NAME(releaseVideoPictureInPictureWindow(_:));
- (nullable NSWindow*)nativeDownloadDialogWindowForProfilePath:(NSString*)path
    NS_SWIFT_NAME(nativeDownloadDialogWindow(forProfilePath:));
- (BOOL)nativeDownloadDialogWindow:(NSWindow*)window
            representsProfilePath:(NSString*)path
    NS_SWIFT_NAME(nativeDownloadDialogWindow(_:representsProfilePath:));
@required

- (void)nativeApplicationDownloadDidUpdate:(NSDictionary<NSString*, id>*)update;

- (nullable id<PCNativeBrowserWindowClient>)
    prepareNativeWindowForRequest:(PCNativeWindowRequest*)request
    NS_SWIFT_NAME(prepareNativeWindow(request:));
- (void)nativeApplicationRelaunchedWithArguments:(NSArray<NSString*>*)arguments
                                currentDirectory:(NSString*)currentDirectory
    NS_SWIFT_NAME(nativeApplicationRelaunched(arguments:currentDirectory:));
@end

NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeEmbeddedPageRequest : NSObject
@property(nonatomic, readonly, getter=isPending) BOOL pending;
- (void)cancel;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeBrowserWindow : NSObject
@property(nonatomic, readonly, getter=isPrivateBrowsing) BOOL privateBrowsing;
- (BOOL)beginPrivateBrowsingWithProfilePath:(NSString*)path error:(NSError**)error
    NS_SWIFT_NAME(beginPrivateBrowsing(profilePath:));
- (BOOL)adoptPrivateContextFromRequest:(PCNativeWindowRequest*)request error:(NSError**)error
    NS_SWIFT_NAME(adoptPrivateContext(request:));
@property(nonatomic, readonly) PCNativeBrowsingContextKind browsingContextKind;
@property(nonatomic, readonly, weak, nullable) NSWindow* window;
@property(nonatomic, readonly, weak, nullable) id<PCNativeBrowserWindowClient>
    client;
- (void)openURL:(NSURL*)url
    profilePath:(NSString*)profilePath
      container:(NSView*)container
     completion:
         (void (^)(PCNativePage* _Nullable, NSError* _Nullable))completion;
- (void)openBackgroundURL:(NSURL*)url
              profilePath:(NSString*)profilePath
                container:(NSView*)container
               completion:(void (^)(PCNativePage* _Nullable, NSError* _Nullable))completion;
- (void)openNavigationState:(NSObject*)state
                profilePath:(NSString*)profilePath
                  container:(NSView*)container
                 background:(BOOL)background
                 completion:(void (^)(PCNativePage* _Nullable, NSError* _Nullable))completion;
- (PCNativeEmbeddedPageRequest*)createEmbeddedPageWithURL:(NSURL*)url
    referrer:(nullable NSURL*)referrer
    profilePath:(NSString*)profilePath container:(NSView*)container
    validateOwner:(BOOL (^)(void))validateOwner
    completion:(void (^)(PCNativePage* _Nullable, NSError* _Nullable))completion
    NS_SWIFT_NAME(createEmbeddedPage(url:referrer:profilePath:container:validateOwner:completion:));
- (void)synchronizeSelectionAndLayout;
- (void)synchronizeLayout;
- (BOOL)returnPictureInPictureToOpener;
@property(nonatomic, readonly) BOOL canReturnPictureInPictureToOpener;
- (void)setWebsiteThemeStylesheet:(nullable NSString*)stylesheet;
- (void)pageWillDetach:(PCNativePage*)page;
- (BOOL)pageDidAttach:(PCNativePage*)page container:(NSView*)container;
- (BOOL)pageWillPark:(PCNativePage*)page;
- (void)reportNextFrameOfPage:(PCNativePage*)page;
- (void)requestClose:(void (^)(BOOL allow))completion;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

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

NS_SWIFT_UI_ACTOR
@interface PCNativeBrowserWindow (PageFocus)
- (BOOL)requestFocusForPage:(PCNativePage*)page NS_SWIFT_NAME(requestFocus(for:));
@end

NS_SWIFT_UI_ACTOR
@interface PCNativeBrowserWindow (TaskManager)
@property(nonatomic, readonly) BOOL canOpenTaskManager;
- (BOOL)openTaskManager;
@end

NS_SWIFT_UI_ACTOR
@interface PCNativeBrowserWindow (OpenAppActions)
- (nullable PCNativeOpenAppAction*)openAppActionForPage:(PCNativePage*)page
    NS_SWIFT_NAME(openAppAction(for:));
- (BOOL)executeOpenAppAction:(PCNativeOpenAppAction*)action
                   forPage:(PCNativePage*)page
    NS_SWIFT_NAME(executeOpenAppAction(_:for:));
@end

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
- (BOOL)paymentFeedbackPresented:(PCNativePaymentAction*)action
                         forPage:(PCNativePage*)page
    NS_SWIFT_NAME(paymentFeedbackPresented(_:for:));
@end

NS_SWIFT_UI_ACTOR
@protocol PCNativeMenuPresenter <NSObject>
- (BOOL)presentMenu:(NSMenu*)menu NS_SWIFT_NAME(present(_:));
- (void)cancelMenu NS_SWIFT_NAME(cancel());
@end

NS_SWIFT_UI_ACTOR
@interface PCNativeBrowserWindow (ExtensionActions)
- (BOOL)closeExtensionSidePanel;
- (NSArray<PCNativeExtensionAction*>*)extensionActionsForPage:
    (PCNativePage*)page NS_SWIFT_NAME(extensionActions(for:));
- (BOOL)hasEnabledExtensionsForPage:(PCNativePage*)page
    NS_SWIFT_NAME(hasEnabledExtensions(for:));
- (NSArray<PCNativeEnabledExtension*>*)enabledExtensionsForPage:(PCNativePage*)page
    NS_SWIFT_NAME(enabledExtensions(for:));
- (BOOL)executeEnabledExtension:(PCNativeEnabledExtension*)extension
                        forPage:(PCNativePage*)page
    NS_SWIFT_NAME(executeEnabledExtension(_:for:));
- (BOOL)showEnabledExtensionContextMenu:(PCNativeEnabledExtension*)extension
                                forPage:(PCNativePage*)page
    NS_SWIFT_NAME(showEnabledExtensionContextMenu(_:for:));
- (BOOL)executeExtensionAction:(PCNativeExtensionAction*)action
                       forPage:(PCNativePage*)page
    NS_SWIFT_NAME(executeExtensionAction(_:for:));
- (BOOL)showExtensionActionContextMenu:(PCNativeExtensionAction*)action
                               forPage:(PCNativePage*)page
    NS_SWIFT_NAME(showExtensionActionContextMenu(_:for:));
- (BOOL)showExtensionActionContextMenu:(PCNativeExtensionAction*)action
                               forPage:(PCNativePage*)page
                             presenter:(nullable id<PCNativeMenuPresenter>)presenter
    NS_SWIFT_NAME(showExtensionActionContextMenu(_:for:presenter:));
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
@property(nonatomic, readonly) BOOL canParticipateInPageTransfer;
@property(nonatomic, readonly) BOOL canAdmitHiddenPageTransferDestination;
- (void)transferPage:(PCNativePage*)page
         profilePath:(NSString*)profilePath
           container:(NSView*)container
          completion:(void (^)(PCNativePageTransferResult result,
                               NSError* _Nullable error))completion
    NS_SWIFT_NAME(transferPage(_:profilePath:container:completion:));
- (void)transferPages:(NSArray<PCNativePage*>*)pages
         profilePath:(NSString*)profilePath
          containers:(NSArray<NSView*>*)containers
              commit:(BOOL (^)(void))commit
          completion:(void (^)(PCNativePageTransferResult result,
                               NSError* _Nullable error))completion
    NS_SWIFT_NAME(transferPages(_:profilePath:containers:commit:completion:));
@end

NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeBrowserApplication : NSObject
+ (void)preparePrivateBrowsingWithProfilePath:(NSString*)path
    completion:(void (^)(NSError* _Nullable error))completion
    NS_SWIFT_NAME(preparePrivateBrowsing(profilePath:completion:));
+ (void)accessibilityRoleRequested;
+ (void)accessibilitySetValue:(nullable id)value
                 forAttribute:(NSString*)attribute;
+ (BOOL)accessibilityHandleObservationForKeyPath:(nullable NSString*)keyPath
                                        ofObject:(nullable id)object
                                          change:(nullable NSDictionary*)change
                                         context:(nullable void*)context
    NS_SWIFT_NAME(handleAccessibilityObservation(forKeyPath:of:change:context:));
+ (BOOL)performDownloadAction:(PCNativeDownloadAction)action
                   identifier:(NSString*)identifier
                  profilePath:(NSString*)profilePath
    NS_SWIFT_NAME(performDownloadAction(_:identifier:profilePath:));
+ (void)refreshDownloadsForProfilePath:(NSString*)profilePath
                           completion:(void (^)(NSArray<NSString*>* _Nullable identifiers, NSError* _Nullable error))completion
    NS_SWIFT_NAME(refreshDownloads(profilePath:completion:));
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

+ (void)loadDownloadPreferencesForProfilePath:(NSString*)profilePath
    completion:(void (^)(PCNativeDownloadPreferences* _Nullable preferences,
                         NSError* _Nullable error))completion
    NS_SWIFT_NAME(downloadPreferences(profilePath:completion:));
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
+ (nullable PCNativeBrowserWindow*)ownerForPage:(PCNativePage*)page
    NS_SWIFT_NAME(owner(of:));
+ (nullable PCNativeBrowserWindow*)registerWindowClient:
                                       (id<PCNativeBrowserWindowClient>)client
                                                  error:(NSError**)error;
+ (void)setApplicationClient:(id<PCNativeBrowserApplicationClient>)client;
+ (NSArray<PCNativePrivateDownloadContext*>*)privateDownloadContexts;
+ (void)requestCloseAllWindows:(void (^)(BOOL allow))completion;
+ (void)cancelQuit;
@end
NS_SWIFT_UI_ACTOR
@interface PCNativeBrowserApplication (CookieStore)
@property(class, nonatomic, readonly) BOOL restoresSessionCookies;
+ (void)flushCookieStores;
@end
NS_SWIFT_UI_ACTOR
@interface PCNativeBrowserApplication (TabAudioBatch)
+ (BOOL)setAllTabAudioMuted:(BOOL)muted inWindow:(NSWindow*)window NS_SWIFT_NAME(setAllTabAudioMuted(_:in:));
@end

NS_SWIFT_UI_ACTOR
@interface PCNativeBrowserApplication (PageRetirement)
+ (void)requestClosePages:(NSArray<PCNativePage*>*)pages
             shouldCommit:(BOOL (^)(void))shouldCommit
               completion:(void (^)(BOOL success))completion
    NS_SWIFT_NAME(requestClosePages(_:shouldCommit:completion:));
@end
NS_SWIFT_UI_ACTOR
@interface PCNativePage (TabSharing)
@property(nonatomic, readonly) BOOL canShareThisTabInstead;
- (BOOL)shareThisTabInstead;
@end
#define PCNativePageDebuggerWarningsDidChangeNotification \
  @"PCNativePageDebuggerWarningsDidChange"
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeDebuggerWarning : NSObject
@property(nonatomic, readonly, copy) NSString* message;
@property(nonatomic, readonly, copy) NSString* cancelTitle;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
NS_SWIFT_UI_ACTOR
@interface PCNativePage (DebuggerWarning)
@property(nonatomic, readonly, copy) NSArray<PCNativeDebuggerWarning*>* debuggerWarnings;
- (BOOL)cancelDebuggerWarning:(PCNativeDebuggerWarning*)warning
    NS_SWIFT_NAME(cancelDebuggerWarning(_:));
- (BOOL)dismissDebuggerWarning:(PCNativeDebuggerWarning*)warning
    NS_SWIFT_NAME(dismissDebuggerWarning(_:));
@end
NS_SWIFT_UI_ACTOR
@interface PCNativePage (SiteInfo)
@property(nonatomic, readonly) BOOL canShowSiteInfo;
- (BOOL)showSiteInfoFromView:(NSView*)anchor
    NS_SWIFT_NAME(showSiteInfo(from:));
@end
NS_SWIFT_UI_ACTOR
@interface PCNativePage (SiteControls)
- (BOOL)openSiteControlsWithHandler:(void (^)(NSArray<NSDictionary<NSString*, id>*>* _Nullable rows))handler
    NS_SWIFT_NAME(openSiteControls(handler:));
- (BOOL)toggleSiteControlsPermission:(NSInteger)index revision:(NSUInteger)revision
    NS_SWIFT_NAME(toggleSiteControlsPermission(_:revision:));
- (BOOL)openSiteControlsSystemSettings:(NSInteger)index revision:(NSUInteger)revision
    NS_SWIFT_NAME(openSiteControlsSystemSettings(_:revision:));
- (void)closeSiteControls;
@property(nonatomic, readonly) BOOL canShowCertificate;
- (BOOL)showCertificate;
@end
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
@property(nonatomic, readonly, copy) NSString* editText;
@property(nonatomic, readonly, copy, nullable) NSString* inlineCompletionText;
@property(nonatomic, readonly) BOOL canCompleteWithTab;
@property(nonatomic, readonly, copy) NSString* matchType;
@property(nonatomic, readonly) NSInteger relevance;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
NS_SWIFT_UI_ACTOR
@interface PCNativeBrowserApplication (Search)
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
+ (void)resolveSearchInput:(NSString*)input typedText:(nullable NSString*)typedText
    profilePath:(NSString*)path page:(nullable PCNativePage*)page
    window:(nullable PCNativeBrowserWindow*)window
    completion:(void (^)(PCNativeSearchNavigation* _Nullable, NSError* _Nullable))completion
    NS_SWIFT_NAME(resolveSearchInput(_:typedText:profilePath:page:window:completion:));
@end
NS_SWIFT_UI_ACTOR
@interface PCNativePage (Search)
- (BOOL)loadSearchNavigation:(PCNativeSearchNavigation*)navigation
    NS_SWIFT_NAME(loadSearchNavigation(_:));
@end
NS_SWIFT_UI_ACTOR
@interface PCNativeBrowserWindow (Search)
- (void)openBackgroundSearchNavigation:(PCNativeSearchNavigation*)navigation
    sourcePage:(nullable PCNativePage*)sourcePage container:(NSView*)container validateOwner:(BOOL (^)(void))validateOwner
    completion:(void (^)(PCNativePage* _Nullable, NSError* _Nullable))completion;
- (void)openSearchNavigation:(PCNativeSearchNavigation*)navigation container:(NSView*)container
                 completion:(void (^)(PCNativePage* _Nullable, NSError* _Nullable))completion;
@end
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
@property(nonatomic, readonly) NSUInteger resultIndex;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeOmniboxScope : NSObject
@property(nonatomic, readonly, copy) NSString* identifier;
@property(nonatomic, readonly, copy) NSString* name;
@property(nonatomic, readonly, copy) NSString* keyword;
@property(nonatomic, readonly) uint64_t revision;
@property(nonatomic, readonly) BOOL spaceTriggerEnabled;
@property(nonatomic, readonly, strong, nullable) PCNativeSearchNavigation* result;
@property(nonatomic, readonly, strong, nullable) PCNativeOmniboxExtensionAction* extensionAction;
@property(nonatomic, readonly, getter=isExtension) BOOL extension;
@property(nonatomic, readonly, copy) NSString* templateURL;
@property(nonatomic, readonly, copy) NSString* searchHost;
@property(nonatomic, readonly, getter=isPrepopulated) BOOL prepopulated;
@property(nonatomic, readonly, getter=isLearned) BOOL learned;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
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
@property(nonatomic, readonly, copy) NSArray<PCNativeOmniboxScope*>* siteScopes;
@property(nonatomic, readonly, strong, nullable) PCNativeOmniboxScope* offeredScope;
@property(nonatomic, readonly, strong, nullable) PCNativeOmniboxScope* activeScope;
@property(nonatomic, readonly, strong, nullable) NSError* error;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeOmnibox : NSObject
@property(nonatomic, copy, nullable) void (^snapshotChanged)(PCNativeOmniboxSnapshot*);
@property(nonatomic, copy, nullable) void (^resultsChanged)(NSArray<PCNativeSearchNavigation*>*, NSError* _Nullable);
- (instancetype)initWithProfilePath:(NSString*)path page:(nullable PCNativePage*)page NS_SWIFT_NAME(init(profilePath:page:));
- (instancetype)initWithProfilePath:(NSString*)path page:(nullable PCNativePage*)page
    window:(nullable PCNativeBrowserWindow*)window NS_SWIFT_NAME(init(profilePath:page:window:));
- (void)updateInput:(NSString*)input NS_SWIFT_NAME(updateInput(_:));
- (void)updateInput:(NSString*)input allowsInlineCompletion:(BOOL)allowed
    NS_SWIFT_NAME(updateInput(_:allowsInlineCompletion:));
- (BOOL)enterScope:(PCNativeOmniboxScope*)offer NS_SWIFT_NAME(enterScope(_:));
- (BOOL)leaveScope;
- (nullable PCNativeOmniboxScopeMenu*)scopeMenu;
- (BOOL)canUseScopeMenu:(PCNativeOmniboxScopeMenu*)menu NS_SWIFT_NAME(canUseScopeMenu(_:));
- (BOOL)changeScope:(PCNativeOmniboxScope*)scope menu:(PCNativeOmniboxScopeMenu*)menu
    NS_SWIFT_NAME(changeScope(_:menu:));
- (BOOL)removeScope:(PCNativeOmniboxScopeMenu*)menu confirmed:(BOOL)confirmed
    NS_SWIFT_NAME(removeScope(_:confirmed:));
@property(nonatomic, readonly) BOOL canSubmit;
- (BOOL)canDeleteResult:(PCNativeSearchNavigation*)result NS_SWIFT_NAME(canDeleteResult(_:));
- (BOOL)deleteResult:(PCNativeSearchNavigation*)result NS_SWIFT_NAME(deleteResult(_:));
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
+ (void)faviconForURL:(NSURL*)url profilePath:(NSString*)path
          completion:(void (^)(NSImage* _Nullable))completion
    NS_SWIFT_NAME(favicon(for:profilePath:completion:));
@end

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
- (nullable PCNativeRenderFrameObservation*)observeRenderFrameViewportSize:
    (void (^)(NSSize size))handler NS_SWIFT_NAME(observeRenderFrameViewportSize(_:));
@end

typedef NS_ENUM(NSInteger, PCNativeSecureContextState) {
  PCNativeSecureContextStateNone,
  PCNativeSecureContextStateInsecure,
  PCNativeSecureContextStateSecure,
};
NS_SWIFT_UI_ACTOR
@interface PCNativePage (SecureContext)
@property(nonatomic, readonly) PCNativeSecureContextState secureContextState;
@end

NS_SWIFT_UI_ACTOR
@interface PCNativePage (PageBackgroundColor)
@property(nonatomic, readonly, nullable) NSColor* pageBackgroundColor;
@end

NS_SWIFT_UI_ACTOR
@interface PCNativePage (TopBandColor)
@property(nonatomic, readonly) BOOL hasTopBandColorSample;
@property(nonatomic, readonly, nullable) NSColor* topBandColor;
@property(nonatomic, readonly, nullable, copy) NSString* topBandColorHost;
@property(nonatomic, readonly) BOOL topBandColorCrossfades;
@end

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
- (void)invalidate;
@end

NS_SWIFT_UI_ACTOR
@interface PCNativeBrowserApplication (RecentPages)
+ (nullable PCNativeHistoryQuery*)recentPagesForDomain:(NSString*)domain
    profilePath:(NSString*)path
    completion:(void (^)(NSArray<PCNativeRecentPage*>*))completion
    NS_SWIFT_NAME(recentPages(forDomain:profilePath:completion:));
@end

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
@property(nonatomic, readonly, copy) NSString* persistentIdentifier;
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
- (BOOL)navigateToEntry:(PCNativeNavigationEntry*)entry inNewTab:(BOOL)inNewTab
    NS_SWIFT_NAME(navigate(to:inNewTab:));
- (void)invalidate;
- (instancetype)init NS_UNAVAILABLE;
@end
typedef NS_ENUM(NSInteger, PCNativeMediaSessionStatus) {
  PCNativeMediaSessionStatusActive, PCNativeMediaSessionStatusDucking,
  PCNativeMediaSessionStatusSuspended, PCNativeMediaSessionStatusInactive
};
NS_SWIFT_UI_ACTOR
@interface PCNativePage (MediaControls)
@property(nonatomic, readonly) PCNativeMediaSessionStatus mediaSessionStatus;
@property(nonatomic, readonly) uint64_t mediaControlsRevision;
- (BOOL)dismissMediaState:(PCNativeMediaState*)state NS_SWIFT_NAME(dismissMediaState(_:));
@property(nonatomic, readonly, nullable) NSObject* tabAudioState;
- (BOOL)tabAudioIsAudible:(NSObject*)state NS_SWIFT_NAME(tabAudioIsAudible(_:));
- (BOOL)tabAudioIsMuted:(NSObject*)state NS_SWIFT_NAME(tabAudioIsMuted(_:));
- (BOOL)toggleTabAudioMuted:(NSObject*)state NS_SWIFT_NAME(toggleTabAudioMuted(_:));
@property(nonatomic, readonly, nullable) PCNativeMediaState* mediaState;
- (nullable PCNativeMediaState*)admitMediaState NS_SWIFT_NAME(admitMediaState());
- (nullable NSObject*)captureMediaPresentationLease NS_SWIFT_NAME(captureMediaPresentationLease());
- (void)mediaPresentationDidRemove:(NSObject*)lease NS_SWIFT_NAME(mediaPresentationDidRemove(_:));
- (void)withdrawMediaState NS_SWIFT_NAME(withdrawMediaState());
- (BOOL)performMediaAction:(PCNativeMediaAction)action state:(PCNativeMediaState*)state
    NS_SWIFT_NAME(performMediaAction(_:state:));
- (BOOL)setMediaVolume:(double)volume state:(PCNativeMediaState*)state
    NS_SWIFT_NAME(setMediaVolume(_:state:));
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
- (BOOL)showAirPlayPickerForMediaState:(PCNativeMediaState*)state
                        relativeToRect:(NSRect)rect
                                ofView:(NSView*)view
                              inWindow:(NSWindow*)window
                             dismissed:(void (^)(void))dismissed;
- (BOOL)showCastChooserForMediaState:(PCNativeMediaState*)state
                      relativeToRect:(NSRect)rect
                              ofView:(NSView*)view
                            inWindow:(NSWindow*)window
                           dismissed:(void (^)(void))dismissed;
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
@property(nonatomic, readonly, nullable) PCNativePage* alternateNavigationSourcePage
    NS_SWIFT_NAME(alternateNavigationSourcePage);
@property(nonatomic, readonly) BOOL alternateNavigationPlacesAtTop;
@end

NS_SWIFT_UI_ACTOR
@interface PCNativePage (HistoryEntries)
@property(nonatomic, readonly) NSUInteger historyRevision;
@property(nonatomic, readonly, copy) NSArray<PCNativeNavigationEntry*>* historyEntries;
@property(nonatomic, readonly) NSInteger currentHistoryIndex;
@property(nonatomic, readonly) BOOL historyNavigationPending;
- (BOOL)goToHistoryEntry:(NSString*)persistentIdentifier NS_SWIFT_NAME(goToHistoryEntry(_:));
- (BOOL)removeHistoryEntriesAfterCurrent NS_SWIFT_NAME(removeHistoryEntriesAfterCurrent());
+ (nullable NSObject*)navigationState:(NSObject*)state
                       atHistoryEntry:(NSString*)persistentIdentifier
                        endingAtEntry:(nullable NSString*)lastPersistentIdentifier
    NS_SWIFT_NAME(navigationState(_:at:endingAt:));
@end

typedef NS_ENUM(NSInteger, PCNativeLinkCopyFormat) {
  PCNativeLinkCopyFormatPlain, PCNativeLinkCopyFormatMarkdown, PCNativeLinkCopyFormatQuote,
};
typedef NS_ENUM(NSInteger, PCNativeLinkCopyResult) {
  PCNativeLinkCopyResultCopied, PCNativeLinkCopyResultUnavailable,
  PCNativeLinkCopyResultCancelled, PCNativeLinkCopyResultBlocked,
};
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
- (BOOL)canCaptureInWindow:(NSWindow*)window NS_SWIFT_NAME(canCapture(in:));
- (nullable PCNativePageCapture*)beginCaptureInWindow:(NSWindow*)window
    NS_SWIFT_NAME(beginCapture(in:));
- (nullable PCNativePageCapture*)beginPlaceholderCaptureInWindow:(NSWindow*)window
    NS_SWIFT_NAME(beginPlaceholderCapture(in:));
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
@property(nonatomic, readonly) double liveCaptureSiteZoomFactor;
- (void)setLiveCaptureDisplayZoom:(double)factor NS_SWIFT_NAME(setLiveCaptureDisplayZoom(_:));
- (nullable PCNativeLiveCapturePosition*)positionLiveCapture:(NSRect)region
    scrollOffset:(NSPoint)scrollOffset
    scrollContainers:(NSArray<PCNativeCaptureScrollContainer*>*)scrollContainers
    displayWidth:(double)displayWidth completion:(void (^)(BOOL))completion
    NS_SWIFT_NAME(positionLiveCapture(_:scrollOffset:scrollContainers:displayWidth:completion:));
@end

NS_SWIFT_UI_ACTOR
@interface PCNativePage (EmbeddedSnapshot)
- (BOOL)snapshotEmbeddedPageWithCompletion:(void (^)(PCNativePageCaptureResult*))completion
    NS_SWIFT_NAME(snapshotEmbeddedPage(completion:));
@end

NS_ASSUME_NONNULL_END

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
@property(nonatomic, readonly, copy) NSString* directoryName;
@property(nonatomic, readonly) PCNativeImportCategories supportedCategories;
@property(nonatomic, readonly, copy) NSArray<PCNativeImportExtension*>* extensions;
@property(nonatomic, readonly) PCNativeImportAccess access;
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
@property(nonatomic, readonly, copy) NSArray<PCNativeImportedBookmark*>* bookmarks;
@property(nonatomic, readonly, copy) NSDictionary<NSString*, NSNumber*>* historyVisitCounts;
@property(nonatomic, readonly, copy) NSArray<NSString*>* warnings;
@property(nonatomic, readonly, nullable) NSError* error;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeImportDiscovery : NSObject
- (void)cancel;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeImportSession : NSObject
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
+ (PCNativeImportDiscovery*)loadSafariExportProfiles:(NSArray<NSURL*>*)directories
    names:(NSArray<NSString*>*)names
    completion:(void (^)(PCNativeImportProfileResult*))completion
    NS_SWIFT_NAME(loadSafariExportProfiles(_:names:completion:));
+ (nullable PCNativeImportSession*)importBrowserDataFromProfile:(PCNativeImportProfile*)source
    toProfilePath:(NSString*)profilePath
    inWindow:(NSWindow*)window
    categories:(PCNativeImportCategories)categories
    skipExistingCookies:(BOOL)skipExistingCookies
    progress:(void (^)(PCNativeImportEvent*))progress
    completion:(void (^)(PCNativeImportResult*))completion
    NS_SWIFT_NAME(importBrowserData(from:toProfilePath:in:categories:skipExistingCookies:progress:completion:));
@end
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeImportExtensionRequest : NSObject
- (instancetype)initWithSource:(PCNativeImportProfile*)source
    profilePath:(NSString*)profilePath
    extensionIDs:(NSSet<NSString*>*)extensionIDs
    NS_SWIFT_NAME(init(source:profilePath:extensionIDs:));
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
typedef NS_ENUM(NSInteger, PCNativeExtensionRestriction) {
  PCNativeExtensionRestrictionNone,
  PCNativeExtensionRestrictionAdministrator,
  PCNativeExtensionRestrictionOtherApp,
  PCNativeExtensionRestrictionParentalApproval,
  PCNativeExtensionRestrictionBlocklisted,
};
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeImportExtensionFailure : NSObject
@property(nonatomic, readonly, copy) NSString* identifier;
@property(nonatomic, readonly, copy) NSString* name;
@property(nonatomic, readonly, copy) NSString* profilePath;
@property(nonatomic, readonly) PCNativeExtensionRestriction restriction;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
NS_SWIFT_UI_ACTOR
__attribute__((visibility("default")))
@interface PCNativeImportExtensionResult : NSObject
@property(nonatomic, readonly) PCNativeImportOutcome outcome;
@property(nonatomic, readonly, copy) NSSet<NSString*>* installedIdentifiers;
@property(nonatomic, readonly, copy) NSSet<NSString*>* installingIdentifiers;
@property(nonatomic, readonly, copy) NSArray<PCNativeImportExtensionFailure*>* failures;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
NS_SWIFT_UI_ACTOR
@interface PCNativeBrowserApplication (ImportedExtensions)
+ (nullable PCNativeImportSession*)installImportedExtensions:
    (NSArray<PCNativeImportExtensionRequest*>*)requests
    completion:(void (^)(PCNativeImportExtensionResult*))completion
    backgroundFailures:(void (^)(NSArray<PCNativeImportExtensionFailure*>*))backgroundFailures
    NS_SWIFT_NAME(installImportedExtensions(_:completion:backgroundFailures:));
@end

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

NS_SWIFT_UI_ACTOR
@interface PCNativeBrowserApplication (SetupPasswordExtension)
+ (void)installICloudPasswordsExtensionToProfilePath:(NSString*)profilePath
    completion:(void (^)(NSError* _Nullable))completion
    NS_SWIFT_NAME(installICloudPasswordsExtension(toProfilePath:completion:));
+ (void)installSetupAdBlockerToProfilePath:(NSString*)profilePath
    completion:(void (^)(NSError* _Nullable))completion
    NS_SWIFT_NAME(installSetupAdBlocker(toProfilePath:completion:));
+ (void)removeSetupAdBlockers:(NSSet<NSString*>*)extensionIDs
    fromProfilePath:(NSString*)profilePath
    completion:(void (^)(NSError* _Nullable))completion
    NS_SWIFT_NAME(removeSetupAdBlockers(_:fromProfilePath:completion:));
+ (PCNativeExtensionRestriction)extensionRestrictionForError:(nullable NSError*)error
    NS_SWIFT_NAME(extensionRestriction(for:));
@end

NS_SWIFT_UI_ACTOR
@interface PCNativeBrowserApplication (FairPlayIdentity)
+ (void)setFairPlayIdentitySafariSites:(NSArray<NSString*>*)safariSites
                           chromeSites:(NSArray<NSString*>*)chromeSites
                           profilePath:(NSString*)profilePath
                          offTheRecord:(BOOL)offTheRecord
    NS_SWIFT_NAME(setFairPlayIdentity(safariSites:chromeSites:profilePath:offTheRecord:));
@end

NS_SWIFT_UI_ACTOR
@interface PCNativePage (FairPlayIdentity)
@property(nonatomic, readonly, nullable, copy) NSString* fairPlayIdentitySite;
@property(nonatomic, readonly) BOOL usesSafariIdentity;
@property(nonatomic, readonly) BOOL fairPlayIdentityOffTheRecord;
@end

NS_ASSUME_NONNULL_END
