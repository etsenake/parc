#import "find_bar_view.h"
#include <cmath>
#include <cstdio>
#include <cstdlib>

static int assertions = 0;
#define EXPECT(value) do { ++assertions; if (!(value)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #value); exit(1); } } while (0)
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
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 480) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  window.contentView = [[FlippedContainer alloc] initWithFrame:NSMakeRect(0, 0, 640, 480)];
  return window;
}
static void Pump() {
  NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:0.015];
  while ([limit timeIntervalSinceNow] > 0) [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:limit];
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
int main() { @autoreleasepool {
  [NSApplication sharedApplication];
  NSWindow *window = Window();
  PCNativeFocusManager *manager = [[PCNativeFocusManager alloc] initWithWindow:window];
  NSTextField *page = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 100, 220, 30)];
  [window.contentView addSubview:page];
  PCNativeFocusRegistration *pageToken = [manager registerResponder:page forKey:@"page-a" didBecome:nil didResign:nil];
  EXPECT(pageToken != nil);
  PCNativeFindView *view = [[PCNativeFindView alloc] initWithFrame:NSZeroRect];
  FindReceiver *receiver = [[FindReceiver alloc] init]; view.delegate = receiver;
  EXPECT(!view.isPresented);
  EXPECT([view attachToContainer:window.contentView topInset:10 focusManager:manager focusKey:@"find-a" pageFocusKey:@"page-a"]);
  [window.contentView layoutSubtreeIfNeeded];
  EXPECT(view.superview == window.contentView);
  EXPECT(std::abs(view.frame.size.height - 32) < 0.01);
  EXPECT(std::abs(view.frame.size.width - 300) < 0.01);
  EXPECT(std::abs(NSMaxX(view.frame) - 630) < 0.01);
  EXPECT(std::abs(view.frame.origin.y - 10) < 0.01);
  EXPECT([manager requestFocusForKey:@"page-a"] != PCNativeFocusRequestRejected);
  [manager reconcileFirstResponder];
  view.text = @"alpha";
  [view presentTakingFocus:YES]; Pump(); [manager reconcileFirstResponder];
  EXPECT(view.isPresented); EXPECT(view.hasFindFocus);
  EXPECT(NSEqualRanges(view.selectedRange, NSMakeRange(0, 5)));
  EXPECT([manager.focusedKey isEqual:@"find-a"]);
  EXPECT([receiver.focusChanges containsObject:@YES]);
  EXPECT(receiver.actions.count == 0);
  NSTextView *editor = (NSTextView *)view.textField.currentEditor;
  EXPECT(editor != nil);
  [editor insertText:@"native edit" replacementRange:NSMakeRange(0, editor.string.length)];
  Pump();
  EXPECT([receiver.queries.lastObject isEqual:@"native edit"]);
  EXPECT(receiver.actions.lastObject.integerValue == PCNativeFindQueryChanged);
  [editor setMarkedText:@"composing" selectedRange:NSMakeRange(2, 0) replacementRange:NSMakeRange(0, editor.string.length)];
  EXPECT(view.hasMarkedText);
  [editor unmarkText]; EXPECT(!view.hasMarkedText);

  Query(view, @"café 🪐");
  EXPECT(receiver.actions.lastObject.integerValue == PCNativeFindQueryChanged);
  EXPECT([receiver.queries.lastObject isEqual:@"café 🪐"]);
  view.selectedRange = NSMakeRange(NSUIntegerMax, NSUIntegerMax);
  EXPECT(NSEqualRanges(view.selectedRange, NSMakeRange(view.text.length, 0)));
  [view setMatchCount:-1 ordinal:-1]; EXPECT(view.matchCountText.length == 0);
  [view setMatchCount:0 ordinal:0]; EXPECT([view.matchCountText isEqual:@"No results"]);
  [view setMatchCount:9 ordinal:3]; EXPECT([view.matchCountText isEqual:@"3 / 9"]);
  NSButton *nextButton = Button(view, @"Next match"); EXPECT(nextButton != nil);
  NSUInteger beforeClick = receiver.actions.count;
  [nextButton performClick:nil];
  EXPECT(receiver.actions.count == beforeClick + 1);
  EXPECT(receiver.actions.lastObject.integerValue == PCNativeFindNext);
  [view setMatchCount:0 ordinal:0];
  EXPECT(!nextButton.enabled);
  beforeClick = receiver.actions.count; [nextButton performClick:nil];
  EXPECT(receiver.actions.count == beforeClick);
  [view setMatchCount:9 ordinal:3];

  EXPECT(Command(view, @selector(insertNewline:)));
  EXPECT(receiver.actions.lastObject.integerValue == PCNativeFindNext);
  Shift(view, YES); EXPECT(Command(view, @selector(insertNewline:)));
  EXPECT(receiver.actions.lastObject.integerValue == PCNativeFindPrevious);
  Shift(view, NO);
  EXPECT(Command(view, @selector(moveUp:)));
  EXPECT(receiver.actions.lastObject.integerValue == PCNativeFindPrevious);
  EXPECT(Command(view, @selector(moveDown:)));
  EXPECT(receiver.actions.lastObject.integerValue == PCNativeFindNext);
  NSUInteger before = receiver.actions.count;
  EXPECT(!Command(view, @selector(deleteBackward:))); EXPECT(receiver.actions.count == before);
  EXPECT(Command(view, @selector(cancelOperation:)));
  EXPECT(receiver.actions.lastObject.integerValue == PCNativeFindClose);
  [view dismiss]; EXPECT(!view.isPresented);
  [view restoreSavedFocus]; Pump(); [manager reconcileFirstResponder];
  EXPECT([manager.focusedKey isEqual:@"page-a"]);
  EXPECT(!view.hasFindFocus);
  before = receiver.actions.count;
  EXPECT(!Command(view, @selector(moveDown:))); EXPECT(receiver.actions.count == before);
  puts("PASS editing, results, commands and keyed focus");

  FlippedContainer *pane = [[FlippedContainer alloc] initWithFrame:NSMakeRect(0, 60, 240, 260)];
  [window.contentView addSubview:pane];
  EXPECT([view attachToContainer:pane topInset:42 focusManager:manager focusKey:@"find-b" pageFocusKey:@"page-a"]);
  [view presentTakingFocus:NO]; [pane layoutSubtreeIfNeeded];
  EXPECT(view.superview == pane);
  EXPECT(NSMinX(view.frame) >= 9.99);
  EXPECT(std::abs(NSMaxX(view.frame) - 230) < 0.01);
  EXPECT(std::abs(view.frame.origin.y - 42) < 0.01);
  EXPECT(view.isPresented);
  NSWindow *other = Window();
  EXPECT(![view attachToContainer:other.contentView topInset:10 focusManager:manager focusKey:@"find-c" pageFocusKey:@"page-a"]);
  EXPECT(view.superview == nil); EXPECT(!view.isPresented);
  EXPECT(![view attachToContainer:pane topInset:NAN focusManager:manager focusKey:@"find-c" pageFocusKey:@"page-a"]);
  EXPECT(![view attachToContainer:pane topInset:10 focusManager:manager focusKey:@"" pageFocusKey:@"page-a"]);
  puts("PASS page geometry, reattachment and invalid contexts");

  EXPECT([view attachToContainer:window.contentView topInset:10 focusManager:manager focusKey:@"find-a" pageFocusKey:@"page-a"]);
  [manager requestFocusForKey:@"page-a"];
  [view presentTakingFocus:YES];
  NSTextField *unrelated = [[NSTextField alloc] initWithFrame:NSMakeRect(270, 100, 200, 30)];
  [window.contentView addSubview:unrelated];
  EXPECT([window makeFirstResponder:unrelated]);
  [view dismiss]; [view restoreSavedFocus];
  EXPECT(window.firstResponder == unrelated.currentEditor);
  [view presentTakingFocus:YES]; [view dismiss]; [view restoreSavedFocus];
  EXPECT(window.firstResponder == unrelated.currentEditor);
  puts("PASS no stolen focus and unregistered field-editor restoration");

  [view presentTakingFocus:YES];
  receiver.onAction = ^(PCNativeFindView *target) { [target invalidate]; };
  Query(view, @"closing");
  EXPECT(view.invalidated); EXPECT(view.superview == nil); EXPECT(!view.isPresented);
  EXPECT(!Command(view, @selector(cancelOperation:)));
  EXPECT(![view attachToContainer:window.contentView topInset:10 focusManager:manager focusKey:@"late" pageFocusKey:@"page-a"]);
  before = receiver.actions.count; Query(view, @"late"); EXPECT(receiver.actions.count == before);
  [view invalidate];
  PCNativeFindView *focusVictim = [[PCNativeFindView alloc] initWithFrame:NSZeroRect];
  FindReceiver *focusReceiver = [[FindReceiver alloc] init]; focusVictim.delegate = focusReceiver;
  focusReceiver.onFocus = ^(PCNativeFindView *target) { if (target.hasFindFocus) [target invalidate]; };
  EXPECT([focusVictim attachToContainer:window.contentView topInset:10 focusManager:manager focusKey:@"find-victim" pageFocusKey:@"page-a"]);
  [focusVictim presentTakingFocus:YES];
  EXPECT(focusVictim.invalidated); EXPECT(focusVictim.superview == nil);
  puts("PASS terminal and reentrant teardown");

  PCNativeFindView *moving = [[PCNativeFindView alloc] initWithFrame:NSZeroRect];
  FindReceiver *movingReceiver = [[FindReceiver alloc] init]; moving.delegate = movingReceiver;
  EXPECT([moving attachToContainer:window.contentView topInset:10 focusManager:manager focusKey:@"moving-find" pageFocusKey:@"page-a"]);
  [moving presentTakingFocus:YES];
  FlippedContainer *destination = [[FlippedContainer alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
  [window.contentView addSubview:destination];
  movingReceiver.onFocus = ^(PCNativeFindView *target) {
    if (!target.hasFindFocus) [other.contentView addSubview:destination];
  };
  EXPECT(![moving attachToContainer:destination topInset:10 focusManager:manager focusKey:@"moved-find" pageFocusKey:@"page-a"]);
  EXPECT(destination.window == other); EXPECT(moving.superview == nil);
  [moving invalidate];
  puts("PASS callback-driven destination window change");

  __weak PCNativeFindView *weakView;
  __weak FindReceiver *weakDelegate;
  @autoreleasepool {
    PCNativeFindView *temporary = [[PCNativeFindView alloc] initWithFrame:NSZeroRect]; weakView = temporary;
    FindReceiver *ephemeral = [[FindReceiver alloc] init]; weakDelegate = ephemeral; temporary.delegate = ephemeral;
    EXPECT([temporary attachToContainer:window.contentView topInset:10 focusManager:manager focusKey:@"temporary" pageFocusKey:@"page-a"]);
    ephemeral = nil; EXPECT(weakDelegate == nil);
    [temporary invalidate];
  }
  EXPECT(weakView == nil);
  [manager invalidate]; [pageToken invalidate]; [window close]; [other close];
  printf("PASS %d assertions in 6 groups\n", assertions);
} return 0; }
