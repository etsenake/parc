#import <AppKit/AppKit.h>
#import "ParcNativeTest.h"
#import "ParcNativeClock.h"
#import <Security/Security.h>
#import <SecurityInterface/SFCertificatePanel.h>
#import <objc/runtime.h>

#include <cstdio>
#include <cstdlib>

#import "certificate_viewer_presenter.h"
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
  [w orderFront:nil];
  return w;
}
static NSData* FixtureCertificate() {
  NSString* path = [@(__FILE__).stringByDeletingLastPathComponent
      stringByAppendingPathComponent:@"certificate-fixture.pem"];
  NSString* pem = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
  NSRange begin = [pem rangeOfString:@"-----BEGIN CERTIFICATE-----"];
  NSRange end = [pem rangeOfString:@"-----END CERTIFICATE-----"];
  if (begin.location == NSNotFound || end.location == NSNotFound) return nil;
  NSUInteger start = NSMaxRange(begin);
  NSString* body = [pem substringWithRange:NSMakeRange(start, end.location - start)];
  return [[NSData alloc] initWithBase64EncodedString:body
                                             options:NSDataBase64DecodingIgnoreUnknownCharacters];
}
using Begin = void (*)(id, SEL, NSWindow*, id, SEL, void*, NSArray*, BOOL);
static SEL BeginSelector(void) {
  return @selector(beginSheetForWindow:modalDelegate:didEndSelector:contextInfo:certificates:showGroup:);
}

@interface CertificateViewerPresenterTests : ParcNativeTestCase
@end

@implementation CertificateViewerPresenterTests {
  NSArray* _certificates;
  NSWindow* _window;
  NSView* _page;
  int _done;
  Method _begin;
  IMP _original;
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
  _begin = class_getInstanceMethod(SFCertificatePanel.class, BeginSelector());
  _original = method_getImplementation(_begin);
}

- (void)tearDown {
  method_setImplementation(_begin, _original);
  [_window close];
  Pump();
  [super tearDown];
}

- (PCServerCertificatePresenter*)presenterValidating:(BOOL (^)(void))validate {
  int* done = &_done;
  return [[PCServerCertificatePresenter alloc] initWithPage:_page
                                                     window:_window
                                               certificates:_certificates
                                                   validate:validate
                                                   finished:^{
                                                     ++*done;
                                                   }];
}

- (PCServerCertificatePresenter*)presenter {
  return [self presenterValidating:^{
    return YES;
  }];
}

- (void)interceptBegin:(void (^)(id panel, NSWindow* parent, id delegate))after {
  IMP original = _original;
  IMP intercept = imp_implementationWithBlock(
      ^(id panel, NSWindow* parent, id delegate, SEL ended, void* context, NSArray* certs, BOOL group) {
        reinterpret_cast<Begin>(original)(panel, BeginSelector(), parent, delegate, ended, context, certs, group);
        after(panel, parent, delegate);
      });
  method_setImplementation(_begin, intercept);
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
    EXPECT(_done == 0 && !_window.attachedSheet);
    Pump();
    EXPECT(_window.attachedSheet == p.panel);
    EXPECT(p.panel.sheetParent == _window && p.panel.visible);
    weak = p;
    [p invalidate];
    [p invalidate];
    EXPECT(_done == 1);
    p = nil;
    Pump();
    EXPECT(!_window.attachedSheet);
  }
  Pump();
  EXPECT(!weak);
}

- (void)testInvalidatingBeforeTheSheetAppearsFinishesWithoutOne {
  PCServerCertificatePresenter* p = [self presenter];
  [p show];
  [p invalidate];
  Pump();
  EXPECT(_done == 1 && !_window.attachedSheet);
}

- (void)testARefusedValidationFinishesWithoutASheet {
  PCServerCertificatePresenter* p = [self presenterValidating:^{
    return NO;
  }];
  [p show];
  Pump();
  EXPECT(_done == 1 && !_window.attachedSheet);
}

- (void)testAHiddenWindowGetsNoSheet {
  [_window orderOut:nil];
  PCServerCertificatePresenter* p = [self presenter];
  [p show];
  Pump();
  EXPECT(_done == 1 && !_window.attachedSheet);
}

- (void)testAPageRemovedDuringValidationGetsNoSheet {
  NSView* page = _page;
  PCServerCertificatePresenter* p = [self presenterValidating:^{
    [page removeFromSuperview];
    return YES;
  }];
  [p show];
  Pump();
  EXPECT(_done == 1 && !_window.attachedSheet);
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
    weak = released;
    [released show];
    Pump();
    EXPECT(_window.attachedSheet);
    [NSApp endSheet:released.panel];
    Pump();
    EXPECT(_done == 1);
  }
  Pump();
  EXPECT(!weak);
  EXPECT(!_window.attachedSheet);
}

- (void)testAReplacementShownDuringBeginOutlivesTheOldPresenter {
  __block int replacementDone = 0;
  __block bool intercepted = false;
  __block PCServerCertificatePresenter* replacement;
  int* done = &_done;
  NSView* page = _page;
  NSArray* certificates = _certificates;
  [self interceptBegin:^(id panel, NSWindow* parent, id delegate) {
    if (intercepted) return;
    intercepted = true;
    EXPECT(parent.attachedSheet);
    [NSApp endSheet:parent.attachedSheet];
    Pump();
    EXPECT(*done == 1 && !parent.attachedSheet);
    replacement = [[PCServerCertificatePresenter alloc] initWithPage:page
                                                              window:parent
                                                        certificates:certificates
                                                            validate:^{
                                                              return YES;
                                                            }
                                                            finished:^{
                                                              ++replacementDone;
                                                            }];
    [replacement start];
    Pump();
    EXPECT(parent.attachedSheet == replacement.panel && replacement.panel.visible);
  }];
  PCServerCertificatePresenter* p = [self presenter];
  [p show];
  Pump();
  method_setImplementation(_begin, _original);
  EXPECT(intercepted && _done == 1 && replacementDone == 0);
  EXPECT(_window.attachedSheet == replacement.panel && replacement.panel.visible);
  [p invalidate];
  Pump();
  EXPECT(_window.attachedSheet == replacement.panel && replacement.panel.visible);
  [replacement invalidate];
  Pump();
  EXPECT(replacementDone == 1 && !_window.attachedSheet);
}

- (void)testCancellingDuringBeginKeepsTheSheetOwnerUntilTheSystemCallsBack {
  __block bool intercepted = false;
  __weak PCServerCertificatePresenter* weak;
  @autoreleasepool {
    __block PCServerCertificatePresenter* cancelled;
    int* done = &_done;
    [self interceptBegin:^(id panel, NSWindow* parent, id delegate) {
      intercepted = true;
      EXPECT(parent.attachedSheet);
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
    weak = cancelled;
    [cancelled show];
    Pump();
    method_setImplementation(_begin, _original);
    EXPECT(intercepted && _done == 1 && !_window.attachedSheet);
  }
  Pump();
  EXPECT(!weak);
}

- (void)testClosingTheWindowFinishesThePresenter {
  PCServerCertificatePresenter* p = [self presenter];
  [p show];
  Pump();
  EXPECT(_window.attachedSheet);
  [_window close];
  Pump();
  EXPECT(_done == 1);
  EXPECT(!p.panel.sheetParent);
}

@end
