#import <AppKit/AppKit.h>
#import <Security/Security.h>
#import <SecurityInterface/SFCertificatePanel.h>
#import <objc/runtime.h>

#include <cstdio>
#include <cstdlib>

#import "certificate_viewer_presenter.h"
// Invoke the existing start method only to force replacement inside the
// intercepted OS call; nested main-queue dispatch is deliberately not assumed.
@interface PCServerCertificatePresenter (NestedBeginTest)
- (void)start;
@end
static int checks = 0;
#define EXPECT(x)                                          \
  do {                                                     \
    ++checks;                                              \
    if (!(x)) {                                            \
      fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); \
      std::exit(1);                                        \
    }                                                      \
  } while (0)
static void Pump() {
  for (int i = 0; i < 20; ++i) {
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, .01, false);
  }
}
static NSWindow* Window() {
  NSWindow* w =
      [[NSWindow alloc] initWithContentRect:NSMakeRect(-2500, -2500, 640, 480)
                                  styleMask:NSWindowStyleMaskTitled
                                    backing:NSBackingStoreBuffered
                                      defer:NO];
  w.releasedWhenClosed = NO;
  [w orderFront:nil];
  return w;
}
int main(int argc, char** argv) {
  @autoreleasepool {
    EXPECT(argc == 2);
    [NSApplication sharedApplication];
    NSData* der = [NSData dataWithContentsOfFile:@(argv[1])];
    SecCertificateRef cert =
        SecCertificateCreateWithData(nullptr, (__bridge CFDataRef)der);
    EXPECT(cert);
    NSArray* certificates = @[ (__bridge id)cert ];
    CFRelease(cert);
    NSWindow* window = Window();
    NSView* page = [[NSView alloc] initWithFrame:window.contentView.bounds];
    [window.contentView addSubview:page];
    __block int done = 0;
    PCServerCertificatePresenter* p;
    __weak PCServerCertificatePresenter* weak;
    @autoreleasepool {
      p = [[PCServerCertificatePresenter alloc] initWithPage:page
          window:window
          certificates:certificates
          validate:^{
            return YES;
          }
          finished:^{
            ++done;
          }];
      EXPECT([p.panel isKindOfClass:SFCertificatePanel.class]);
      NSArray* policies = [(SFCertificatePanel*)p.panel policies];
      EXPECT(policies.count == 1);
      SecPolicyRef basic = SecPolicyCreateBasicX509();
      EXPECT(CFEqual((__bridge CFTypeRef)policies.firstObject, basic));
      CFRelease(basic);
      [p show];
      EXPECT(done == 0 && !window.attachedSheet);
      Pump();
      EXPECT(window.attachedSheet == p.panel);
      EXPECT(p.panel.sheetParent == window && p.panel.visible);
      weak = p;
      [p invalidate];
      [p invalidate];
      EXPECT(done == 1);
      p = nil;
      Pump();
      EXPECT(!window.attachedSheet);
    }
    Pump();
    EXPECT(!weak);

    done = 0;
    p = [[PCServerCertificatePresenter alloc] initWithPage:page
        window:window
        certificates:certificates
        validate:^{
          return YES;
        }
        finished:^{
          ++done;
        }];
    [p show];
    [p invalidate];
    Pump();
    EXPECT(done == 1 && !window.attachedSheet);
    p = nil;

    done = 0;
    p = [[PCServerCertificatePresenter alloc] initWithPage:page
        window:window
        certificates:certificates
        validate:^{
          return NO;
        }
        finished:^{
          ++done;
        }];
    [p show];
    Pump();
    EXPECT(done == 1 && !window.attachedSheet);
    p = nil;

    done = 0;
    [window orderOut:nil];
    p = [[PCServerCertificatePresenter alloc] initWithPage:page
        window:window
        certificates:certificates
        validate:^{
          return YES;
        }
        finished:^{
          ++done;
        }];
    [p show];
    Pump();
    EXPECT(done == 1 && !window.attachedSheet);
    p = nil;
    [window orderFront:nil];

    done = 0;
    p = [[PCServerCertificatePresenter alloc] initWithPage:page
        window:window
        certificates:certificates
        validate:^{
          [page removeFromSuperview];
          return YES;
        }
        finished:^{
          ++done;
        }];
    [p show];
    Pump();
    EXPECT(done == 1 && !window.attachedSheet);
    p = nil;
    [window.contentView addSubview:page];

    done = 0;
    @autoreleasepool {
      __block PCServerCertificatePresenter* released =
          [[PCServerCertificatePresenter alloc] initWithPage:page
              window:window
              certificates:certificates
              validate:^{
                return YES;
              }
              finished:^{
                ++done;
                released = nil;
              }];
      weak = released;
      [released show];
      Pump();
      EXPECT(window.attachedSheet);
      [NSApp endSheet:released.panel];
      Pump();
      EXPECT(done == 1);
    }
    Pump();
    EXPECT(!weak);
    EXPECT(!window.attachedSheet);

    // Exercise reentry while the original real OS begin invocation is still
    // on the presenter stack. Both sheets are genuine SFCertificatePanels.
    done = 0;
    __block int replacementDone = 0;
    __block bool intercepted = false;
    __block PCServerCertificatePresenter* replacement;
    SEL begin = @selector(
        beginSheetForWindow:
              modalDelegate:didEndSelector:contextInfo:certificates:showGroup:);
    Method method = class_getInstanceMethod(SFCertificatePanel.class, begin);
    IMP original = method_getImplementation(method);
    using Begin = void (*)(id, SEL, NSWindow*, id, SEL, void*, NSArray*, BOOL);
    IMP intercept = imp_implementationWithBlock(
        ^(id panel, NSWindow* parent, id delegate, SEL ended, void* context,
          NSArray* certs, BOOL group) {
          reinterpret_cast<Begin>(original)(panel, begin, parent, delegate,
                                            ended, context, certs, group);
          if (intercepted) {
            return;
          }
          intercepted = true;
          EXPECT(parent.attachedSheet);
          [NSApp endSheet:parent.attachedSheet];
          Pump();
          EXPECT(done == 1 && !parent.attachedSheet);
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
          EXPECT(parent.attachedSheet == replacement.panel &&
                 replacement.panel.visible);
        });
    method_setImplementation(method, intercept);
    p = [[PCServerCertificatePresenter alloc] initWithPage:page
        window:window
        certificates:certificates
        validate:^{
          return YES;
        }
        finished:^{
          ++done;
        }];
    [p show];
    Pump();
    method_setImplementation(method, original);
    imp_removeBlock(intercept);
    EXPECT(intercepted && done == 1 && replacementDone == 0);
    EXPECT(window.attachedSheet == replacement.panel &&
           replacement.panel.visible);
    [p invalidate];
    Pump();
    EXPECT(window.attachedSheet == replacement.panel &&
           replacement.panel.visible);
    [replacement invalidate];
    Pump();
    EXPECT(replacementDone == 1 && !window.attachedSheet);
    replacement = nil;
    p = nil;

    // Cancellation can release the external owner before begin returns and
    // before the presenter has captured the sheet. The real didEnd still owns
    // its callback target even in that interval.
    done = 0;
    intercepted = false;
    @autoreleasepool {
      __block PCServerCertificatePresenter* cancelled;
      intercept = imp_implementationWithBlock(
          ^(id panel, NSWindow* parent, id delegate, SEL ended, void* context,
            NSArray* certs, BOOL group) {
            reinterpret_cast<Begin>(original)(panel, begin, parent, delegate,
                                              ended, context, certs, group);
            intercepted = true;
            EXPECT(parent.attachedSheet);
            [delegate invalidate];
            EXPECT(done == 1 && !cancelled);
            EXPECT([delegate valueForKey:@"sheetLifetime"] == delegate);
            // Do not pump didEnd here: the returned begin frame must capture
            // and retire its own actual OS sheet before releasing the callback
            // target.
          });
      method_setImplementation(method, intercept);
      cancelled = [[PCServerCertificatePresenter alloc] initWithPage:page
          window:window
          certificates:certificates
          validate:^{
            return YES;
          }
          finished:^{
            ++done;
            cancelled = nil;
          }];
      weak = cancelled;
      [cancelled show];
      Pump();
      method_setImplementation(method, original);
      imp_removeBlock(intercept);
      EXPECT(intercepted && done == 1 && !window.attachedSheet);
    }
    Pump();
    EXPECT(!weak);

    done = 0;
    p = [[PCServerCertificatePresenter alloc] initWithPage:page
        window:window
        certificates:certificates
        validate:^{
          return YES;
        }
        finished:^{
          ++done;
        }];
    [p show];
    Pump();
    EXPECT(window.attachedSheet);
    [window close];
    Pump();
    EXPECT(done == 1);
    EXPECT(!p.panel.sheetParent);
    p = nil;
    puts("PASS: real SFCertificatePanel lifecycle; no trust/identity writes");
    printf("%d assertions\n", checks);
  }
}
