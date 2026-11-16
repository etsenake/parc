// Copyright 2026 Parc contributors.
#import "status_text.h"

#import <QuartzCore/QuartzCore.h>

@class PCStatusOverlay;
@interface PCNativeStatusTextController ()
- (void)layoutOverlay;
- (void)hostChanged;
- (void)updatePointerInOverlay:(NSPoint)point;
- (void)updateModifierFlags:(NSEventModifierFlags)flags;
- (void)appearanceChanged;
- (void)windowThemeChanged:(NSNotification*)notification;
- (void)invalidateAvoidanceFingerprint;
- (void)captureAvoidanceFingerprint;
@end

@protocol PCStatusTextThemeSelectors <NSObject>
- (nullable NSColor*)statusTextThemeBackgroundColor;
- (nullable NSAppearance*)statusTextThemeAppearance;
@end

namespace {
NSColor* NamedColor(NSString* name, CGFloat light, CGFloat light_alpha,
                    CGFloat dark, CGFloat dark_alpha) {
  return [NSColor colorWithName:name dynamicProvider:^NSColor*(NSAppearance* appearance) {
    const BOOL is_dark = [[appearance bestMatchFromAppearancesWithNames:
        @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameDarkAqua];
    const CGFloat value = is_dark ? dark : light;
    return [NSColor colorWithSRGBRed:value green:value blue:value alpha:is_dark ? dark_alpha : light_alpha];
  }];
}
NSColor* BaseSecondary() {
  static NSColor* color = NamedColor(@"BaseSecondary", 0, .7, 1, .7);
  return color;
}
NSColor* BaseTertiary() {
  static NSColor* color = NamedColor(@"BaseTertiary", 0, .3, 1, 1);
  return color;
}
NSColor* FloatingScrimBorder() {
  static NSColor* color = NamedColor(@"FloatingScrimBorder", 0, .1, 1, .2);
  return color;
}
constexpr CGFloat kHeight = 24;
constexpr CGFloat kInset = 10;
constexpr CGFloat kHorizontalPadding = 9;
constexpr CGFloat kIconSpacing = 6;
constexpr CGFloat kCompactWidth = 400;
constexpr NSEventModifierFlags kLinkModifiers = NSEventModifierFlagShift |
    NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagCommand;
NSNotificationName const kWindowThemeDidChange = @"PCNativeAirPlayThemeDidChange";

bool StatusTextAvoidanceNeedsLayout(NSRect bounds, NSRect pill, BOOL trailing,
                                    NSPoint point) {
  const CGFloat width = NSWidth(pill) + 20;
  const NSRect left = NSMakeRect(NSMinX(bounds), NSMinY(pill) - 10, width, 44);
  const NSRect right = NSMakeRect(NSMaxX(bounds) - width, NSMinY(pill) - 10, width, 44);
  const BOOL in_left = NSPointInRect(point, left);
  if (in_left && NSPointInRect(point, right)) return false;
  return trailing != in_left;
}

NSString* SchemePrefix(NSString* text) {
  for (NSString* prefix in @[@"mailto:", @"http://", @"https://"]) {
    if ([text hasPrefix:prefix]) return prefix;
  }
  return nil;
}
NSImage* SchemeIcon(NSString* prefix) {
  NSString* symbol = [prefix isEqualToString:@"mailto:"] ? @"envelope.fill"
      : [prefix isEqualToString:@"http://"] ? @"lock.slash.fill" : nil;
  NSString* description = [prefix isEqualToString:@"mailto:"] ? @"envelope"
      : @"lock with a slash through it";
  if (!symbol) return nil;
  NSImage* image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:description];
  return [image imageWithSymbolConfiguration:
      [NSImageSymbolConfiguration configurationWithPointSize:10 weight:NSFontWeightHeavy]];
}
NSString* OutcomeFormat(PCNativeStatusLinkOutcome outcome) {
  switch (outcome) {
    case PCNativeStatusLinkOutcomeNewBackgroundTab: return @"Open %@ in a new tab";
    case PCNativeStatusLinkOutcomeNewForegroundTab: return @"Open %@ in a new tab and focus it";
    case PCNativeStatusLinkOutcomeNewWindow: return @"Open %@ in a new window";
    case PCNativeStatusLinkOutcomePeek: return @"Open %@ in Peek";
    case PCNativeStatusLinkOutcomeSplitView: return @"Open %@ in Split View";
    case PCNativeStatusLinkOutcomeNone: return nil;
  }
  return nil;
}
}

@interface PCStatusOverlay : NSView
@property(nonatomic, weak) PCNativeStatusTextController* controller;
@end
@implementation PCStatusOverlay
@synthesize controller = _controller;
- (BOOL)isFlipped { return YES; }
- (NSView*)hitTest:(NSPoint)point { return nil; }
- (void)layout {
  [super layout];
  [self.controller layoutOverlay];
}
- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  [self.controller hostChanged];
}
- (void)viewDidMoveToSuperview {
  [super viewDidMoveToSuperview];
  [self.controller hostChanged];
}
- (void)viewDidHide {
  [super viewDidHide];
  [self.controller reset];
}
- (void)viewDidChangeEffectiveAppearance {
  [super viewDidChangeEffectiveAppearance];
  [self.controller appearanceChanged];
}
@end

@interface PCStatusBackground : NSView
@property(nonatomic, copy, nullable) NSColor* overlayColor;
@end
@implementation PCStatusBackground {
  NSVisualEffectView* _effect;
  CALayer* _overlay;
  CGFloat _cornerRadius;
}
@synthesize overlayColor = _overlayColor;
- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.wantsLayer = YES;
    self.layer.masksToBounds = NO;
    _effect = [[NSVisualEffectView alloc] initWithFrame:self.bounds];
    _effect.material = NSVisualEffectMaterialPopover;
    _effect.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    _effect.wantsLayer = YES;
    [self addSubview:_effect];
    _overlay = [CALayer layer];
    _overlay.zPosition = 3;
    [self.layer addSublayer:_overlay];
  }
  return self;
}
- (BOOL)isFlipped { return YES; }
- (NSView*)hitTest:(NSPoint)point { return nil; }
- (BOOL)wantsUpdateLayer { return YES; }
- (void)setOverlayColor:(NSColor*)color {
  if (color == _overlayColor || [color isEqual:_overlayColor]) return;
  _overlayColor = [color copy];
  self.needsDisplay = YES;
}
- (void)layout {
  [super layout];
  _effect.frame = self.bounds;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  _overlay.frame = self.bounds;
  const CGFloat radius = NSHeight(self.bounds) * 0.5;
  if (radius != _cornerRadius) {
    _cornerRadius = radius;
    _effect.layer.cornerRadius = radius;
    _overlay.cornerRadius = radius;
    self.layer.cornerRadius = radius;
    const CGFloat side = radius * 2 + 1;
    NSImage* mask = [NSImage imageWithSize:NSMakeSize(side, side) flipped:NO
        drawingHandler:^BOOL(NSRect rect) {
          [NSColor.blackColor setFill];
          [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius] fill];
          return YES;
        }];
    mask.capInsets = NSEdgeInsetsMake(radius, radius, radius, radius);
    mask.resizingMode = NSImageResizingModeStretch;
    _effect.maskImage = mask;
  }
  CGPathRef path = CGPathCreateWithRoundedRect(self.bounds, radius, radius, nullptr);
  self.layer.shadowPath = path;
  CGPathRelease(path);
  [CATransaction commit];
}
- (void)updateLayer {
  CALayer* layer = self.layer;
  __block CGColorRef border = nil;
  __block CGColorRef overlay = nil;
  [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
    border = CGColorRetain(FloatingScrimBorder().CGColor);
    overlay = self->_overlayColor ? CGColorRetain(self->_overlayColor.CGColor) : nil;
  }];
  layer.shadowColor = NSColor.blackColor.CGColor;
  layer.shadowOpacity = 0.12f;
  layer.shadowRadius = 5;
  layer.shadowOffset = CGSizeZero;
  layer.borderColor = border;
  layer.borderWidth = 1;
  layer.masksToBounds = NO;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  _overlay.backgroundColor = overlay;
  [CATransaction commit];
  CGColorRelease(border);
  CGColorRelease(overlay);
}
- (void)viewDidChangeEffectiveAppearance {
  [super viewDidChangeEffectiveAppearance];
  self.needsDisplay = YES;
}
@end

@implementation PCNativeStatusTextController {
  __weak NSView* _page;
  __weak NSWindow* _attachedWindow;
  BOOL (^_validate)(void);
  PCStatusOverlay* _overlay;
  NSView* _pill;
  PCStatusBackground* _background;
  NSImageView* _icon;
  NSTextField* _label;
  NSString* _text;
  NSTimer* _visibilityTimer;
  NSTimer* _expansionTimer;
  id _mouseMonitor;
  id _flagsMonitor;
  NSEventModifierFlags _modifiers;
  NSUInteger _generation;
  NSUInteger _animationGeneration;
  BOOL _attached;
  BOOL _invalidated;
  BOOL _expanded;
  BOOL _explained;
  BOOL _trailing;
  BOOL _layingOut;
  NSRect _avoidanceBounds;
  NSRect _avoidancePill;
  BOOL _avoidanceTrailing;
  BOOL _avoidanceFingerprintValid;
}
@synthesize linkOutcome = _linkOutcome;
- (instancetype)initWithPage:(NSView*)page validate:(BOOL (^)(void))validate {
  NSAssert(NSThread.isMainThread, @"Status text requires the main thread");
  NSParameterAssert(page);
  NSParameterAssert(validate);
  if ((self = [super init])) {
    _page = page;
    _validate = [validate copy];
    _text = @"";
    _overlay = [[PCStatusOverlay alloc] initWithFrame:page.bounds];
    _overlay.identifier = @"parc-status-overlay";
    _overlay.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _overlay.controller = self;
    _pill = [[NSView alloc] initWithFrame:NSZeroRect];
    _pill.identifier = @"parc-status-pill";
    _pill.wantsLayer = YES;
    _pill.layer.masksToBounds = NO;
    _pill.hidden = YES;
    _pill.alphaValue = 0;
    _background = [[PCStatusBackground alloc] initWithFrame:NSZeroRect];
    _background.identifier = @"parc-status-background";
    [_pill addSubview:_background];
    _icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _icon.identifier = @"parc-status-icon";
    _icon.contentTintColor = BaseSecondary();
    _icon.hidden = YES;
    [_pill addSubview:_icon];
    _label = [NSTextField labelWithString:@""];
    _label.identifier = @"parc-status-label";
    _label.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    _label.usesSingleLineMode = YES;
    _label.maximumNumberOfLines = 1;
    _label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _label.selectable = NO;
    [_pill addSubview:_label];
    [_overlay addSubview:_pill];
    [page addSubview:_overlay positioned:NSWindowAbove relativeTo:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(windowThemeChanged:)
                                               name:kWindowThemeDidChange
                                             object:nil];
  }
  return self;
}
- (void)dealloc {
  [NSNotificationCenter.defaultCenter removeObserver:self];
  [_visibilityTimer invalidate];
  [_expansionTimer invalidate];
  if (_mouseMonitor) { [NSEvent removeMonitor:_mouseMonitor]; }
  if (_flagsMonitor) { [NSEvent removeMonitor:_flagsMonitor]; }
  [_overlay removeFromSuperview];
}
- (BOOL)isValid {
  return !_invalidated && _attached && _page && _attachedWindow &&
         _page.window == _attachedWindow &&
         _overlay.superview == _page && _overlay.window == _attachedWindow &&
         _attachedWindow.visible && !_attachedWindow.miniaturized &&
         !_page.hiddenOrHasHiddenAncestor && _validate && _validate();
}
- (void)setAttached:(BOOL)attached {
  NSAssert(NSThread.isMainThread, @"Status text requires the main thread");
  if (_invalidated) { return; }
  if (!attached || _attachedWindow != _page.window) { [self reset]; }
  _attached = attached;
  _attachedWindow = attached ? _page.window : nil;
}
- (void)hostChanged {
  if (_attached && (_page.window != _attachedWindow ||
                    _overlay.superview != _page)) {
    [self setAttached:NO];
  }
}
- (void)applyTheme {
  id<PCStatusTextThemeSelectors> source = nil;
  id delegate = _attachedWindow.delegate;
  if ([delegate respondsToSelector:@selector(statusTextThemeBackgroundColor)] &&
      [delegate respondsToSelector:@selector(statusTextThemeAppearance)]) source = delegate;
  _pill.appearance = source ? [source statusTextThemeAppearance] : nil;
  _background.overlayColor = source ? [source statusTextThemeBackgroundColor] : nil;
}
- (void)appearanceChanged {
  if (_invalidated) { return; }
  [self applyTheme];
}
- (void)windowThemeChanged:(NSNotification*)notification {
  if (_invalidated || _pill.hidden || !_attachedWindow ||
      notification.object != _attachedWindow) { return; }
  [self applyTheme];
}
- (void)rebuildContent {
  NSString* text = _text;
  PCNativeStatusLinkOutcome outcome = PCNativeStatusLinkOutcomeNone;
  NSURL* url = text.length && _linkOutcome ? [NSURL URLWithString:text] : nil;
  if (url && url.scheme.length &&
      (url.host.length || [url.scheme caseInsensitiveCompare:@"mailto"] == NSOrderedSame)) {
    outcome = _linkOutcome(_modifiers & kLinkModifiers, url);
  }
  NSString* format = OutcomeFormat(outcome);
  NSFont* font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
  NSMutableParagraphStyle* paragraph = [[NSMutableParagraphStyle alloc] init];
  NSMutableAttributedString* content;
  NSString* prefix;
  if (format) {
    NSString* absolute = url.absoluteString ?: text;
    NSString* sentence = [NSString stringWithFormat:format, absolute];
    content = [[NSMutableAttributedString alloc] initWithString:sentence attributes:@{
      NSFontAttributeName : font, NSForegroundColorAttributeName : BaseSecondary()}];
    NSRange range = [sentence rangeOfString:absolute];
    if (range.location != NSNotFound) {
      [content addAttribute:NSForegroundColorAttributeName value:BaseTertiary() range:range];
    }
    prefix = SchemePrefix(absolute);
    paragraph.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _explained = YES;
  } else {
    prefix = SchemePrefix(text);
    NSString* display = prefix ? [text substringFromIndex:prefix.length] : text;
    if ([display hasSuffix:@"/"]) display = [display substringToIndex:display.length - 1];
    content = [[NSMutableAttributedString alloc] initWithString:display attributes:@{
      NSFontAttributeName : font, NSForegroundColorAttributeName : BaseSecondary()}];
    paragraph.lineBreakMode = _expanded ? NSLineBreakByTruncatingTail : NSLineBreakByTruncatingMiddle;
    _explained = NO;
  }
  [content addAttribute:NSParagraphStyleAttributeName value:paragraph
                  range:NSMakeRange(0, content.length)];
  NSImage* icon = SchemeIcon(prefix);
  _icon.image = icon;
  _icon.hidden = icon == nil;
  _label.lineBreakMode = paragraph.lineBreakMode;
  _label.attributedStringValue = content;
  if (_explained && !_expanded) {
    [_expansionTimer invalidate];
    _expansionTimer = nil;
    _expanded = YES;
  }
  [self layoutOverlay];
}
- (void)updateText:(NSString*)text {
  NSAssert(NSThread.isMainThread, @"Status text requires the main thread");
  if (![self isValid]) { [self reset]; return; }
  if ([_text isEqualToString:text]) { return; }
  _text = [text copy];
  const NSUInteger generation = ++_generation;
  [_visibilityTimer invalidate];
  [_expansionTimer invalidate];
  _visibilityTimer = _expansionTimer = nil;
  if (_text.length) {
    _modifiers = NSEvent.modifierFlags;
    [self startFlagsMonitor];
    [self applyTheme];
    [self rebuildContent];
  }
  __weak PCNativeStatusTextController* weak = self;
  _visibilityTimer = [NSTimer scheduledTimerWithTimeInterval:.5 repeats:NO
      block:^(NSTimer*) {
        PCNativeStatusTextController* owner = weak;
        if (!owner || generation != owner->_generation) { return; }
        owner->_visibilityTimer = nil;
        if (![owner isValid]) { [owner reset]; return; }
        [owner setVisible:owner->_text.length != 0];
      }];
  if (_text.length && !_explained) {
    _expansionTimer = [NSTimer scheduledTimerWithTimeInterval:1.5 repeats:NO
        block:^(NSTimer*) {
          PCNativeStatusTextController* owner = weak;
          if (!owner || generation != owner->_generation) { return; }
          owner->_expansionTimer = nil;
          if (![owner isValid]) { [owner reset]; return; }
          owner->_expanded = YES;
          [owner rebuildContent];
        }];
  }
}
- (void)setVisible:(BOOL)visible {
  if (![self isValid]) { [self reset]; return; }
  const NSUInteger animation = ++_animationGeneration;
  if (visible) {
    _pill.hidden = NO;
    [self applyTheme];
    [self layoutOverlay];
    [self startMouseMonitor];
  }
  __weak PCNativeStatusTextController* weak = self;
  [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
    context.allowsImplicitAnimation = YES;
    self->_pill.animator.alphaValue = visible ? 1 : 0;
  } completionHandler:^{
    PCNativeStatusTextController* owner = weak;
    if (!owner || animation != owner->_animationGeneration) { return; }
    if (![owner isValid]) { [owner reset]; return; }
    if (!visible) {
      owner->_pill.hidden = YES;
      owner->_expanded = NO;
      owner->_label.lineBreakMode = NSLineBreakByTruncatingMiddle;
      [owner stopMouseMonitor];
      [owner invalidateAvoidanceFingerprint];
      if (!owner->_text.length) [owner stopFlagsMonitor];
      [owner layoutOverlay];
    }
  }];
}
- (void)invalidateAvoidanceFingerprint {
  _avoidanceFingerprintValid = NO;
}
- (void)captureAvoidanceFingerprint {
  _avoidanceBounds = _overlay.bounds;
  _avoidancePill = _pill.frame;
  _avoidanceTrailing = _trailing;
  _avoidanceFingerprintValid = YES;
}
- (void)layoutOverlay {
  if (_invalidated || _layingOut) { return; }
  _layingOut = YES;
  NSRect bounds = _overlay.bounds;
  const NSSize text = [_label.cell cellSizeForBounds:NSMakeRect(0, 0, CGFLOAT_MAX, kHeight)];
  const NSSize icon = _icon.hidden ? NSZeroSize : _icon.intrinsicContentSize;
  const CGFloat leading = kHorizontalPadding + (_icon.hidden ? 0 : icon.width + kIconSpacing);
  CGFloat available = MAX(0, NSWidth(bounds) - 2 * kInset);
  CGFloat desired = ceil(leading + text.width + kHorizontalPadding);
  CGFloat width = MIN(available, MIN(desired, _expanded ? CGFLOAT_MAX : kCompactWidth));
  CGFloat height = MIN(kHeight, MAX(0, NSHeight(bounds) - 2 * kInset));
  CGFloat x = _trailing ? NSMaxX(bounds) - width - kInset : NSMinX(bounds) + kInset;
  const NSRect pill_frame = NSMakeRect(
      x, MAX(NSMinY(bounds), NSMaxY(bounds) - height - kInset), width, height);
  const NSRect background_frame = NSMakeRect(0, 0, width, height);
  NSRect icon_frame = NSZeroRect;
  if (!_icon.hidden) {
    icon_frame = NSMakeRect(kHorizontalPadding, floor((height - icon.height) / 2),
                            icon.width, icon.height);
  }
  const CGFloat labelHeight = MIN(height, ceil(_label.intrinsicContentSize.height));
  const NSRect label_frame = NSMakeRect(
      leading, floor((height - labelHeight) / 2),
      MAX(0, width - leading - kHorizontalPadding), labelHeight);
  if (NSEqualRects(_pill.frame, pill_frame) &&
      NSEqualRects(_background.frame, background_frame) &&
      (_icon.hidden || NSEqualRects(_icon.frame, icon_frame)) &&
      NSEqualRects(_label.frame, label_frame)) {
    _layingOut = NO;
    [self captureAvoidanceFingerprint];
    return;
  }
  _pill.frame = pill_frame;
  _background.frame = background_frame;
  if (!_icon.hidden) _icon.frame = icon_frame;
  _label.frame = label_frame;
  _layingOut = NO;
  [self captureAvoidanceFingerprint];
}
- (void)updatePointerInOverlay:(NSPoint)point {
  if (![self isValid]) { return; }
  if (_pill.hidden) {
    [self stopMouseMonitor];
    [self invalidateAvoidanceFingerprint];
    return;
  }
  NSRect bounds = _overlay.bounds;
  NSRect pill = _pill.frame;
  if (_avoidanceFingerprintValid &&
      NSEqualRects(bounds, _avoidanceBounds) &&
      NSEqualRects(pill, _avoidancePill) &&
      _trailing == _avoidanceTrailing &&
      !StatusTextAvoidanceNeedsLayout(bounds, pill, _trailing, point)) {
    return;
  }
  if (!StatusTextAvoidanceNeedsLayout(bounds, pill, _trailing, point)) {
    [self captureAvoidanceFingerprint];
    return;
  }
  const CGFloat width = NSWidth(pill) + 20;
  const NSRect left = NSMakeRect(NSMinX(bounds), NSMinY(pill) - 10, width, 44);
  _trailing = NSPointInRect(point, left);
  [self layoutOverlay];
}
- (void)startMouseMonitor {
  if (_mouseMonitor) { return; }
  if (_pill.hidden) { return; }
  NSWindow* window = _attachedWindow;
  NSPoint point = [window convertPointFromScreen:NSEvent.mouseLocation];
  [self updatePointerInOverlay:[_overlay convertPoint:point fromView:nil]];
  __weak PCNativeStatusTextController* weak = self;
  _mouseMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskMouseMoved
      handler:^NSEvent*(NSEvent* event) {
        PCNativeStatusTextController* owner = weak;
        if (!owner || event.window != owner->_attachedWindow) return event;
        if (![owner isValid]) {
          [owner reset];
          return event;
        }
        if (owner->_pill.hidden) {
          [owner stopMouseMonitor];
          [owner invalidateAvoidanceFingerprint];
          return event;
        }
        [owner updatePointerInOverlay:
            [owner->_overlay convertPoint:event.locationInWindow fromView:nil]];
        return event;
      }];
}
- (void)stopMouseMonitor {
  if (_mouseMonitor) { [NSEvent removeMonitor:_mouseMonitor]; _mouseMonitor = nil; }
}
- (BOOL)hasMouseMovedMonitor {
  return _mouseMonitor != nil;
}
- (BOOL)pointerAvoidanceWouldLayoutAt:(NSPoint)point {
  if (![self isValid] || _pill.hidden) return NO;
  return StatusTextAvoidanceNeedsLayout(_overlay.bounds, _pill.frame, _trailing, point);
}
- (void)startFlagsMonitor {
  if (_flagsMonitor || !_linkOutcome) { return; }
  __weak PCNativeStatusTextController* weak = self;
  _flagsMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskFlagsChanged
      handler:^NSEvent*(NSEvent* event) {
        PCNativeStatusTextController* owner = weak;
        if (owner) [owner updateModifierFlags:event.modifierFlags];
        return event;
      }];
}
- (void)updateModifierFlags:(NSEventModifierFlags)flags {
  if (!_text.length || (flags & kLinkModifiers) == (_modifiers & kLinkModifiers)) { return; }
  _modifiers = flags;
  if (![self isValid]) { [self reset]; }
  else { [self rebuildContent]; }
}
- (void)stopFlagsMonitor {
  if (_flagsMonitor) { [NSEvent removeMonitor:_flagsMonitor]; _flagsMonitor = nil; }
}
- (void)reset {
  ++_generation;
  ++_animationGeneration;
  [_visibilityTimer invalidate];
  [_expansionTimer invalidate];
  _visibilityTimer = _expansionTimer = nil;
  [self stopMouseMonitor];
  [self stopFlagsMonitor];
  [self invalidateAvoidanceFingerprint];
  [_pill.layer removeAllAnimations];
  _pill.alphaValue = 0;
  _pill.hidden = YES;
  _expanded = NO;
  _explained = NO;
  _text = @"";
  _label.stringValue = @"";
  _icon.image = nil;
  _icon.hidden = YES;
  _label.lineBreakMode = NSLineBreakByTruncatingMiddle;
}
- (void)invalidate {
  if (_invalidated) { return; }
  _invalidated = YES;
  [NSNotificationCenter.defaultCenter removeObserver:self];
  [self reset];
  _attached = NO;
  _attachedWindow = nil;
  _validate = nil;
  _linkOutcome = nil;
  _overlay.controller = nil;
  [_overlay removeFromSuperview];
  _page = nil;
}
@end
