#import "find_bar_view.h"
#import <QuartzCore/QuartzCore.h>

namespace {
void MainThread() { NSCAssert(NSThread.isMainThread, @"Find UI is main-thread-only"); }
BOOL ResponderBelongsToField(NSResponder *responder, NSTextField *field) {
  return responder == field || (field.currentEditor && responder == field.currentEditor);
}
NSResponder *StableResponder(NSResponder *responder) {
  // AppKit shares its field editor. Save its owning control, not that shared
  // editor, which will belong to the Find field after focus changes.
  if ([responder isKindOfClass:NSTextView.class] && ((NSTextView *)responder).isFieldEditor) {
    id delegate = ((NSTextView *)responder).delegate;
    if ([delegate isKindOfClass:NSView.class]) return delegate;
    return nil;
  }
  return responder;
}
BOOL SameWindow(NSResponder *responder, NSWindow *window) {
  return window && [responder isKindOfClass:NSView.class] && ((NSView *)responder).window == window;
}
}

@interface PCNativeFindView () {
  NSTextField *_textField;
  NSTextField *_countLabel;
  NSButton *_previousButton;
  NSButton *_nextButton;
  NSButton *_closeButton;
  NSArray<NSLayoutConstraint *> *_placement;
  NSLayoutConstraint *_topConstraint;
  __weak NSView *_container;
  __weak PCNativeFocusManager *_focusManager;
  PCNativeFocusRegistration *_registration;
  NSString *_focusKey;
  NSString *_pageFocusKey;
  NSString *_savedFocusKey;
  __weak NSResponder *_savedResponder;
  __weak NSWindow *_savedWindow;
  NSRange _selection;
  NSInteger _matchCount;
  BOOL _invalidated;
  BOOL _focusReported;
  BOOL _searchBackwards;
  NSUInteger _attachmentGeneration;
  BOOL _restoreAfterHide;
  __weak NSResponder *_responderAfterHide;
}
@end

@implementation PCNativeFindView
@synthesize delegate = _delegate;
- (instancetype)initWithFrame:(NSRect)frame {
  MainThread();
  if (!(self = [super initWithFrame:frame])) return nil;
  self.translatesAutoresizingMaskIntoConstraints = NO;
  self.hidden = YES;
  self.wantsLayer = YES;
  self.layer.cornerRadius = 7;
  self.layer.borderWidth = 1;
  _matchCount = -1;
  _textField = [[NSTextField alloc] initWithFrame:NSZeroRect];
  _textField.delegate = self;
  _textField.placeholderString = @"Find in page...";
  _textField.font = [NSFont systemFontOfSize:13];
  _textField.bezeled = NO;
  _textField.drawsBackground = NO;
  _textField.usesSingleLineMode = YES;
  _textField.cell.wraps = NO;
  _textField.cell.scrollable = YES;
  _textField.focusRingType = NSFocusRingTypeNone;
  _textField.accessibilityLabel = @"Find in page";
  [_textField setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
  _countLabel = [NSTextField labelWithString:@""];
  _countLabel.font = [NSFont systemFontOfSize:11];
  _countLabel.textColor = NSColor.secondaryLabelColor;
  _countLabel.accessibilityLabel = @"Find results";
  _previousButton = [self button:@"chevron.up" label:@"Previous match" action:@selector(previous:)];
  _nextButton = [self button:@"chevron.down" label:@"Next match" action:@selector(next:)];
  _closeButton = [self button:@"xmark" label:@"Close Find" action:@selector(close:)];
  NSImageView *icon = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:@"magnifyingglass" accessibilityDescription:nil]];
  icon.accessibilityElement = NO;
  icon.contentTintColor = NSColor.secondaryLabelColor;
  NSStackView *stack = [NSStackView stackViewWithViews:@[icon, _textField, _countLabel, _previousButton, _nextButton, _closeButton]];
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  stack.alignment = NSLayoutAttributeCenterY;
  stack.spacing = 5;
  [self addSubview:stack];
  [NSLayoutConstraint activateConstraints:@[
    [self.heightAnchor constraintEqualToConstant:32],
    [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8],
    [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-3],
    [stack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    [icon.widthAnchor constraintEqualToConstant:15],
    [icon.heightAnchor constraintEqualToConstant:15],
  ]];
  [self setMatchCount:-1 ordinal:-1];
  [self updateLayer];
  return self;
}
- (NSButton *)button:(NSString *)symbol label:(NSString *)label action:(SEL)action {
  NSButton *button = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:label] target:self action:action];
  button.bordered = NO;
  button.toolTip = label;
  button.accessibilityLabel = label;
  [button.widthAnchor constraintEqualToConstant:21].active = YES;
  [button.heightAnchor constraintEqualToConstant:26].active = YES;
  return button;
}
- (BOOL)isFlipped { return YES; }
- (BOOL)wantsUpdateLayer { return YES; }
- (void)updateLayer {
  self.layer.backgroundColor = NSColor.controlBackgroundColor.CGColor;
  self.layer.borderColor = NSColor.separatorColor.CGColor;
}
- (NSTextField *)textField { return _textField; }
- (NSString *)text { return _textField.stringValue; }
- (void)setText:(NSString *)text {
  MainThread();
  if (_invalidated) return;
  _textField.stringValue = text;
  self.selectedRange = _selection;
  [self updateButtons];
}
- (NSRange)selectedRange {
  MainThread();
  if (self.hasFindFocus && _textField.currentEditor) return _textField.currentEditor.selectedRange;
  return _selection;
}
- (void)setSelectedRange:(NSRange)range {
  MainThread();
  if (_invalidated) return;
  NSUInteger length = self.text.length;
  range.location = MIN(range.location, length);
  range.length = MIN(range.length, length - range.location);
  _selection = range;
  if (self.hasFindFocus) _textField.currentEditor.selectedRange = range;
}
- (NSString *)matchCountText { return _countLabel.stringValue; }
- (BOOL)isInvalidated { return _invalidated; }
- (BOOL)isPresented { return !_invalidated && !self.hidden && self.superview != nil; }
- (BOOL)hasMarkedText {
  return [(NSTextView *)_textField.currentEditor hasMarkedText];
}
- (BOOL)hasFindFocus {
  return !_invalidated && self.window && ResponderBelongsToField(self.window.firstResponder, _textField);
}
- (BOOL)attachToContainer:(NSView *)container topInset:(CGFloat)topInset
            focusManager:(PCNativeFocusManager *)manager focusKey:(NSString *)focusKey
            pageFocusKey:(NSString *)pageFocusKey {
  MainThread();
  __attribute__((objc_precise_lifetime)) PCNativeFindView *lifetime = self;
  (void)lifetime;
  if (_invalidated) return NO;
  auto validContext = [&]() { return container && manager && !manager.invalidated && container.window == manager.window &&
      container.window && focusKey.length && pageFocusKey.length && isfinite(topInset) && topInset >= 0; };
  BOOL valid = validContext();
  if (valid && _container == container && _focusManager == manager && [_focusKey isEqual:focusKey] && [_pageFocusKey isEqual:pageFocusKey]) {
    _topConstraint.constant = topInset;
    return YES;
  }
  if (![self detach]) return NO;
  if (_invalidated || !validContext()) return NO;
  _container = container;
  _focusManager = manager;
  _focusKey = [focusKey copy];
  _pageFocusKey = [pageFocusKey copy];
  [container addSubview:self positioned:NSWindowAbove relativeTo:nil];
  _topConstraint = [self.topAnchor constraintEqualToAnchor:container.topAnchor constant:topInset];
  NSLayoutConstraint *left = [self.leftAnchor constraintGreaterThanOrEqualToAnchor:container.leftAnchor constant:10];
  left.priority = 750;
  NSLayoutConstraint *width = [self.widthAnchor constraintEqualToConstant:300];
  width.priority = 250;
  _placement = @[_topConstraint, left, width, [self.rightAnchor constraintEqualToAnchor:container.rightAnchor constant:-10]];
  [NSLayoutConstraint activateConstraints:_placement];
  __weak PCNativeFindView *weakSelf = self;
  _registration = [manager registerResponder:_textField forKey:_focusKey didBecome:^{
    [weakSelf reportFocus:YES];
  } didResign:^{ [weakSelf reportFocus:NO]; }];
  if (!_registration) { [self detach]; return NO; }
  return YES;
}
- (BOOL)detach {
  NSUInteger generation = ++_attachmentGeneration;
  self.hidden = YES;
  if (generation != _attachmentGeneration) return NO;
  [_registration invalidate];
  _registration = nil;
  [NSLayoutConstraint deactivateConstraints:_placement ?: @[]];
  _placement = nil;
  _topConstraint = nil;
  [self removeFromSuperview];
  if (generation != _attachmentGeneration) return NO;
  _container = nil;
  _focusManager = nil;
  _focusKey = nil;
  _pageFocusKey = nil;
  _savedFocusKey = nil;
  _savedResponder = nil;
  _savedWindow = nil;
  _focusReported = NO;
  _restoreAfterHide = NO;
  _responderAfterHide = nil;
  return YES;
}
- (void)presentTakingFocus:(BOOL)focus {
  MainThread();
  if (_invalidated || !_container || !_registration) return;
  self.hidden = NO;
  if (focus) [self focusAndSelectAll];
}
- (void)focusAndSelectAll {
  MainThread();
  __attribute__((objc_precise_lifetime)) PCNativeFindView *lifetime = self;
  (void)lifetime;
  if (!self.isPresented) return;
  if (!self.hasFindFocus) {
    _savedFocusKey = _focusManager.focusedKey;
    if ([_savedFocusKey isEqual:_focusKey]) _savedFocusKey = nil;
    _savedResponder = StableResponder(self.window.firstResponder);
    _savedWindow = self.window;
  }
  PCNativeFocusRequestResult result = [_focusManager requestFocusForKey:_focusKey];
  if (!_invalidated && self.hasFindFocus && (result == PCNativeFocusRequestAccepted || result == PCNativeFocusRequestAlreadyFocused)) {
    self.selectedRange = NSMakeRange(0, self.text.length);
  }
}
- (void)dismiss {
  MainThread();
  __attribute__((objc_precise_lifetime)) PCNativeFindView *lifetime = self;
  (void)lifetime;
  if (_invalidated) return;
  _selection = self.selectedRange;
  _restoreAfterHide = self.hasFindFocus;
  self.hidden = YES;
  if (!_invalidated) _responderAfterHide = self.window.firstResponder;
}
- (void)restoreSavedFocus {
  MainThread();
  if (_invalidated || !self.window) return;
  // Do not steal focus from a control chosen after Find was dismissed.
  NSResponder *current = self.window.firstResponder;
  if (current && !ResponderBelongsToField(current, _textField) &&
      !(_restoreAfterHide && current == _responderAfterHide)) return;
  _restoreAfterHide = NO;
  _responderAfterHide = nil;
  NSString *saved = _savedFocusKey;
  NSResponder *responder = _savedResponder;
  NSWindow *window = _savedWindow;
  _savedFocusKey = nil;
  _savedResponder = nil;
  _savedWindow = nil;
  if (saved && [_focusManager requestFocusForKey:saved] != PCNativeFocusRequestRejected) return;
  if (window == self.window && SameWindow(responder, window) && [window makeFirstResponder:responder]) {
    [_focusManager reconcileFirstResponder];
    return;
  }
  [_focusManager requestFocusForKey:_pageFocusKey];
}
- (void)setMatchCount:(NSInteger)count ordinal:(NSInteger)ordinal {
  MainThread();
  if (_invalidated) return;
  _matchCount = count;
  _countLabel.stringValue = count < 0 || self.text.length == 0 ? @"" :
      count == 0 ? @"No results" :
      [NSString stringWithFormat:@"%ld / %ld", (long)MAX(0, ordinal), (long)count];
  [self updateButtons];
}
- (void)updateButtons {
  BOOL enabled = self.text.length > 0 && _matchCount != 0 && !_invalidated;
  _previousButton.enabled = enabled;
  _nextButton.enabled = enabled;
}
- (void)reportFocus:(BOOL)focused {
  if (_invalidated || _focusReported == focused) return;
  _focusReported = focused;
  id<PCNativeFindViewDelegate> delegate = self.delegate;
  [delegate findView:self didChangeFocus:focused];
}
- (void)perform:(PCNativeFindAction)action {
  if (_invalidated || !self.isPresented) return;
  id<PCNativeFindViewDelegate> delegate = self.delegate;
  NSString *text = [self.text copy];
  [delegate findView:self perform:action text:text];
}
- (void)previous:(id)sender { [self perform:PCNativeFindPrevious]; }
- (void)next:(id)sender { [self perform:PCNativeFindNext]; }
- (void)close:(id)sender { [self perform:PCNativeFindClose]; }
- (void)controlTextDidChange:(NSNotification *)notification {
  MainThread();
  if (notification.object != _textField) return;
  _selection = self.selectedRange;
  [self updateButtons];
  [self perform:PCNativeFindQueryChanged];
}
- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)selector {
  MainThread();
  if (_invalidated || control != _textField || !self.isPresented) return NO;
  if (selector == @selector(cancelOperation:)) [self perform:PCNativeFindClose];
  else if (selector == @selector(insertNewline:)) {
    [self perform:_searchBackwards ? PCNativeFindPrevious : PCNativeFindNext];
  } else if (selector == @selector(moveUp:)) [self perform:PCNativeFindPrevious];
  else if (selector == @selector(moveDown:)) [self perform:PCNativeFindNext];
  else return NO;
  return YES;
}
- (void)flagsChanged:(NSEvent *)event {
  [super flagsChanged:event];
  _searchBackwards = (event.modifierFlags & NSEventModifierFlagShift) != 0;
}
- (void)invalidate {
  MainThread();
  if (_invalidated) return;
  _invalidated = YES;
  self.delegate = nil;
  _textField.delegate = nil;
  [self detach];
  [self updateButtons];
}
- (void)dealloc { [_registration invalidate]; }
@end
