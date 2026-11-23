#import "extension_install_presenter.h"

#import "dialog_style.h"

#include <algorithm>
#include <cmath>

@interface PCExtensionInstallPresenter () <NSTextViewDelegate, NSTextFieldDelegate> {
  NSWindow* __weak _window;
  NSString* _title;
  NSImage* _icon;
  NSString* _heading;
  NSArray<NSString*>* _permissions;
  NSArray<NSString*>* _details;
  NSString* _acceptLabel;
  NSString* _cancelLabel;
  NSString* _checkboxLabel;
  NSString* _justificationLabel;
  NSString* _justificationPlaceholder;
  NSString* (^_justificationCounterText)(NSUInteger);
  NSTextView* _justificationInput;
  NSTextField* _justificationCounter;
  NSArray<NSString*>* _parentAccounts;
  NSArray<NSString*>* _parentInstructions;
  NSString* _parentPasswordLabel;
  void (^_parentSubmit)(NSInteger, NSString*);
  NSPopUpButton* _parentChoice;
  NSSecureTextField* _parentPassword;
  NSTextField* _parentError;
  NSProgressIndicator* _parentProgress;
  BOOL _parentPending;
  BOOL _installationEducation;
  BOOL (^_validate)(void);
  BOOL (^_inputAllowed)(NSWindow*);
  void (^_result)(PCExtensionInstallChoice, BOOL);
  NSWindow* _sheet;
  NSStackView* _stack;
  NSButton* _accept;
  NSButton* _checkbox;
  NSTimer* _timer;
  id _closeObserver;
  NSTimeInterval _allowAfter;
  BOOL _wasObstructed;
  BOOL _started;
  BOOL _finished;
  BOOL _invalidated;
}
- (void)accept:(id)sender;
- (void)cancel:(id)sender;
- (void)finish:(PCExtensionInstallChoice)choice;
@end
@interface PCExtensionJustificationTextView : NSTextView
@property(nonatomic, copy) NSString* placeholder;
@end
@implementation PCExtensionJustificationTextView
@synthesize placeholder = _placeholder;
- (void)drawRect:(NSRect)dirtyRect {
  [super drawRect:dirtyRect];
  if (!self.string.length && self.placeholder.length) {
    NSRect rect = NSInsetRect(self.bounds, self.textContainerInset.width + 5,
                             self.textContainerInset.height);
    [self.placeholder drawInRect:rect
                 withAttributes:@{
                   NSFontAttributeName : self.font ?: [NSFont systemFontOfSize:13],
                   NSForegroundColorAttributeName : NSColor.placeholderTextColor
                 }];
  }
}
@end
@interface PCExtensionInstallSheet : NSWindow
@property(nonatomic, weak) PCExtensionInstallPresenter* request;
@end
@implementation PCExtensionInstallSheet
@synthesize request = _request;
- (void)cancelOperation:(id)sender {
  [self.request finish:PCExtensionInstallCancel];
}
- (BOOL)performKeyEquivalent:(NSEvent*)event {
  NSResponder* responder = self.firstResponder;
  if (event.type == NSEventTypeKeyDown && [responder isKindOfClass:NSTextView.class] &&
      ((NSTextView*)responder).hasMarkedText) {
    return NO;
  }
  return [super performKeyEquivalent:event];
}
@end
using namespace parc_dialog;
@interface PCDialogFade : NSView
@end
@implementation PCDialogFade
- (BOOL)isFlipped {
  return YES;
}
- (NSView*)hitTest:(NSPoint)point {
  return nil;
}
- (void)drawRect:(NSRect)dirtyRect {
  NSColor* background = PopoverBackground();
  [[[NSGradient alloc] initWithStartingColor:[background colorWithAlphaComponent:.01]
                                 endingColor:background] drawInRect:self.bounds angle:90];
}
- (void)viewDidChangeEffectiveAppearance {
  self.needsDisplay = YES;
}
@end
@interface PCDialogExplainerDocument : PCDialogFlippedView
- (instancetype)initWithHeading:(NSString*)heading
                    permissions:(NSArray<NSString*>*)permissions
                        details:(NSArray<NSString*>*)details;
- (CGFloat)layOutForWidth:(CGFloat)width;
@end
@implementation PCDialogExplainerDocument {
  NSTextField* _heading;
  NSArray<NSTextField*>* _bullets;
  NSArray<NSTextField*>* _messages;
  NSArray<NSTextField*>* _details;
  CGFloat _bulletWidth;
}
- (instancetype)initWithHeading:(NSString*)heading
                    permissions:(NSArray<NSString*>*)permissions
                        details:(NSArray<NSString*>*)details {
  if ((self = [super initWithFrame:NSZeroRect])) {
    NSFont* font = [NSFont systemFontOfSize:14];
    _bulletWidth = [@"•" sizeWithAttributes:@{NSFontAttributeName : font}].width;
    _heading = Label(heading, font, PopoverMessage(), 1);
    [self addSubview:_heading];
    NSMutableArray* bullets = [NSMutableArray array];
    NSMutableArray* messages = [NSMutableArray array];
    NSMutableArray* extra = [NSMutableArray array];
    for (NSUInteger i = 0; i < permissions.count; ++i) {
      NSTextField* bullet = Label(@"•", font, PopoverMessage(), 1);
      [bullet setAccessibilityElement:NO];
      NSTextField* message = Label(permissions[i], font, PopoverMessage(), 1);
      NSTextField* detail = Label(details[i], font, PopoverMessage(), 1);
      detail.hidden = !details[i].length;
      for (NSTextField* label in @[ bullet, message, detail ]) [self addSubview:label];
      [bullets addObject:bullet];
      [messages addObject:message];
      [extra addObject:detail];
    }
    _bullets = bullets;
    _messages = messages;
    _details = extra;
  }
  return self;
}
- (CGFloat)layOutForWidth:(CGFloat)width {
  const CGFloat rowSpacing = 8.66, textX = 3 + _bulletWidth + 3 + 8;
  CGFloat y = 1 + PlaceLabel(_heading, 0, 1, width);
  for (NSUInteger i = 0; i < _messages.count; ++i) {
    y += rowSpacing + 1;
    PlaceLabel(_bullets[i], 3, y, _bulletWidth);
    y += PlaceLabel(_messages[i], textX, y, width - textX);
    if (!_details[i].hidden) y += 1 + PlaceLabel(_details[i], textX, y + 1, width - textX);
  }
  self.frame = NSMakeRect(0, 0, width, y);
  return y;
}
@end
@interface PCDialogExplainerScroll : NSScrollView
@property(nonatomic, weak) NSView* fade;
@end
@implementation PCDialogExplainerScroll
@synthesize fade = _fade;
- (void)tile {
  [super tile];
  PCDialogExplainerDocument* document = self.documentView;
  const CGFloat width = NSWidth(self.contentView.bounds);
  if (document && std::abs(NSWidth(document.frame) - width) > .5) {
    [document layOutForWidth:width];
  }
  [self updateFade];
}
- (void)reflectScrolledClipView:(NSClipView*)clipView {
  [super reflectScrolledClipView:clipView];
  [self updateFade];
}
- (void)updateFade {
  _fade.hidden = NSMaxY(self.contentView.bounds) >= NSHeight(self.documentView.frame) - .5;
}
@end
@implementation PCExtensionInstallPresenter
@synthesize presentation = _presentation;
@synthesize scheduler = _scheduler;
- (instancetype)initWithWindow:(NSWindow*)window
                         title:(NSString*)title
                          icon:(NSImage*)icon
                       heading:(NSString*)heading
                   permissions:(NSArray<NSString*>*)permissions
                       details:(NSArray<NSString*>*)details
                   acceptLabel:(NSString*)acceptLabel
                   cancelLabel:(NSString*)cancelLabel
                 checkboxLabel:(NSString*)checkboxLabel
                      validate:(BOOL (^)(void))validate
                  inputAllowed:(BOOL (^)(NSWindow*))inputAllowed
                        result:
                            (void (^)(PCExtensionInstallChoice, BOOL))result {
  NSParameterAssert(window && title.length &&
                    cancelLabel.length && permissions.count == details.count &&
                    validate && inputAllowed && result);
  if ((self = [super init])) {
    _window = window;
    _title = [title copy];
    _icon = icon;
    _heading = [heading copy];
    _permissions = [permissions copy];
    _details = [details copy];
    _acceptLabel = [acceptLabel copy];
    _cancelLabel = [cancelLabel copy];
    _checkboxLabel = [checkboxLabel copy];
    _validate = [validate copy];
    _inputAllowed = [inputAllowed copy];
    _result = [result copy];
    _presentation = PCNativeSystemPresentation.sharedPresentation;
    _scheduler = PCNativeSystemScheduling.sharedScheduling;
    __weak PCExtensionInstallPresenter* weak = self;
    _closeObserver = [NSNotificationCenter.defaultCenter
        addObserverForName:NSWindowWillCloseNotification
                    object:window
                     queue:nil
                usingBlock:^(NSNotification*) {
                  [weak invalidate];
                }];
  }
  return self;
}
- (void)configureJustificationLabel:(NSString*)label
                       placeholder:(NSString*)placeholder
                       counterText:(NSString* (^)(NSUInteger))counter {
  NSParameterAssert(!_started && label.length && counter);
  _justificationLabel = [label copy];
  _justificationPlaceholder = [placeholder copy];
  _justificationCounterText = [counter copy];
}
- (void)configureParentAccounts:(NSArray<NSString*>*)accounts
                   instructions:(NSArray<NSString*>*)instructions
                  passwordLabel:(NSString*)label
                         submit:(void (^)(NSInteger, NSString*))submit {
  NSParameterAssert(!_started && accounts.count && submit && label.length);
  _parentAccounts = [accounts copy];
  _parentInstructions = [instructions copy];
  _parentPasswordLabel = [label copy];
  _parentSubmit = [submit copy];
}
- (void)setParentApprovalPending:(BOOL)pending error:(NSString*)error {
  if (_finished) return;
  _parentPending = pending;
  _parentPassword.stringValue = @"";
  _parentPassword.enabled = !pending;
  _parentChoice.enabled = !pending;
  _parentError.stringValue = error;
  _parentProgress.hidden = !pending;
  if (pending) [_parentProgress startAnimation:nil];
  else {
    [_parentProgress stopAnimation:nil];
    [_sheet makeFirstResponder:_parentPassword];
    if (error.length)
      NSAccessibilityPostNotification(_parentError, NSAccessibilityValueChangedNotification);
  }
  _accept.enabled = [self acceptAllowed];
  [self fitStandardSheet:_sheet];
}
- (void)configureInstallationEducationWithName:(NSString*)name {
  NSParameterAssert(!_started && !_parentAccounts);
  _installationEducation = YES;
  _title = name.length
               ? [NSString stringWithFormat:@"Add the “%@” extension to Parc?", name]
               : @"Add this extension to Parc?";
  _heading = _permissions.count ? @"It can:"
                               : @"This extension requires no special permissions.";
  _acceptLabel = @"Add Extension";
  _cancelLabel = @"Cancel";
}
- (void)controlTextDidChange:(NSNotification*)notification {
  if (notification.object == _parentPassword)
    _accept.enabled = [self acceptAllowed];
}
- (NSString*)justification {
  return [_justificationInput.string copy] ?: @"";
}
- (void)textDidChange:(NSNotification*)notification {
  if (notification.object != _justificationInput || _finished) {
    return;
  }
  const NSUInteger length = _justificationInput.string.length;
  _justificationCounter.stringValue = _justificationCounterText(length);
  _justificationCounter.textColor =
      length <= 280 ? NSColor.secondaryLabelColor : NSColor.systemRedColor;
  _justificationInput.needsDisplay = YES;
  _accept.enabled = [self acceptAllowed];
}
- (BOOL)valid {
  __attribute__((objc_precise_lifetime)) PCExtensionInstallPresenter* keep =
      self;
  (void)keep;
  NSWindow* window = _window;
  if (_invalidated || !window || ![_presentation isWindowVisible:window] ||
      window.miniaturized) {
    return NO;
  }
  BOOL valid = _validate && _validate();
  return valid && !_invalidated && _window == window &&
         [_presentation isWindowVisible:window] && !window.miniaturized;
}
- (void)later:(void (^)(void))block {
  [_scheduler performInModes:@[ NSRunLoopCommonModes, NSModalPanelRunLoopMode ]
                       block:block];
}
- (BOOL)acceptAllowed {
  if (_finished || !_accept || ![_presentation isWindowVisible:_sheet] || ![self valid] ||
      _justificationInput.string.length > 280 || _parentPending ||
      (_parentAccounts && !_parentPassword.stringValue.length)) {
    return NO;
  }
  BOOL unobstructed = _inputAllowed && _inputAllowed(_sheet);
  if (_finished || !_sheet || ![self valid]) {
    return NO;
  }
  if (!unobstructed) {
    _wasObstructed = YES;
  } else if (_wasObstructed) {
    _wasObstructed = NO;
    _allowAfter = _scheduler.systemUptime + .5;
  }
  return unobstructed && _scheduler.systemUptime >= _allowAfter;
}
- (void)layOutPromptInSheet:(NSWindow*)sheet {
  PrepareSheet(sheet);
  const CGFloat dialogWidth = kWidth, inset = kInset, width = dialogWidth - 2 * inset;
  PCDialogBaseView* root = [[PCDialogBaseView alloc] initWithFrame:NSZeroRect];
  CGFloat y = inset;

  NSRect markRect;
  NSImage* mark = ParcMark(&markRect);
  PCDialogPictureIcon* app = [[PCDialogPictureIcon alloc] initWithImage:mark imageRect:markRect];
  app.frameOrigin = NSMakePoint(inset, y);
  NSImageView* arrow = [NSImageView imageViewWithImage:
      [NSImage imageWithSystemSymbolName:@"arrow.left" accessibilityDescription:nil]];
  arrow.symbolConfiguration =
      [NSImageSymbolConfiguration configurationWithPointSize:28 weight:NSFontWeightRegular];
  arrow.contentTintColor = PopoverArrowIcon();
  arrow.imageScaling = NSImageScaleNone;
  arrow.frame = NSMakeRect(inset + 62, y, 62, 62);
  NSImageView* extension = ExtensionArt(_icon);
  extension.frameOrigin = NSMakePoint(inset + 124, y);
  for (NSView* view in @[ app, arrow, extension ]) {
    [view setAccessibilityElement:NO];
    [root addSubview:view];
  }
  y += 62;

  y = AddHeading(root, _title, nil, y, 0);

  NSFont* body = BodyFont();
  if (_permissions.count) {
    PCDialogExplainerDocument* document =
        [[PCDialogExplainerDocument alloc] initWithHeading:_heading
                                               permissions:_permissions
                                                   details:_details];
    CGFloat contentHeight = [document layOutForWidth:width];
    if (contentHeight > 113 && NSScroller.preferredScrollerStyle == NSScrollerStyleLegacy) {
      contentHeight = [document layOutForWidth:width - [NSScroller
          scrollerWidthForControlSize:NSControlSizeRegular scrollerStyle:NSScrollerStyleLegacy]];
    }
    const CGFloat visibleHeight = std::min<CGFloat>(contentHeight, 113);
    PCDialogExplainerScroll* scroll =
        [[PCDialogExplainerScroll alloc] initWithFrame:NSMakeRect(inset, y, width, visibleHeight)];
    scroll.drawsBackground = NO;
    scroll.contentView.drawsBackground = NO;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.documentView = document;
    PCDialogFade* fade = [[PCDialogFade alloc]
        initWithFrame:NSMakeRect(inset, y + visibleHeight - 26, width, 26)];
    fade.hidden = contentHeight <= visibleHeight;
    scroll.fade = fade;
    [root addSubview:scroll];
    [root addSubview:fade];
    y += visibleHeight;
  } else if (_heading.length) {
    NSTextField* heading = Label(_heading, body, PopoverMessage(), 1);
    [root addSubview:heading];
    y += PlaceLabel(heading, inset, y, width) + 8;
  }
  y += 8;

  PCDialogButton* cancel = [[PCDialogButton alloc] initWithTitle:_cancelLabel primary:NO];
  cancel.target = self;
  cancel.action = @selector(cancel:);
  cancel.keyEquivalent = @"\033";
  _accept = [[PCDialogButton alloc] initWithTitle:_acceptLabel primary:YES];
  _accept.target = self;
  _accept.action = @selector(accept:);
  _accept.keyEquivalent = @"\r";
  _accept.enabled = NO;
  if (_checkboxLabel.length) {
    _checkbox = [[PCDialogCheckbox alloc] initWithTitle:_checkboxLabel target:nil action:nil];
  }
  y = PlaceFooter(root, y, _checkbox, @[ _accept, cancel ]);
  root.frame = NSMakeRect(0, 0, dialogWidth, y);
  sheet.contentView = root;
  [sheet setContentSize:NSMakeSize(dialogWidth, y)];
}
- (void)fitStandardSheet:(NSWindow*)sheet {
  [sheet.contentView layoutSubtreeIfNeeded];
  [sheet setContentSize:NSMakeSize(
      kWidth, MAX(230, ceil(_stack.fittingSize.height) + kInset + 22 + 38.5 + 28))];
}
- (void)layOutStandardInSheet:(NSWindow*)sheet {
  PrepareSheet(sheet);
  PCDialogBaseView* root = [[PCDialogBaseView alloc] initWithFrame:NSMakeRect(0, 0, kWidth, 320)];
  sheet.contentView = root;
  const CGFloat width = kWidth - 2 * kInset;
  NSStackView* stack = [NSStackView stackViewWithViews:@[]];
  _stack = stack;
  stack.orientation = NSUserInterfaceLayoutOrientationVertical;
  stack.alignment = NSLayoutAttributeLeading;
  stack.spacing = 12;
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  auto addLabel = ^NSTextField*(NSString* text, NSFont* font, NSColor* color, CGFloat spacing) {
    NSTextField* label = Label(text, font, color, spacing);
    label.preferredMaxLayoutWidth = width;
    [stack addArrangedSubview:label];
    [label.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    return label;
  };
  if (_icon) {
    NSImageView* image = ExtensionArt(_icon);
    [image.widthAnchor constraintEqualToConstant:kArtSize].active = YES;
    [image.heightAnchor constraintEqualToConstant:kArtSize].active = YES;
    [stack addArrangedSubview:image];
    [stack setCustomSpacing:17 afterView:image];
  }
  NSTextField* title = addLabel(_title, TitleFont(), PopoverTitle(), 4);
  [stack setCustomSpacing:8 afterView:title];
  if (_heading.length) {
    addLabel(_heading, BodyFont(), PopoverMessage(), 1);
  }
  NSStackView* list = [NSStackView stackViewWithViews:@[]];
  list.orientation = NSUserInterfaceLayoutOrientationVertical;
  list.alignment = NSLayoutAttributeLeading;
  list.spacing = 10;
  list.translatesAutoresizingMaskIntoConstraints = NO;
  for (NSUInteger i = 0; i < _permissions.count; ++i) {
    NSTextField* permission =
        Label([@"• " stringByAppendingString:_permissions[i]], BodyFont(), PopoverMessage(), 1);
    [list addArrangedSubview:permission];
    [permission.widthAnchor constraintEqualToAnchor:list.widthAnchor].active = YES;
    if (_details[i].length) {
      NSTextField* detail = Label(_details[i], BodyFont(), PopoverMessage(), 1);
      [list addArrangedSubview:detail];
      [detail.widthAnchor constraintEqualToAnchor:list.widthAnchor].active = YES;
    }
  }
  NSScrollView* scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
  scroll.hasVerticalScroller = YES;
  scroll.drawsBackground = NO;
  scroll.contentView.drawsBackground = NO;
  scroll.documentView = list;
  [NSLayoutConstraint activateConstraints:@[
    [list.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor],
    [list.leadingAnchor constraintEqualToAnchor:scroll.contentView.leadingAnchor],
    [list.topAnchor constraintEqualToAnchor:scroll.contentView.topAnchor],
  ]];
  [stack addArrangedSubview:scroll];
  [scroll.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
  CGFloat permissionHeight = _permissions.count
      ? (_parentAccounts.count ? 160 : 220) : 0;
  [scroll.heightAnchor constraintEqualToConstant:permissionHeight].active = YES;
  if (_checkboxLabel.length) {
    _checkbox = [[PCDialogCheckbox alloc] initWithTitle:_checkboxLabel target:nil action:nil];
    [stack addArrangedSubview:_checkbox];
    [_checkbox.widthAnchor constraintLessThanOrEqualToAnchor:stack.widthAnchor].active = YES;
  }
  if (_justificationLabel.length) {
    NSTextField* label = addLabel(_justificationLabel, BodyFont(), PopoverMessage(), 1);
    [stack setCustomSpacing:8 afterView:label];
    PCDialogCard* card = [[PCDialogCard alloc] initWithFrame:NSMakeRect(0, 0, width, 72)];
    NSScrollView* editor = [[NSScrollView alloc] initWithFrame:NSInsetRect(card.bounds, 4, 4)];
    editor.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    editor.borderType = NSNoBorder;
    editor.drawsBackground = NO;
    editor.contentView.drawsBackground = NO;
    editor.hasVerticalScroller = YES;
    editor.autohidesScrollers = YES;
    PCExtensionJustificationTextView* input =
        [[PCExtensionJustificationTextView alloc]
            initWithFrame:NSMakeRect(0, 0, width - 8, 64)];
    input.font = BodyFont();
    input.textColor = PopoverTitle();
    input.drawsBackground = NO;
    input.richText = NO;
    input.importsGraphics = NO;
    input.verticallyResizable = YES;
    input.horizontallyResizable = NO;
    input.autoresizingMask = NSViewWidthSizable;
    input.textContainer.widthTracksTextView = YES;
    input.textContainerInset = NSMakeSize(4, 4);
    input.placeholder = _justificationPlaceholder;
    input.delegate = self;
    [input setAccessibilityLabel:_justificationLabel];
    _justificationInput = input;
    editor.documentView = input;
    [card addSubview:editor];
    card.field = input;
    [stack addArrangedSubview:card];
    [card.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    [card.heightAnchor constraintEqualToConstant:72].active = YES;
    [stack setCustomSpacing:6 afterView:card];
    _justificationCounter = [NSTextField
        labelWithString:_justificationCounterText(0)];
    _justificationCounter.font = [NSFont systemFontOfSize:11];
    _justificationCounter.textColor = NSColor.secondaryLabelColor;
    [stack addArrangedSubview:_justificationCounter];
  }
  if (_parentAccounts.count) {
    for (NSString* instruction in _parentInstructions) {
      addLabel(instruction, BodyFont(), PopoverMessage(), 1);
    }
    _parentChoice = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_parentChoice addItemsWithTitles:_parentAccounts];
    _parentChoice.accessibilityLabel = @"Parent account";
    [stack addArrangedSubview:_parentChoice];
    NSTextField* passwordLabel = addLabel(_parentPasswordLabel,
        [NSFont systemFontOfSize:13 weight:NSFontWeightMedium], PopoverMessage(), 0);
    [stack setCustomSpacing:6 afterView:passwordLabel];
    PCDialogInputField* password = [[PCDialogInputField alloc] initWithText:@"" secure:YES];
    _parentPassword = (NSSecureTextField*)password.field;
    _parentPassword.delegate = self;
    _parentPassword.accessibilityLabel = _parentPasswordLabel;
    [stack addArrangedSubview:password];
    [password.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    [password.heightAnchor constraintEqualToConstant:36].active = YES;
    _parentError = [NSTextField wrappingLabelWithString:@""];
    _parentError.font = BodyFont();
    _parentError.textColor = NSColor.systemRedColor;
    _parentError.preferredMaxLayoutWidth = width;
    [stack addArrangedSubview:_parentError];
    [_parentError.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    [_parentError.heightAnchor constraintGreaterThanOrEqualToConstant:32].active = YES;
    _parentProgress = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _parentProgress.style = NSProgressIndicatorStyleSpinning;
    _parentProgress.controlSize = NSControlSizeSmall;
    _parentProgress.indeterminate = YES;
    _parentProgress.hidden = YES;
    [stack addArrangedSubview:_parentProgress];
  }
  PCDialogButton* cancel = [[PCDialogButton alloc] initWithTitle:_cancelLabel primary:NO];
  cancel.target = self;
  cancel.action = @selector(cancel:);
  cancel.keyEquivalent = @"\033";
  NSStackView* buttons = [NSStackView stackViewWithViews:@[]];
  buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  buttons.spacing = 8;
  buttons.translatesAutoresizingMaskIntoConstraints = NO;
  NSMutableArray<PCDialogButton*>* buttonViews = [NSMutableArray arrayWithObject:cancel];
  if (_acceptLabel.length) {
    PCDialogButton* accept = [[PCDialogButton alloc] initWithTitle:_acceptLabel primary:YES];
    accept.target = self;
    accept.action = @selector(accept:);
    accept.enabled = NO;
    accept.keyEquivalent = @"";
    accept.showsHint = NO;
    _accept = accept;
    [buttonViews addObject:accept];
  }
  for (PCDialogButton* button in buttonViews) {
    [button.widthAnchor constraintEqualToConstant:button.bodyWidth + 1].active = YES;
    [button.heightAnchor constraintEqualToConstant:38.5].active = YES;
    [buttons addView:button inGravity:NSStackViewGravityTrailing];
  }
  [root addSubview:stack];
  [root addSubview:buttons];
  [NSLayoutConstraint activateConstraints:@[
    [stack.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:kInset],
    [stack.widthAnchor constraintEqualToConstant:width],
    [stack.topAnchor constraintEqualToAnchor:root.topAnchor constant:kInset],
    [buttons.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-27.5],
    [buttons.topAnchor constraintEqualToAnchor:stack.bottomAnchor constant:22],
  ]];
  [self fitStandardSheet:sheet];
}
- (void)start {
  NSCAssert(NSThread.isMainThread, @"UI thread required");
  if (_started || _finished) {
    return;
  }
  _started = YES;
  [self later:^{
    if (self->_finished) {
      return;
    }
    __attribute__((objc_precise_lifetime)) NSWindow* window = self->_window;
    id<PCNativePresentation> presentation = self->_presentation;
    id<PCNativeScheduling> scheduler = self->_scheduler;
    if (![self valid] || !window || [presentation attachedSheetOfWindow:window]) {
      [self finish:PCExtensionInstallInterrupted];
      return;
    }
    PCExtensionInstallSheet* sheet = [[PCExtensionInstallSheet alloc]
        initWithContentRect:NSMakeRect(0, 0, kWidth, 320)
                  styleMask:NSWindowStyleMaskTitled
                    backing:NSBackingStoreBuffered
                      defer:NO];
    sheet.releasedWhenClosed = NO;
    sheet.title = self->_title;
    sheet.request = self;
    if (self->_installationEducation) {
      [self layOutPromptInSheet:sheet];
    } else {
      [self layOutStandardInSheet:sheet];
    }
    if (self->_finished || ![self valid] || [presentation attachedSheetOfWindow:window]) {
      [self finish:PCExtensionInstallInterrupted];
      return;
    }
    self->_sheet = sheet;
    [presentation window:window
               beginSheet:sheet
        completionHandler:^(NSModalResponse) {
          [self finish:PCExtensionInstallInterrupted];
        }];
    if (self->_finished || ![self valid] || [presentation sheetParentOfWindow:sheet] != window ||
        [presentation attachedSheetOfWindow:window] != sheet ||
        ![presentation isWindowVisible:sheet]) {
      [self finish:PCExtensionInstallInterrupted];
      return;
    }
    if (self->_parentPassword) [sheet makeFirstResponder:self->_parentPassword];
    self->_allowAfter = scheduler.systemUptime + .5;
    __weak PCExtensionInstallPresenter* weak = self;
    self->_timer = [scheduler
        timerWithTimeInterval:.05
                      repeats:YES
                        block:^(NSTimer*) {
                          PCExtensionInstallPresenter* strong = weak;
                          if (!strong || strong->_finished) {
                            return;
                          }
                          if (![strong valid]) {
                            [strong finish:PCExtensionInstallInterrupted];
                            return;
                          }
                          strong->_accept.enabled = [strong acceptAllowed];
                        }];
    [scheduler addTimer:self->_timer forMode:NSRunLoopCommonModes];
    [scheduler addTimer:self->_timer forMode:NSModalPanelRunLoopMode];
  }];
}
- (void)accept:(NSButton*)sender {
  if (sender != _accept || sender.window != _sheet || ![self acceptAllowed]) {
    return;
  }
  NSEvent* key = [sender isKindOfClass:PCDialogButton.class]
                     ? ((PCDialogButton*)sender).keyEvent
                     : nil;
  if (key && (key.isARepeat || key.timestamp < _allowAfter)) {
    return;
  }
  if (_parentSubmit) {
    NSString* credential = [_parentPassword.stringValue copy];
    NSInteger parent = _parentChoice.indexOfSelectedItem;
    _parentPassword.stringValue = @"";
    auto submit = _parentSubmit;
    submit(parent, credential);
    return;
  }
  [self finish:PCExtensionInstallAccept];
}
- (void)cancel:(NSButton*)sender {
  if (sender.window != _sheet) {
    return;
  }
  [self finish:PCExtensionInstallCancel];
}
- (void)finish:(PCExtensionInstallChoice)choice {
  if (_finished) {
    return;
  }
  _finished = YES;
  _parentPassword.stringValue = @"";
  _parentSubmit = nil;
  [_parentProgress stopAnimation:nil];
  [_timer invalidate];
  _timer = nil;
  BOOL checked = _checkbox && _checkbox.state == NSControlStateValueOn;
  NSWindow* sheet = _sheet;
  _sheet = nil;
  if ([_presentation sheetParentOfWindow:sheet]) {
    [_presentation window:[_presentation sheetParentOfWindow:sheet] endSheet:sheet];
  }
  [_presentation orderOutWindow:sheet];
  [self later:^{
    if (!self->_result) {
      return;
    }
    BOOL valid = [self valid];
    if (choice == PCExtensionInstallAccept) {
      valid = valid && self->_inputAllowed && self->_inputAllowed(sheet) &&
              [self valid];
    }
    auto result = self->_result;
    self->_result = nil;
    self->_validate = nil;
    self->_inputAllowed = nil;
    result(valid ? choice : PCExtensionInstallInterrupted, checked);
  }];
}
- (void)invalidate {
  _invalidated = YES;
  [self finish:PCExtensionInstallInterrupted];
}
- (NSWindow*)sheet {
  return _sheet;
}
- (void)dealloc {
  [_timer invalidate];
  if (_closeObserver) {
    [NSNotificationCenter.defaultCenter removeObserver:_closeObserver];
  }
  NSCAssert(!_sheet, @"Owner must invalidate presented consent");
}
@end
