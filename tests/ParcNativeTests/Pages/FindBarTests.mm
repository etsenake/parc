#import "find_bar_view.h"
#import "ParcNativeTest.h"
#import "ParcNativeClock.h"
#include <cmath>
#include <cstdio>
#include <cstdlib>

#define EXPECT(condition) PARC_CHECK(condition)
@interface FlippedContainer : NSView
@end
@implementation FlippedContainer
- (BOOL)isFlipped { return YES; }
@end
@interface FindReceiver : NSObject <PCNativeFindViewDelegate>
@property NSMutableArray<NSNumber *> *actions;
@property NSMutableArray<NSString *> *queries;
@property NSMutableArray<NSNumber *> *focusChanges;
@property(copy) void (^onAction)(PCNativeFindView *);
@property(copy) void (^onFocus)(PCNativeFindView *);
@end
@implementation FindReceiver
- (instancetype)init {
  if ((self = [super init])) { _actions = [NSMutableArray array]; _queries = [NSMutableArray array]; _focusChanges = [NSMutableArray array]; }
  return self;
}
- (void)findView:(PCNativeFindView *)view perform:(PCNativeFindAction)action text:(NSString *)text {
  [_actions addObject:@(action)]; [_queries addObject:text];
  if (_onAction) _onAction(view);
}
- (void)findView:(PCNativeFindView *)view didChangeFocus:(BOOL)focus {
  [_focusChanges addObject:@(focus)];
  if (_onFocus) _onFocus(view);
}
@end
static NSWindow *Window() {
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 480) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  window.contentView = [[FlippedContainer alloc] initWithFrame:NSMakeRect(0, 0, 640, 480)];
  return window;
}
static void Pump() {
  ParcNativeAdvance(0.015);
}
static void Query(PCNativeFindView *view, NSString *value) {
  view.textField.stringValue = value;
  [view controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:view.textField]];
}
static NSButton *Button(NSView *view, NSString *label) {
  if ([view isKindOfClass:NSButton.class] && [view.accessibilityLabel isEqual:label]) return (NSButton *)view;
  for (NSView *child in view.subviews) { NSButton *found = Button(child, label); if (found) return found; }
  return nil;
}
static BOOL Command(PCNativeFindView *view, SEL selector) {
  return [view control:view.textField textView:(NSTextView *)view.textField.currentEditor doCommandBySelector:selector];
}
static void Shift(PCNativeFindView *view, BOOL down) {
  NSEvent *event = [NSEvent keyEventWithType:NSEventTypeFlagsChanged location:NSZeroPoint modifierFlags:down ? NSEventModifierFlagShift : 0 timestamp:0 windowNumber:view.window.windowNumber context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:56];
  [view flagsChanged:event];
}
@interface FindBarTests : ParcNativeTestCase
@end

@implementation FindBarTests {
  NSWindow* _window;
  PCNativeFocusManager* _manager;
  NSTextField* _page;
  PCNativeFocusRegistration* _pageToken;
  PCNativeFindView* _view;
  FindReceiver* _receiver;
  NSWindow* _other;
}

- (void)setUp {
  [super setUp];
  _window = Window();
  _manager = [[PCNativeFocusManager alloc] initWithWindow:_window];
  _page = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 100, 220, 30)];
  [_window.contentView addSubview:_page];
  _pageToken = [_manager registerResponder:_page forKey:@"page-a" didBecome:nil didResign:nil];
  EXPECT(_pageToken != nil);
  _view = [[PCNativeFindView alloc] initWithFrame:NSZeroRect];
  _receiver = [[FindReceiver alloc] init];
  _view.delegate = _receiver;
}

- (void)tearDown {
  [_view invalidate];
  [_manager invalidate];
  [_pageToken invalidate];
  [_window close];
  [_other close];
  [super tearDown];
}

- (void)attach {
  EXPECT([_view attachToContainer:_window.contentView topInset:10 focusManager:_manager focusKey:@"find-a"
                     pageFocusKey:@"page-a"]);
  [_window.contentView layoutSubtreeIfNeeded];
}

- (void)present {
  [self attach];
  EXPECT([_manager requestFocusForKey:@"page-a"] != PCNativeFocusRequestRejected);
  [_manager reconcileFirstResponder];
  _view.text = @"alpha";
  [_view presentTakingFocus:YES];
  Pump();
  [_manager reconcileFirstResponder];
}

- (void)testAttachingPlacesTheHiddenBarAtTheTopTrailingEdge {
  EXPECT(!_view.isPresented);
  [self attach];
  EXPECT(_view.superview == _window.contentView);
  EXPECT(std::abs(_view.frame.size.height - 32) < 0.01);
  EXPECT(std::abs(_view.frame.size.width - 300) < 0.01);
  EXPECT(std::abs(NSMaxX(_view.frame) - 630) < 0.01);
  EXPECT(std::abs(_view.frame.origin.y - 10) < 0.01);
}

- (void)testPresentingTakesFocusAndSelectsTheText {
  [self present];
  EXPECT(_view.isPresented);
  EXPECT(_view.hasFindFocus);
  EXPECT(NSEqualRanges(_view.selectedRange, NSMakeRange(0, 5)));
  EXPECT([_manager.focusedKey isEqual:@"find-a"]);
  EXPECT([_receiver.focusChanges containsObject:@YES]);
  EXPECT(_receiver.actions.count == 0);
}

- (void)testNativeEditingReportsTheQueryAndComposition {
  [self present];
  NSTextView* editor = (NSTextView*)_view.textField.currentEditor;
  EXPECT(editor != nil);
  [editor insertText:@"native edit" replacementRange:NSMakeRange(0, editor.string.length)];
  Pump();
  EXPECT([_receiver.queries.lastObject isEqual:@"native edit"]);
  EXPECT(_receiver.actions.lastObject.integerValue == PCNativeFindQueryChanged);
  [editor setMarkedText:@"composing" selectedRange:NSMakeRange(2, 0) replacementRange:NSMakeRange(0, editor.string.length)];
  EXPECT(_view.hasMarkedText);
  [editor unmarkText];
  EXPECT(!_view.hasMarkedText);
}

- (void)testAChangedQueryIsReportedAndSelectionIsClamped {
  [self present];
  Query(_view, @"café 🪐");
  EXPECT(_receiver.actions.lastObject.integerValue == PCNativeFindQueryChanged);
  EXPECT([_receiver.queries.lastObject isEqual:@"café 🪐"]);
  _view.selectedRange = NSMakeRange(NSUIntegerMax, NSUIntegerMax);
  EXPECT(NSEqualRanges(_view.selectedRange, NSMakeRange(_view.text.length, 0)));
}

- (void)testMatchCountsReadAsText {
  [self present];
  [_view setMatchCount:-1 ordinal:-1];
  EXPECT(_view.matchCountText.length == 0);
  [_view setMatchCount:0 ordinal:0];
  EXPECT([_view.matchCountText isEqual:@"No results"]);
  [_view setMatchCount:9 ordinal:3];
  EXPECT([_view.matchCountText isEqual:@"3 / 9"]);
}

- (void)testTheNextButtonWorksOnlyWithResults {
  [self present];
  [_view setMatchCount:9 ordinal:3];
  NSButton* nextButton = Button(_view, @"Next match");
  EXPECT(nextButton != nil);
  NSUInteger beforeClick = _receiver.actions.count;
  [nextButton performClick:nil];
  EXPECT(_receiver.actions.count == beforeClick + 1);
  EXPECT(_receiver.actions.lastObject.integerValue == PCNativeFindNext);
  [_view setMatchCount:0 ordinal:0];
  EXPECT(!nextButton.enabled);
  beforeClick = _receiver.actions.count;
  [nextButton performClick:nil];
  EXPECT(_receiver.actions.count == beforeClick);
}

- (void)testKeyCommandsBecomeFindActions {
  [self present];
  [_view setMatchCount:9 ordinal:3];
  EXPECT(Command(_view, @selector(insertNewline:)));
  EXPECT(_receiver.actions.lastObject.integerValue == PCNativeFindNext);
  Shift(_view, YES);
  EXPECT(Command(_view, @selector(insertNewline:)));
  EXPECT(_receiver.actions.lastObject.integerValue == PCNativeFindPrevious);
  Shift(_view, NO);
  EXPECT(Command(_view, @selector(moveUp:)));
  EXPECT(_receiver.actions.lastObject.integerValue == PCNativeFindPrevious);
  EXPECT(Command(_view, @selector(moveDown:)));
  EXPECT(_receiver.actions.lastObject.integerValue == PCNativeFindNext);
  NSUInteger before = _receiver.actions.count;
  EXPECT(!Command(_view, @selector(deleteBackward:)));
  EXPECT(_receiver.actions.count == before);
  EXPECT(Command(_view, @selector(cancelOperation:)));
  EXPECT(_receiver.actions.lastObject.integerValue == PCNativeFindClose);
}

- (void)testDismissingRestoresThePageFocusAndIgnoresCommands {
  [self present];
  [_view dismiss];
  EXPECT(!_view.isPresented);
  [_view restoreSavedFocus];
  Pump();
  [_manager reconcileFirstResponder];
  EXPECT([_manager.focusedKey isEqual:@"page-a"]);
  EXPECT(!_view.hasFindFocus);
  NSUInteger before = _receiver.actions.count;
  EXPECT(!Command(_view, @selector(moveDown:)));
  EXPECT(_receiver.actions.count == before);
}

- (void)testTheBarFitsANarrowPaneAndRefusesInvalidContexts {
  FlippedContainer* pane = [[FlippedContainer alloc] initWithFrame:NSMakeRect(0, 60, 240, 260)];
  [_window.contentView addSubview:pane];
  EXPECT([_view attachToContainer:pane topInset:42 focusManager:_manager focusKey:@"find-b" pageFocusKey:@"page-a"]);
  [_view presentTakingFocus:NO];
  [pane layoutSubtreeIfNeeded];
  EXPECT(_view.superview == pane);
  EXPECT(NSMinX(_view.frame) >= 9.99);
  EXPECT(std::abs(NSMaxX(_view.frame) - 230) < 0.01);
  EXPECT(std::abs(_view.frame.origin.y - 42) < 0.01);
  EXPECT(_view.isPresented);
  _other = Window();
  EXPECT(![_view attachToContainer:_other.contentView topInset:10 focusManager:_manager focusKey:@"find-c"
                      pageFocusKey:@"page-a"]);
  EXPECT(_view.superview == nil);
  EXPECT(!_view.isPresented);
  EXPECT(![_view attachToContainer:pane topInset:NAN focusManager:_manager focusKey:@"find-c" pageFocusKey:@"page-a"]);
  EXPECT(![_view attachToContainer:pane topInset:10 focusManager:_manager focusKey:@"" pageFocusKey:@"page-a"]);
}

- (void)testDismissingNeverStealsFocusFromAnUnrelatedField {
  [self attach];
  [_manager requestFocusForKey:@"page-a"];
  [_view presentTakingFocus:YES];
  NSTextField* unrelated = [[NSTextField alloc] initWithFrame:NSMakeRect(270, 100, 200, 30)];
  [_window.contentView addSubview:unrelated];
  EXPECT([_window makeFirstResponder:unrelated]);
  [_view dismiss];
  [_view restoreSavedFocus];
  EXPECT(_window.firstResponder == unrelated.currentEditor);
  [_view presentTakingFocus:YES];
  [_view dismiss];
  [_view restoreSavedFocus];
  EXPECT(_window.firstResponder == unrelated.currentEditor);
}

- (void)testInvalidatingFromAnActionCallbackEndsTheBar {
  [self attach];
  [_view presentTakingFocus:YES];
  _receiver.onAction = ^(PCNativeFindView* target) {
    [target invalidate];
  };
  Query(_view, @"closing");
  EXPECT(_view.invalidated);
  EXPECT(_view.superview == nil);
  EXPECT(!_view.isPresented);
  EXPECT(!Command(_view, @selector(cancelOperation:)));
  EXPECT(![_view attachToContainer:_window.contentView topInset:10 focusManager:_manager focusKey:@"late"
                      pageFocusKey:@"page-a"]);
  NSUInteger before = _receiver.actions.count;
  Query(_view, @"late");
  EXPECT(_receiver.actions.count == before);
}

- (void)testInvalidatingWhenFocusArrivesDetachesTheBar {
  PCNativeFindView* focusVictim = [[PCNativeFindView alloc] initWithFrame:NSZeroRect];
  FindReceiver* focusReceiver = [[FindReceiver alloc] init];
  focusVictim.delegate = focusReceiver;
  focusReceiver.onFocus = ^(PCNativeFindView* target) {
    if (target.hasFindFocus) [target invalidate];
  };
  EXPECT([focusVictim attachToContainer:_window.contentView topInset:10 focusManager:_manager
                               focusKey:@"find-victim" pageFocusKey:@"page-a"]);
  [focusVictim presentTakingFocus:YES];
  EXPECT(focusVictim.invalidated);
  EXPECT(focusVictim.superview == nil);
}

- (void)testADestinationMovedToAnotherWindowDuringFocusLossIsRefused {
  _other = Window();
  PCNativeFindView* moving = [[PCNativeFindView alloc] initWithFrame:NSZeroRect];
  FindReceiver* movingReceiver = [[FindReceiver alloc] init];
  moving.delegate = movingReceiver;
  EXPECT([moving attachToContainer:_window.contentView topInset:10 focusManager:_manager focusKey:@"moving-find"
                      pageFocusKey:@"page-a"]);
  [moving presentTakingFocus:YES];
  FlippedContainer* destination = [[FlippedContainer alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
  [_window.contentView addSubview:destination];
  NSWindow* other = _other;
  movingReceiver.onFocus = ^(PCNativeFindView* target) {
    if (!target.hasFindFocus) [other.contentView addSubview:destination];
  };
  EXPECT(![moving attachToContainer:destination topInset:10 focusManager:_manager focusKey:@"moved-find"
                       pageFocusKey:@"page-a"]);
  EXPECT(destination.window == _other);
  EXPECT(moving.superview == nil);
  [moving invalidate];
}

- (void)testTheBarAndItsDelegateAreHeldWeakly {
  __weak PCNativeFindView* weakView;
  __weak FindReceiver* weakDelegate;
  @autoreleasepool {
    PCNativeFindView* temporary = [[PCNativeFindView alloc] initWithFrame:NSZeroRect];
    weakView = temporary;
    FindReceiver* ephemeral = [[FindReceiver alloc] init];
    weakDelegate = ephemeral;
    temporary.delegate = ephemeral;
    EXPECT([temporary attachToContainer:_window.contentView topInset:10 focusManager:_manager focusKey:@"temporary"
                           pageFocusKey:@"page-a"]);
    ephemeral = nil;
    EXPECT(weakDelegate == nil);
    [temporary invalidate];
  }
  EXPECT(weakView == nil);
}

@end
