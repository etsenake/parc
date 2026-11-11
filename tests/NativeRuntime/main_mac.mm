#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include <sys/stat.h>
#include <unistd.h>

#include <cstdio>
#include <cstring>

#import "VideoPiPWindow.h"
#import "native_appkit_bridge.h"
#import "native_engine_entry.h"
#import "native_application_protocols.h"
#import "runtime_driver.h"

namespace {
struct API {
  decltype(&parc_engine_initialize) initialize;
  decltype(&parc_engine_run_message_loop) run;
  decltype(&parc_engine_request_quit_when_idle) quit;
  decltype(&parc_engine_shutdown_if_idle) shutdown;
  decltype(&parc_test_http_auth) auth;
  decltype(&parc_test_cancel_http_auth) cancel;
  decltype(&parc_test_extension_actions) extensions;
  decltype(&parc_test_cancel_extension_actions) cancel_extensions;
  decltype(&parc_test_video_pip) pip;
  decltype(&parc_test_cancel_video_pip) cancel_pip;
};
API api{};
int result = 1;
bool shutdown_complete = false;
}
@class PCRuntimeController;
@interface PCRuntimeApplication : NSApplication <CrAppControlProtocol>
@property(nonatomic, assign) BOOL handlingSendEvent;
@property(nonatomic, weak) PCRuntimeController* runtime;
@end
@interface PCRuntimeController : NSObject <NSApplicationDelegate,
                                           NSWindowDelegate,
                                           PCNativeBrowserApplicationClient,
                                           PCNativeBrowserWindowClient,
                                           PCNativePageObserver>
- (instancetype)initWithRoot:(NSString*)root
           extensionDocument:(NSString*)document
               videoDocument:(NSString*)video;
- (void)begin;
- (void)fail:(NSString*)reason;
@end
@implementation PCRuntimeApplication
@synthesize handlingSendEvent = _handlingSendEvent;
@synthesize runtime = _runtime;
- (BOOL)isHandlingSendEvent {
  return self.handlingSendEvent;
}
- (NSAccessibilityRole)accessibilityRole {
  [NSClassFromString(@"PCNativeBrowserApplication") accessibilityRoleRequested];
  return [super accessibilityRole];
}
- (void)accessibilitySetValue:(id)value forAttribute:(NSString*)attribute {
  [NSClassFromString(@"PCNativeBrowserApplication")
      accessibilitySetValue:value
               forAttribute:attribute];
  [super accessibilitySetValue:value forAttribute:attribute];
}
- (void)observeValueForKeyPath:(NSString*)keyPath
                      ofObject:(id)object
                        change:(NSDictionary*)change
                       context:(void*)context {
  if (![NSClassFromString(@"PCNativeBrowserApplication")
          accessibilityHandleObservationForKeyPath:keyPath
                                          ofObject:object
                                            change:change
                                           context:context]) {
    [super observeValueForKeyPath:keyPath
                         ofObject:object
                           change:change
                          context:context];
  }
}
- (void)sendEvent:(NSEvent*)event {
  const BOOL previous = self.handlingSendEvent;
  self.handlingSendEvent = YES;
  @try {
    [super sendEvent:event];
  } @finally {
    self.handlingSendEvent = previous;
  }
}
- (void)terminate:(id)sender {
  [self.runtime fail:@"App termination interrupted the test."];
}
@end
@implementation PCRuntimeController {
  NSString* _root;
  NSWindow* _window;
  NSView* _container;
  NSView* _sidePanel;
  PCNativeBrowserWindow* _binding;
  PCNativePage* _page;
  PCNativePage* _otherPage;
  PCNativePage* _selectedPage;
  NSView* _otherContainer;
  NSString* _extensionDocument;
  NSString* _videoDocument;
  PCVideoPiPPresenter* _videoPresenter;
  NSTimer* _deadline;
  NSInteger _case;
  BOOL _running;
  BOOL _closing;
  BOOL _failed;
}
- (instancetype)initWithRoot:(NSString*)root
           extensionDocument:(NSString*)document
               videoDocument:(NSString*)video {
  if ((self = [super init])) {
    _root = [root copy];
    _extensionDocument = [document copy];
    _videoDocument = [video copy];
  }
  return self;
}
- (void)begin {
  _deadline = [NSTimer
      scheduledTimerWithTimeInterval:80
                             repeats:NO
                               block:^(NSTimer* timer) {
                                 [self fail:@"Overall test deadline expired."];
                               }];
  _window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(100, 100, 850, 620)
                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                          NSWindowStyleMaskResizable |
                          NSWindowStyleMaskMiniaturizable
                  backing:NSBackingStoreBuffered
                    defer:NO];
  _window.releasedWhenClosed = NO;
  _window.title = @"Parc native controller regression";
  _window.delegate = self;
  _container = [[NSView alloc] initWithFrame:_window.contentView.bounds];
  _container.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [_window.contentView addSubview:_container];
  if (_extensionDocument) {
    _otherContainer = [[NSView alloc] initWithFrame:_container.frame];
    _otherContainer.autoresizingMask = _container.autoresizingMask;
    _otherContainer.hidden = YES;
    [_window.contentView addSubview:_otherContainer];
  }
  _sidePanel = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 320, 620)];
  _sidePanel.hidden = YES;
  [_window.contentView addSubview:_sidePanel];
  Class application = NSClassFromString(@"PCNativeBrowserApplication");
  [application setApplicationClient:self];
  NSError* error = nil;
  _binding = [application registerWindowClient:self error:&error];
  if (!_binding) {
    [self fail:error.localizedDescription ?: @"Registration failed."];
    return;
  }
  [_window makeKeyAndOrderFront:nil];
  [NSApp activateIgnoringOtherApps:YES];
  NSString* initial =
      _videoDocument
          ?: (_extensionDocument
                  ? [_extensionDocument stringByAppendingString:@"?tab=first"]
                  : PCRuntimeDocumentURLString());
  [_binding openURL:[NSURL URLWithString:initial]
        profilePath:[_root stringByAppendingPathComponent:@"runtime-profile"]
          container:_container
         completion:^(PCNativePage* page, NSError* failure) {
           if (self->_closing) {
             return;
           }
           if (!page || failure) {
             [self fail:failure.localizedDescription ?: @"No real page."];
             return;
           }
           self->_page = page;
           self->_selectedPage = page;
           page.observer = self;
           [self->_binding synchronizeSelectionAndLayout];
           if (self->_extensionDocument) {
             [self openSecondExtensionPage];
           } else {
             [self maybeStart];
           }
         }];
}
- (void)openSecondExtensionPage {
  [_binding
          openURL:[NSURL
                      URLWithString:[_extensionDocument
                                        stringByAppendingString:@"?tab=second"]]
      profilePath:[_root stringByAppendingPathComponent:@"runtime-profile"]
        container:_otherContainer
       completion:^(PCNativePage* page, NSError* error) {
         if (self->_closing) {
           return;
         }
         if (!page || error || page == self->_page) {
           [self fail:error.localizedDescription
                          ?: @"Second actual tab creation failed."];
           return;
         }
         self->_otherPage = page;
         page.observer = self;
         [self->_binding synchronizeSelectionAndLayout];
         [self maybeStart];
       }];
}
- (void)maybeStart {
  if (_videoDocument) {
    if (_closing || _running || !_page) {
      return;
    }
    _running = YES;
    __weak PCRuntimeController* weakSelf = self;
    api.pip(
        _page, _binding, _videoDocument,
        ^id<PCNativeVideoPiPWindow> {
          PCRuntimeController* self = weakSelf;
          return self ? self->_videoPresenter : nil;
        },
        ^(BOOL passed, NSString* detail) {
          PCRuntimeController* self = weakSelf;
          if (!self || self->_closing) {
            return;
          }
          if (!passed) {
            [self fail:detail];
            return;
          }
          self->_case = 7;
          dispatch_async(dispatch_get_main_queue(), ^{
            [self close];
          });
        });
    return;
  }
  if (_extensionDocument) {
    if (_closing || _running || !_page || !_otherPage) {
      return;
    }
    _running = YES;
    api.extensions(
        _page, _otherPage, _binding, _extensionDocument,
        ^BOOL(PCNativePage* selected) {
          if (self->_closing ||
              (selected != self->_page && selected != self->_otherPage) ||
              selected.closed) {
            return NO;
          }
          self->_selectedPage = selected;
          self->_container.hidden = selected != self->_page;
          self->_otherContainer.hidden = selected != self->_otherPage;
          [self->_binding synchronizeSelectionAndLayout];
          return !self->_closing && self->_selectedPage == selected;
        },
        ^(BOOL passed, NSString* detail) {
          if (self->_closing) {
            return;
          }
          if (!passed) {
            [self fail:detail];
            return;
          }
          self->_case = 1;
          [self close];
        });
    return;
  }
  if (_closing || _running || !_page || _page.loading ||
      ![_page.URL.absoluteString
          isEqualToString:PCRuntimeDocumentURLString()]) {
    return;
  }
  _running = YES;
  [self nextCase];
}
- (void)nextCase {
  if (_closing) {
    return;
  }
  if (_case == 3) {
    [self close];
    return;
  }
  const NSInteger current = _case;
  api.auth(_page, _binding, _container,
           static_cast<PCRuntimeHTTPAuthCase>(current),
           ^(BOOL passed, NSString* detail) {
             if (self->_closing) {
               return;
             }
             std::fprintf(stdout, "HTTP_AUTH_CONTROLLER_%ld %s: %s\n",
                          static_cast<long>(current), passed ? "PASS" : "FAIL",
                          detail.UTF8String);
             std::fflush(stdout);
             if (!passed) {
               [self fail:detail];
               return;
             }
             self->_case++;
             dispatch_async(dispatch_get_main_queue(), ^{
               [self nextCase];
             });
           });
}
- (void)fail:(NSString*)reason {
  _failed = YES;
  result = 1;
  std::fprintf(stderr, "FAIL: %s\n", reason.UTF8String);
  [self close];
}
- (void)failWithError:(NSError*)error
                 page:(PCNativePage*)page
               source:(NSString*)source {
  std::fprintf(stderr,
               "NATIVE_RUNTIME_ERROR source=%s domain=%s code=%ld closing=%d "
               "completed_cases=%ld page=%s expected_page=%s page_closed=%d\n",
               source.UTF8String, error.domain.UTF8String,
               static_cast<long>(error.code), static_cast<int>(_closing),
               static_cast<long>(_case),
               (page.identifier ?: @"<none>").UTF8String,
               (_page.identifier ?: @"<none>").UTF8String,
               static_cast<int>(page.isClosed));
  std::fflush(stderr);
  [self fail:error.localizedDescription];
}
- (void)close {
  if (_closing) {
    return;
  }
  _closing = YES;
  [_deadline invalidate];
  _deadline = nil;
  api.cancel();
  api.cancel_extensions();
  api.cancel_pip();
  [NSClassFromString(@"PCNativeBrowserApplication") requestCloseAllWindows:^(
                                                        BOOL allow) {
    if (!allow) {
      self->_failed = YES;
      std::fprintf(stderr, "FAIL: Actual Browser close refused; launcher "
                           "deadline will terminate.\n");
      return;
    }
    if (self->_videoDocument && self->_videoPresenter) {
      self->_failed = YES;
      std::fprintf(stderr,
                   "FAIL: PiP presenter survived actual Browser close.\n");
    }
    result =
        (!self->_failed &&
         self->_case ==
             (self->_videoDocument ? 7 : (self->_extensionDocument ? 1 : 3)))
            ? 0
            : 1;
    if (!api.quit(
            [](void* context) {
              shutdown_complete = api.shutdown() == 1;
              if (!shutdown_complete) {
                result = 1;
              } else {
                (void)[NSApp accessibilityRole];
                std::fprintf(stdout, "NATIVE_ACCESSIBILITY_SHUTDOWN_PASS "
                                     "query_after_shutdown=true\n");
                std::fflush(stdout);
              }
            },
            nullptr)) {
      result = 1;
      std::fprintf(stderr, "FAIL: Engine did not accept idle shutdown.\n");
    }
  }];
}
- (BOOL)windowShouldClose:(NSWindow*)sender {
  [self fail:@"Window close interrupted test."];
  return NO;
}
- (NSWindow*)nativeBrowserWindow {
  return _window;
}
- (PCNativePage*)selectedNativePage {
  return _extensionDocument ? _selectedPage : _page;
}
- (NSArray<PCNativePage*>*)visibleNativePages {
  PCNativePage* selected = self.selectedNativePage;
  return selected && selected.nativeView.window == _window ? @[ selected ]
                                                           : @[];
}
- (NSView*)nativeBrowser:(PCNativeBrowserWindow*)browser
        containerForPage:(PCNativePage*)page
             disposition:(PCNativePageDisposition)disposition {
  if (_extensionDocument && page == _otherPage) {
    return _otherContainer;
  }
  if (page == _page) {
    if (!_extensionDocument && !_videoDocument && _running &&
        _case == PCRuntimeHTTPAuthDetach && page.nativeView.window == nil) {
      return nil;
    }
    return _container;
  }
  [self fail:@"Unexpected internal page adoption; external container binding "
             @"failed."];
  return nil;
}
- (void)nativeBrowser:(PCNativeBrowserWindow*)browser
         didClosePage:(PCNativePage*)page {
  if (page == _otherPage) {
    _otherPage.observer = nil;
    _otherPage = nil;
  }
  if (page == _selectedPage) {
    _selectedPage = nil;
  }
  if (page == _page) {
    _page.observer = nil;
    _page = nil;
  }
  if (!_closing) {
    [self fail:@"Page closed before controller tests finished."];
  }
}
- (void)nativeBrowser:(PCNativeBrowserWindow*)browser
        didSelectPage:(PCNativePage*)page {
  if (_closing || browser != _binding || page.closed ||
      (page != _page && page != _otherPage) ||
      page.nativeView.window != _window) {
    return;
  }
  if (_extensionDocument) {
    _selectedPage = page;
    _container.hidden = page != _page;
    _otherContainer.hidden = page != _otherPage;
  }
  [browser synchronizeLayout];
}
- (void)nativeBrowser:(PCNativeBrowserWindow*)browser
     didFailWithError:(NSError*)error {
  [self failWithError:error page:_page source:@"browser"];
}
- (void)nativePageDidChange:(PCNativePage*)page {
  [self maybeStart];
}
- (void)nativePageDidClose:(PCNativePage*)page {
  if (!_closing) {
    [self fail:@"Unexpected WebContents destruction."];
  }
}
- (void)nativePage:(PCNativePage*)page didFailWithError:(NSError*)error {
  [self failWithError:error page:page source:@"page"];
}
- (void)nativeBrowserFocusAddress:(PCNativeBrowserWindow*)browser {
  [self fail:@"Unexpected address action."];
}
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
    rotateFocusForward:(BOOL)forward {
  if (forward) {
    [_window selectNextKeyView:nil];
  } else {
    [_window selectPreviousKeyView:nil];
  }
  return YES;
}
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
    setTabFullscreenPage:(PCNativePage*)page {
  if (page) {
    [self fail:@"Unexpected fullscreen request."];
    return NO;
  }
  return YES;
}
- (void)nativeBrowserShowTabSearch:(PCNativeBrowserWindow*)browser {
  [self fail:@"Unexpected tab search."];
}
- (void)nativeBrowserCloseTabSearch:(PCNativeBrowserWindow*)browser {
  [self fail:@"Unexpected tab search close."];
}
- (void)nativeBrowserShowProfiles:(PCNativeBrowserWindow*)browser {
  [self fail:@"Unexpected profile UI."];
}
- (void)nativeBrowser:(PCNativeBrowserWindow*)browser bookmarkURL:(NSURL*)url {
  [self fail:@"Unexpected bookmark request."];
}
- (NSView*)nativeBrowserSidePanelContainer:(PCNativeBrowserWindow*)browser {
  return _sidePanel;
}
- (BOOL)nativeBrowser:(PCNativeBrowserWindow*)browser
    setSidePanelVisible:(BOOL)visible {
  if (visible) {
    [self fail:@"Unexpected side panel."];
    return NO;
  }
  _sidePanel.hidden = YES;
  return YES;
}
- (void)nativeBrowser:(PCNativeBrowserWindow*)browser
    capabilityUnavailable:(NSString*)capability {
  [self fail:capability];
}
- (id<PCNativeVideoPiPWindow>)
    createVideoPictureInPictureWindow:(NSView*)view
                          sourceFrame:(NSRect)frame
                               action:(void (^)(PCVideoPiPAction, double))action
                              changed:(dispatch_block_t)changed {
  _videoPresenter = [[PCVideoPiPPresenter alloc] initWithVideoView:view
                                                       sourceFrame:frame
                                                            action:action
                                                           changed:changed];
  return _videoPresenter;
}
- (void)releaseVideoPictureInPictureWindow:
    (id<PCNativeVideoPiPWindow>)presenter {
  [presenter invalidate];
  if (_videoPresenter == presenter) {
    _videoPresenter = nil;
  }
}
- (void)nativeApplicationDownloadDidUpdate:
    (NSDictionary<NSString*, id>*)update {
  [self fail:@"Unexpected download."];
}
- (id<PCNativeBrowserWindowClient>)
    prepareNativeWindowForRequest:(PCNativeWindowRequest*)request {
  [self fail:@"Unexpected new Browser preflight."];
  return nil;
}
- (void)nativeApplicationRelaunchedWithArguments:(NSArray<NSString*>*)arguments
                                currentDirectory:(NSString*)currentDirectory {
  [self fail:@"Unexpected profile singleton handoff."];
}
@end

namespace {
bool ValidateRoot(NSString* root) {
  if (!root.absolutePath ||
      ![root.stringByResolvingSymlinksInPath isEqualToString:root]) {
    return false;
  }
  struct stat st;
  if (lstat(root.fileSystemRepresentation, &st) || !S_ISDIR(st.st_mode) ||
      st.st_uid != getuid() || (st.st_mode & 0777) != 0700) {
    return false;
  }
  NSArray* entries =
      [[NSFileManager defaultManager] contentsOfDirectoryAtPath:root error:nil];
  if (entries.count != 1 ||
      ![entries.firstObject isEqual:@"parc-native-runtime-test.marker"]) {
    return false;
  }
  NSString* marker = [root stringByAppendingPathComponent:entries.firstObject];
  if (lstat(marker.fileSystemRepresentation, &st) || !S_ISREG(st.st_mode) ||
      st.st_nlink != 1 || st.st_uid != getuid() ||
      (st.st_mode & 0777) != 0600) {
    return false;
  }
  return [[NSString stringWithContentsOfFile:marker
                                    encoding:NSUTF8StringEncoding
                                       error:nil]
      isEqualToString:@"Parc native runtime test v1\n"];
}
}
int main(int argc, char** argv) {
  @autoreleasepool {
    const bool extension_suite =
        argc == 5 && std::strcmp(argv[3], "--extension-actions") == 0;
    const bool video_suite =
        argc == 5 && std::strcmp(argv[3], "--video-pip") == 0;
    if ((!extension_suite && !video_suite && argc != 3) ||
        std::strcmp(argv[2], "--use-mock-keychain") != 0) {
      return 64;
    }
    NSString* document = (extension_suite || video_suite)
                             ? [NSString stringWithUTF8String:argv[4]]
                             : nil;
    if (extension_suite || video_suite) {
      NSURLComponents* url = [NSURLComponents componentsWithString:document];
      if (![url.scheme isEqual:@"http"] || ![url.host isEqual:@"127.0.0.1"] ||
          !url.port || url.port.integerValue < 1 ||
          url.port.integerValue > 65535 ||
          ![url.path isEqual:(video_suite ? @"/bear.webm"
                                          : @"/extension-actions.html")] ||
          url.query || url.fragment || url.user || url.password ||
          ![url.URL.absoluteString isEqual:document]) {
        return 64;
      }
    }
    NSString* root = [NSString stringWithUTF8String:argv[1]];
    if (!ValidateRoot(root)) {
      std::fprintf(stderr, "Refusing unmarked/reused test profile root.\n");
      return 64;
    }
    PCRuntimeApplication* app = [PCRuntimeApplication sharedApplication];
    [app setActivationPolicy:NSApplicationActivationPolicyRegular];
    NSString* bundle = NSBundle.mainBundle.bundlePath;
    NSString* framework = [bundle
        stringByAppendingPathComponent:
            @"Contents/Frameworks/Chromium Embedded Framework.framework"];
    NSString* helper = [bundle
        stringByAppendingPathComponent:
            @"Contents/Frameworks/parc_native_runtime_tests "
            @"Helper.app/Contents/MacOS/parc_native_runtime_tests Helper"];
    void* engine = dlopen(
        [framework
            stringByAppendingPathComponent:@"Chromium Embedded Framework"]
            .fileSystemRepresentation,
        RTLD_NOW | RTLD_LOCAL);
    if (!engine) {
      std::fprintf(stderr, "%s\n", dlerror());
      return 1;
    }
#define LOAD(member, symbol)                                                   \
  api.member = reinterpret_cast<decltype(api.member)>(dlsym(engine, #symbol)); \
  if (!api.member) {                                                           \
    std::fprintf(stderr, "Missing %s\n", #symbol);                             \
    return 1;                                                                  \
  }
    LOAD(initialize, parc_engine_initialize)
    LOAD(run, parc_engine_run_message_loop)
    LOAD(quit, parc_engine_request_quit_when_idle)
    LOAD(shutdown, parc_engine_shutdown_if_idle)
    LOAD(auth, parc_test_http_auth)
    LOAD(cancel, parc_test_cancel_http_auth)
    LOAD(extensions, parc_test_extension_actions)
    LOAD(cancel_extensions, parc_test_cancel_extension_actions)
    LOAD(pip, parc_test_video_pip)
    LOAD(cancel_pip, parc_test_cancel_video_pip)
#undef LOAD
    char test_switch[] = "--parc-native-runtime-controller-tests";
    char* engine_argv[] = {argv[0], argv[2], test_switch, nullptr};
    int exit_code = 1;
    auto start = api.initialize(3, engine_argv, root.fileSystemRepresentation,
                                framework.fileSystemRepresentation,
                                bundle.fileSystemRepresentation,
                                helper.fileSystemRepresentation, &exit_code);
    if (start != PARC_ENGINE_START_READY) {
      return exit_code == 0 ? 1 : exit_code;
    }
    PCRuntimeController* controller = [[PCRuntimeController alloc]
             initWithRoot:root
        extensionDocument:extension_suite ? document : nil
            videoDocument:video_suite ? document : nil];
    app.runtime = controller;
    app.delegate = controller;
    dispatch_async(dispatch_get_main_queue(), ^{
      [controller begin];
    });
    api.run();
    if (!shutdown_complete) {
      result = 1;
    }
    if (video_suite) {
      std::fprintf(stdout, "NATIVE_PIP_RUNTIME_%s cases=7 clean_shutdown=%s\n",
                   result == 0 ? "PASS" : "FAIL",
                   shutdown_complete ? "true" : "false");
    } else if (extension_suite) {
      std::fprintf(stdout, "NATIVE_EXTENSION_RUNTIME_%s clean_shutdown=%s\n",
                   result == 0 ? "PASS" : "FAIL",
                   shutdown_complete ? "true" : "false");
    } else {
      std::fprintf(stdout,
                   "NATIVE_RUNTIME_%s cases=3 synthetic_http_auth=true "
                   "clean_shutdown=%s\n",
                   result == 0 ? "PASS" : "FAIL",
                   shutdown_complete ? "true" : "false");
    }
    return result;
  }
}
