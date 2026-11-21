#import <AppKit/AppKit.h>
#import "ParcNativeTest.h"
#import "ParcNativeClock.h"
#import "ParcNativeWindows.h"

#import "external_protocol_presenter.h"
#define Check(...) ParcNativeCheckMessage(__FILE__, __LINE__, __VA_ARGS__)
static void Pump() {
  ParcNativeAdvance(.08);
}
static NSWindow* Window(bool visible = true) {
  NSWindow* w = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(-2300, -2300, 640, 480)
                styleMask:NSWindowStyleMaskBorderless
                  backing:NSBackingStoreBuffered
                    defer:NO];
  w.releasedWhenClosed = NO;
  if (visible) {
    ParcNativeMarkVisible(w);
  }
  return w;
}
static NSView* Page(NSWindow* w) {
  NSView* p = [[NSView alloc] initWithFrame:w.contentView.bounds];
  [w.contentView addSubview:p];
  return p;
}
static NSView* Find(NSView* v, NSString* name) {
  if ([v.identifier isEqual:name] ||
      ([v isKindOfClass:NSButton.class] &&
       [static_cast<NSButton*>(v).title isEqual:name])) {
    return v;
  }
  for (NSView* child in v.subviews) {
    if (auto f = Find(child, name)) {
      return f;
    }
  }
  return nil;
}
static PCExternalProtocolPresenter* Make(NSView* p,
                                         NSWindow* w,
                                         NSString* remember,
                                         BOOL (^valid)(void),
                                         BOOL (^input)(NSEvent*),
                                         void (^result)(BOOL, BOOL)) {
  return [[PCExternalProtocolPresenter alloc]
       initWithPage:p
             window:w
              title:@"“example.test” wants to open “Example”."
            message:@""
               icon:[NSImage imageNamed:NSImageNameComputer]
        acceptLabel:@"Open “Example”"
        cancelLabel:@"Cancel"
      rememberLabel:remember
           validate:valid
       inputAllowed:input
       stateChanged:^{
       }
             result:result];
}
@interface ProtocolState : NSObject
@property int results;
@property BOOL accepted;
@property BOOL remembered;
@property BOOL inputAllowed;
@end
@implementation ProtocolState
@end

static NSString* const kRemember = @"Always open “Example”";

static NSButton* Control(PCExternalProtocolPresenter* r, NSString* name) {
  return static_cast<NSButton*>(Find(r.sheet.contentView, name));
}

static NSEvent* KeypadEnter(NSWindow* window) {
  return [NSEvent keyEventWithType:NSEventTypeKeyDown
                          location:NSZeroPoint
                     modifierFlags:0
                         timestamp:NSProcessInfo.processInfo.systemUptime
                      windowNumber:window.windowNumber
                           context:nil
                        characters:@"\003"
       charactersIgnoringModifiers:@"\003"
                         isARepeat:NO
                           keyCode:76];
}

@interface ExternalProtocolDecisionTests : ParcNativeTestCase
@end

@implementation ExternalProtocolDecisionTests {
  NSWindow* _window;
  NSView* _page;
  ProtocolState* _state;
}

- (void)setUp {
  [super setUp];
  _window = Window();
  _page = Page(_window);
  _state = [ProtocolState new];
  _state.inputAllowed = YES;
}

- (void)tearDown {
  [_window close];
  [super tearDown];
}

- (PCExternalProtocolPresenter*)presenterRemembering:(NSString*)remember {
  ProtocolState* state = _state;
  NSWindow* window = _window;
  return Make(
      _page, _window, remember,
      ^{
        return YES;
      },
      ^(NSEvent*) {
        return state.inputAllowed;
      },
      ^(BOOL accepted, BOOL remembered) {
        ++state.results;
        state.accepted = accepted;
        state.remembered = remembered;
        Check(!window.attachedSheet, "presentation ends before decision");
      });
}

- (PCExternalProtocolPresenter*)shownPresenter {
  PCExternalProtocolPresenter* r = [self presenterRemembering:kRemember];
  [r show];
  Pump();
  return r;
}

- (void)testAnUnpresentedPresenterAlreadyOwnsAnInvisibleNativeSheet {
  PCExternalProtocolPresenter* r = [self presenterRemembering:kRemember];
  Check(r.sheet && !r.sheet.visible, "unpresented native sheet exists");
}

- (void)testShowIsDeferredEvenWhenCalledTwice {
  PCExternalProtocolPresenter* r = [self presenterRemembering:kRemember];
  [r show];
  [r show];
  Check(_state.results == 0, "show is deferred");
}

- (void)testTheOriginatingWindowOwnsThePresentedSheet {
  PCExternalProtocolPresenter* r = [self shownPresenter];
  Check(r.sheet.visible && r.sheet.sheetParent == _window, "actual originating window owns sheet");
}

- (void)testOpenIsTheDefaultAndCancelAnswersEscape {
  PCExternalProtocolPresenter* r = [self shownPresenter];
  NSButton* open = Control(r, @"external-protocol-open");
  NSButton* cancel = Control(r, @"external-protocol-cancel");
  NSButton* box = Control(r, @"external-protocol-remember");
  Check([open.keyEquivalent isEqual:@"\r"] && r.sheet.accessibilityDefaultButton == open &&
            [cancel.keyEquivalent isEqual:@"\033"] && !box.keyEquivalent.length,
        "Open is the default and Cancel answers Escape");
}

- (void)testCancelSitsLeftOfOpenAndAlwaysOpenIsLeftOfCancelOrWrapsAbove {
  PCExternalProtocolPresenter* r = [self shownPresenter];
  NSButton* open = Control(r, @"external-protocol-open");
  NSButton* cancel = Control(r, @"external-protocol-cancel");
  NSButton* box = Control(r, @"external-protocol-remember");
  const BOOL boxFirst = NSMidY(box.frame) == NSMidY(open.frame) ? NSMinX(box.frame) < NSMinX(cancel.frame)
                                                                 : NSMaxY(box.frame) <= NSMinY(open.frame);
  Check(open.superview == box.superview && box.superview == cancel.superview &&
            NSMidY(cancel.frame) == NSMidY(open.frame) && NSMinX(cancel.frame) < NSMinX(open.frame) && boxFirst,
        "Cancel sits left of Open; Always open is left of Cancel or wraps above");
}

- (void)testEveryButtonStaysInsideTheSheet {
  PCExternalProtocolPresenter* r = [self shownPresenter];
  NSRect bounds = r.sheet.contentView.bounds;
  Check(NSContainsRect(bounds, Control(r, @"external-protocol-open").frame) &&
            NSContainsRect(bounds, Control(r, @"external-protocol-cancel").frame) &&
            NSContainsRect(bounds, Control(r, @"external-protocol-remember").frame),
        "every button stays inside the sheet");
}

- (void)testRememberIsTheAlwaysOpenButton {
  PCExternalProtocolPresenter* r = [self shownPresenter];
  Check([Control(r, @"external-protocol-remember").title isEqual:kRemember], "remember is the Always open button");
}

- (void)testInputProtectionRefusalKeepsTheRequestPending {
  PCExternalProtocolPresenter* r = [self shownPresenter];
  _state.inputAllowed = NO;
  [Control(r, @"external-protocol-remember") performClick:nil];
  Check(_state.results == 0 && r.sheet.visible, "input protection refusal keeps request pending");
}

- (void)testKeypadEnterIsHeldByTheSameInputProtection {
  PCExternalProtocolPresenter* r = [self shownPresenter];
  _state.inputAllowed = NO;
  Check([r.sheet performKeyEquivalent:KeypadEnter(r.sheet)] && _state.results == 0 && r.sheet.visible,
        "keypad Enter is held by the same input protection");
}

- (void)testOpenAcceptsWithoutRemembering {
  PCExternalProtocolPresenter* r = [self shownPresenter];
  [Control(r, @"external-protocol-open") performClick:nil];
  Pump();
  Check(_state.results == 1 && _state.accepted && !_state.remembered, "Open accepts without remembering");
}

- (void)testAlwaysOpenAcceptsAndRemembersOnce {
  PCExternalProtocolPresenter* r = [self shownPresenter];
  [Control(r, @"external-protocol-remember") performClick:nil];
  Pump();
  Check(_state.results == 1 && _state.accepted && _state.remembered, "Always open accepts and remembers once");
}

- (void)testATerminalPresenterCannotReplay {
  PCExternalProtocolPresenter* r = [self shownPresenter];
  NSButton* open = Control(r, @"external-protocol-open");
  [Control(r, @"external-protocol-remember") performClick:nil];
  Pump();
  Check(_state.results == 1, "the first decision lands once");
  [r invalidate];
  [open performClick:nil];
  [r show];
  Pump();
  Check(_state.results == 1, "terminal cannot replay");
}

- (void)testAnUnsupportedRememberButtonIsAbsent {
  PCExternalProtocolPresenter* r = [self presenterRemembering:@""];
  [r show];
  Pump();
  Check(!Find(r.sheet.contentView, @"external-protocol-remember"), "unsupported remember absent");
}

- (void)testCancelCancelsOnceWithoutRemembering {
  PCExternalProtocolPresenter* r = [self presenterRemembering:@""];
  [r show];
  Pump();
  [Control(r, @"external-protocol-cancel") performClick:nil];
  Pump();
  Check(_state.results == 1 && !_state.accepted && !_state.remembered, "Cancel cancels once and never remembers");
}

@end

@interface ExternalProtocolInvalidationTests : ParcNativeTestCase
@end

@implementation ExternalProtocolInvalidationTests {
  NSWindow* _window;
  NSView* _page;
  PCExternalProtocolPresenter* _presenter;
  ProtocolState* _state;
}

- (void)tearDown {
  [_window close];
  [super tearDown];
}

- (void)showInWindowVisible:(BOOL)visible valid:(BOOL)valid {
  _window = Window(visible);
  _page = Page(_window);
  _state = [ProtocolState new];
  ProtocolState* state = _state;
  _presenter = Make(
      _page, _window, @"",
      ^{
        return valid;
      },
      ^(NSEvent*) {
        return YES;
      },
      ^(BOOL accepted, BOOL remembered) {
        ++state.results;
        Check(!accepted && !remembered, "invalid request does not authorize");
      });
  [_presenter show];
}

- (void)expectInterruptedOnce {
  Pump();
  Check(_state.results == 1 && !_window.attachedSheet, "invalid owner interrupts actual sheet");
  [_presenter invalidate];
  Pump();
  Check(_state.results == 1, "interruption remains once only");
}

- (void)testAnInvisibleWindowInterruptsTheRequest {
  [self showInWindowVisible:NO valid:YES];
  [self expectInterruptedOnce];
}

- (void)testAFailedValidationInterruptsTheRequest {
  [self showInWindowVisible:YES valid:NO];
  [self expectInterruptedOnce];
}

- (void)testARemovedPageInterruptsTheRequest {
  [self showInWindowVisible:YES valid:YES];
  [_page removeFromSuperview];
  [self expectInterruptedOnce];
}

- (void)testInvalidatingInterruptsTheRequest {
  [self showInWindowVisible:YES valid:YES];
  [_presenter invalidate];
  [self expectInterruptedOnce];
}

- (void)testAClosedWindowInterruptsTheRequest {
  [self showInWindowVisible:YES valid:YES];
  [_window close];
  [self expectInterruptedOnce];
}

- (void)testAHiddenPageInterruptsTheRequest {
  [self showInWindowVisible:YES valid:YES];
  _page.hidden = YES;
  [self expectInterruptedOnce];
}

@end

@interface ExternalProtocolReentryTests : ParcNativeTestCase
@end

@implementation ExternalProtocolReentryTests {
  NSWindow* _window;
  NSView* _page;
  PCExternalProtocolPresenter* _presenter;
  PCExternalProtocolPresenter* _replacement;
  ProtocolState* _state;
}

- (void)setUp {
  [super setUp];
  _window = Window();
  _page = Page(_window);
  _state = [ProtocolState new];
}

- (void)tearDown {
  [_window close];
  [super tearDown];
}

- (void)testNoSheetIsResurrectedAfterAValidationReentry {
  ProtocolState* state = _state;
  __block BOOL reenter = NO;
  __block PCExternalProtocolPresenter* r;
  r = Make(
      _page, _window, @"",
      ^{
        if (reenter) {
          [r invalidate];
        }
        return YES;
      },
      ^(NSEvent*) {
        return YES;
      },
      ^(BOOL accepted, BOOL) {
        ++state.results;
        Check(!accepted, "validation reentry cancels");
      });
  reenter = YES;
  [r show];
  Pump();
  Check(state.results == 1 && !_window.attachedSheet, "no resurrection after validation");
  r = nil;
}

- (void)showWithInputReentry {
  ProtocolState* state = _state;
  NSView* page = _page;
  NSWindow* window = _window;
  __weak ExternalProtocolReentryTests* weakSelf = self;
  __block PCExternalProtocolPresenter* r;
  r = Make(
      page, window, @"",
      ^{
        return YES;
      },
      ^(NSEvent*) {
        [r invalidate];
        return YES;
      },
      ^(BOOL accepted, BOOL) {
        ++state.results;
        Check(!accepted, "input reentry cannot authorize");
        ExternalProtocolReentryTests* strongSelf = weakSelf;
        strongSelf->_replacement = Make(
            page, window, @"",
            ^{
              return YES;
            },
            ^(NSEvent*) {
              return YES;
            },
            ^(BOOL, BOOL) {
              ++state.results;
            });
        [strongSelf->_replacement show];
      });
  _presenter = r;
  [r show];
  Pump();
  [Control(r, @"external-protocol-open") performClick:nil];
  Pump();
  r = nil;
}

- (void)testAnInputReentryPreservesTheReplacementSheet {
  [self showWithInputReentry];
  Check(_state.results == 1 && _window.attachedSheet == _replacement.sheet, "old input frame preserves replacement");
}

- (void)testAReplacementOwnsItsOwnResult {
  [self showWithInputReentry];
  [_replacement invalidate];
  Pump();
  Check(_state.results == 2, "replacement owns own result");
}

@end
