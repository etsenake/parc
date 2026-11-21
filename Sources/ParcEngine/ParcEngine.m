#import "ParcEngine.h"

#include <sysexits.h>

#import "native_engine_entry.h"

static NSError* PCEngineError(NSString* message) {
  return [NSError errorWithDomain:@"org.parc.independent-engine"
                             code:1
                         userInfo:@{NSLocalizedDescriptionKey : message}];
}
@interface PCBrowserEngineStartup ()
- (instancetype)initWithStatus:(PCBrowserEngineStartStatus)status
                      exitCode:(int)exitCode
                         error:(NSError* _Nullable)error;
@end
@implementation PCBrowserEngineStartup
- (instancetype)initWithStatus:(PCBrowserEngineStartStatus)status
                      exitCode:(int)exitCode
                         error:(NSError*)error {
  self = [super init];
  if (self) {
    _status = status;
    _exitCode = exitCode;
    _error = error;
  }
  return self;
}
@end
static PCBrowserEngineStartup* PCStartupFailure(int exitCode,
                                                NSString* message) {
  return [[PCBrowserEngineStartup alloc]
      initWithStatus:PCBrowserEngineStartStatusFailed
            exitCode:exitCode
               error:PCEngineError(message)];
}
static BOOL PCStartAttempted;
static BOOL PCStarted;
static BOOL PCTerminating;
static BOOL PCStopped;
static NSMutableArray<void (^)(BOOL)>* PCTerminationReplies;

static void PCFinishEngineTermination(void* unused) {
  NSCAssert(NSThread.isMainThread,
            @"Engine completion must be on the main thread");
  BOOL stopped = parc_engine_shutdown_if_idle() != 0;
  PCStopped = stopped;
  PCTerminating = NO;
  NSArray<void (^)(BOOL)>* replies = [PCTerminationReplies copy];
  [PCTerminationReplies removeAllObjects];
  for (void (^reply)(BOOL) in replies) {
    reply(stopped);
  }
}

@implementation PCBrowserEngine
+ (PCBrowserEngineStartup*)startWithFrameworkPath:(NSString*)frameworkPath
                                        cachePath:(NSString*)cachePath {
  NSCAssert(NSThread.isMainThread,
            @"Engine initialization must be on the main thread");
  if (PCStartAttempted) {
    return PCStartupFailure(EX_USAGE,
                            @"The engine may be initialized only once.");
  }
  PCStartAttempted = YES;
  NSString* bundlePath = NSBundle.mainBundle.bundlePath;
  NSString* helper = [bundlePath
      stringByAppendingPathComponent:
          @"Contents/Frameworks/Parc Helper.app/Contents/MacOS/Parc Helper"];
  if (!frameworkPath.isAbsolutePath || !cachePath.isAbsolutePath ||
      ![NSFileManager.defaultManager isExecutableFileAtPath:helper]) {
    return PCStartupFailure(EX_CONFIG, @"The packaged independent engine or "
                                       @"its sandbox helper is unavailable.");
  }
  NSMutableArray<NSString*>* arguments =
      [NSProcessInfo.processInfo.arguments mutableCopy];
  if (arguments.count &&
      ![PCNativeBrowserApplication
          respondsToSelector:NSSelectorFromString(@"restoresSessionCookies")] &&
      ![arguments containsObject:@"--restore-last-session"]) {
    [arguments insertObject:@"--restore-last-session" atIndex:1];
  }
  NSString* noProfiler = @"--disable-stack-profiler";
  if (arguments.count > 0 && ![arguments containsObject:noProfiler]) {
    [arguments insertObject:noProfiler atIndex:1];
  }
  char** argv = calloc(arguments.count + 1, sizeof(char*));
  if (!argv) {
    return PCStartupFailure(EX_OSERR, @"Unable to allocate engine arguments.");
  }
  BOOL allocated = YES;
  for (NSUInteger index = 0; index < arguments.count; ++index) {
    argv[index] = strdup(arguments[index].UTF8String);
    if (!argv[index]) {
      allocated = NO;
      break;
    }
  }
  int exitCode = EX_OSERR;
  parc_engine_start_result result = PARC_ENGINE_START_FAILED;
  if (allocated) {
    result = parc_engine_initialize((int)arguments.count, argv,
                                    cachePath.fileSystemRepresentation,
                                    frameworkPath.fileSystemRepresentation,
                                    bundlePath.fileSystemRepresentation,
                                    helper.fileSystemRepresentation, &exitCode);
  }
  for (NSUInteger index = 0; index < arguments.count; ++index) {
    free(argv[index]);
  }
  free(argv);
  if (!allocated) {
    return PCStartupFailure(exitCode, @"Unable to allocate engine arguments.");
  }
  if (result == PARC_ENGINE_START_EARLY_EXIT) {
    return [[PCBrowserEngineStartup alloc]
        initWithStatus:PCBrowserEngineStartStatusEarlyExit
              exitCode:exitCode
                 error:nil];
  }
  if (result != PARC_ENGINE_START_READY) {
    return PCStartupFailure(
        exitCode, [NSString stringWithFormat:@"The browser engine did not "
                                             @"initialize (exit %d).",
                                             exitCode]);
  }
  PCStarted = YES;
  PCTerminationReplies = [NSMutableArray array];
  return [[PCBrowserEngineStartup alloc]
      initWithStatus:PCBrowserEngineStartStatusReady
            exitCode:exitCode
               error:nil];
}
+ (int)run {
  NSCAssert(NSThread.isMainThread && PCStarted && !PCStopped,
            @"Engine run lifecycle is invalid");
  parc_engine_run_message_loop();
  return 0;
}
+ (void)requestTermination:(void (^)(BOOL))completion {
  NSCAssert(NSThread.isMainThread, @"Termination must be on the main thread");
  if (!PCStarted || PCStopped) {
    completion(YES);
    return;
  }
  [PCTerminationReplies addObject:[completion copy]];
  if (PCTerminating) {
    return;
  }
  PCTerminating = YES;
  dispatch_async(dispatch_get_main_queue(), ^{
    [PCNativeBrowserApplication requestCloseAllWindows:^(BOOL approved) {
      if (!approved) {
        PCTerminating = NO;
        NSArray<void (^)(BOOL)>* replies = [PCTerminationReplies copy];
        [PCTerminationReplies removeAllObjects];
        for (void (^reply)(BOOL) in replies) {
          reply(NO);
        }
        return;
      }
      if (!parc_engine_request_quit_when_idle(PCFinishEngineTermination,
                                              NULL)) {
        PCTerminating = NO;
        NSArray<void (^)(BOOL)>* replies = [PCTerminationReplies copy];
        [PCTerminationReplies removeAllObjects];
        for (void (^reply)(BOOL) in replies) {
          reply(NO);
        }
      }
    }];
  });
}
+ (void)shutdown {
  if (!PCStarted || PCStopped) {
    return;
  }
  PCStopped = parc_engine_shutdown_if_idle() != 0;
}
@end

@interface PCImportedExtensionFailure ()
- (instancetype)initWithName:(NSString*)name
                  identifier:(NSString*)identifier
                 profilePath:(NSString*)profilePath
                 restriction:(PCNativeExtensionRestriction)restriction;
@end
@implementation PCImportedExtensionFailure
- (instancetype)initWithName:(NSString*)name
                  identifier:(NSString*)identifier
                 profilePath:(NSString*)profilePath
                 restriction:(PCNativeExtensionRestriction)restriction {
  self = [super init];
  if (self) {
    _name = [name copy];
    _identifier = [identifier copy];
    _profilePath = [profilePath copy];
    _restriction = restriction;
  }
  return self;
}
@end

static NSString* PCReportedString(id object, SEL property) {
  if (![object respondsToSelector:property]) {
    return nil;
  }
  id value = [object valueForKey:NSStringFromSelector(property)];
  return [value isKindOfClass:[NSString class]] ? value : nil;
}
static PCImportedExtensionFailure* PCReportedFailure(id reported) {
  if ([reported isKindOfClass:[NSString class]]) {
    return [[PCImportedExtensionFailure alloc]
        initWithName:reported
          identifier:nil
         profilePath:nil
         restriction:PCNativeExtensionRestrictionNone];
  }
  PCNativeImportExtensionFailure* failure = reported;
  NSString* name = PCReportedString(failure, @selector(name));
  if (!name) {
    return nil;
  }
  NSString* identifier = PCReportedString(failure, @selector(identifier));
  NSString* profilePath = PCReportedString(failure, @selector(profilePath));
  PCNativeExtensionRestriction restriction =
      [failure respondsToSelector:@selector(restriction)]
          ? failure.restriction
          : PCNativeExtensionRestrictionNone;
  if (restriction < PCNativeExtensionRestrictionNone ||
      restriction > PCNativeExtensionRestrictionBlocklisted) {
    restriction = PCNativeExtensionRestrictionNone;
  }
  BOOL located = identifier && profilePath;
  return [[PCImportedExtensionFailure alloc]
      initWithName:name
        identifier:located ? identifier : nil
       profilePath:located ? profilePath : nil
       restriction:located ? restriction : PCNativeExtensionRestrictionNone];
}
static NSArray<PCImportedExtensionFailure*>* PCReportedFailures(id reported) {
  NSMutableArray<PCImportedExtensionFailure*>* failures = [NSMutableArray array];
  if (![reported isKindOfClass:[NSArray class]]) {
    return failures;
  }
  for (id item in (NSArray*)reported) {
    PCImportedExtensionFailure* failure = PCReportedFailure(item);
    if (failure) {
      [failures addObject:failure];
    }
  }
  return failures;
}
static NSArray<PCImportedExtensionFailure*>* PCResultFailures(
    PCNativeImportExtensionResult* result) {
  for (NSString* key in @[ @"failures", @"failedNames" ]) {
    if ([result respondsToSelector:NSSelectorFromString(key)]) {
      return PCReportedFailures([result valueForKey:key]);
    }
  }
  return @[];
}

@implementation PCImportedExtensions
+ (PCNativeImportSession*)install:(NSArray<PCNativeImportExtensionRequest*>*)requests
                       completion:(void (^)(PCNativeImportExtensionResult*,
                                            NSArray<PCImportedExtensionFailure*>*))completion
               backgroundFailures:(void (^)(NSArray<PCImportedExtensionFailure*>*))
                                      backgroundFailures {
  return [PCNativeBrowserApplication installImportedExtensions:requests
      completion:^(PCNativeImportExtensionResult* result) {
        completion(result, PCResultFailures(result));
      }
      backgroundFailures:^(NSArray* failures) {
        backgroundFailures(PCReportedFailures(failures));
      }];
}
+ (PCNativeExtensionRestriction)restrictionForError:(NSError*)error {
  if (![PCNativeBrowserApplication
          respondsToSelector:@selector(extensionRestrictionForError:)]) {
    return PCNativeExtensionRestrictionNone;
  }
  return [PCNativeBrowserApplication extensionRestrictionForError:error];
}
@end

@interface PCBrowserView () <PCNativePageObserver>
@end
@implementation PCBrowserView {
  NSString* _profilePath;
  PCNativePage* _nativePage;
  NSURL* _pendingURL;
  PCNativeSearchNavigation* _pendingSearch;
  NSObject* _pendingNavigationState;
  NSError* _creationError;
  BOOL _creating;
  BOOL _backgroundCreation;
  BOOL _embeddedMode;
  PCNativeEmbeddedPageRequest* _embeddedRequest;
  BOOL _disposed;
  NSMutableArray<void (^)(PCNativePageCloseResult)>* _pendingClose;
  PCBrowserView* _closeLease;
  NSString* _publishedTitle;
  NSURL* _publishedURL;
  BOOL _hasPublishedHistory;
  NSUInteger _publishedHistoryRevision;
  BOOL _hasPublishedLoading;
  BOOL _publishedLoading;
  BOOL _publishedBack;
  BOOL _publishedForward;
  BOOL _hasPublishedCapture;
  BOOL _publishedCapturePresent;
  BOOL _publishedCaptureCamera;
  BOOL _publishedCaptureMicrophone;
  BOOL _publishedCaptureTab;
  BOOL _publishedCaptureWindow;
  BOOL _publishedCaptureDisplay;
  BOOL _publishedCaptureMirrored;
  BOOL _publishedCaptureShared;
  BOOL _publishedCaptureCanStopDevices;
  BOOL _publishedCaptureCanStopSharing;
  BOOL _hasPublishedCrash;
  PCNativeRendererCrash* _publishedCrash;
  BOOL _hasPublishedPageColor;
  NSColor* _publishedTint;
  NSColor* _publishedPageBackground;
  BOOL _publishedTopBandSample;
  NSColor* _publishedTopBand;
  NSString* _publishedTopBandHost;
  BOOL _hasPublishedMedia;
  uint64_t _publishedMediaRevision;
}
- (instancetype)initWithFrame:(NSRect)frame profilePath:(NSString*)profilePath {
  self = [super initWithFrame:frame];
  if (self) {
    _profilePath = [profilePath copy];
    _pendingClose = [NSMutableArray array];
    self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  }
  return self;
}
- (instancetype)initWithFrame:(NSRect)frame
           adoptingNativePage:(PCNativePage*)page {
  self = [self initWithFrame:frame profilePath:page.profilePath];
  if (self) {
    [self adoptPage:page];
  }
  return self;
}
- (void)adoptPage:(PCNativePage*)page {
  NSCAssert(!_nativePage || _nativePage == page,
            @"A wrapper cannot replace a live page");
  NSCAssert(!page.observer || page.observer == self,
            @"A page has one live wrapper observer");
  _nativePage = page;
  _nativePage.observer = self;
  if (self.window) {
    PCNativeBrowserWindow* binding =
        [PCNativeBrowserApplication windowForNativeWindow:self.window];
    [binding pageDidAttach:page container:self];
  }
  [self nativePageDidChange:page];
}
- (void)setDelegate:(id<PCBrowserViewDelegate>)delegate {
  if (_delegate == delegate) {
    return;
  }
  _delegate = delegate;
  _publishedTitle = nil;
  _publishedURL = nil;
  _hasPublishedHistory = NO;
  _hasPublishedLoading = NO;
  _hasPublishedCapture = NO;
  _hasPublishedCrash = NO;
  _publishedCrash = nil;
  _hasPublishedPageColor = NO;
  _publishedTint = nil;
  _publishedPageBackground = nil;
  _publishedTopBandSample = NO;
  _publishedTopBand = nil;
  _publishedTopBandHost = nil;
  _hasPublishedMedia = NO;
  if (_disposed || !_nativePage || !delegate) {
    return;
  }
  [self nativePageDidChange:_nativePage];
}
- (BOOL)canShareThisTabInstead {
  return !_disposed && [_nativePage respondsToSelector:@selector(canShareThisTabInstead)] &&
      _nativePage.canShareThisTabInstead;
}
- (BOOL)shareThisTabInstead {
  return !_disposed && [_nativePage respondsToSelector:@selector(shareThisTabInstead)] &&
      [_nativePage shareThisTabInstead];
}
- (BOOL)hasPageInfo {
  NSString* scheme = self.URL.scheme.lowercaseString;
  return !_disposed && ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) &&
      _nativePage.developerModeHost != nil;
}
- (BOOL)canShowSiteInfo { return !_disposed && self.hasPageInfo && _nativePage.canShowSiteInfo; }
- (BOOL)showSiteInfoFromView:(NSView*)anchor {
  return self.canShowSiteInfo && [_nativePage showSiteInfoFromView:anchor];
}
- (PCNativeCaptureState*)captureState {
  return _disposed ? nil : _nativePage.captureState;
}
- (BOOL)stopCapture:(PCNativeCaptureState*)state sharing:(BOOL)sharing {
  return !_disposed && [_nativePage stopCapture:state sharing:sharing];
}
- (PCNativePage*)nativePage {
  return _nativePage;
}
- (PCNativeRendererCrash*)rendererCrash {
  return _disposed ? nil : _nativePage.rendererCrash;
}
- (BOOL)rendererCrashDidPresent:(PCNativeRendererCrash*)crash {
  return !_disposed && !_nativePage.isClosed &&
         [_nativePage rendererCrashDidPresent:crash];
}
- (BOOL)performRendererCrashAction:(PCNativeRendererCrash*)crash {
  return !_disposed && !_nativePage.isClosed &&
         [_nativePage performRendererCrashAction:crash];
}
- (NSURL*)URL {
  return _nativePage ? _nativePage.URL : _pendingURL;
}
- (NSString*)title {
  return _nativePage.title ?: @"";
}
- (BOOL)isLoading {
  return _creating || _nativePage.loading;
}
- (BOOL)canGoBack {
  return _nativePage.canGoBack;
}
- (BOOL)canGoForward {
  return _nativePage.canGoForward;
}
- (PCArchiveProtectionState)automaticArchiveProtectionState {
  if (!_nativePage || _creating || _disposed) {
    return PCArchiveProtectionStateUnknown;
  }
  switch (_nativePage.archiveProtectionState) {
    case PCNativeArchiveProtectionStateEligible:
      return PCArchiveProtectionStateEligible;
    case PCNativeArchiveProtectionStateProtected:
      return PCArchiveProtectionStateProtected;
    case PCNativeArchiveProtectionStateUnknown:
      return PCArchiveProtectionStateUnknown;
  }
}
- (NSError*)automaticArchiveProtectionError {
  return self.automaticArchiveProtectionState == PCArchiveProtectionStateUnknown
             ? PCEngineError(
                   @"Native page protection state is not available yet.")
             : nil;
}
- (void)viewWillMoveToWindow:(NSWindow*)newWindow {
  if (_nativePage && self.window && self.window != newWindow) {
    [[PCNativeBrowserApplication windowForNativeWindow:self.window]
        pageWillDetach:_nativePage];
  }
  [super viewWillMoveToWindow:newWindow];
}
- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  if (!self.window || _disposed) {
    return;
  }
  if (_nativePage) {
    [[PCNativeBrowserApplication windowForNativeWindow:self.window]
        pageDidAttach:_nativePage
            container:self];
  } else {
    [self ensurePage];
  }
}
- (void)ensurePage {
  NSCAssert(NSThread.isMainThread, @"Page creation must be on the main thread");
  if (_disposed || _embeddedMode || _nativePage || _creating || !self.window || !_pendingURL) {
    return;
  }
  PCNativeBrowserWindow* binding =
      [PCNativeBrowserApplication windowForNativeWindow:self.window];
  if (!binding) {
    [self fail:PCEngineError(@"This native window must be registered before "
                             @"opening pages.")];
    return;
  }
  _creating = YES;
  NSURL* requestedURL = _pendingURL;
  PCNativeSearchNavigation* requestedSearch = _pendingSearch;
  NSObject* restoring = requestedSearch ? nil : _pendingNavigationState;
  _pendingNavigationState = nil;
  __weak PCBrowserView* weak = self;
  void (^completed)(PCNativePage*, NSError*) = ^(PCNativePage* page, NSError* error) {
          PCBrowserView* view = weak;
          if (!view) {
            if (page) {
              [page requestClose:^(PCNativePageCloseResult result){
              }];
            }
            return;
          }
          view->_creating = NO;
          if (error || !page) {
            [view fail:error
                           ?: PCEngineError(
                                  @"The native page could not be created.")];
            [view finishPendingClose:PCNativePageCloseResultClosed];
            return;
          }
          [view adoptPage:page];
          if (view->_pendingSearch && view->_pendingSearch != requestedSearch) {
            if (![page loadSearchNavigation:view->_pendingSearch]) {
              [view fail:PCEngineError(@"The search result is no longer current. Try the search again.")];
            }
          } else if (!view->_pendingSearch && view->_pendingURL &&
                     (requestedSearch || ![view->_pendingURL isEqual:requestedURL])) {
            [page loadURL:view->_pendingURL];
          }
          if (view->_pendingClose.count) {
            [view requestPageClose];
          }
        };
  if (restoring) {
    [binding openNavigationState:restoring profilePath:_profilePath container:self
                      background:_backgroundCreation
                      completion:^(PCNativePage* page, NSError* error) {
      PCBrowserView* view = weak;
      if (!page && view && !view->_disposed && !view->_pendingClose.count && error.code == 1 &&
          [error.domain isEqualToString:@"org.parc.independent-engine"]) {
        view->_creating = NO;
        [view ensurePage];
        return;
      }
      completed(page, error);
    }];
  } else if (requestedSearch) {
    [binding openSearchNavigation:requestedSearch container:self completion:completed];
  } else if (_backgroundCreation) {
    [binding openBackgroundURL:requestedURL profilePath:_profilePath container:self completion:completed];
  } else {
    [binding openURL:requestedURL profilePath:_profilePath container:self completion:completed];
  }
}
- (PCNativeEmbeddedPageRequest*)beginEmbeddedNavigation:(NSURL*)URL
    referrer:(NSURL*)referrer
    validateOwner:(BOOL (^)(void))validateOwner
    completion:(void (^)(PCNativePage*, NSError*))completion {
  NSCAssert(NSThread.isMainThread, @"Embedded creation must be on main");
  if (_disposed || _nativePage || _creating || !self.window || !URL || !validateOwner || !completion) return nil;
  PCNativeBrowserWindow* binding = [PCNativeBrowserApplication windowForNativeWindow:self.window];
  if (!binding) return nil;
  _embeddedMode = YES;
  _creating = YES;
  _pendingURL = URL;
  _creationError = nil;
  __weak PCBrowserView* weak = self;
  _embeddedRequest = [binding createEmbeddedPageWithURL:URL referrer:referrer profilePath:_profilePath container:self
      validateOwner:^BOOL {
        PCBrowserView* view = weak;
        return view && !view->_disposed && view->_creating &&
            view->_pendingClose.count == 0 && validateOwner();
      } completion:^(PCNativePage* page, NSError* error) {
        PCBrowserView* view = weak;
        if (!view) {
          if (page) [page requestClose:^(PCNativePageCloseResult result) {}];
          completion(nil, error ?: PCEngineError(@"The embedded page owner closed."));
          return;
        }
        view->_embeddedRequest = nil;
        view->_creating = NO;
        view->_pendingURL = nil;
        if (page) [view adoptPage:page];
        else if (error.code != NSUserCancelledError || ![error.domain isEqual:NSCocoaErrorDomain]) [view fail:error];
        completion(page, error);
        if (view->_pendingClose.count) {
          if (page) [view requestPageClose];
          else [view finishPendingClose:PCNativePageCloseResultClosed];
        }
      }];
  return _embeddedRequest;
}
- (BOOL)loadBackgroundURL:(NSURL*)URL {
  if (_disposed || _nativePage || _creating || !self.window || !URL) return NO;
  _backgroundCreation = YES;
  [self loadURL:URL];
  return YES;
}
- (BOOL)loadBackgroundSearchNavigation:(PCNativeSearchNavigation*)navigation
    sourcePage:(PCNativePage*)sourcePage validateOwner:(BOOL (^)(void))validateOwner
    completion:(void (^)(BOOL, NSError*))completion {
  NSCAssert(NSThread.isMainThread, @"Page creation must be on main");
  if (_disposed || _nativePage || _creating || !self.window || !navigation ||
      ![navigation.profilePath isEqualToString:_profilePath] || !validateOwner || !completion) return NO;
  PCNativeBrowserWindow* binding = [PCNativeBrowserApplication windowForNativeWindow:self.window];
  if (!binding || !validateOwner()) return NO;
  _creating = YES;
  _pendingSearch = navigation;
  _pendingURL = navigation.URL;
  __weak PCBrowserView* weak = self;
  [binding openBackgroundSearchNavigation:navigation sourcePage:sourcePage container:self validateOwner:^BOOL {
    PCBrowserView* view = weak;
    return view && !view->_disposed && view->_creating && !view->_pendingClose.count && validateOwner();
  } completion:^(PCNativePage* page, NSError* error) {
    PCBrowserView* view = weak;
    if (!view) { if (page) [page requestClose:^(PCNativePageCloseResult result) {}]; completion(NO, error); return; }
    view->_creating = NO;
    if (page) { [view adoptPage:page]; view->_creationError = nil; }
    else [view fail:error ?: PCEngineError(@"The background page could not open.")];
    completion(page != nil, error);
    if (view->_pendingClose.count) {
      if (page) [view requestPageClose]; else [view finishPendingClose:PCNativePageCloseResultClosed];
    }
  }];
  return YES;
}
- (void)loadSearchNavigation:(PCNativeSearchNavigation*)navigation {
  if (_disposed || ![navigation.profilePath isEqualToString:_profilePath]) return;
  _pendingSearch = navigation;
  _pendingURL = navigation.URL;
  _creationError = nil;
  if (_nativePage) {
    if (![_nativePage loadSearchNavigation:navigation])
      [self fail:PCEngineError(@"The search result is no longer current. Try the search again.")];
  } else {
    [self ensurePage];
  }
}
- (BOOL)restoreNavigationState:(NSObject*)state URL:(NSURL*)URL {
  if (_disposed || _embeddedMode || _nativePage || _creating || !state || !URL ||
      ![PCNativeBrowserWindow instancesRespondToSelector:@selector(
          openNavigationState:profilePath:container:background:completion:)]) {
    return NO;
  }
  _pendingSearch = nil;
  _pendingURL = [URL copy];
  _pendingNavigationState = state;
  _creationError = nil;
  [self ensurePage];
  return YES;
}
- (void)loadURL:(NSURL*)URL {
  _pendingSearch = nil;
  _pendingNavigationState = nil;
  _pendingURL = [URL copy];
  _creationError = nil;
  if (_nativePage) {
    [_nativePage loadURL:URL];
  } else {
    [self ensurePage];
  }
}
- (void)goBack {
  [_nativePage goBack];
}
- (void)goForward {
  [_nativePage goForward];
}
- (void)reload {
  if (_nativePage) {
    [_nativePage reload];
  } else {
    _creationError = nil;
    [self ensurePage];
  }
}
- (void)stop {
  [_nativePage stop];
}
- (void)setZoomLevel:(double)level {
  [_nativePage setZoomLevel:level];
}
- (BOOL)zoomPage:(NSInteger)direction {
  if (![PCNativePage instancesRespondToSelector:@selector(zoomPage:)]) return NO;
  if (!_disposed) [_nativePage zoomPage:direction];
  return YES;
}
- (double)pageZoomLevel {
  return !_disposed && [_nativePage respondsToSelector:@selector(pageZoomLevel)] ? _nativePage.pageZoomLevel : 0;
}
- (void)showDevTools {
  [_nativePage showDeveloperTools];
}
- (BOOL)canPerformPageTool:(PCNativePageTool)tool {
  return [_nativePage canPerformPageTool:tool];
}
- (BOOL)performPageTool:(PCNativePageTool)tool {
  return [_nativePage performPageTool:tool];
}
- (PCNativeReaderMode)readerMode {
  return _nativePage.readerMode;
}
- (NSUInteger)readerRevision {
  return _nativePage.readerRevision;
}
- (NSString*)readerMessage {
  return _nativePage.readerMessage ?: @"";
}
- (BOOL)canToggleReaderMode {
  return [_nativePage canToggleReaderMode];
}
- (BOOL)toggleReaderMode {
  return [_nativePage toggleReaderMode];
}
- (void)findText:(NSString*)text forward:(BOOL)forward findNext:(BOOL)findNext {
  [_nativePage findText:text forward:forward findNext:findNext];
}
- (void)stopFinding {
  [_nativePage stopFinding];
}
- (void)requestClose:(void (^)(PCNativePageCloseResult))completion {
  NSCAssert(NSThread.isMainThread, @"Close must be on the main thread");
  [_pendingClose addObject:[completion copy]];
  _closeLease = self;
  if (_creating) {
    [_embeddedRequest cancel];
    return;
  }
  if (!_nativePage || _nativePage.isClosed) {
    [self finishPendingClose:PCNativePageCloseResultClosed];
  } else if (_pendingClose.count == 1) {
    [self requestPageClose];
  }
}
- (void)requestPageClose {
  __weak PCBrowserView* weak = self;
  [_nativePage requestClose:^(PCNativePageCloseResult result) {
    [weak finishPendingClose:result];
  }];
}
- (void)finishPendingClose:(PCNativePageCloseResult)result {
  PCBrowserView* __attribute__((objc_precise_lifetime)) keep = self;
  NSArray<void (^)(PCNativePageCloseResult)>* callbacks = [_pendingClose copy];
  [_pendingClose removeAllObjects];
  _closeLease = nil;
  for (void (^callback)(PCNativePageCloseResult) in callbacks) {
    callback(result);
  }
}
- (void)closeBrowser {
  if (_disposed) {
    return;
  }
  if (_creating || (_nativePage && !_nativePage.isClosed)) {
    __weak PCBrowserView* weak = self;
    [self requestClose:^(PCNativePageCloseResult result) {
      if (result == PCNativePageCloseResultClosed) {
        [weak closeBrowser];
      }
    }];
    return;
  }
  _disposed = YES;
  if (_nativePage.observer == self) {
    _nativePage.observer = nil;
  }
  [_nativePage.nativeView removeFromSuperview];
  _nativePage = nil;
}
- (void)nativePage:(PCNativePage*)page addContextImageToEasel:(PCNativeContextImage*)image {
  if (_disposed || page != _nativePage || !image.valid) return;
  id<PCBrowserViewDelegate> target = self.delegate;
  if ([target respondsToSelector:@selector(browserView:addContextImageToEasel:)]) {
    [target browserView:self addContextImageToEasel:image];
  }
}
- (BOOL)nativePageCanOpenLinkInSplitView:(PCNativePage*)page {
  if (_disposed || page != _nativePage || page.observer != self || page.closed) return NO;
  id<PCBrowserViewDelegate> target = self.delegate;
  return [target respondsToSelector:@selector(browserViewCanOpenLinkInSplitView:)] &&
      [target browserViewCanOpenLinkInSplitView:self];
}
- (void)nativePage:(PCNativePage*)page openLinkInSplitView:(NSURL*)url {
  if (_disposed || page != _nativePage || page.observer != self || page.closed) return;
  id<PCBrowserViewDelegate> target = self.delegate;
  if ([target respondsToSelector:@selector(browserView:openLinkInSplitView:)]) {
    [target browserView:self openLinkInSplitView:url];
  }
}
- (void)nativePage:(PCNativePage*)page didLearnSafariIdentityForSite:(NSString*)site {
  if (page != _nativePage || page.observer != self || site.length == 0) return;
  id<PCBrowserViewDelegate> target = self.delegate;
  if ([target respondsToSelector:@selector(browserView:didLearnSafariIdentityForSite:profilePath:offTheRecord:)]) {
    [target browserView:self
        didLearnSafariIdentityForSite:site
                          profilePath:page.profilePath
                         offTheRecord:page.fairPlayIdentityOffTheRecord];
  }
}
- (void)nativePageFaviconDidChange:(PCNativePage*)page {
  if (page != _nativePage || _disposed || page.observer != self) return;
  id<PCBrowserViewDelegate> target = self.delegate;
  if ([target respondsToSelector:@selector(browserViewDidChangeFavicon:)]) {
    [target browserViewDidChangeFavicon:self];
  }
}
- (void)nativePageDidPresentFrame:(PCNativePage*)page {
  if (page != _nativePage || _disposed || page.observer != self) return;
  id<PCBrowserViewDelegate> target = self.delegate;
  if ([target respondsToSelector:@selector(browserViewDidPresentFrame:)]) {
    [target browserViewDidPresentFrame:self];
  }
}
- (void)nativePageDidChange:(PCNativePage*)page {
  if (page != _nativePage || _disposed) {
    return;
  }
  id<PCBrowserViewDelegate> target = self.delegate;
  PCNativeCaptureState* capture = page.captureState;
  const BOOL capturePresent = capture != nil;
  const BOOL captureChanged =
      !_hasPublishedCapture || capturePresent != _publishedCapturePresent ||
      (capturePresent &&
       (capture.camera != _publishedCaptureCamera ||
        capture.microphone != _publishedCaptureMicrophone ||
        capture.tab != _publishedCaptureTab ||
        capture.window != _publishedCaptureWindow ||
        capture.display != _publishedCaptureDisplay ||
        capture.mirrored != _publishedCaptureMirrored ||
        capture.shared != _publishedCaptureShared ||
        capture.canStopDevices != _publishedCaptureCanStopDevices ||
        capture.canStopSharing != _publishedCaptureCanStopSharing));
  if (captureChanged &&
      [target respondsToSelector:@selector(browserView:didChangeCaptureState:)]) {
    [target browserView:self didChangeCaptureState:capture];
    if (_disposed || _nativePage != page || self.delegate != target ||
        page.observer != self) {
      return;
    }
    _hasPublishedCapture = YES;
    _publishedCapturePresent = capturePresent;
    _publishedCaptureCamera = capturePresent ? capture.camera : NO;
    _publishedCaptureMicrophone = capturePresent ? capture.microphone : NO;
    _publishedCaptureTab = capturePresent ? capture.tab : NO;
    _publishedCaptureWindow = capturePresent ? capture.window : NO;
    _publishedCaptureDisplay = capturePresent ? capture.display : NO;
    _publishedCaptureMirrored = capturePresent ? capture.mirrored : NO;
    _publishedCaptureShared = capturePresent ? capture.shared : NO;
    _publishedCaptureCanStopDevices =
        capturePresent ? capture.canStopDevices : NO;
    _publishedCaptureCanStopSharing =
        capturePresent ? capture.canStopSharing : NO;
  }
  if (_disposed || _nativePage != page || self.delegate != target ||
      page.observer != self) {
    return;
  }
  PCNativeRendererCrash* crash = page.rendererCrash;
  if ((!_hasPublishedCrash || _publishedCrash != crash) &&
      [target respondsToSelector:@selector(browserView:
                                     didChangeRendererCrash:)]) {
    [target browserView:self didChangeRendererCrash:crash];
    if (_disposed || _nativePage != page || self.delegate != target ||
        page.observer != self) {
      return;
    }
    _hasPublishedCrash = YES;
    _publishedCrash = crash;
  }
  if (_disposed || _nativePage != page || self.delegate != target ||
      page.observer != self) {
    return;
  }
  NSString* title = page.title ?: @"";
  if (![_publishedTitle isEqualToString:title] &&
      [target respondsToSelector:@selector(browserView:didChangeTitle:)]) {
    [target browserView:self didChangeTitle:title];
    if (_disposed || _nativePage != page || self.delegate != target ||
        page.observer != self) {
      return;
    }
    _publishedTitle = [title copy];
  }
  if (_disposed || _nativePage != page || self.delegate != target ||
      page.observer != self) {
    return;
  }
  NSURL* url = page.URL;
  if (url && ![_publishedURL isEqual:url] &&
      [target respondsToSelector:@selector(browserView:didChangeURL:)]) {
    [target browserView:self didChangeURL:url];
    if (_disposed || _nativePage != page || self.delegate != target ||
        page.observer != self) {
      return;
    }
    _publishedURL = [url copy];
  }
  if ([page respondsToSelector:@selector(historyRevision)]) {
    const NSUInteger revision = page.historyRevision;
    if ((!_hasPublishedHistory || revision != _publishedHistoryRevision) &&
        [target respondsToSelector:@selector(browserViewDidChangeHistory:)]) {
      [target browserViewDidChangeHistory:self];
      if (_disposed || _nativePage != page || self.delegate != target ||
          page.observer != self) {
        return;
      }
      _hasPublishedHistory = YES;
      _publishedHistoryRevision = revision;
    }
  }
  if (_disposed || _nativePage != page || self.delegate != target ||
      page.observer != self) {
    return;
  }
  const BOOL loading = page.loading;
  const BOOL back = page.canGoBack;
  const BOOL forward = page.canGoForward;
  if ((!_hasPublishedLoading || loading != _publishedLoading ||
       back != _publishedBack || forward != _publishedForward) &&
      [target respondsToSelector:@selector
              (browserView:didChangeLoading:canGoBack:canGoForward:)]) {
    [target browserView:self
        didChangeLoading:loading
               canGoBack:back
            canGoForward:forward];
    if (_disposed || _nativePage != page || self.delegate != target ||
        page.observer != self) {
      return;
    }
    _hasPublishedLoading = YES;
    _publishedLoading = loading;
    _publishedBack = back;
    _publishedForward = forward;
  }
  if (_disposed || _nativePage != page || self.delegate != target ||
      page.observer != self) {
    return;
  }
  NSColor* tint = page.developerModeTint;
  NSColor* background =
      [page respondsToSelector:@selector(pageBackgroundColor)]
          ? page.pageBackgroundColor
          : nil;
  const BOOL tintChanged =
      _publishedTint != tint && ![_publishedTint isEqual:tint];
  const BOOL backgroundChanged =
      _publishedPageBackground != background &&
      ![_publishedPageBackground isEqual:background];
  const BOOL reportsTopBand =
      [page respondsToSelector:@selector(hasTopBandColorSample)];
  const BOOL topBandSample = reportsTopBand && page.hasTopBandColorSample;
  NSColor* topBand = topBandSample ? page.topBandColor : nil;
  NSString* topBandHost = topBandSample ? page.topBandColorHost : nil;
  const BOOL topBandChanged =
      _publishedTopBandSample != topBandSample ||
      (_publishedTopBand != topBand && ![_publishedTopBand isEqual:topBand]) ||
      (_publishedTopBandHost != topBandHost &&
       ![_publishedTopBandHost isEqual:topBandHost]);
  if ((!_hasPublishedPageColor || tintChanged || backgroundChanged ||
       topBandChanged) &&
      [target respondsToSelector:@selector(browserViewDidChangePageColor:)]) {
    [target browserViewDidChangePageColor:self];
    if (_disposed || _nativePage != page || self.delegate != target ||
        page.observer != self) {
      return;
    }
    _hasPublishedPageColor = YES;
    _publishedTint = tint;
    _publishedPageBackground = background;
    _publishedTopBandSample = topBandSample;
    _publishedTopBand = topBand;
    _publishedTopBandHost = topBandHost;
  }
  if (_disposed || _nativePage != page || self.delegate != target ||
      page.observer != self) {
    return;
  }
  const BOOL reportsMedia =
      [page respondsToSelector:@selector(mediaControlsRevision)];
  const uint64_t media = reportsMedia ? page.mediaControlsRevision : 0;
  if (reportsMedia && (!_hasPublishedMedia || media != _publishedMediaRevision) &&
      [target respondsToSelector:@selector(browserViewDidChangeMedia:)]) {
    [target browserViewDidChangeMedia:self];
    if (_disposed || _nativePage != page || self.delegate != target ||
        page.observer != self) {
      return;
    }
    _hasPublishedMedia = YES;
    _publishedMediaRevision = media;
  }
}
- (void)nativePage:(PCNativePage*)page
    requestFocusForRendererCrash:(PCNativeRendererCrash*)crash {
  if (_disposed || page != _nativePage || page.rendererCrash != crash) {
    return;
  }
  id<PCBrowserViewDelegate> target = self.delegate;
  if ([target respondsToSelector:@selector(browserView:
                                     requestFocusForRendererCrash:)]) {
    [target browserView:self requestFocusForRendererCrash:crash];
  }
}
- (void)nativePageDidClose:(PCNativePage*)page {
  if (page != _nativePage) {
    return;
  }
  id<PCBrowserViewDelegate> target = self.delegate;
  if ([target respondsToSelector:@selector(browserViewDidRequestClose:)]) {
    [target browserViewDidRequestClose:self];
  }
}
- (void)fail:(NSError*)error {
  _creationError = error;
  id<PCBrowserViewDelegate> target = self.delegate;
  if ([target respondsToSelector:@selector(browserView:didFailWithError:)]) {
    [target browserView:self didFailWithError:error];
  }
}
- (void)nativePage:(PCNativePage*)page didFailWithError:(NSError*)error {
  if (page == _nativePage) {
    [self fail:error];
  }
}

- (void)captureRenderingMetricsWithCompletion:
    (void (^)(NSDictionary<NSString*, id>* _Nullable,
              NSError* _Nullable))completion {
  completion(nil,
             PCEngineError(
                 @"Independent renderer diagnostics are not connected yet."));
}
@end
