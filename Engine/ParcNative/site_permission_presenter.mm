#import "site_permission_presenter.h"

//
//
// the recovered opacities, chosen by the view's appearance.
static BOOL PCPromptDark(NSView* view) {
  NSAppearanceName match = [view.effectiveAppearance
      bestMatchFromAppearancesWithNames:@[
        NSAppearanceNameAqua, NSAppearanceNameDarkAqua
      ]];
  return [match isEqualToString:NSAppearanceNameDarkAqua];
}
static NSColor* PCPromptWhite(CGFloat alpha) {
  return [NSColor colorWithWhite:1 alpha:alpha];
}
static NSColor* PCPromptBlack(CGFloat alpha) {
  return [NSColor colorWithWhite:0 alpha:alpha];
}
// Title, button text and icon: white (dark) or black (light) at 66%
//
static NSColor* PCPromptForeground(BOOL dark) {
  return dark ? PCPromptWhite(0.66) : PCPromptBlack(0.66);
}
static NSColor* PCPromptIconForeground(BOOL dark) {
  return PCPromptForeground(dark);
}

// The 14-point title, recolored with the popover's appearance.
@interface PCPromptTitle : NSTextField
@end
@implementation PCPromptTitle
- (void)viewDidChangeEffectiveAppearance {
  [super viewDidChangeEffectiveAppearance];
  self.textColor = PCPromptForeground(PCPromptDark(self));
}
@end

// The 32-point icon circle: white 5% in dark, black 8% in light.
@interface PCPromptIcon : NSView
@property(nonatomic, copy) NSString* symbol;
@property(nonatomic) CGFloat pointSize;
@property(nonatomic) BOOL bold;
@property(nonatomic) CGFloat offsetY;
@end
@implementation PCPromptIcon
@synthesize symbol = _symbol;
@synthesize pointSize = _pointSize;
@synthesize bold = _bold;
@synthesize offsetY = _offsetY;
- (BOOL)isFlipped {
  return YES;
}
- (NSSize)intrinsicContentSize {
  return NSMakeSize(32, 32);
}
- (void)viewDidChangeEffectiveAppearance {
  [super viewDidChangeEffectiveAppearance];
  self.needsDisplay = YES;
}
- (void)drawRect:(NSRect)dirty {
  const BOOL dark = PCPromptDark(self);
  NSRect circle = NSMakeRect(0, 0, 32, 32);
  [(dark ? PCPromptWhite(0.05) : PCPromptBlack(0.08)) set];
  [[NSBezierPath bezierPathWithOvalInRect:circle] fill];
  NSImage* image = [NSImage imageWithSystemSymbolName:_symbol
                             accessibilityDescription:nil];
  if (!image) {
    image = [NSImage imageWithSystemSymbolName:@"gearshape.fill"
                      accessibilityDescription:nil];
  }
  NSImageSymbolConfiguration* configuration = [[NSImageSymbolConfiguration
      configurationWithPointSize:_pointSize
                          weight:_bold ? NSFontWeightBold : NSFontWeightMedium]
      configurationByApplyingConfiguration:
          [NSImageSymbolConfiguration configurationWithHierarchicalColor:
                                          PCPromptIconForeground(dark)]];
  image = [image imageWithSymbolConfiguration:configuration];
  NSSize size = image.size;
  // SwiftUI's offset moves the glyph; a negative y lifts it.
  NSRect target = NSMakeRect(16 - size.width / 2, 16 - size.height / 2 + _offsetY,
                             size.width, size.height);
  [image drawInRect:target
           fromRect:NSZeroRect
          operation:NSCompositingOperationSourceOver
           fraction:1
     respectFlipped:YES
              hints:nil];
}
@end

// ActionButton: 32 high, radius 6. Primary: white 20% (dark) or white (light)
// under a white-to-black-22% top-to-bottom gradient at 5% (dark) or 13%
// (light), a 1-point inner top highlight (white 22% / 8%) and an outer
// 0.25-point hairline (black 87% / 50%). Secondary: white 5% (dark) or black
// 13% (light). Light buttons cast a black 11% shadow, radius 2, 1 down.
@interface PCPromptButton : NSButton
@property(nonatomic) BOOL primary;
@end
@implementation PCPromptButton
@synthesize primary = _primary;
- (instancetype)initWithTitle:(NSString*)title primary:(BOOL)primary {
  if ((self = [super initWithFrame:NSMakeRect(0, 0, 100, 32)])) {
    _primary = primary;
    self.title = title;
    self.bordered = NO;
    self.buttonType = NSButtonTypeMomentaryChange;
    self.wantsLayer = YES;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    [self updateShadow];
  }
  return self;
}
- (NSSize)intrinsicContentSize {
  return NSMakeSize(NSViewNoIntrinsicMetric, 32);
}
- (void)updateShadow {
  if (PCPromptDark(self)) {
    self.shadow = nil;
    return;
  }
  NSShadow* shadow = [NSShadow new];
  shadow.shadowColor = PCPromptBlack(0.11);
  shadow.shadowBlurRadius = 2;
  shadow.shadowOffset = NSMakeSize(0, -1);
  self.shadow = shadow;
}
- (void)viewDidChangeEffectiveAppearance {
  [super viewDidChangeEffectiveAppearance];
  [self updateShadow];
  self.needsDisplay = YES;
}
- (void)drawRect:(NSRect)dirty {
  const BOOL dark = PCPromptDark(self);
  const NSRect bounds = self.bounds;
  //
  // with no hover state or animation modifier; the style's feedback is the
  // whole button at 75% while pressed (measured on macOS 27 SwiftUI; any
  // framework fade was unobservable, so it is treated as instant). WEB19.
  CGContextRef context = NSGraphicsContext.currentContext.CGContext;
  const BOOL pressed = self.isHighlighted;
  if (pressed) {
    CGContextSaveGState(context);
    CGContextSetAlpha(context, 0.75);
    CGContextBeginTransparencyLayer(context, NULL);
  }
  NSBezierPath* shape = [NSBezierPath bezierPathWithRoundedRect:bounds
                                                        xRadius:6
                                                        yRadius:6];
  [NSGraphicsContext saveGraphicsState];
  [shape addClip];
  [(_primary ? (dark ? PCPromptWhite(0.2) : PCPromptWhite(1))
             : (dark ? PCPromptWhite(0.05) : PCPromptBlack(0.13))) set];
  NSRectFill(bounds);
  if (_primary) {
    NSGradient* gradient = [[NSGradient alloc]
        initWithStartingColor:PCPromptWhite(dark ? 0.05 : 0.13)
                  endingColor:PCPromptBlack(0.22 * (dark ? 0.05 : 0.13))];
    // The view is flipped: 90 degrees runs from the top edge down.
    [gradient drawInRect:bounds angle:90];
    NSBezierPath* highlight = [NSBezierPath
        bezierPathWithRoundedRect:NSOffsetRect(NSInsetRect(bounds, -0.5, -0.5),
                                               0, 1)
                          xRadius:6.5
                          yRadius:6.5];
    highlight.lineWidth = 1;
    [(dark ? PCPromptWhite(0.22) : PCPromptWhite(0.08)) set];
    [highlight stroke];
  }
  [NSGraphicsContext restoreGraphicsState];
  if (_primary) {
    NSBezierPath* hairline = [NSBezierPath
        bezierPathWithRoundedRect:NSInsetRect(bounds, -0.25, -0.25)
                          xRadius:6.25
                          yRadius:6.25];
    hairline.lineWidth = 0.25;
    [(dark ? PCPromptBlack(0.87) : PCPromptBlack(0.5)) set];
    [hairline stroke];
  }
  NSMutableParagraphStyle* paragraph = [NSMutableParagraphStyle new];
  paragraph.alignment = NSTextAlignmentCenter;
  paragraph.lineBreakMode = NSLineBreakByTruncatingTail;
  NSDictionary* attributes = @{
    NSFontAttributeName : [NSFont systemFontOfSize:14
                                            weight:NSFontWeightSemibold],
    NSForegroundColorAttributeName : PCPromptForeground(dark),
    NSParagraphStyleAttributeName : paragraph,
  };
  NSSize text = [self.title sizeWithAttributes:attributes];
  NSRect line = NSMakeRect(4, (bounds.size.height - text.height) / 2,
                           MAX(0, bounds.size.width - 8), text.height);
  [self.title drawInRect:line withAttributes:attributes];
  if (pressed) {
    CGContextEndTransparencyLayer(context);
    CGContextRestoreGState(context);
  }
}
@end

@interface PCSitePermissionPresenter () <NSPopoverDelegate> {
  __weak NSView* _page;
  __weak NSWindow* _window;
  NSString* _title;
  NSString* _symbol;
  CGFloat _symbolPointSize;
  BOOL _symbolBold;
  CGFloat _symbolOffsetY;
  NSString* _followUpTitle;
  NSArray<NSString*>* _followUpLabels;
  NSArray<NSNumber*>* _followUpChoices;
  void (^_systemAction)(PCSitePermissionChoice);
  NSProgressIndicator* _systemProgress;
  NSTextField* _systemStatus;
  NSButton* _systemRequestButton;
  BOOL (^_validate)(void);
  void (^_presented)(void);
  void (^_result)(PCSitePermissionChoice, BOOL);
  NSPopover* _popover;
  NSView* _card;
  PCSiteLocationMode _locationMode;
  BOOL _precise;
  id _closeObserver;
  id _sheetObserver;
  BOOL _started;
  BOOL _finished;
  BOOL _invalidated;
}
- (void)choose:(id)sender;
- (void)finish:(PCSitePermissionChoice)choice;
@end

// Shown prompts, so a second request in the same window refuses rather than
// stacking a popover (a sheet used to refuse through attachedSheet).
static NSHashTable<PCSitePermissionPresenter*>* PCShownPrompts(void) {
  static NSHashTable* table = [NSHashTable weakObjectsHashTable];
  return table;
}

static void Later(void (^block)(void)) {
  [NSRunLoop.mainRunLoop
      performInModes:@[ NSRunLoopCommonModes, NSModalPanelRunLoopMode ]
               block:block];
}

@implementation PCSitePermissionPresenter
- (instancetype)initWithPage:(NSView*)page
                      window:(NSWindow*)window
                       title:(NSString*)title
                locationMode:(PCSiteLocationMode)locationMode
              initialPrecise:(BOOL)initialPrecise
                    validate:(BOOL (^)(void))validate
                   presented:(void (^)(void))presented
                      result:(void (^)(PCSitePermissionChoice, BOOL))result {
  NSParameterAssert(page && window && title.length && validate && presented &&
                    result);
  NSCAssert(NSThread.isMainThread, @"UI thread required");
  if ((self = [super init])) {
    _page = page;
    _window = window;
    _title = [title copy];
    _symbol = @"gearshape.fill";
    _symbolPointSize = 14;
    _locationMode = locationMode;
    //
    _precise = locationMode == PCSiteLocationUpgradeToPrecise ||
               (locationMode == PCSiteLocationApproximateOrPrecise &&
                initialPrecise);
    _validate = [validate copy];
    _presented = [presented copy];
    _result = [result copy];
    __weak PCSitePermissionPresenter* weak = self;
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
- (void)configureSymbol:(NSString*)name
              pointSize:(CGFloat)pointSize
                   bold:(BOOL)bold
                offsetY:(CGFloat)offsetY {
  NSCAssert(NSThread.isMainThread && !_started,
            @"Configure before presentation");
  _symbol = [name copy];
  _symbolPointSize = pointSize;
  _symbolBold = bold;
  _symbolOffsetY = offsetY;
}
- (void)configureFollowUpWithTitle:(NSString*)title
                           labels:(NSArray<NSString*>*)labels
                          choices:(NSArray<NSNumber*>*)choices
                     systemAction:(void (^)(PCSitePermissionChoice))action {
  NSCAssert(NSThread.isMainThread && !_started, @"Configure before presentation");
  NSParameterAssert(title.length && labels.count == choices.count && action);
  _followUpTitle = [title copy];
  _followUpLabels = [labels copy];
  _followUpChoices = [choices copy];
  _systemAction = [action copy];
}
- (void)resizePopover {
  [_card layoutSubtreeIfNeeded];
  _popover.contentSize = _card.fittingSize;
}
- (void)setSystemRequestPending:(BOOL)pending {
  NSCAssert(NSThread.isMainThread, @"UI thread required");
  if (_finished) return;
  _systemRequestButton.enabled = !pending;
  _systemProgress.hidden = !pending;
  if (pending) [_systemProgress startAnimation:nil];
  else [_systemProgress stopAnimation:nil];
  _systemStatus.stringValue = pending
      ? @"Respond to the macOS permission request to continue."
      : @"macOS has not returned a permission decision. Continue to request access again.";
  [self resizePopover];
}
- (BOOL)valid {
  __attribute__((objc_precise_lifetime)) PCSitePermissionPresenter* keep = self;
  (void)keep;
  NSView* page = _page;
  NSWindow* window = _window;
  if (_invalidated || !page || !window || page.window != window ||
      !window.visible || window.miniaturized ||
      page.hiddenOrHasHiddenAncestor) {
    return NO;
  }
  BOOL valid = _validate && _validate();
  return valid && !_invalidated && _page == page && _window == window &&
         page.window == window && window.visible && !window.miniaturized &&
         !page.hiddenOrHasHiddenAncestor;
}
- (NSView*)buildCard {
  NSView* card = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 236, 120)];
  card.translatesAutoresizingMaskIntoConstraints = NO;
  // Top row: icon, 8 points, the 14-point title (66% black or white).
  PCPromptIcon* icon = [PCPromptIcon new];
  icon.symbol = _symbol;
  icon.pointSize = _symbolPointSize;
  icon.bold = _symbolBold;
  icon.offsetY = _symbolOffsetY;
  icon.translatesAutoresizingMaskIntoConstraints = NO;
  PCPromptTitle* title = [PCPromptTitle wrappingLabelWithString:_followUpTitle ?: _title];
  title.font = [NSFont systemFontOfSize:14 weight:NSFontWeightRegular];
  title.textColor = PCPromptForeground(PCPromptDark(_page ?: card));
  title.preferredMaxLayoutWidth = 216 - 32 - 8;
  title.translatesAutoresizingMaskIntoConstraints = NO;
  [card addSubview:icon];
  [card addSubview:title];
  //
  // taller than the icon aligns the icon to its top, otherwise centers it.
  const BOOL tall = title.fittingSize.height > 32;
  NSMutableArray<NSLayoutConstraint*>* constraints = [NSMutableArray arrayWithArray:@[
    [card.widthAnchor constraintEqualToConstant:236],
    [icon.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:10],
    [icon.widthAnchor constraintEqualToConstant:32],
    [icon.heightAnchor constraintEqualToConstant:32],
    [title.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:8],
    [title.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor
                                                   constant:-10],
  ]];
  if (tall) {
    [constraints addObjectsFromArray:@[
      [title.topAnchor constraintEqualToAnchor:card.topAnchor constant:10],
      [icon.topAnchor constraintEqualToAnchor:title.topAnchor],
    ]];
  } else {
    [constraints addObjectsFromArray:@[
      [icon.topAnchor constraintEqualToAnchor:card.topAnchor constant:10],
      [title.centerYAnchor constraintEqualToAnchor:icon.centerYAnchor],
    ]];
  }
  NSView* above = tall ? (NSView*)title : (NSView*)icon;
  // A permission-element stage awaiting macOS shows its progress and status
  //
  if ([_followUpChoices containsObject:@(PCSitePermissionRequestSystem)]) {
    _systemProgress = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _systemProgress.style = NSProgressIndicatorStyleSpinning;
    _systemProgress.controlSize = NSControlSizeSmall;
    _systemProgress.indeterminate = YES;
    _systemProgress.translatesAutoresizingMaskIntoConstraints = NO;
    _systemStatus = [NSTextField wrappingLabelWithString:
        @"Respond to the macOS permission request to continue."];
    _systemStatus.textColor = NSColor.secondaryLabelColor;
    _systemStatus.font = [NSFont systemFontOfSize:12];
    _systemStatus.preferredMaxLayoutWidth = 216;
    _systemStatus.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:_systemProgress];
    [card addSubview:_systemStatus];
    [constraints addObjectsFromArray:@[
      [_systemProgress.leadingAnchor constraintEqualToAnchor:card.leadingAnchor
                                                    constant:10],
      [_systemProgress.topAnchor constraintEqualToAnchor:above.bottomAnchor
                                                constant:16],
      [_systemStatus.leadingAnchor
          constraintEqualToAnchor:_systemProgress.trailingAnchor
                         constant:8],
      [_systemStatus.trailingAnchor
          constraintLessThanOrEqualToAnchor:card.trailingAnchor
                                   constant:-10],
      [_systemStatus.topAnchor constraintEqualToAnchor:_systemProgress.topAnchor],
    ]];
    above = _systemStatus;
  }
  //
  // the width. A Chromium stage's labels keep their order, the last primary;
  // more than two stack vertically at full width.
  NSArray<NSString*>* labels = _followUpLabels ?: @[ @"Not Now", @"Allow" ];
  NSArray<NSNumber*>* choices =
      _followUpChoices ?: @[ @(PCSitePermissionDismiss), @(PCSitePermissionAllow) ];
  NSMutableArray<NSView*>* buttons = [NSMutableArray array];
  for (NSUInteger i = 0; i < labels.count; ++i) {
    PCPromptButton* button =
        [[PCPromptButton alloc] initWithTitle:labels[i]
                                      primary:i + 1 == labels.count];
    button.target = self;
    button.action = @selector(choose:);
    button.tag = choices[i].integerValue;
    if (button.tag == PCSitePermissionRequestSystem) {
      _systemRequestButton = button;
      button.enabled = NO;
    }
    [buttons addObject:button];
  }
  NSStackView* row = [NSStackView stackViewWithViews:buttons];
  row.orientation = labels.count > 2 ? NSUserInterfaceLayoutOrientationVertical
                                     : NSUserInterfaceLayoutOrientationHorizontal;
  row.distribution = NSStackViewDistributionFillEqually;
  row.alignment = labels.count > 2 ? NSLayoutAttributeWidth
                                   : NSLayoutAttributeCenterY;
  row.spacing = 8;
  row.translatesAutoresizingMaskIntoConstraints = NO;
  [card addSubview:row];
  [constraints addObjectsFromArray:@[
    [row.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:10],
    [row.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-10],
    [row.topAnchor constraintEqualToAnchor:above.bottomAnchor constant:16],
    [row.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-10],
  ]];
  for (NSView* button in buttons) {
    [constraints addObject:[button.heightAnchor constraintEqualToConstant:32]];
  }
  if (!tall) {
    [constraints addObject:[title.bottomAnchor
                               constraintLessThanOrEqualToAnchor:row.topAnchor
                                                        constant:-16]];
  }
  [NSLayoutConstraint activateConstraints:constraints];
  return card;
}
//
// window's controller names that anchor. Otherwise the requesting page's top
// leading corner, as other page controls do while the sidebar is away.
- (BOOL)showPopover:(NSPopover*)popover {
  NSView* page = _page;
  NSWindow* window = _window;
  id controller = window.windowController;
  NSDictionary* anchor = nil;
  if ([controller respondsToSelector:@selector(parcSitePermissionAnchorForPage:)]) {
    anchor = [(id<PCSitePermissionAnchorProviding>)controller
        parcSitePermissionAnchorForPage:page];
  }
  NSView* view = [anchor[@"view"] isKindOfClass:NSView.class] ? anchor[@"view"]
                                                              : nil;
  if (view && view.window == window && !view.hiddenOrHasHiddenAncestor &&
      [anchor[@"rect"] isKindOfClass:NSValue.class] &&
      [anchor[@"edge"] isKindOfClass:NSNumber.class]) {
    [popover showRelativeToRect:[anchor[@"rect"] rectValue]
                         ofView:view
                  preferredEdge:static_cast<NSRectEdge>(
                                    [anchor[@"edge"] integerValue])];
  } else {
    const NSRect bounds = page.bounds;
    const CGFloat top = page.isFlipped ? NSMinY(bounds) : NSMaxY(bounds) - 1;
    [popover showRelativeToRect:NSMakeRect(NSMinX(bounds), top, 1, 1)
                         ofView:page
                  preferredEdge:page.isFlipped ? NSRectEdgeMaxY
                                               : NSRectEdgeMinY];
  }
  return popover.shown;
}
- (void)start {
  NSCAssert(NSThread.isMainThread, @"UI thread required");
  if (_started || _finished) {
    return;
  }
  _started = YES;
  Later(^{
    if (self->_finished) {
      return;
    }
    __attribute__((objc_precise_lifetime)) NSWindow* window = self->_window;
    __attribute__((objc_precise_lifetime)) NSView* page = self->_page;
    BOOL busy = NO;
    for (PCSitePermissionPresenter* other in PCShownPrompts()) {
      busy |= other != self && !other->_finished && other->_window == window;
    }
    if (![self valid] || !window || !page || window.attachedSheet || busy) {
      [self finish:PCSitePermissionInterrupted];
      return;
    }
    NSView* card = [self buildCard];
    self->_card = card;
    NSViewController* content = [NSViewController new];
    content.view = card;
    //
    // that hands off to macOS stays up while another app is in front.
    NSPopover* popover = [NSPopover new];
    const BOOL system =
        [self->_followUpChoices containsObject:@(PCSitePermissionRequestSystem)] ||
        [self->_followUpChoices
            containsObject:@(PCSitePermissionOpenSystemSettings)];
    popover.behavior = system ? NSPopoverBehaviorApplicationDefined
                              : NSPopoverBehaviorTransient;
    popover.contentViewController = content;
    popover.delegate = self;
    self->_popover = popover;
    [self resizePopover];
    if (self->_finished || ![self valid] || window.attachedSheet) {
      [self finish:PCSitePermissionInterrupted];
      return;
    }
    [PCShownPrompts() addObject:self];
    if (![self showPopover:popover] || self->_finished || ![self valid]) {
      [self finish:PCSitePermissionInterrupted];
      return;
    }
    // A popover does not occupy the window's sheet slot. Another dialog's
    // sheet on this window ends the prompt rather than leaving it undecidable.
    __weak PCSitePermissionPresenter* weak = self;
    self->_sheetObserver = [NSNotificationCenter.defaultCenter
        addObserverForName:NSWindowWillBeginSheetNotification
                    object:window
                     queue:nil
                usingBlock:^(NSNotification*) {
                  [weak finish:PCSitePermissionInterrupted];
                }];
    auto presented = self->_presented;
    self->_presented = nil;
    if (presented) {
      presented();
    }
  });
}
- (void)choose:(NSButton*)sender {
  if (_finished || !_popover.shown || sender.window != _card.window ||
      !sender.enabled) {
    return;
  }
  auto choice = static_cast<PCSitePermissionChoice>(sender.tag);
  if (choice == PCSitePermissionOpenSystemSettings ||
      choice == PCSitePermissionRequestSystem) {
    if (![self valid]) {
      [self finish:PCSitePermissionInterrupted];
      return;
    }
    auto action = _systemAction;
    if (action) action(choice);
    return;
  }
  [self finish:choice];
}
//
//
- (void)popoverDidClose:(NSNotification*)notification {
  if (notification.object == _popover) {
    [self finish:PCSitePermissionDismiss];
  }
}
- (void)finish:(PCSitePermissionChoice)choice {
  NSCAssert(NSThread.isMainThread, @"UI thread required");
  if (_finished) {
    return;
  }
  _finished = YES;
  _presented = nil;
  _systemAction = nil;
  [_systemProgress stopAnimation:nil];
  [PCShownPrompts() removeObject:self];
  if (_sheetObserver) {
    [NSNotificationCenter.defaultCenter removeObserver:_sheetObserver];
    _sheetObserver = nil;
  }
  NSPopover* popover = _popover;
  _popover = nil;
  popover.delegate = nil;
  if (popover.shown) {
    [popover close];
  }
  Later(^{
    if (!self->_result) {
      return;
    }
    BOOL valid = [self valid];
    auto result = self->_result;
    self->_result = nil;
    self->_validate = nil;
    if (self->_closeObserver) {
      [NSNotificationCenter.defaultCenter removeObserver:self->_closeObserver];
      self->_closeObserver = nil;
    }
    result(valid ? choice : PCSitePermissionInterrupted, self->_precise);
  });
}
- (void)invalidate {
  _invalidated = YES;
  [self finish:PCSitePermissionInterrupted];
}
- (NSWindow*)sheet {
  return _popover.shown ? _card.window : nil;
}
- (BOOL)isShown {
  return !_finished && _popover.shown && _card.window.visible && [self valid];
}
- (void)dealloc {
  if (_closeObserver) {
    [NSNotificationCenter.defaultCenter removeObserver:_closeObserver];
  }
  if (_sheetObserver) {
    [NSNotificationCenter.defaultCenter removeObserver:_sheetObserver];
  }
  NSCAssert(!_popover, @"Owner must invalidate a presented permission");
}
@end
