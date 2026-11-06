// Copyright 2026 Parc contributors.
#import "certificate_viewer_presenter.h"

#import <Security/Security.h>
#import <SecurityInterface/SFCertificatePanel.h>

@interface PCServerCertificatePresenter () {
  __weak NSView* _page;
  __weak NSWindow* _window;
  NSArray* _certificates;
  SFCertificatePanel* _panel;
  NSWindow* _sheet;
  BOOL (^_validate)(void);
  void (^_finished)(void);
  PCServerCertificatePresenter* _sheetLifetime;
  id _closeObserver;
  BOOL _scheduled;
  BOOL _began;
  BOOL _terminal;
}
@end
@implementation PCServerCertificatePresenter
- (instancetype)initWithPage:(NSView*)page
                      window:(NSWindow*)window
                certificates:(NSArray*)certificates
                    validate:(BOOL (^)(void))validate
                    finished:(void (^)(void))finished {
  NSParameterAssert(page && window && validate && finished);
  if ((self = [super init])) {
    _page = page;
    _window = window;
    _certificates = [certificates copy];
    _validate = [validate copy];
    _finished = [finished copy];
    _panel = [[SFCertificatePanel alloc] init];
    SecPolicyRef policy = SecPolicyCreateBasicX509();
    if (policy) {
      [_panel setPolicies:@[ (__bridge id)policy ]];
      CFRelease(policy);
    } else {
      _certificates = @[];
    }
  }
  return self;
}
- (NSWindow*)panel {
  return _sheet ?: _panel;
}
- (void)dealloc {
  if (_closeObserver) {
    [NSNotificationCenter.defaultCenter removeObserver:_closeObserver];
  }
}
- (BOOL)valid {
  if (_terminal || !_page || !_window || !_validate ||
      _page.window != _window || !_window.visible || _window.miniaturized ||
      _page.hiddenOrHasHiddenAncestor || _certificates.count == 0) {
    return NO;
  }
  BOOL (^validate)(void) = _validate;
  return validate();
}
- (void)show {
  NSAssert(NSThread.isMainThread, @"UI thread required");
  if (_scheduled || _terminal) {
    return;
  }
  _scheduled = YES;
  __weak PCServerCertificatePresenter* weak = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    [weak start];
  });
}
- (void)start {
  __attribute__((objc_precise_lifetime)) PCServerCertificatePresenter* keep =
      self;
  __attribute__((objc_precise_lifetime)) NSWindow* window = _window;
  __attribute__((objc_precise_lifetime)) NSView* page = _page;
  if (![keep valid] || _terminal || page.window != window || !window.visible ||
      window.miniaturized || window.attachedSheet) {
    [keep invalidate];
    return;
  }
  __weak PCServerCertificatePresenter* weak = keep;
  _closeObserver = [NSNotificationCenter.defaultCenter
      addObserverForName:NSWindowWillCloseNotification
                  object:window
                   queue:nil
              usingBlock:^(NSNotification*) {
                [weak invalidate];
              }];
  // SFCertificatePanel's legacy selector callback does not provide ownership
  // of its modal delegate. Hold the actual delegate until that callback ends.
  _sheetLifetime = keep;
  _began = YES;
  __attribute__((objc_precise_lifetime)) SFCertificatePanel* panel = _panel;
  __attribute__((objc_precise_lifetime)) NSArray* certificates = _certificates;
  [panel beginSheetForWindow:window
               modalDelegate:keep
              didEndSelector:@selector(certificateSheetDidEnd:
                                                   returnCode:contextInfo:)
                 contextInfo:nullptr
                certificates:certificates
                   showGroup:YES];
  // The OS delegate may finish this operation in a nested event loop. Its
  // completion may already have shown another sheet on this same window.
  if (!_began) {
    return;
  }
  // SecurityInterface creates a separate SFCertificatePanel for the sheet.
  // Capture that exact result of this synchronous begin call, not the factory.
  NSWindow* sheet = window.attachedSheet;
  if ([sheet isKindOfClass:SFCertificatePanel.class]) {
    _sheet = sheet;
  }
  if (_terminal || ![keep valid] || _terminal || page.window != window ||
      !_sheet || _sheet.sheetParent != window ||
      window.attachedSheet != _sheet || !_sheet.visible || !window.visible ||
      window.miniaturized) {
    [keep invalidate];
  }
}
- (void)finish {
  if (_terminal) {
    return;
  }
  _terminal = YES;
  _validate = nil;
  if (_closeObserver) {
    [NSNotificationCenter.defaultCenter removeObserver:_closeObserver];
    _closeObserver = nil;
  }
  void (^finished)(void) = _finished;
  _finished = nil;
  if (finished) {
    finished();
  }
}
- (void)invalidate {
  NSAssert(NSThread.isMainThread, @"UI thread required");
  __attribute__((objc_precise_lifetime)) PCServerCertificatePresenter* keep =
      self;
  [keep finish];
  NSWindow* parent = _sheet.sheetParent;
  if (_began && parent) {
    [NSApp endSheet:_sheet];
  }
  [_sheet orderOut:nil];
  // During beginSheet the actual sheet may not be captured yet. Its OS
  // callback still owns this delegate contract until genuine didEnd.
  if (!_began) {
    _sheetLifetime = nil;
  }
}
- (void)certificateSheetDidEnd:(NSWindow*)sheet
                    returnCode:(NSInteger)returnCode
                   contextInfo:(void*)contextInfo {
  __attribute__((objc_precise_lifetime)) PCServerCertificatePresenter* keep =
      self;
  _began = NO;
  // Return codes are dismissal only. No SSL/network decision is attached.
  NSWindow* actualSheet = _sheet;
  [sheet orderOut:nil];
  [actualSheet orderOut:nil];
  [keep finish];
  _panel = nil;
  _sheet = nil;
  _certificates = nil;
  _sheetLifetime = nil;
}
@end
