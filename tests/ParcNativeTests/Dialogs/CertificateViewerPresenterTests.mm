#import <AppKit/AppKit.h>
#import "ParcNativeTest.h"
#import "ParcNativeClock.h"
#import "ParcNativeWindows.h"
#import <Security/Security.h>
#import <SecurityInterface/SFCertificatePanel.h>

#include <cstdio>
#include <cstdlib>

#import "certificate_viewer_presenter.h"

#import <objc/message.h>
#import <objc/runtime.h>

@interface CertificateTestPresentation : ParcNativeTestPresentation <PCCertificatePresentation>
@property(nonatomic, copy) void (^didBeginCertificateSheet)(NSWindow* window, id delegate);
@end
@implementation CertificateTestPresentation
@synthesize didBeginCertificateSheet = _didBeginCertificateSheet;
- (void)beginSheetForPanel:(SFCertificatePanel*)panel
                    window:(NSWindow*)window
             modalDelegate:(id)delegate
            didEndSelector:(SEL)didEndSelector
               contextInfo:(void*)contextInfo
              certificates:(NSArray*)certificates
                 showGroup:(BOOL)showGroup {
  SFCertificatePanel* sheet = [SFCertificatePanel new];
  __weak id target = delegate;
  [self window:window beginSheet:sheet completionHandler:^(NSModalResponse code) {
    ((void (*)(id, SEL, NSWindow*, NSInteger, void*))objc_msgSend)(target, didEndSelector, sheet, code, contextInfo);
  }];
  if (self.didBeginCertificateSheet) self.didBeginCertificateSheet(window, delegate);
}
@end
@interface PCServerCertificatePresenter (NestedBeginTest)
- (void)start;
@end
#define EXPECT(condition) PARC_CHECK(condition)
static void Pump() {
  ParcNativeAdvance(.2);
}
static NSWindow* Window() {
  NSWindow* w =
      [[NSWindow alloc] initWithContentRect:NSMakeRect(-2500, -2500, 640, 480)
                                  styleMask:NSWindowStyleMaskBorderless
                                    backing:NSBackingStoreBuffered
                                      defer:NO];
  w.releasedWhenClosed = NO;
  ParcNativeMarkVisible(w);
  return w;
}
static NSData* FixtureCertificate() {
  NSString* path = [SWIFTPM_MODULE_BUNDLE pathForResource:@"certificate-fixture" ofType:@"pem"];
  NSString* pem = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
  if (!pem) return nil;
  NSRange begin = [pem rangeOfString:@"-----BEGIN CERTIFICATE-----"];
  NSRange end = [pem rangeOfString:@"-----END CERTIFICATE-----"];
  if (begin.location == NSNotFound || end.location == NSNotFound) return nil;
  NSUInteger start = NSMaxRange(begin);
  NSString* body = [pem substringWithRange:NSMakeRange(start, end.location - start)];
  return [[NSData alloc] initWithBase64EncodedString:body
                                             options:NSDataBase64DecodingIgnoreUnknownCharacters];
}
static CertificateTestPresentation* Certificates(void) {
  return (CertificateTestPresentation*)ParcNativePresentation();
}
static PCServerCertificatePresenter* Offscreen(PCServerCertificatePresenter* presenter) NS_RETURNS_RETAINED {
  presenter.presentation = Certificates();
  presenter.scheduler = ParcNativeScheduler();
  return presenter;
}

@interface ParcNativeTests_CertificateViewerPresenterTests : ParcNativeTestCase
@end

@implementation ParcNativeTests_CertificateViewerPresenterTests {
  NSArray* _certificates;
  NSWindow* _window;
  NSView* _page;
  int _done;
}

+ (Class)presentationClass {
  return CertificateTestPresentation.class;
}

- (void)setUp {
  [super setUp];
  NSData* der = FixtureCertificate();
  SecCertificateRef cert = SecCertificateCreateWithData(nullptr, (__bridge CFDataRef)der);
  EXPECT(cert);
  _certificates = @[ (__bridge id)cert ];
  CFRelease(cert);
  _window = Window();
  _page = [[NSView alloc] initWithFrame:_window.contentView.bounds];
  [_window.contentView addSubview:_page];
}

- (void)tearDown {
  ParcNativeClose(_window);
  Pump();
  [super tearDown];
}

- (PCServerCertificatePresenter*)presenterValidating:(BOOL (^)(void))validate {
  int* done = &_done;
  return Offscreen([[PCServerCertificatePresenter alloc] initWithPage:_page
                                                              window:_window
                                                        certificates:_certificates
                                                            validate:validate
                                                            finished:^{
                                                              ++*done;
                                                            }]);
}

- (PCServerCertificatePresenter*)presenter {
  return [self presenterValidating:^{
    return YES;
  }];
}

- (void)interceptBegin:(void (^)(NSWindow* parent, id delegate))after {
  Certificates().didBeginCertificateSheet = after;
}

- (void)testThePanelShowsTheCertificateWithTheBasicX509Policy {
  PCServerCertificatePresenter* p = [self presenter];
  EXPECT([p.panel isKindOfClass:SFCertificatePanel.class]);
  NSArray* policies = [(SFCertificatePanel*)p.panel policies];
  EXPECT(policies.count == 1);
  SecPolicyRef basic = SecPolicyCreateBasicX509();
  EXPECT(CFEqual((__bridge CFTypeRef)policies.firstObject, basic));
  CFRelease(basic);
}

- (void)testShowingAttachesASheetAndInvalidationEndsItOnce {
  __weak PCServerCertificatePresenter* weak;
  @autoreleasepool {
    PCServerCertificatePresenter* p = [self presenter];
    [p show];
    EXPECT(_done == 0 && !ParcNativeAttachedSheet(_window));
    Pump();
    EXPECT(ParcNativeAttachedSheet(_window) == p.panel);
    EXPECT(ParcNativeSheetParent(p.panel) == _window && ParcNativeVisible(p.panel));
    weak = p;
    [p invalidate];
    [p invalidate];
    EXPECT(_done == 1);
    p = nil;
    Pump();
    EXPECT(!ParcNativeAttachedSheet(_window));
  }
  Pump();
  EXPECT(!weak);
}

- (void)testInvalidatingBeforeTheSheetAppearsFinishesWithoutOne {
  PCServerCertificatePresenter* p = [self presenter];
  [p show];
  [p invalidate];
  Pump();
  EXPECT(_done == 1 && !ParcNativeAttachedSheet(_window));
}

- (void)testARefusedValidationFinishesWithoutASheet {
  PCServerCertificatePresenter* p = [self presenterValidating:^{
    return NO;
  }];
  [p show];
  Pump();
  EXPECT(_done == 1 && !ParcNativeAttachedSheet(_window));
}

- (void)testAHiddenWindowGetsNoSheet {
  ParcNativeOrderOut(_window);
  PCServerCertificatePresenter* p = [self presenter];
  [p show];
  Pump();
  EXPECT(_done == 1 && !ParcNativeAttachedSheet(_window));
}

- (void)testAPageRemovedDuringValidationGetsNoSheet {
  NSView* page = _page;
  PCServerCertificatePresenter* p = [self presenterValidating:^{
    [page removeFromSuperview];
    return YES;
  }];
  [p show];
  Pump();
  EXPECT(_done == 1 && !ParcNativeAttachedSheet(_window));
}

- (void)testAnExternalSheetEndFinishesAndReleasesThePresenter {
  __weak PCServerCertificatePresenter* weak;
  @autoreleasepool {
    __block PCServerCertificatePresenter* released;
    int* done = &_done;
    released = [[PCServerCertificatePresenter alloc] initWithPage:_page
                                                           window:_window
                                                     certificates:_certificates
                                                         validate:^{
                                                           return YES;
                                                         }
                                                         finished:^{
                                                           ++*done;
                                                           released = nil;
                                                         }];
    Offscreen(released);
    weak = released;
    [released show];
    Pump();
    EXPECT(ParcNativeAttachedSheet(_window));
    [ParcNativePresentation() endApplicationSheet:released.panel];
    Pump();
    EXPECT(_done == 1);
  }
  Pump();
  EXPECT(!weak);
  EXPECT(!ParcNativeAttachedSheet(_window));
}

- (void)testAReplacementShownDuringBeginOutlivesTheOldPresenter {
  __block int replacementDone = 0;
  __block bool intercepted = false;
  __block PCServerCertificatePresenter* replacement;
  int* done = &_done;
  NSView* page = _page;
  NSArray* certificates = _certificates;
  [self interceptBegin:^(NSWindow* parent, id delegate) {
    if (intercepted) return;
    intercepted = true;
    EXPECT(ParcNativeAttachedSheet(parent));
    [ParcNativePresentation() endApplicationSheet:ParcNativeAttachedSheet(parent)];
    Pump();
    EXPECT(*done == 1 && !ParcNativeAttachedSheet(parent));
    replacement = [[PCServerCertificatePresenter alloc] initWithPage:page
                                                              window:parent
                                                        certificates:certificates
                                                            validate:^{
                                                              return YES;
                                                            }
                                                            finished:^{
                                                              ++replacementDone;
                                                            }];
    Offscreen(replacement);
    [replacement start];
    Pump();
    EXPECT(ParcNativeAttachedSheet(parent) == replacement.panel && ParcNativeVisible(replacement.panel));
  }];
  PCServerCertificatePresenter* p = [self presenter];
  [p show];
  Pump();
  Certificates().didBeginCertificateSheet = nil;
  EXPECT(intercepted && _done == 1 && replacementDone == 0);
  EXPECT(ParcNativeAttachedSheet(_window) == replacement.panel && ParcNativeVisible(replacement.panel));
  [p invalidate];
  Pump();
  EXPECT(ParcNativeAttachedSheet(_window) == replacement.panel && ParcNativeVisible(replacement.panel));
  [replacement invalidate];
  Pump();
  EXPECT(replacementDone == 1 && !ParcNativeAttachedSheet(_window));
}

- (void)testCancellingDuringBeginKeepsTheSheetOwnerUntilTheSystemCallsBack {
  __block bool intercepted = false;
  __weak PCServerCertificatePresenter* weak;
  @autoreleasepool {
    __block PCServerCertificatePresenter* cancelled;
    int* done = &_done;
    [self interceptBegin:^(NSWindow* parent, id delegate) {
      intercepted = true;
      EXPECT(ParcNativeAttachedSheet(parent));
      [delegate invalidate];
      EXPECT(*done == 1 && !cancelled);
      EXPECT([delegate valueForKey:@"sheetLifetime"] == delegate);
    }];
    cancelled = [[PCServerCertificatePresenter alloc] initWithPage:_page
                                                            window:_window
                                                      certificates:_certificates
                                                          validate:^{
                                                            return YES;
                                                          }
                                                          finished:^{
                                                            ++*done;
                                                            cancelled = nil;
                                                          }];
    Offscreen(cancelled);
    weak = cancelled;
    [cancelled show];
    Pump();
    Certificates().didBeginCertificateSheet = nil;
    EXPECT(intercepted && _done == 1 && !ParcNativeAttachedSheet(_window));
  }
  Pump();
  EXPECT(!weak);
}

- (void)testClosingTheWindowFinishesThePresenter {
  PCServerCertificatePresenter* p = [self presenter];
  [p show];
  Pump();
  EXPECT(ParcNativeAttachedSheet(_window));
  ParcNativeClose(_window);
  Pump();
  EXPECT(_done == 1);
  EXPECT(!ParcNativeSheetParent(p.panel));
}

@end
